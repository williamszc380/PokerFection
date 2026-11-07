/// Listing the legal plays of a hand: every lead, or every play that beats
/// the one on the table.
///
/// Works on rank counts (15 numbers, see cards.dart), which is all the
/// rules look at, so the bots and the coach can call it millions of times.
library;

import 'cards.dart';
import 'plays.dart';
import 'rules.dart';

/// Every play [counts] can lead with, when the trick is empty.
List<Play> leadPlays(List<int> counts, [DdzRules rules = DdzRules.standard]) {
  final out = <Play>[];
  for (final type in PlayType.values) {
    _addType(out, counts, type, 0, -1, rules);
  }
  return out;
}

/// Every play [counts] can beat [current] with (passing is not included).
List<Play> beatingPlays(List<int> counts, Play current, [DdzRules rules = DdzRules.standard]) {
  final out = <Play>[];
  switch (current.type) {
    case PlayType.rocket:
      return out;
    case PlayType.bomb:
      _addType(out, counts, PlayType.bomb, 0, current.rank, rules);
    default:
      _addType(out, counts, current.type, current.length, current.rank, rules);
      _addType(out, counts, PlayType.bomb, 0, -1, rules);
  }
  _addType(out, counts, PlayType.rocket, 0, -1, rules);
  return out;
}

/// Whether [counts] holds any play that beats [current]. Faster than
/// building the list, for card counting and the bots' checks.
bool canBeat(List<int> counts, Play current, [DdzRules rules = DdzRules.standard]) {
  if (current.type == PlayType.rocket) return false;
  if (counts[Rank.littleJoker] > 0 && counts[Rank.bigJoker] > 0) return true;
  for (var r = 0; r <= Rank.two; r++) {
    if (counts[r] == 4 && (current.type != PlayType.bomb || r > current.rank)) return true;
  }
  if (current.type == PlayType.bomb) return false;
  final out = <Play>[];
  _addType(out, counts, current.type, current.length, current.rank, rules, firstOnly: true);
  return out.isNotEmpty;
}

/// Adds the plays of [type] to [out]. [length] fixes a chain's length (0 =
/// any); only main ranks above [above] count. With [firstOnly] it stops at
/// the first one found.
void _addType(List<Play> out, List<int> c, PlayType type, int length, int above, DdzRules rules,
    {bool firstOnly = false}) {
  switch (type) {
    case PlayType.solo:
      for (var r = above + 1; r < Rank.count; r++) {
        if (c[r] >= 1) {
          out.add(Play(type, r, 1, [r]));
          if (firstOnly) return;
        }
      }
    case PlayType.pair:
      for (var r = above + 1; r <= Rank.two; r++) {
        if (c[r] >= 2) {
          out.add(Play(type, r, 1, [r, r]));
          if (firstOnly) return;
        }
      }
    case PlayType.trio:
      for (var r = above + 1; r <= Rank.two; r++) {
        if (c[r] >= 3) {
          out.add(Play(type, r, 1, [r, r, r]));
          if (firstOnly) return;
        }
      }
    case PlayType.bomb:
      for (var r = above + 1; r <= Rank.two; r++) {
        if (c[r] == 4) {
          out.add(Play(type, r, 1, [r, r, r, r]));
          if (firstOnly) return;
        }
      }
    case PlayType.rocket:
      if (c[Rank.littleJoker] > 0 && c[Rank.bigJoker] > 0) {
        out.add(Play(type, Rank.littleJoker, 1, [Rank.littleJoker, Rank.bigJoker]));
      }
    case PlayType.trioSolo || PlayType.trioPair:
      for (var t = above + 1; t <= Rank.two; t++) {
        if (c[t] < 3) continue;
        final main = [t, t, t];
        final kickers = type == PlayType.trioSolo
            ? _soloKickers(c, t, 1, 1, 1, rules)
            : _pairKickers(c, t, 1, 1);
        for (final k in kickers) {
          out.add(Play(type, t, 1, [...main, ...k]));
          if (firstOnly) return;
        }
      }
    case PlayType.fourTwoSolos || PlayType.fourTwoPairs:
      if (!rules.fourWithTwo) return;
      for (var f = above + 1; f <= Rank.two; f++) {
        if (c[f] != 4) continue;
        final main = [f, f, f, f];
        final kickers = type == PlayType.fourTwoSolos
            ? _soloKickers(c, f, 1, 2, 1, rules)
            : _pairKickers(c, f, 1, 2);
        for (final k in kickers) {
          out.add(Play(type, f, 1, [...main, ...k]));
          if (firstOnly) return;
        }
      }
    case PlayType.straight || PlayType.pairStraight || PlayType.airplane:
      final copies = type.mainCopies;
      final minLen = length > 0 ? length : type.minLength;
      final maxLen = length > 0 ? length : Rank.highestInChain + 1;
      for (var start = above + 1; start + minLen - 1 <= Rank.highestInChain; start++) {
        // Grow the run from start while every rank has enough cards.
        var len = 0;
        while (start + len <= Rank.highestInChain && c[start + len] >= copies && len < maxLen) {
          len++;
          if (len >= minLen) {
            out.add(Play(type, start, len, [
              for (var r = start; r < start + len; r++)
                for (var i = 0; i < copies; i++) r,
            ]));
            if (firstOnly) return;
          }
        }
      }
    case PlayType.airplaneSolos || PlayType.airplanePairs:
      final minLen = length > 0 ? length : 2;
      final maxLen = length > 0 ? length : Rank.highestInChain + 1;
      for (var start = above + 1; start + minLen - 1 <= Rank.highestInChain; start++) {
        var len = 0;
        while (start + len <= Rank.highestInChain && c[start + len] >= 3 && len < maxLen) {
          len++;
          if (len < minLen) continue;
          // A hand never has more than 20 cards, so longer planes can't fit.
          if (len * (type == PlayType.airplaneSolos ? 4 : 5) > 20) break;
          final main = [
            for (var r = start; r < start + len; r++) ...[r, r, r],
          ];
          final kickers = type == PlayType.airplaneSolos
              ? _soloKickers(c, start, len, len, 2, rules)
              : _pairKickers(c, start, len, len);
          for (final k in kickers) {
            out.add(Play(type, start, len, [...main, ...k]));
            if (firstOnly) return;
          }
        }
      }
  }
}

/// Every choice of [units] solo kickers from [c], leaving out the main
/// ranks [mainStart] .. [mainStart] + [mainLength] - 1, with at most
/// [maxPerRank] of one rank, low to high. Both jokers together only when
/// the rules allow it. Each choice is a sorted list of ranks.
List<List<int>> _soloKickers(List<int> c, int mainStart, int mainLength, int units, int maxPerRank, DdzRules rules) {
  final out = <List<int>>[];
  final pick = <int>[];
  void go(int from) {
    if (pick.length == units) {
      if (!rules.rocketAsKickers && pick.contains(Rank.littleJoker) && pick.contains(Rank.bigJoker)) return;
      out.add([...pick]);
      return;
    }
    for (var r = from; r < Rank.count; r++) {
      if (r >= mainStart && r < mainStart + mainLength) continue;
      final avail = c[r] < maxPerRank ? c[r] : maxPerRank;
      if (avail == 0) continue;
      // Take this rank once, then possibly again (handled by recursing with
      // the same rank allowed when a second copy is available).
      pick.add(r);
      if (avail >= 2 && pick.length < units) {
        pick.add(r);
        go(r + 1);
        pick.removeLast();
      }
      go(r + 1);
      pick.removeLast();
    }
  }

  go(0);
  return out;
}

/// Every choice of [units] pairs of different ranks from [c] as kickers,
/// leaving out the main ranks. Jokers can't pair.
List<List<int>> _pairKickers(List<int> c, int mainStart, int mainLength, int units) {
  final out = <List<int>>[];
  final pick = <int>[];
  void go(int from) {
    if (pick.length == units * 2) {
      out.add([...pick]);
      return;
    }
    for (var r = from; r <= Rank.two; r++) {
      if (r >= mainStart && r < mainStart + mainLength) continue;
      if (c[r] < 2) continue;
      pick
        ..add(r)
        ..add(r);
      go(r + 1);
      pick
        ..removeLast()
        ..removeLast();
    }
  }

  go(0);
  return out;
}
