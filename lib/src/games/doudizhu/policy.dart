/// The rule-of-thumb player: the Easy bot, and the fast policy the coach
/// uses to play guessed deals to the end.
///
/// It thinks the way a decent club player does:
/// - Plan the hand (hand_plan.dart) and play it group by group, lowest
///   groups first, keeping bombs and the rocket.
/// - Go out when you can; when every group but one is safe (nobody can
///   beat it), play the safe ones first.
/// - Follow with a group from the plan when one fits; break a group only
///   when it doesn't cost much, or when an opponent is close to going out.
/// - Teamwork for peasants: don't beat your partner's play (unless you
///   go out), and lead your smallest solo when your partner has one card.
/// - Against an opponent with one or two cards, don't lead solos or pairs
///   they can follow, and answer with high cards.
library;

import 'cards.dart';
import 'hand_plan.dart';
import 'play_gen.dart';
import 'plays.dart';
import 'rules.dart';

/// What the policy knows at one decision: the seat's own cards, the hand
/// sizes, the trick and the cards it can't see. All of it is public or the
/// seat's own, so the policy never cheats.
class DdzSituation {
  DdzSituation({
    required this.seat,
    required this.landlord,
    required this.hand,
    required this.handSizes,
    required this.current,
    required this.currentPlayer,
    required this.unseen,
    this.rules = DdzRules.standard,
    this.hands,
  });

  final int seat;
  final int landlord;

  /// The seat's rank counts.
  final List<int> hand;
  final List<int> handSizes;

  /// The play to beat, or null when leading.
  final Play? current;

  /// Who made [current] (-1 when leading).
  final int currentPlayer;

  /// Rank counts of every card in the other two hands.
  final List<int> unseen;
  final DdzRules rules;

  /// Every seat's rank counts, only inside the coach's guessed deals (never
  /// for a real seat). With them the safety checks look at each opponent's
  /// actual hand, which makes the play-outs closer to best play by
  /// everyone ("double dummy", as bridge players say) and so a sharper
  /// judge of the move being rated.
  final List<List<int>>? hands;

  bool get isLandlord => seat == landlord;

  /// The other peasant, or -1 for the landlord.
  int get partner => isLandlord ? -1 : 3 - landlord - seat;

  /// The smallest hand among this seat's opponents.
  int get minOpponentSize => isLandlord
      ? (handSizes[(seat + 1) % 3] < handSizes[(seat + 2) % 3] ? handSizes[(seat + 1) % 3] : handSizes[(seat + 2) % 3])
      : handSizes[landlord];

  /// The largest hand among this seat's opponents.
  int get maxOpponentSize => isLandlord
      ? (handSizes[(seat + 1) % 3] > handSizes[(seat + 2) % 3] ? handSizes[(seat + 1) % 3] : handSizes[(seat + 2) % 3])
      : handSizes[landlord];
}

/// Whether an opponent might beat [p], from the unseen cards and the
/// opponents' hand sizes. Conservative: for a peasant the unseen cards
/// include the partner's, so "might" is often too cautious, never too bold.
bool opponentsMightBeat(Play p, DdzSituation s) {
  if (p.isRocket) return false;
  final hands = s.hands;
  if (hands != null) {
    for (var o = 0; o < 3; o++) {
      if (o == s.seat || (!s.isLandlord && o != s.landlord)) continue;
      if (canBeat(hands[o], p, s.rules)) return true;
    }
    return false;
  }
  final u = s.unseen;
  final maxOpp = s.maxOpponentSize;
  if (p.size > maxOpp) {
    // Only a bomb (4 cards) or the rocket (2) can answer a longer play.
    if (u[Rank.littleJoker] > 0 && u[Rank.bigJoker] > 0 && maxOpp >= 2) return true;
    if (maxOpp >= 4) {
      for (var r = 0; r <= Rank.two; r++) {
        if (u[r] == 4 && (!p.isBomb || r > p.rank)) return true;
      }
    }
    return false;
  }
  return canBeat(u, p, s.rules);
}

/// The heuristic player. Stateless; one instance can serve every seat.
class HeuristicPolicy {
  const HeuristicPolicy();

  /// The play to make, or null to pass.
  Play? choose(DdzSituation s) {
    final hand = s.hand;
    final size = s.handSizes[s.seat];
    final current = s.current;

    // Go out at once when the whole hand is one play.
    if (size <= 20) {
      final whole = [
        for (var r = 0; r < Rank.count; r++)
          for (var i = 0; i < hand[r]; i++) r,
      ];
      final p = readPlay(whole, current, s.rules);
      if (p != null) return p;
    }
    final plan = planHand(hand, s.rules);
    return current == null ? _lead(s, plan) : _follow(s, plan, current);
  }

  Play _lead(DdzSituation s, HandPlan plan) {
    final plays = plan.plays;
    // Every group but one is safe: cash the safe ones, then go out.
    final safe = [for (final p in plays) if (!opponentsMightBeat(p, s)) p];
    if (safe.isNotEmpty && plays.length - safe.length <= 1) {
      safe.sort((a, b) {
        final d = (a.isBombLike ? 1 : 0) - (b.isBombLike ? 1 : 0);
        return d != 0 ? d : comparePlays(a, b);
      });
      return safe.first;
    }
    // Partner has one card: lead the smallest solo we have.
    if (!s.isLandlord && s.handSizes[s.partner] == 1) {
      for (var r = 0; r < Rank.count; r++) {
        if (s.hand[r] > 0) return Play(PlayType.solo, r, 1, [r]);
      }
    }
    final minOpp = s.minOpponentSize;
    final normal = [for (final p in plays) if (!p.isBombLike) p];
    if (normal.isEmpty) return plays.first; // only bombs / rocket left
    var choices = normal;
    if (minOpp <= 2) {
      // Don't lead what an opponent could follow with their last cards.
      final unfollowable = [
        for (final p in normal)
          if (p.size > minOpp || (p.type != PlayType.solo && p.type != PlayType.pair) || !opponentsMightBeat(p, s)) p
      ];
      if (unfollowable.isNotEmpty) {
        choices = unfollowable;
      } else if (minOpp == 1) {
        // Only solos left to lead: the highest one, so they can't follow.
        final solos = [for (final p in normal) if (p.type == PlayType.solo) p];
        if (solos.isNotEmpty) return solos.reduce((a, b) => a.rank > b.rank ? a : b);
      }
    }
    // Lead the lowest group, slightly preferring groups of more cards.
    Play best = choices.first;
    var bestKey = double.infinity;
    for (final p in choices) {
      final key = groupValue(p.type, p.rank, p.length) - 0.6 * (p.size - 1);
      if (key < bestKey) {
        bestKey = key;
        best = p;
      }
    }
    return best;
  }

  Play? _follow(DdzSituation s, HandPlan plan, Play current) {
    final fromPartner = !s.isLandlord && s.currentPlayer == s.partner;
    // Let the partner's play win; we already checked for going out.
    if (fromPartner) return null;

    final answers = beatingPlays(s.hand, current, s.rules);
    if (answers.isEmpty) return null;
    final cpSize = s.currentPlayer >= 0 ? s.handSizes[s.currentPlayer] : 20;
    final danger = s.minOpponentSize <= 2 || cpSize <= 3;

    // A group of the plan that fits exactly.
    final exact = [
      for (final p in plan.plays)
        if (!p.isBombLike && p.beats(current)) p
    ];
    if (exact.isNotEmpty) {
      exact.sort(comparePlays);
      final pick = danger ? exact.last : exact.first;
      // Keep 2s and jokers for later against a low play while it's early.
      final early = !danger && plan.turns > 3 && cpSize > 8;
      if (early && pick.rank >= Rank.two && current.rank <= Rank.ten - 1 && current.type == PlayType.solo) {
        return null;
      }
      return pick;
    }

    // Break a group when it costs little, or when we must stop them.
    final before = plan.score;
    Play? best;
    var bestScore = before - (danger ? 40 : 4);
    final rest = List<int>.of(s.hand);
    for (final a in answers) {
      if (a.isBombLike) continue;
      for (final r in a.ranks) {
        rest[r]--;
      }
      var score = handScore(rest);
      if (danger) score += a.rank * 0.5;
      for (final r in a.ranks) {
        rest[r]++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    if (best != null) return best;

    // Bombs: when they are about to win, or when we can finish after it.
    final bombs = [for (final a in answers) if (a.isBombLike) a];
    if (bombs.isEmpty) return null;
    bombs.sort((a, b) => (a.isRocket ? 100 : a.rank) - (b.isRocket ? 100 : b.rank));
    final bomb = bombs.first;
    for (final r in bomb.ranks) {
      rest[r]--;
    }
    final after = planHand(rest, s.rules);
    if (danger || after.plainTurns <= 2) return bomb;
    return null;
  }

  /// A bid from 0 (pass) to 3 for a 17-card hand, by a rule of thumb: high
  /// cards and bombs, and how few turns the hand needs.
  int bidFor(List<int> counts) {
    final s = bidStrength(counts);
    if (s >= 9) return 3;
    if (s >= 7) return 2;
    if (s >= 5) return 1;
    return 0;
  }
}

/// The rule-of-thumb strength of a hand for bidding: big joker 4, little
/// joker 3, each 2 counts 2, each ace 0.5, each bomb 4, plus a bonus for a
/// hand that needs few turns.
double bidStrength(List<int> counts) {
  var s = 0.0;
  if (counts[Rank.bigJoker] > 0) s += 4;
  if (counts[Rank.littleJoker] > 0) s += 3;
  s += counts[Rank.two] * 2;
  s += counts[Rank.ace] * 0.5;
  for (var r = 0; r < Rank.two; r++) {
    if (counts[r] == 4) s += 4;
  }
  final plan = planHand(counts);
  s += (8 - plan.plainTurns) * 0.6;
  return s;
}
