/// Who goes first: the short step every deal opens with, before the first
/// play, and what it shows the table.
///
/// Pagat's rules decide the starter in one of three ways, and each shows
/// only what the rules make public:
/// - **Three or four players**: every card that matters is dealt, so the
///   holder of the deck's lowest card (the 3♦; the 3♣ under the Taiwan and
///   Pusoy Dos orders) starts. The step names them and shows that card, and
///   with three players the face-up 52nd card they take too. Nobody else
///   shows anything: the card is the deck's lowest, and the first play
///   must hold it anyway.
/// - **Two players**: some cards stay undealt, so low cards are called from
///   the bottom up (3♦, 3♣, 3♥, 3♠, 4♦, …) until a player holds one. Only
///   that card is shown, in its holder's seat. The other player shows
///   nothing; everyone now knows they hold no card below it, and the cards
///   called before it were never dealt. Everyone showing their smallest
///   card would give away more than the rules call for.
/// - **A chosen leader** (the winner of the last deal leads): nobody shows
///   anything, and the step only names the leader.
///
/// Everything here follows from the public facts of a deal
/// ([BigTwoView.startCode], [BigTwoView.startSeat], the face-up card), so a
/// state rebuilt from any seat's or spectator's view gives the same step.
library;

import 'state.dart';

/// How the starter was found (see the library comment).
enum BigTwoOpeningKind {
  /// Three or four players: the holder of the deck's lowest card starts.
  startingCard,

  /// Two players: low cards called upward until someone holds one.
  lowestCalled,

  /// A chosen seat leads; nothing is shown.
  chosen,
}

/// One deal's who-goes-first step: who starts, and the cards the table is
/// shown on the way. Engine codes throughout (see BigTwoRules.cardOf).
class BigTwoOpening {
  const BigTwoOpening._({
    required this.kind,
    required this.starter,
    required this.startCode,
    required this.called,
    required this.extraCode,
  });

  /// The step of the deal [s] as it was dealt, from its public facts only;
  /// null for a deal a dealt dragon won before anyone played (there is no
  /// first play to find a starter for).
  static BigTwoOpening? of(BigTwoState s) {
    if (s.dragonWin) return null;
    if (s.leaderChosen || s.startSeat < 0 || s.startCode < 0) {
      // A chosen leader leads the first trick: in a state replayed to a
      // later move the leader is the first turn's seat.
      final history = s.history;
      final leader = history.isNotEmpty ? history.first.seat : s.toMove;
      return BigTwoOpening._(
        kind: BigTwoOpeningKind.chosen,
        starter: leader,
        startCode: -1,
        called: const [],
        extraCode: -1,
      );
    }
    final two = s.players == 2;
    return BigTwoOpening._(
      kind: two ? BigTwoOpeningKind.lowestCalled : BigTwoOpeningKind.startingCard,
      starter: s.startSeat,
      startCode: s.startCode,
      // Two players: every code from the lowest up to the starting card is
      // called; only the last is held. Three or four: the deck's lowest
      // card is the starting card, so there is one call.
      called: List.unmodifiable(two ? [for (var c = 0; c <= s.startCode; c++) c] : [s.startCode]),
      extraCode: s.extraCode >= 0 && s.extraCode != s.startCode ? s.extraCode : -1,
    );
  }

  final BigTwoOpeningKind kind;

  /// The seat that makes the first play.
  final int starter;

  /// The starting card (-1 under a chosen leader).
  final int startCode;

  /// The cards called, lowest first, the starting card last: with two
  /// players every card below it was called and nobody held it; with three
  /// or four only the starting card. Empty under a chosen leader.
  final List<int> called;

  /// A three-player deal's face-up card when it isn't the starting card
  /// itself (its taker is the [starter]); else -1.
  final int extraCode;

  /// The cards the step shows face up, landing in the [starter]'s seat:
  /// the starting card, and a three-player deal's face-up card.
  List<int> get shown => [if (startCode >= 0) startCode, if (extraCode >= 0) extraCode];

  /// The cards called that nobody was dealt (two players), lowest first.
  List<int> get undealtCalls => called.isEmpty ? const [] : called.sublist(0, called.length - 1);

  /// The step's length at Normal speed: about two seconds with cards to
  /// show, a little over one when it only names a chosen leader.
  Duration get normalLength => kind == BigTwoOpeningKind.chosen ? chosenLength : cardsLength;

  static const cardsLength = Duration(milliseconds: 2000), chosenLength = Duration(milliseconds: 1200);

  /// The step's length at a speed whose factor is [factor] (Normal 1, Fast
  /// 0.35, Instant 0: no step, only its result).
  Duration lengthAt(double factor) => Duration(milliseconds: (normalLength.inMilliseconds * factor).round());

  /// When, as a share of the step (0 to 1), the calls end and the starter
  /// is named: with two players each call takes 15% of the step, at most
  /// half of it in all; otherwise the card is up after 15%.
  double get namedAt {
    if (kind == BigTwoOpeningKind.chosen) return 0;
    if (kind == BigTwoOpeningKind.startingCard) return 0.15;
    final perCall = (0.5 / called.length).clamp(0.0, 0.15);
    return perCall * called.length;
  }

  /// The share of the step at which call [i] (of [called]) is made.
  double callAt(int i) => kind == BigTwoOpeningKind.lowestCalled ? namedAt * i / called.length : 0;

  /// The share of the step from which the shown cards fly to the
  /// [starter]'s seat; they land at the end.
  static const flyFrom = 0.75;

  @override
  String toString() => 'BigTwoOpening($kind, seat $starter, start $startCode, called $called, extra $extraCode)';
}
