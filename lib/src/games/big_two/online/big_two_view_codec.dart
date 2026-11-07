/// Big Two's views in a room, as plain JSON (pure Dart: the room's runner,
/// the app's table, the bots and the spectators' coach all read them).
///
/// Every card is written as its own short text in quotes (`"3d"`, `"Ts"`),
/// never as a number, so a card shows up in a message only where it is
/// meant to: a hand, or a play already made. (A test can then look for a
/// hidden card's text in a message and know it leaked.) The rules stay the
/// engine's own JSON ([BigTwoRules.toJson]).
///
/// - **A seat's view** ([bigTwoSeatView]): the rules, the seat, its own
///   hand, then the public facts of the deal (cards held, the history of
///   plays and passes, the play to beat, the starting card and its holder,
///   the face-up card of a three-player deal and its taker), the deal's
///   number and the match. Once the deal is over, every hand (`shown`).
/// - **The spectators' view** ([bigTwoSpectatorView]): the same public
///   facts, plus the hands the spectators may see (`hands`: every person's,
///   the bots' only with the host's switch; every hand once the deal is
///   over).
///
/// The starting card (`start`, with its holder `startSeat`) is public from
/// the deal, two players included: its holder leads with it, so everyone
/// sees it until it is played (BigTwoState.visibleCards). Under a chosen
/// leader `startSeat` is -1, and `start` is the deck's lowest card with
/// three or four players, null with two.
/// - **Rebuilt** ([bigTwoSeatViewFrom]): a seat's view made from the
///   spectators' one, key for key the same as the room's, or null when that
///   seat's hand isn't in it. The spectators' coach works from it.
///
/// The undealt cards of a two-player deal and the deck's order are in no
/// view.
library;

import 'dart:typed_data';

import '../../../kit/match.dart';
import '../big_two.dart';

/// [seat] making [play], in the moves' notation (the same as a game
/// record's, big_two_record.dart, written here too because the room may
/// not reach the record's code): `"<seat>:<cards>"`, the cards lowest
/// first under the rules (`"2:7c 7h"`), or `"<seat>:pass"`.
String bigTwoMove(int seat, Play play) =>
    '$seat:${play.isPass ? 'pass' : [for (final card in play.cards) card.short].join(' ')}';

/// [text] read as a move under [rules]: its seat and play. Throws
/// [FormatException] when it isn't one (an unknown seat, unreadable cards,
/// a card twice, cards that make no combination).
({int seat, Play play}) bigTwoReadMove(BigTwoRules rules, String text) {
  final colon = text.indexOf(':');
  final seat = colon < 0 ? null : int.tryParse(text.substring(0, colon));
  if (seat == null || seat < 0 || seat >= rules.players) throw FormatException('Not a move', text);
  final rest = text.substring(colon + 1);
  if (rest == 'pass') return (seat: seat, play: Play.pass);
  final cards = parseCards(rest);
  if (cards.isEmpty || cards.length > 5 || cards.toSet().length != cards.length) {
    throw FormatException('Not a move', text);
  }
  final play = rules.classify(cards);
  if (play == null) throw FormatException('Not a combination', text);
  return (seat: seat, play: play);
}

/// The cards of a move's text (none for a pass).
List<Card> bigTwoMoveCardsOf(String text) {
  final rest = text.substring(text.indexOf(':') + 1);
  return rest == 'pass' ? const [] : parseCards(rest);
}

/// [code] (an engine code under [rules]) as its short text ("3d").
String bigTwoCardText(BigTwoRules rules, int code) => rules.cardOf(code).short;

/// [codes] as card texts, in the same order.
List<String> bigTwoCardTexts(BigTwoRules rules, Iterable<int> codes) => [
  for (final c in codes) bigTwoCardText(rules, c),
];

/// The text of one turn of the history: `"<seat>:<cards>"` (lowest first)
/// or `"<seat>:pass"`, the same as a move (big_two_record.dart's notation),
/// with a `!` after the cards when the last-card rule forced the player's
/// highest single (which tells everyone they hold nothing higher).
String _turnText(BigTwoRules rules, BigTwoTurn turn) {
  final cards = turn.play.isPass ? 'pass' : bigTwoCardTexts(rules, turn.play.codes).join(' ');
  return '${turn.seat}:$cards${turn.forcedHighest ? '!' : ''}';
}

/// The facts of [state] every seat and every spectator may see, plus the
/// deal's number [deal] and the [match] (null: no target).
Map<String, Object?> _public(BigTwoState state, {required int deal, required MatchScore? match}) {
  final rules = state.rules;
  final n = state.players;
  final current = state.current;
  final start = BigTwoView.publicStartOf(state);
  return {
    'counts': [for (var i = 0; i < n; i++) state.countOf(i)],
    'dealt': [for (var i = 0; i < n; i++) state.dealtTo(i)],
    'bounds': [for (var i = 0; i < n; i++) state.boundOf(i)],
    'toMove': state.toMove,
    'current': current == null ? null : bigTwoCardTexts(rules, current.codes),
    'lastPlayer': state.lastPlayer,
    'passes': state.passesInRow,
    'locked': state.lockedMask,
    'first': state.firstPlay,
    'chosen': state.leaderChosen,
    'start': start < 0 ? null : bigTwoCardText(rules, start),
    'startSeat': state.leaderChosen ? -1 : state.startSeat,
    'winner': state.winner,
    'extra': state.extraCode < 0 ? null : bigTwoCardText(rules, state.extraCode),
    'extraSeat': state.extraSeat,
    'history': [for (final t in state.history) _turnText(rules, t)],
    'deal': deal,
    'match': match?.toJson(),
  };
}

/// A seat's view in its one key order (the room's and the rebuilt one must
/// match as text): [rules] JSON, [seat], its [hand] (card texts), then the
/// [public] facts, then every hand ([shown]) once the deal is over.
Map<String, Object?> _seatMap(
  Map<String, Object?> rules,
  int seat,
  List<String> hand,
  Map<String, Object?> public,
  Map<String, Object?>? shown,
) => {'rules': rules, 'seat': seat, 'hand': hand, ...public, 'shown': ?shown};

/// Every hand of [state] by seat (`{"0": ["3d", …], …}`).
Map<String, Object?> _hands(BigTwoState state, Iterable<int> seats) => {
  for (final s in seats) '$s': bigTwoCardTexts(state.rules, state.handCodesOf(s)),
};

/// Hand seat [seat]'s view of [state] (see the library comment).
Map<String, Object?> bigTwoSeatView(BigTwoState state, int seat, {required int deal, required MatchScore? match}) {
  final rules = state.rules;
  return _seatMap(
    rules.toJson(),
    seat,
    bigTwoCardTexts(rules, state.handCodesOf(seat)),
    _public(state, deal: deal, match: match),
    state.isOver ? _hands(state, [for (var s = 0; s < state.players; s++) s]) : null,
  );
}

/// The spectators' view of [state]: the hands of the seats in [visible]
/// (every hand once the deal is over), see the library comment.
Map<String, Object?> bigTwoSpectatorView(
  BigTwoState state, {
  required Set<int> visible,
  required int deal,
  required MatchScore? match,
}) {
  final rules = state.rules;
  final seats = [
    for (var s = 0; s < state.players; s++)
      if (state.isOver || visible.contains(s)) s,
  ];
  return {
    'rules': rules.toJson(),
    ..._public(state, deal: deal, match: match),
    'hands': _hands(state, seats),
  };
}

/// Hand seat [seat]'s view rebuilt from [spectatorView] (the same JSON as
/// [bigTwoSeatView] gives it, key for key), or null when its hand isn't
/// there (a bot while the host's switch is off) or the view can't be read.
Map<String, Object?>? bigTwoSeatViewFrom(Map<String, Object?> spectatorView, int seat) {
  final hands = spectatorView['hands'];
  if (hands is! Map || hands['$seat'] is! List) return null;
  final over = spectatorView['winner'] is int && (spectatorView['winner']! as int) >= 0;
  final public = {
    for (final key in _publicKeys)
      if (spectatorView.containsKey(key)) key: spectatorView[key],
  };
  if (public.length != _publicKeys.length || spectatorView['rules'] is! Map) return null;
  return _seatMap(
    (spectatorView['rules']! as Map).cast<String, Object?>(),
    seat,
    [for (final c in hands['$seat']! as List) c as String],
    public,
    over ? {for (final MapEntry(:key, :value) in hands.entries) key as String: value} : null,
  );
}

/// The public keys, in their order (see [_public]).
const _publicKeys = [
  'counts',
  'dealt',
  'bounds',
  'toMove',
  'current',
  'lastPlayer',
  'passes',
  'locked',
  'first',
  'chosen',
  'start',
  'startSeat',
  'winner',
  'extra',
  'extraSeat',
  'history',
  'deal',
  'match',
];

/// One turn of a view's history read back: its seat, its cards (empty for
/// a pass) and whether the last-card rule forced it.
({int seat, List<Card> cards, bool forced}) bigTwoReadTurn(String text) {
  final colon = text.indexOf(':');
  final seat = int.parse(text.substring(0, colon));
  var rest = text.substring(colon + 1);
  final forced = rest.endsWith('!');
  if (forced) rest = rest.substring(0, rest.length - 1);
  return (seat: seat, cards: rest == 'pass' ? const [] : parseCards(rest), forced: forced);
}

/// What the app reads from any view (a seat's or the spectators'): the
/// rules, the public facts and the hands it holds.
class BigTwoWireView {
  BigTwoWireView._(this.json, this.rules);

  /// [json] read; throws [FormatException] if it isn't a Big Two view.
  factory BigTwoWireView.read(Map<String, Object?> json) {
    try {
      final rules = BigTwoRules.fromJson((json['rules']! as Map).cast<String, Object?>());
      final view = BigTwoWireView._(json, rules);
      // Read everything once, so a broken view fails here, not mid-draw.
      view.counts;
      view.history;
      view.hands;
      return view;
    } on Object catch (error) {
      throw FormatException('Not a Big Two view: $error');
    }
  }

  final Map<String, Object?> json;
  final BigTwoRules rules;

  int get players => rules.players;

  List<int> _ints(String key) => [for (final v in json[key]! as List) v as int];

  /// The seat this view is for; null: the spectators'.
  int? get seat => json['seat'] as int?;

  List<int> get counts => _ints('counts');
  List<int> get dealt => _ints('dealt');
  int get toMove => json['toMove']! as int;
  int get winner => json['winner']! as int;
  bool get isOver => winner >= 0;

  /// The deal's number in the game (1, 2, …).
  int get deal => json['deal']! as int;

  /// The match, or null without a target.
  MatchScore? get match => MatchScore.fromJson(json['match']);

  /// The face-up card of a three-player deal and who took it, or null.
  ({Card card, int seat})? get extra => switch (json['extra']) {
    final String c => (card: Card.parse(c), seat: json['extraSeat']! as int),
    _ => null,
  };

  /// The starting card and who was dealt it, or null under a chosen leader
  /// (or in a view without them).
  ({Card card, int seat})? get start => switch ((json['start'], json['startSeat'])) {
    (final String c, final int s) when s >= 0 => (card: Card.parse(c), seat: s),
    _ => null,
  };

  /// The cards everyone has seen that are still in a hand, with their
  /// holders (BigTwoState.visibleCards): the starting card until it is
  /// played and a three-player deal's face-up card. The app draws them
  /// face up in their seats with the eye.
  List<({Card card, int seat})> get visible {
    final played = {for (final t in history) ...t.cards};
    final start = this.start, extra = this.extra;
    return [
      if (start != null && !played.contains(start.card)) start,
      if (extra != null && extra.card != start?.card && !played.contains(extra.card)) extra,
    ];
  }

  /// Every turn so far.
  List<({int seat, List<Card> cards, bool forced})> get history => [
    for (final t in json['history']! as List) bigTwoReadTurn(t as String),
  ];

  /// The hands this view holds, by seat: its own (a seat's view), the ones
  /// the spectators may see, and every one once the deal is over.
  Map<int, List<Card>> get hands {
    final out = <int, List<Card>>{};
    void add(Object? map) {
      if (map is! Map) return;
      for (final MapEntry(:key, :value) in map.entries) {
        out[int.parse(key as String)] = [for (final c in value as List) Card.parse(c as String)];
      }
    }

    add(json['hands']);
    add(json['shown']);
    if (seat case final s?) out[s] = [for (final c in json['hand']! as List) Card.parse(c as String)];
    return out;
  }
}

/// A seat's view ([bigTwoSeatView]'s JSON) as the engine's [BigTwoView],
/// for the bots and the coach. Throws [FormatException] if it can't be read.
BigTwoView bigTwoEngineView(Map<String, Object?> seatView) {
  try {
    final rules = BigTwoRules.fromJson((seatView['rules']! as Map).cast<String, Object?>());
    List<int> codes(Object? cards) => [for (final c in cards! as List) rules.codeOf(Card.parse(c as String))];
    final history = [
      for (final t in seatView['history']! as List)
        if (bigTwoReadTurn(t as String) case (:final seat, :final cards, :final forced))
          [seat, forced ? 1 : 0, for (final c in cards) rules.codeOf(c)],
    ];
    // The cards played so far, as 13 rank masks.
    final played = Uint8List(13);
    for (final turn in history) {
      for (final c in turn.skip(2)) {
        played[c >> 2] |= 1 << (c & 3);
      }
    }
    final extra = seatView['extra'] as String?;
    final start = seatView['start'] as String?;
    return BigTwoView.fromJson({
      'rules': rules.toJson(),
      'seat': seatView['seat']! as int,
      'hand': codes(seatView['hand'])..sort(),
      'counts': seatView['counts'],
      'dealt': seatView['dealt'],
      'bounds': seatView['bounds'],
      'played': [for (final m in played) m],
      'toMove': seatView['toMove'],
      'current': seatView['current'] == null ? null : (codes(seatView['current'])..sort()),
      'lastPlayer': seatView['lastPlayer'],
      'passes': seatView['passes'],
      'locked': seatView['locked'],
      'first': seatView['first'],
      'chosen': seatView['chosen'],
      'start': start == null ? -1 : rules.codeOf(Card.parse(start)),
      'startSeat': seatView['startSeat'] ?? -1,
      'winner': seatView['winner'],
      'extra': [extra == null ? -1 : rules.codeOf(Card.parse(extra)), seatView['extraSeat']],
      'history': history,
    });
  } on Object catch (error) {
    throw FormatException('Not a Big Two seat view: $error');
  }
}
