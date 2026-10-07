import 'dart:convert';

import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/hand_evaluator.dart';
import '../engine/positions.dart';

/// Game events as JSON, to send a hand over the network. Seats are numbers
/// (as map keys, strings: JSON needs them), cards are [PlayingCard.index],
/// hand values [HandValue.score], streets, positions and action kinds
/// their names.
Map<String, Object?> encodeEvent(GameEvent event) => switch (event) {
      HandStarted() => {
          'e': 'start',
          'hand': event.handNumber,
          'button': event.buttonSeat,
          'stacks': List.of(event.stacks),
          'pos': {for (final MapEntry(:key, :value) in event.positions.entries) '$key': value.name},
        },
      AntesPosted() => {'e': 'antes', 'a': _bySeat(event.amounts, (a) => a)},
      BlindPosted() => {'e': 'blind', 's': event.seat, 'a': event.amount, 'big': event.isBigBlind},
      HoleCardsDealt() => {'e': 'dealt', 'order': List.of(event.dealOrder), 'cards': _bySeat(event.cards, _indices)},
      ActionTaken() => {
          'e': 'act',
          's': event.seat,
          'k': event.kind.name,
          'add': event.chipsAdded,
          'bet': event.streetBet,
          'allIn': event.isAllIn,
          'st': event.street.name,
        },
      UncalledBetReturned() => {'e': 'return', 's': event.seat, 'a': event.amount},
      BetsCollected() => {
          'e': 'collect',
          'pots': [
            for (final pot in event.pots) [pot.amount, List.of(pot.eligibleSeats)],
          ],
        },
      BoardDealt() => {'e': 'board', 'st': event.street.name, 'cards': _indices(event.cards)},
      HandsRevealed() => {'e': 'reveal', 'cards': _bySeat(event.cards, _indices)},
      PotAwarded() => {
          'e': 'award',
          'i': event.potIndex,
          'a': event.amount,
          'shares': _bySeat(event.shares, (a) => a),
          'hv': event.winningHand?.score,
        },
      HandEnded() => {'e': 'end', 'stacks': List.of(event.finalStacks), 'net': _bySeat(event.netChange, (a) => a)},
    };

List<Object?> encodeEvents(Iterable<GameEvent> events) => [for (final e in events) encodeEvent(e)];

/// The event [json] stands for (see [encodeEvent]). Strict: anything
/// malformed (a wrong type, a seat or card out of range, a card twice)
/// throws a [FormatException].
GameEvent decodeEvent(Object? json) {
  final m = _map(json);
  final type = m['e'];
  return switch (type) {
    'start' => HandStarted(
        handNumber: _int(m['hand'], min: 1),
        buttonSeat: _seat(m['button']),
        stacks: _list(m['stacks'], (v) => _int(v, min: 0)),
        positions: _seatMap(m['pos'], (v) => _byName(Position.values, v)),
      ),
    'antes' => AntesPosted(_seatMap(m['a'], (v) => _int(v, min: 0))),
    'blind' => BlindPosted(seat: _seat(m['s']), amount: _int(m['a'], min: 1), isBigBlind: _bool(m['big'])),
    'dealt' => HoleCardsDealt(
        dealOrder: _list(m['order'], _seat),
        cards: _uniqueCards(_seatMap(m['cards'], _holeCards)),
      ),
    'act' => ActionTaken(
        seat: _seat(m['s']),
        kind: _byName(ActionKind.values, m['k']),
        chipsAdded: _int(m['add'], min: 0),
        streetBet: _int(m['bet'], min: 0),
        isAllIn: _bool(m['allIn']),
        street: _byName(Street.values, m['st']),
      ),
    'return' => UncalledBetReturned(seat: _seat(m['s']), amount: _int(m['a'], min: 1)),
    'collect' => BetsCollected(_list(m['pots'], (v) {
        final pot = _list(v, (x) => x);
        if (pot.length != 2) throw FormatException('A pot is [amount, seats]', v);
        return Pot(_int(pot[0], min: 0), _list(pot[1], _seat));
      })),
    'board' => BoardDealt(street: _byName(Street.values, m['st']), cards: _cards(m['cards'], max: 3)),
    'reveal' => HandsRevealed(_uniqueCards(_seatMap(m['cards'], _holeCards))),
    'award' => PotAwarded(
        potIndex: _int(m['i'], min: 0),
        amount: _int(m['a'], min: 0),
        shares: _seatMap(m['shares'], (v) => _int(v, min: 0)),
        winningHand: m['hv'] == null ? null : HandValue(_int(m['hv'], min: 0)),
      ),
    'end' => HandEnded(
        finalStacks: _list(m['stacks'], (v) => _int(v, min: 0)),
        netChange: _seatMap(m['net'], _int),
      ),
    _ => throw FormatException('Unknown event', type),
  };
}

List<GameEvent> decodeEvents(Object? json) => _list(json, decodeEvent);

/// Whether a mirror's events (see mirror.dart) are the server's: the same
/// as JSON, except that the seats who can win each pot may come in any
/// order, and dealt cards are compared only for the seats the server's
/// event has (the only ones this device was sent).
bool sameEvents(List<GameEvent> mirror, List<GameEvent> server) {
  if (mirror.length != server.length) return false;
  for (var i = 0; i < mirror.length; i++) {
    final a = mirror[i], b = server[i];
    if (a is HoleCardsDealt && b is HoleCardsDealt) {
      if (jsonEncode(a.dealOrder) != jsonEncode(b.dealOrder)) return false;
      for (final MapEntry(key: seat, value: cards) in b.cards.entries) {
        final mine = a.cards[seat];
        if (mine == null || jsonEncode(_indices(mine)) != jsonEncode(_indices(cards))) return false;
      }
    } else if (canonicalEvent(a) != canonicalEvent(b)) {
      return false;
    }
  }
  return true;
}

/// [event] as JSON text that is the same for equal events: map keys
/// sorted, and each pot's seats too.
String canonicalEvent(GameEvent event) {
  final json = encodeEvent(event);
  if (event is BetsCollected) {
    json['pots'] = [
      for (final pot in event.pots) [pot.amount, [...pot.eligibleSeats]..sort()],
    ];
  }
  return jsonEncode(_sorted(json));
}

Object? _sorted(Object? json) => switch (json) {
      Map() => {for (final key in json.keys.map((k) => '$k').toList()..sort()) key: _sorted(json[key])},
      List() => [for (final v in json) _sorted(v)],
      _ => json,
    };

// -----------------------------------------------------------------------------
// Encoding
// -----------------------------------------------------------------------------

Map<String, Object?> _bySeat<T>(Map<int, T> bySeat, Object? Function(T) encode) => {
      for (final MapEntry(:key, :value) in bySeat.entries) '$key': encode(value),
    };

List<int> _indices(List<PlayingCard> cards) => [for (final c in cards) c.index];

// -----------------------------------------------------------------------------
// Strict decoding
// -----------------------------------------------------------------------------

Map<String, Object?> _map(Object? json) {
  if (json is! Map) throw FormatException('Expected an object', json);
  final m = <String, Object?>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key is! String) throw FormatException('Keys must be strings', key);
    m[key] = value;
  }
  return m;
}

int _int(Object? json, {int? min}) {
  // JSON numbers may arrive as doubles (on the web): only whole ones count.
  final value = switch (json) {
    int i => i,
    double d when d == d.roundToDouble() && d.abs() < 1e15 => d.toInt(),
    _ => throw FormatException('Expected a whole number', json),
  };
  if (min != null && value < min) throw FormatException('Number out of range', json);
  return value;
}

bool _bool(Object? json) => json is bool ? json : throw FormatException('Expected true or false', json);

/// Tables have up to 8 seats.
int _seat(Object? json) {
  final seat = _int(json, min: 0);
  if (seat > 7) throw FormatException('No such seat', json);
  return seat;
}

PlayingCard _card(Object? json) {
  final index = _int(json, min: 0);
  if (index > 51) throw FormatException('No such card', json);
  return PlayingCard(index);
}

List<PlayingCard> _cards(Object? json, {required int max}) {
  final cards = _list(json, _card);
  if (cards.isEmpty || cards.length > max) throw FormatException('Wrong number of cards', json);
  if (cards.toSet().length != cards.length) throw FormatException('A card is used twice', json);
  return cards;
}

List<PlayingCard> _holeCards(Object? json) {
  final cards = _cards(json, max: 2);
  if (cards.length != 2) throw FormatException('A hand has 2 cards', json);
  return cards;
}

Map<int, List<PlayingCard>> _uniqueCards(Map<int, List<PlayingCard>> bySeat) {
  final all = [for (final cards in bySeat.values) ...cards];
  if (all.toSet().length != all.length) throw const FormatException('A card is used twice');
  return bySeat;
}

List<T> _list<T>(Object? json, T Function(Object?) decode) {
  if (json is! List) throw FormatException('Expected a list', json);
  return List.unmodifiable([for (final v in json) decode(v)]);
}

Map<int, T> _seatMap<T>(Object? json, T Function(Object?) decode) {
  final bySeat = <int, T>{};
  for (final MapEntry(:key, :value) in _map(json).entries) {
    final seat = int.tryParse(key);
    if (seat == null || '$seat' != key) throw FormatException('Expected a seat', key);
    bySeat[_seat(seat)] = decode(value);
  }
  return Map.unmodifiable(bySeat);
}

T _byName<T extends Enum>(List<T> values, Object? json) {
  for (final v in values) {
    if (v.name == json) return v;
  }
  throw FormatException('Unknown name', json);
}
