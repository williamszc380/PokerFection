/// The messages between the app and the game server: JSON text over a
/// WebSocket, one message per frame, each with its type in `t`. Both sides
/// use these classes. The server trusts nothing it is sent: every message
/// is read strictly ([ProtocolError] if anything is off), and the room
/// checks that it is allowed.
///
/// Seats are the server's (see SeatMap for a device's own), cards
/// [PlayingCard.index], chips whole numbers. A room has up to 8 seats
/// ("room seats", as the lobby lists them), some of them empty; each hand
/// is dealt only to the seats taken, in their order ("hand seats": 0 to
/// the number of players - 1, as the engine numbers them). [NextHand]
/// gives the room seat of each hand seat; every message about a hand uses
/// hand seats.
///
/// A player whose connection drops keeps their seat for a while
/// ([OnlineTiming.hold]): their device comes back with [RejoinRoom] and the
/// token it was given, and gets a [Snapshot] of the hand to catch up.
///
/// A player out of chips keeps their seat but isn't dealt in: they watch
/// the hands ([NextHand.you] is null, and they get no hole cards) until
/// they rebuy ([Rebuy], when the host allows it) or the game is over
/// ([GameOver]: back to the lobby).
///
/// Everyone in the room can chat ([Say]), in the lobby and at the table,
/// watching too: the server sends each message to everyone ([ChatLines]),
/// and the last ones to whoever joins or comes back.
///
/// A player may sit out ([SitOut]): they keep their seat and chips but
/// aren't dealt in (they watch, like a player out of chips) until they are
/// back; the server sits out a player who was away through a whole hand,
/// until they come back. The host may remove a player ([RemovePlayer]): they
/// are told why the room ended for them ([CloseReason.removed]), everyone
/// else is told ([PlayerRemoved]), and the room won't let them in again
/// ([JoinError.removed]).
library;

import 'dart:convert';

import '../engine/actions.dart';
import '../engine/cards.dart';
import '../engine/events.dart';
import '../engine/rules.dart';
import 'event_codec.dart';
import 'timing.dart';

/// The version of these messages. A device with another one can't join,
/// nor one with other betting rules ([rulesVersion]).
const protocolVersion = 7;

/// The port a game server listens on unless told otherwise (a host's app
/// takes one of the next few when it is taken). Also where hosts answer
/// devices looking for a room on the local network (UDP).
const gamePort = 47474;

/// The blinds at every online table, in chips (as at a table on the device).
const onlineSmallBlind = 50;
const onlineBigBlind = 100;

/// The bots' names, by room seat.
const onlineBotNames = ['Heidi', 'Alice', 'Bob', 'Charlie', 'David', 'Eve', 'Frank', 'Grace'];

/// The fewest players a hand is dealt to: with fewer, the game waits.
const minPlayers = 2;

/// The bots' styles as sent: BotStyle names, or `random` (picked on the
/// host's device and kept secret).
const botStyleNames = ['random', 'gto', 'tag', 'lag', 'station', 'nit'];

/// The style a bot the host adds starts with.
const defaultBotStyle = 'gto';

/// How much help everyone at the table gets, picked by the host: none,
/// Simple training or Advanced training (worked out on each device).
enum HelpLevel { none, simple, advanced }

/// Why the server refused a message. Nothing changed; after [illegal] the
/// turn stays open.
enum Rejection { stale, notYourTurn, illegal, notHost, badMessage, rateLimited }

/// Why creating, joining or rejoining a room failed (the connection then
/// closes): [roomGone] when the room closed while the device was away,
/// [seatGone] when it was away too long and someone else may have the seat,
/// [removed] when the host removed this player (or this device's) from it.
enum JoinError { upgrade, roomNotFound, tableFull, rateLimited, serverFull, internal, roomGone, seatGone, removed }

/// Why the server ends a connection, or the whole room ([removed]: the host
/// removed this player).
enum CloseReason { serverRestart, roomClosed, idle, replaced, roomError, removed }

/// Who plays a seat: a person, a bot the host added, or nobody.
enum SeatKind { human, bot, empty }

/// Whether a person is still at the table. One who is [away] (their
/// connection dropped) keeps the seat for a while, and the server checks or
/// folds for them after a few seconds; one who [left] (or stayed away too
/// long) gives it up: the server plays their turns and the seat is empty
/// from the next hand.
enum SeatStatus { connected, away, left }

/// What everyone at the table is told about: a player pressed Show GTO,
/// or looked at another player's cards.
enum NoticeKind { help, peek }

/// Who chose an action: the player (or for a bot, the host's device), or
/// the server, when time ran out, the player was away or had left, or the
/// host was away (then the bots check, else fold).
enum ActCause { act, timeout, away, left, hostAway }

/// The lobby before the first hand, then the game (and the lobby again once
/// it is over: see [GameOver]).
enum RoomPhase { lobby, playing }

/// A message that can't be read, or breaks the rules of the protocol.
class ProtocolError implements Exception {
  const ProtocolError(this.message);
  final String message;

  @override
  String toString() => 'ProtocolError: $message';
}

/// Whether [rune] may be shown as sent: not a control or text-direction
/// character (which could hide or reorder what others see), nor half of a
/// character.
bool _printable(int rune) =>
    rune >= 0x20 &&
    !(rune >= 0x7F && rune <= 0x9F) &&
    rune != 0x061C &&
    rune != 0x200E &&
    rune != 0x200F &&
    !(rune >= 0x2028 && rune <= 0x202E) &&
    !(rune >= 0x2066 && rune <= 0x2069) &&
    !(rune >= 0xD800 && rune <= 0xDFFF);

/// [text] trimmed, with only [_printable] characters (line breaks and tabs
/// become spaces), and at most [max] characters. Null if nothing is left.
String? _cleanText(String text, int max) {
  final kept = text.runes
      .map((r) => r == 0x09 || r == 0x0A || r == 0x0D || r == 0x2028 || r == 0x2029 ? 0x20 : r)
      .where(_printable);
  final clean = String.fromCharCodes(kept).trim();
  if (clean.isEmpty) return null;
  final runes = clean.runes.toList();
  return runes.length <= max ? clean : String.fromCharCodes(runes.take(max)).trim();
}

/// A player's name as shown at the table: trimmed, without control or
/// text-direction characters, at most 16 characters. Null if nothing is left.
String? cleanName(String name) => _cleanText(name, 16);

/// The most characters in a chat message, the messages a room keeps (sent
/// to whoever joins or comes back), and how many one player may send in
/// [OnlineTiming.chatWindow].
const chatMaxLength = 256;
const chatKept = 64;
const chatBurst = 4;

/// A chat message as everyone sees it: on one line, trimmed, without
/// control or text-direction characters, at most [chatMaxLength]
/// characters. Null if nothing is left.
String? cleanChat(String text) => _cleanText(text, chatMaxLength);

/// The table the host sets up.
class RoomSettings {
  const RoomSettings({
    this.seats = 8,
    this.stackBb = 100,
    this.ante = 0,
    this.raiseRule = RaiseRule.standard,
    this.resetStacks = false,
    this.rebuys = false,
    this.help = HelpLevel.none,
    this.turnLimit = OnlineTiming.defaultTurnLimit,
    this.showStyles = false,
    this.showCards = false,
  });

  /// Seats at the table, 2 to 8: the most players. Seats nobody takes
  /// stay empty (the host can add bots to them).
  final int seats;

  /// Everyone's starting stack, in big blinds.
  final int stackBb;

  /// Ante per player, in chips (up to one big blind).
  final int ante;
  final RaiseRule raiseRule;
  final bool resetStacks;

  /// A person out of chips may buy in again for the starting stack (bots
  /// do it by themselves). Without, whoever runs out is out of the game,
  /// which ends when one player has every chip.
  final bool rebuys;
  final HelpLevel help;

  /// Seconds for each decision, or 0 for no limit (see
  /// [OnlineTiming.turnLimits]).
  final int turnLimit;

  /// Everyone sees the bots' styles (the host always does).
  final bool showStyles;

  /// Players may look at another player's cards during a hand (everyone
  /// is told when they do).
  final bool showCards;

  int get startingStack => stackBb * onlineBigBlind;

  /// Whether [other] is the same table: seats, stacks and rules, which
  /// only change in the lobby.
  bool sameTable(RoomSettings other) =>
      seats == other.seats &&
      stackBb == other.stackBb &&
      ante == other.ante &&
      raiseRule == other.raiseRule &&
      resetStacks == other.resetStacks &&
      rebuys == other.rebuys;

  RoomSettings copyWith({
    int? seats,
    int? stackBb,
    int? ante,
    RaiseRule? raiseRule,
    bool? resetStacks,
    bool? rebuys,
    HelpLevel? help,
    int? turnLimit,
    bool? showStyles,
    bool? showCards,
  }) => RoomSettings(
    seats: seats ?? this.seats,
    stackBb: stackBb ?? this.stackBb,
    ante: ante ?? this.ante,
    raiseRule: raiseRule ?? this.raiseRule,
    resetStacks: resetStacks ?? this.resetStacks,
    rebuys: rebuys ?? this.rebuys,
    help: help ?? this.help,
    turnLimit: turnLimit ?? this.turnLimit,
    showStyles: showStyles ?? this.showStyles,
    showCards: showCards ?? this.showCards,
  );

  @override
  bool operator ==(Object other) =>
      other is RoomSettings &&
      sameTable(other) &&
      help == other.help &&
      turnLimit == other.turnLimit &&
      showStyles == other.showStyles &&
      showCards == other.showCards;

  @override
  int get hashCode =>
      Object.hash(seats, stackBb, ante, raiseRule, resetStacks, rebuys, help, turnLimit, showStyles, showCards);

  Map<String, Object?> toJson() => {
    'seats': seats,
    'stackBb': stackBb,
    'ante': ante,
    'raiseRule': raiseRule.name,
    'resetStacks': resetStacks,
    'rebuys': rebuys,
    'help': help.name,
    'turnLimit': turnLimit,
    'showStyles': showStyles,
    'showCards': showCards,
  };

  factory RoomSettings.fromJson(Object? json) {
    final m = _Json(json);
    final turnLimit = m.integer('turnLimit');
    if (!OnlineTiming.turnLimits.contains(turnLimit)) throw const ProtocolError('No such time limit');
    return RoomSettings(
      seats: m.integer('seats', min: 2, max: 8),
      stackBb: m.integer('stackBb', min: 1, max: 1000),
      ante: m.integer('ante', min: 0, max: onlineBigBlind),
      raiseRule: m.named('raiseRule', RaiseRule.values),
      resetStacks: m.boolean('resetStacks'),
      rebuys: m.boolean('rebuys'),
      help: m.named('help', HelpLevel.values),
      turnLimit: turnLimit,
      showStyles: m.boolean('showStyles'),
      showCards: m.boolean('showCards'),
    );
  }
}

/// One seat of the table, as the lobby and the seat badges show it.
class SeatInfo {
  const SeatInfo({
    required this.seat,
    required this.kind,
    this.name = '',
    this.status = SeatStatus.connected,
    this.style,
    this.joining,
    this.leaving = false,
    this.out = false,
    this.sittingOut = false,
    this.chips,
  });

  /// The room seat.
  final int seat;
  final SeatKind kind;

  /// Who sits here (empty for an empty seat).
  final String name;
  final SeatStatus status;

  /// A bot's style (see [botStyleNames]); only sent to the host, or to
  /// everyone when styles are shown.
  final String? style;

  /// The name of a person (or bot) who takes this seat from the next hand.
  final String? joining;

  /// The host took this bot away, or removed this player (who leaves when
  /// the hand ends): the seat is empty from the next hand.
  final bool leaving;

  /// Out of chips: not dealt in (a person watches) until they rebuy or the
  /// game ends.
  final bool out;

  /// The player sits out: not dealt in (from the next hand) until they are
  /// back; they keep the seat and their chips.
  final bool sittingOut;

  /// During the game, the seat's chips between hands (as the last hand
  /// ended, or the next one starts); null for the starting stack. For the
  /// seats not in the hand being played: those who sit out, or come back.
  final int? chips;

  bool get isEmpty => kind == SeatKind.empty;

  Map<String, Object?> toJson() => {
    's': seat,
    'kind': kind.name,
    if (kind != SeatKind.empty) 'name': name,
    if (status != SeatStatus.connected) 'status': status.name,
    'style': ?style,
    'joining': ?joining,
    if (leaving) 'leaving': true,
    if (out) 'out': true,
    if (sittingOut) 'sittingOut': true,
    'chips': ?chips,
  };

  factory SeatInfo.fromJson(Object? json) {
    final m = _Json(json);
    final kind = m.named('kind', SeatKind.values);
    return SeatInfo(
      seat: m.seat('s'),
      kind: kind,
      name: kind == SeatKind.empty ? '' : m.name('name'),
      status: m.has('status') ? m.named('status', SeatStatus.values) : SeatStatus.connected,
      style: m.has('style') ? m.style('style') : null,
      joining: m.has('joining') ? m.name('joining') : null,
      leaving: m.has('leaving') && m.boolean('leaving'),
      out: m.has('out') && m.boolean('out'),
      sittingOut: m.has('sittingOut') && m.boolean('sittingOut'),
      chips: m.optionalInteger('chips', min: 0),
    );
  }
}

/// Whose turn it is, with what choices, and how long they have.
class Turn {
  const Turn({
    required this.turnId,
    required this.seat,
    required this.ms,
    required this.waitMs,
    required this.toCall,
    required this.canRaise,
    required this.minRaiseTo,
    required this.maxRaiseTo,
  });

  factory Turn.of(int turnId, int seat, LegalActions legal, {required int? ms, required int waitMs}) => Turn(
    turnId: turnId,
    seat: seat,
    ms: ms,
    waitMs: waitMs,
    toCall: legal.toCall,
    canRaise: legal.canRaise,
    minRaiseTo: legal.minRaiseTo,
    maxRaiseTo: legal.maxRaiseTo,
  );

  /// Counts the turns of a hand, so a move is only taken once, for the
  /// turn it was made at.
  final int turnId;
  final int seat;

  /// The time to decide, in milliseconds, once the actions before have
  /// been shown ([waitMs]); null for no limit. Sent as time left, so the
  /// devices' clocks don't need to agree.
  final int? ms;

  /// The time given to show the actions before this turn.
  final int waitMs;

  final int toCall;
  final bool canRaise;
  final int minRaiseTo;
  final int maxRaiseTo;

  /// The same turn with [ms] left to decide and nothing to watch first
  /// (for a device that catches up: see [Snapshot]).
  Turn resumed(int? ms) => Turn(
    turnId: turnId,
    seat: seat,
    ms: ms,
    waitMs: 0,
    toCall: toCall,
    canRaise: canRaise,
    minRaiseTo: minRaiseTo,
    maxRaiseTo: maxRaiseTo,
  );

  /// Whether a device's own copy of the hand gives the same choices.
  bool matches(LegalActions legal) =>
      legal.toCall == toCall &&
      legal.canRaise == canRaise &&
      legal.minRaiseTo == minRaiseTo &&
      legal.maxRaiseTo == maxRaiseTo;

  Map<String, Object?> toJson() => {
    'turnId': turnId,
    's': seat,
    'ms': ms,
    'waitMs': waitMs,
    'legal': {'toCall': toCall, 'canRaise': canRaise, 'minRaiseTo': minRaiseTo, 'maxRaiseTo': maxRaiseTo},
  };

  factory Turn.fromJson(Object? json) {
    final m = _Json(json);
    final legal = m.object('legal');
    return Turn(
      turnId: m.integer('turnId', min: 1),
      seat: m.seat('s'),
      ms: m.optionalInteger('ms', min: 0),
      waitMs: m.integer('waitMs', min: 0),
      toCall: legal.integer('toCall', min: 0),
      canRaise: legal.boolean('canRaise'),
      minRaiseTo: legal.integer('minRaiseTo', min: 0),
      maxRaiseTo: legal.integer('maxRaiseTo', min: 0),
    );
  }
}

Map<String, Object?> _encodeAction(PlayerAction a) => {
  'k': a.type.name,
  if (a.type == ActionType.raise) 'to': a.amount,
};

PlayerAction _decodeAction(_Json m) => switch (m.named('k', ActionType.values)) {
  ActionType.fold => const PlayerAction.fold(),
  ActionType.check => const PlayerAction.check(),
  ActionType.call => const PlayerAction.call(),
  ActionType.raise => PlayerAction.raiseTo(m.integer('to', min: 1)),
};

// -----------------------------------------------------------------------------
// From the app to the server
// -----------------------------------------------------------------------------

/// A message from a device to the server.
sealed class ClientMessage {
  const ClientMessage();

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  /// The message in [text]; throws [ProtocolError] if it isn't one.
  static ClientMessage decode(String text) {
    final m = _Json.parse(text);
    return switch (m.string('t')) {
      'create' => CreateRoom(
        version: m.integer('v'),
        rules: m.integer('rules'),
        name: m.name('name'),
        settings: RoomSettings.fromJson(m['settings']),
        bots: m.has('bots') ? m.seatMap('bots', (v) => _Json.styleOf(v)) : const {},
      ),
      'join' => JoinRoom(
        version: m.integer('v'),
        rules: m.integer('rules'),
        code: m.string('code', maxLength: 16),
        name: m.name('name'),
        device: m.has('device') ? m.string('device') : null,
      ),
      'rejoin' => RejoinRoom(
        version: m.integer('v'),
        rules: m.integer('rules'),
        code: m.string('code', maxLength: 16),
        token: m.string('token', maxLength: 64),
      ),
      'resync' => const Resync(),
      'settings' => ChangeSettings(
        settings: m.has('settings') ? RoomSettings.fromJson(m['settings']) : null,
        botStyles: m.has('botStyles') ? m.seatMap('botStyles', (v) => _Json.styleOf(v)) : null,
      ),
      'start' => const StartGame(),
      'addBot' => AddBot(style: m.style('style'), seat: m.has('s') ? m.seat('s') : null),
      'removeBot' => RemoveBot(m.seat('s')),
      'usedHelp' => UsedHelp(hand: m.integer('hand', min: 1), turnId: m.integer('turnId', min: 1)),
      'peek' => Peek(hand: m.integer('hand', min: 1), seat: m.seat('s')),
      'show' => ShowCards(hand: m.integer('hand', min: 1)),
      'act' => Act(
        hand: m.integer('hand', min: 1),
        turnId: m.integer('turnId', min: 1),
        action: _decodeAction(m.object('a')),
      ),
      'botAct' => BotAct(
        hand: m.integer('hand', min: 1),
        turnId: m.integer('turnId', min: 1),
        seat: m.seat('s'),
        action: _decodeAction(m.object('a')),
      ),
      'ready' => Ready(m.integer('hand', min: 1)),
      'rebuy' => const Rebuy(),
      'sitOut' => SitOut(m.boolean('on')),
      'removePlayer' => RemovePlayer(seat: m.seat('s'), name: m.name('name')),
      'say' => Say(m.chat('text')),
      'leave' => const Leave(),
      'close' => const CloseRoom(),
      'ping' => Ping(m.integer('n')),
      final type => throw ProtocolError('Unknown message $type'),
    };
  }
}

/// Opens a room: the sender becomes its host, in seat 0. The other seats
/// are empty, but for [bots].
class CreateRoom extends ClientMessage {
  const CreateRoom({
    this.version = protocolVersion,
    this.rules = rulesVersion,
    required this.name,
    this.settings = const RoomSettings(),
    this.bots = const {},
  });

  final int version;
  final int rules;
  final String name;
  final RoomSettings settings;

  /// Bots to seat at once, with their styles, by room seat (see
  /// [botStyleNames]). Seat 0 is the host's.
  final Map<int, String> bots;

  @override
  Map<String, Object?> toJson() => {
    't': 'create',
    'v': version,
    'rules': rules,
    'name': name,
    'settings': settings.toJson(),
    if (bots.isNotEmpty) 'bots': {for (final MapEntry(:key, :value) in bots.entries) '$key': value},
  };
}

/// Takes an empty seat in a room: at once in the lobby, from the next hand
/// during the game.
class JoinRoom extends ClientMessage {
  const JoinRoom({
    this.version = protocolVersion,
    this.rules = rulesVersion,
    required this.code,
    required this.name,
    this.device,
  });

  final int version;
  final int rules;
  final String code;
  final String name;

  /// A random key the app keeps (it says nothing else about the device): a
  /// device the host removed a player from can't join that room again.
  final String? device;

  @override
  Map<String, Object?> toJson() => {
    't': 'join',
    'v': version,
    'rules': rules,
    'code': code,
    'name': name,
    'device': ?device,
  };
}

/// Comes back to a room after the connection dropped (or the app was
/// closed), with the [token] the server gave: the seat is the player's
/// again if they weren't away too long, and they get a [Snapshot] to catch
/// up. Replaces any older connection of theirs.
class RejoinRoom extends ClientMessage {
  const RejoinRoom({
    this.version = protocolVersion,
    this.rules = rulesVersion,
    required this.code,
    required this.token,
  });

  final int version;
  final int rules;
  final String code;
  final String token;

  @override
  Map<String, Object?> toJson() => {'t': 'rejoin', 'v': version, 'rules': rules, 'code': code, 'token': token};
}

/// The device's copy of the hand stopped matching the server's: it asks
/// for a fresh one (a [Snapshot]; at most every [OnlineTiming.resyncGap]).
class Resync extends ClientMessage {
  const Resync();

  @override
  Map<String, Object?> toJson() => {'t': 'resync'};
}

/// The host changes the table: in the lobby at once; during the game, from
/// the next hand, and only the help, the time limit, what players may see
/// and the bots' styles.
class ChangeSettings extends ClientMessage {
  const ChangeSettings({this.settings, this.botStyles});

  final RoomSettings? settings;

  /// Only the (room) seats of bots whose style changes.
  final Map<int, String>? botStyles;

  @override
  Map<String, Object?> toJson() => {
    't': 'settings',
    if (settings != null) 'settings': settings!.toJson(),
    if (botStyles != null) 'botStyles': {for (final MapEntry(:key, :value) in botStyles!.entries) '$key': value},
  };
}

/// The host starts the game (with at least [minPlayers] seats taken).
class StartGame extends ClientMessage {
  const StartGame();

  @override
  Map<String, Object?> toJson() => {'t': 'start'};
}

/// The host seats a bot with [style]: in room seat [seat], or the first
/// empty one. At once in the lobby, from the next hand during the game.
class AddBot extends ClientMessage {
  const AddBot({this.style = defaultBotStyle, this.seat});

  final String style;
  final int? seat;

  @override
  Map<String, Object?> toJson() => {'t': 'addBot', 'style': style, 's': ?seat};
}

/// The host takes the bot in room seat [seat] away (during the game, from
/// the next hand).
class RemoveBot extends ClientMessage {
  const RemoveBot(this.seat);
  final int seat;

  @override
  Map<String, Object?> toJson() => {'t': 'removeBot', 's': seat};
}

/// The player pressed Show GTO at turn [turnId] of hand [hand]: everyone
/// is told.
class UsedHelp extends ClientMessage {
  const UsedHelp({required this.hand, required this.turnId});

  final int hand;
  final int turnId;

  @override
  Map<String, Object?> toJson() => {'t': 'usedHelp', 'hand': hand, 'turnId': turnId};
}

/// The player asks to see the cards of hand seat [seat] in hand [hand]
/// (when the host allows it): they get [PeekCards], everyone a [Notice].
class Peek extends ClientMessage {
  const Peek({required this.hand, required this.seat});

  final int hand;
  final int seat;

  @override
  Map<String, Object?> toJson() => {'t': 'peek', 'hand': hand, 's': seat};
}

/// Once hand [hand] is over (until the next is dealt), the player shows
/// their own cards to everyone: they all get [CardsShown].
class ShowCards extends ClientMessage {
  const ShowCards({required this.hand});

  final int hand;

  @override
  Map<String, Object?> toJson() => {'t': 'show', 'hand': hand};
}

/// A player's move at turn [turnId] of hand [hand].
class Act extends ClientMessage {
  const Act({required this.hand, required this.turnId, required this.action});

  final int hand;
  final int turnId;
  final PlayerAction action;

  @override
  Map<String, Object?> toJson() => {'t': 'act', 'hand': hand, 'turnId': turnId, 'a': _encodeAction(action)};
}

/// The host's device plays a bot's move (for hand seat [seat]).
class BotAct extends ClientMessage {
  const BotAct({required this.hand, required this.turnId, required this.seat, required this.action});

  final int hand;
  final int turnId;
  final int seat;
  final PlayerAction action;

  @override
  Map<String, Object?> toJson() => {
    't': 'botAct',
    'hand': hand,
    'turnId': turnId,
    's': seat,
    'a': _encodeAction(action),
  };
}

/// The device has shown the last hand (and solved the next one, if it
/// needs to): hand [hand] can be dealt.
class Ready extends ClientMessage {
  const Ready(this.hand);
  final int hand;

  @override
  Map<String, Object?> toJson() => {'t': 'ready', 'hand': hand};
}

/// Out of chips, when the host allows rebuys: buys in again for the
/// starting stack, from the next hand.
class Rebuy extends ClientMessage {
  const Rebuy();

  @override
  Map<String, Object?> toJson() => {'t': 'rebuy'};
}

/// Sits out ([on]: not dealt in from the next hand announced, keeping the
/// seat and chips), or is back (dealt in again from the next hand).
class SitOut extends ClientMessage {
  const SitOut(this.on);
  final bool on;

  @override
  Map<String, Object?> toJson() => {'t': 'sitOut', 'on': on};
}

/// The host removes the player in room seat [seat] ([name], so nobody else
/// is removed if the seat changed hands meanwhile): at once, or when the
/// hand they play ends. They can't join the room again.
class RemovePlayer extends ClientMessage {
  const RemovePlayer({required this.seat, required this.name});

  final int seat;
  final String name;

  @override
  Map<String, Object?> toJson() => {'t': 'removePlayer', 's': seat, 'name': name};
}

/// Says [text] to everyone in the room (read with [cleanChat]; at most
/// [chatBurst] messages each [OnlineTiming.chatWindow]).
class Say extends ClientMessage {
  const Say(this.text);
  final String text;

  @override
  Map<String, Object?> toJson() => {'t': 'say', 'text': text};
}

/// Gives up the seat now.
class Leave extends ClientMessage {
  const Leave();

  @override
  Map<String, Object?> toJson() => {'t': 'leave'};
}

/// The host closes the room for everyone.
class CloseRoom extends ClientMessage {
  const CloseRoom();

  @override
  Map<String, Object?> toJson() => {'t': 'close'};
}

/// Says the device is still there (answered with [Pong]).
class Ping extends ClientMessage {
  const Ping(this.n);
  final int n;

  @override
  Map<String, Object?> toJson() => {'t': 'ping', 'n': n};
}

// -----------------------------------------------------------------------------
// From the server to the app
// -----------------------------------------------------------------------------

/// A message from the server to a device.
sealed class ServerMessage {
  const ServerMessage();

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  /// The message in [text]; throws [ProtocolError] if it isn't one.
  static ServerMessage decode(String text) {
    final m = _Json.parse(text);
    return switch (m.string('t')) {
      'welcome' => Welcome(
        code: m.string('code', maxLength: 16),
        token: m.string('token', maxLength: 64),
        seat: m.seat('s'),
        isHost: m.boolean('isHost'),
        waiting: m.boolean('waiting'),
      ),
      'room' => RoomState(
        code: m.string('code', maxLength: 16),
        phase: m.named('phase', RoomPhase.values),
        paused: m.has('paused') && m.boolean('paused'),
        host: m.has('host') ? m.seat('host') : null,
        you: m.has('you') ? m.seat('you') : null,
        settings: RoomSettings.fromJson(m['settings']),
        seats: m.list('seats', SeatInfo.fromJson),
      ),
      'botCards' => BotCards(hand: m.integer('hand', min: 1), cards: m.seatMap('cards', _Json.holeCards)),
      'hand' => HandDealt(
        hand: m.integer('hand', min: 1),
        batch: m.events('batch'),
        turn: m['turn'] == null ? null : Turn.fromJson(m['turn']),
      ),
      'events' => HandEvents(
        hand: m.integer('hand', min: 1),
        turnId: m.integer('turnId', min: 1),
        cause: m.named('cause', ActCause.values),
        batch: m.events('batch'),
        turn: m['turn'] == null ? null : Turn.fromJson(m['turn']),
      ),
      'next' => NextHand._fromJson(m),
      'snapshot' => Snapshot(
        hand: m['hand'] == null ? null : SnapshotHand._fromJson(m.object('hand')),
        next: m['next'] == null ? null : NextHand._fromJson(m.object('next')),
      ),
      'peekCards' => PeekCards(hand: m.integer('hand', min: 1), seat: m.seat('s'), cards: _Json.holeCards(m['cards'])),
      'shown' => CardsShown(hand: m.integer('hand', min: 1), seat: m.seat('s'), cards: _Json.holeCards(m['cards'])),
      'notice' => Notice(
        kind: m.named('kind', NoticeKind.values),
        hand: m.integer('hand', min: 1),
        seat: m.seat('s'),
        name: m.name('name'),
        target: m.has('target') ? m.seat('target') : null,
        targetName: m.has('targetName') ? m.name('targetName') : null,
      ),
      'gameOver' => GameOver(seat: m.has('s') ? m.seat('s') : null, name: m.has('name') ? m.name('name') : null),
      'removed' => PlayerRemoved(seat: m.seat('s'), name: m.name('name')),
      'chat' => ChatLines(m.list('lines', ChatLine.fromJson), all: m.boolean('all')),
      'rejected' => Rejected(m.named('reason', Rejection.values), turnId: m.optionalInteger('turnId')),
      'error' => ServerError(m.named('code', JoinError.values)),
      'closing' => Closing(m.named('reason', CloseReason.values)),
      'pong' => Pong(m.integer('n')),
      final type => throw ProtocolError('Unknown message $type'),
    };
  }
}

/// Who this connection is: the room, a token that proves it, the seat.
class Welcome extends ServerMessage {
  const Welcome({
    required this.code,
    required this.token,
    required this.seat,
    required this.isHost,
    this.waiting = false,
  });

  final String code;
  final String token;
  final int seat;
  final bool isHost;

  /// Joined during the game: the seat is the player's from the next hand.
  final bool waiting;

  @override
  Map<String, Object?> toJson() => {
    't': 'welcome',
    'code': code,
    'token': token,
    's': seat,
    'isHost': isHost,
    'waiting': waiting,
  };
}

/// Everyone at the table and the host's settings, sent again whenever
/// anything changes.
class RoomState extends ServerMessage {
  const RoomState({
    required this.code,
    required this.phase,
    this.paused = false,
    required this.host,
    required this.you,
    required this.settings,
    required this.seats,
  });

  final String code;
  final RoomPhase phase;

  /// During the game, between hands: fewer than [minPlayers] can play
  /// (people still connected, and bots while the host is), so no hand is
  /// dealt until someone joins or comes back (or the host adds a bot).
  final bool paused;

  /// The host's seat (its status says when the host is away; the room
  /// closes when the host leaves).
  final int? host;

  /// The seat of the player this is sent to (it can move in the lobby,
  /// when the host takes seats away).
  final int? you;

  /// During the game, with the host's changes for the next hand.
  final RoomSettings settings;

  /// Every seat of the table, by room seat (empty ones too).
  final List<SeatInfo> seats;

  /// The seats somebody (or a bot) has.
  int get taken => seats.where((s) => !s.isEmpty).length;

  @override
  Map<String, Object?> toJson() => {
    't': 'room',
    'code': code,
    'phase': phase.name,
    if (paused) 'paused': true,
    'host': ?host,
    'you': ?you,
    'settings': settings.toJson(),
    'seats': [for (final s in seats) s.toJson()],
  };
}

/// The bots' cards, to the host's device only (which plays them), before
/// the hand is dealt.
class BotCards extends ServerMessage {
  const BotCards({required this.hand, required this.cards});

  final int hand;
  final Map<int, List<PlayingCard>> cards;

  @override
  Map<String, Object?> toJson() => {'t': 'botCards', 'hand': hand, 'cards': _encodeCards(cards)};
}

/// A new hand: its first events (up to the hole cards, only the
/// player's own; to the end when the blinds put everyone all-in), and
/// the first turn.
class HandDealt extends ServerMessage {
  const HandDealt({required this.hand, required this.batch, required this.turn});

  final int hand;
  final List<GameEvent> batch;
  final Turn? turn;

  @override
  Map<String, Object?> toJson() => {'t': 'hand', 'hand': hand, 'batch': encodeEvents(batch), 'turn': turn?.toJson()};
}

/// One action and everything it led to (the board dealt, hands shown,
/// pots paid), the same for everyone, and the next turn (null once the
/// hand is over).
class HandEvents extends ServerMessage {
  const HandEvents({
    required this.hand,
    required this.turnId,
    required this.cause,
    required this.batch,
    required this.turn,
  });

  final int hand;

  /// The turn this action ended.
  final int turnId;
  final ActCause cause;
  final List<GameEvent> batch;
  final Turn? turn;

  @override
  Map<String, Object?> toJson() => {
    't': 'events',
    'hand': hand,
    'turnId': turnId,
    'cause': cause.name,
    'batch': encodeEvents(batch),
    'turn': turn?.toJson(),
  };
}

/// The next hand, fixed as soon as the last one ends: who plays it, with
/// what stacks, and when it is dealt (between [minWaitMs] and
/// [maxWaitMs] from now, once every device is [Ready]). The number of
/// players can change from one hand to the next.
class NextHand extends ServerMessage {
  const NextHand({
    required this.hand,
    required this.button,
    this.you,
    required this.stacks,
    required this.seats,
    required this.help,
    required this.turnLimit,
    this.showCards = false,
    required this.minWaitMs,
    required this.maxWaitMs,
  });

  final int hand;

  /// The button's hand seat.
  final int button;

  /// The hand seat of the player this is sent to; null for a player out of
  /// chips, who watches.
  final int? you;

  /// Everyone's stack, by hand seat.
  final List<int> stacks;

  /// The players, by hand seat; [SeatInfo.seat] is each one's room seat.
  final List<SeatInfo> seats;
  final HelpLevel help;

  /// Seconds for each decision (0: no limit).
  final int turnLimit;

  /// Players may look at another player's cards in this hand.
  final bool showCards;
  final int minWaitMs;
  final int maxWaitMs;

  /// Read strictly, if its line-up makes a hand: 2 to 8 players, each with
  /// a stack, in different room seats, and the button and the player (when
  /// not watching) among them.
  factory NextHand._fromJson(_Json m) {
    final next = NextHand(
      hand: m.integer('hand', min: 1),
      button: m.seat('button'),
      you: m.has('you') ? m.seat('you') : null,
      stacks: m.list('stacks', (v) => _Json.wholeNumber(v, min: 1)),
      seats: m.list('seats', SeatInfo.fromJson),
      help: m.named('help', HelpLevel.values),
      turnLimit: m.integer('turnLimit', min: 0),
      showCards: m.boolean('showCards'),
      minWaitMs: m.integer('minWaitMs', min: 0),
      maxWaitMs: m.integer('maxWaitMs', min: 0),
    );
    final n = next.seats.length;
    if (n < minPlayers || n > 8 || next.stacks.length != n) throw const ProtocolError('Not a line-up');
    if (next.button >= n || (next.you ?? 0) >= n) throw const ProtocolError('Seat out of range');
    final rooms = {for (final s in next.seats) s.seat};
    if (rooms.length != n || next.seats.any((s) => s.isEmpty)) throw const ProtocolError('Not a line-up');
    return next;
  }

  /// The same, to be dealt (at the earliest and latest) [minWaitMs] and
  /// [maxWaitMs] from now.
  NextHand waiting({required int minWaitMs, required int maxWaitMs}) => NextHand(
    hand: hand,
    button: button,
    you: you,
    stacks: stacks,
    seats: seats,
    help: help,
    turnLimit: turnLimit,
    showCards: showCards,
    minWaitMs: minWaitMs,
    maxWaitMs: maxWaitMs,
  );

  @override
  Map<String, Object?> toJson() => {
    't': 'next',
    'hand': hand,
    'button': button,
    'you': ?you,
    'stacks': stacks,
    'seats': [for (final s in seats) s.toJson()],
    'help': help.name,
    'turnLimit': turnLimit,
    'showCards': showCards,
    'minWaitMs': minWaitMs,
    'maxWaitMs': maxWaitMs,
  };
}

/// Everything a device needs to catch up after its connection dropped (or
/// its copy of the hand stopped matching): the hand it is in or watches (or
/// the last one, if the next isn't dealt yet), and the next hand if it is
/// announced.
/// Sent after the [Welcome] and [RoomState] of a [RejoinRoom], and for a
/// [Resync]. A player waiting for a seat gets neither.
class Snapshot extends ServerMessage {
  const Snapshot({this.hand, this.next});

  final SnapshotHand? hand;
  final NextHand? next;

  @override
  Map<String, Object?> toJson() => {'t': 'snapshot', 'hand': hand?.toJson(), 'next': next?.toJson()};
}

/// A hand so far, as one player may see it: the line-up it was announced
/// with ([lineup], waits 0), every batch of events (the deal, then one per
/// action; only the player's own hole cards), the open turn with the time
/// left (null once the hand is over), on the host's device the bots' cards,
/// and the cards the player has looked at (see [Peek]).
class SnapshotHand {
  const SnapshotHand({
    required this.lineup,
    required this.batches,
    this.turn,
    this.botCards = const {},
    this.peeks = const {},
  });

  final NextHand lineup;
  final List<List<GameEvent>> batches;
  final Turn? turn;
  final Map<int, List<PlayingCard>> botCards;
  final Map<int, List<PlayingCard>> peeks;

  int get hand => lineup.hand;

  /// The most batches a hand can have, to read (each action makes one).
  static const _maxBatches = 1000;

  Map<String, Object?> toJson() => {
    'lineup': lineup.toJson(),
    'batches': [for (final b in batches) encodeEvents(b)],
    'turn': turn?.toJson(),
    if (botCards.isNotEmpty) 'botCards': _encodeCards(botCards),
    if (peeks.isNotEmpty) 'peeks': _encodeCards(peeks),
  };

  factory SnapshotHand._fromJson(_Json m) {
    final batches = m['batches'];
    if (batches is! List || batches.isEmpty || batches.length > _maxBatches) {
      throw const ProtocolError('Expected the batches of a hand');
    }
    return SnapshotHand(
      lineup: NextHand._fromJson(m.object('lineup')),
      batches: List.unmodifiable([for (final b in batches) _Json.eventList(b)]),
      turn: m['turn'] == null ? null : Turn.fromJson(m['turn']),
      botCards: m.has('botCards') ? m.seatMap('botCards', _Json.holeCards) : const {},
      peeks: m.has('peeks') ? m.seatMap('peeks', _Json.holeCards) : const {},
    );
  }
}

Map<String, Object?> _encodeCards(Map<int, List<PlayingCard>> cards) => {
  for (final MapEntry(:key, :value) in cards.entries) '$key': [for (final c in value) c.index],
};

/// The cards of hand seat [seat] in hand [hand], to the player who asked
/// to see them (see [Peek]) and nobody else.
class PeekCards extends ServerMessage {
  const PeekCards({required this.hand, required this.seat, required this.cards});

  final int hand;
  final int seat;
  final List<PlayingCard> cards;

  @override
  Map<String, Object?> toJson() => {
    't': 'peekCards',
    'hand': hand,
    's': seat,
    'cards': [for (final c in cards) c.index],
  };
}

/// To everyone at the table: the player in room seat [seat] showed their
/// [cards] after hand [hand] (see [ShowCards]).
class CardsShown extends ServerMessage {
  const CardsShown({required this.hand, required this.seat, required this.cards});

  final int hand;
  final int seat;
  final List<PlayingCard> cards;

  @override
  Map<String, Object?> toJson() => {
    't': 'shown',
    'hand': hand,
    's': seat,
    'cards': [for (final c in cards) c.index],
  };
}

/// Told to everyone at the table: the player in room seat [seat] ([name])
/// pressed Show GTO, or looked at the cards of room seat [target]
/// ([targetName]).
class Notice extends ServerMessage {
  const Notice({
    required this.kind,
    required this.hand,
    required this.seat,
    required this.name,
    this.target,
    this.targetName,
  });

  final NoticeKind kind;
  final int hand;
  final int seat;
  final String name;
  final int? target;
  final String? targetName;

  @override
  Map<String, Object?> toJson() => {
    't': 'notice',
    'kind': kind.name,
    'hand': hand,
    's': seat,
    'name': name,
    'target': ?target,
    'targetName': ?targetName,
  };
}

/// Only one player has chips left and nobody can rebuy: the player in room
/// seat [seat] ([name]) won (null when nobody is left). Sent after the last
/// hand's events; the room is back in the lobby with the same seats, bots
/// and rules, for the host to start a new game with fresh stacks.
class GameOver extends ServerMessage {
  const GameOver({this.seat, this.name});

  final int? seat;
  final String? name;

  @override
  Map<String, Object?> toJson() => {'t': 'gameOver', 's': ?seat, 'name': ?name};
}

/// Told to everyone else in the room: the host removed the player in room
/// seat [seat] ([name]), who is gone now.
class PlayerRemoved extends ServerMessage {
  const PlayerRemoved({required this.seat, required this.name});

  final int seat;
  final String name;

  @override
  Map<String, Object?> toJson() => {'t': 'removed', 's': seat, 'name': name};
}

/// One chat message: the [n]th in the room, by [name] ([you]: the player
/// it is sent to), as [cleanChat] leaves it.
class ChatLine {
  const ChatLine({required this.n, required this.name, required this.text, this.you = false});

  final int n;
  final String name;
  final String text;
  final bool you;

  Map<String, Object?> toJson() => {'n': n, 'name': name, 'text': text, if (you) 'you': true};

  factory ChatLine.fromJson(Object? json) {
    final m = _Json(json);
    return ChatLine(
      n: m.integer('n', min: 1),
      name: m.name('name'),
      text: m.chat('text'),
      you: m.has('you') && m.boolean('you'),
    );
  }
}

/// Chat messages, oldest first: each new one as it is said, to everyone in
/// the room; or the room's last [chatKept] ([all]: the whole chat as the
/// room keeps it), to whoever joins or comes back.
class ChatLines extends ServerMessage {
  const ChatLines(this.lines, {this.all = false});

  final List<ChatLine> lines;
  final bool all;

  @override
  Map<String, Object?> toJson() => {
    't': 'chat',
    'lines': [for (final line in lines) line.toJson()],
    'all': all,
  };
}

/// The server refused a message (see [Rejection]).
class Rejected extends ServerMessage {
  const Rejected(this.reason, {this.turnId});

  final Rejection reason;
  final int? turnId;

  @override
  Map<String, Object?> toJson() => {'t': 'rejected', 'reason': reason.name, 'turnId': ?turnId};
}

/// Creating or joining a room failed.
class ServerError extends ServerMessage {
  const ServerError(this.code);
  final JoinError code;

  @override
  Map<String, Object?> toJson() => {'t': 'error', 'code': code.name};
}

/// The connection, or the room, is ending.
class Closing extends ServerMessage {
  const Closing(this.reason);
  final CloseReason reason;

  @override
  Map<String, Object?> toJson() => {'t': 'closing', 'reason': reason.name};
}

class Pong extends ServerMessage {
  const Pong(this.n);
  final int n;

  @override
  Map<String, Object?> toJson() => {'t': 'pong', 'n': n};
}

// -----------------------------------------------------------------------------
// Strict reading
// -----------------------------------------------------------------------------

/// A JSON object read strictly: every getter throws [ProtocolError] for a
/// missing field, a wrong type or a value out of range.
extension type _Json._(Map<String, Object?> _m) {
  factory _Json(Object? json) {
    if (json is! Map) throw const ProtocolError('Expected an object');
    final m = <String, Object?>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key is! String) throw const ProtocolError('Keys must be strings');
      m[key] = value;
    }
    return _Json._(m);
  }

  factory _Json.parse(String text) {
    try {
      return _Json(jsonDecode(text));
    } on FormatException {
      throw const ProtocolError('Not JSON');
    }
  }

  Object? operator [](String key) => _m[key];

  bool has(String key) => _m[key] != null;

  static int wholeNumber(Object? json, {int? min, int? max}) {
    // JSON numbers may arrive as doubles (on the web): only whole ones count.
    final value = switch (json) {
      int i => i,
      double d when d == d.roundToDouble() && d.abs() < 1e15 => d.toInt(),
      _ => throw const ProtocolError('Expected a whole number'),
    };
    if ((min != null && value < min) || (max != null && value > max)) throw const ProtocolError('Number out of range');
    return value;
  }

  int integer(String key, {int? min, int? max}) => wholeNumber(_m[key], min: min, max: max);

  int? optionalInteger(String key, {int? min}) => _m[key] == null ? null : integer(key, min: min);

  int seat(String key) => integer(key, min: 0, max: 7);

  bool boolean(String key) {
    final v = _m[key];
    return v is bool ? v : throw ProtocolError('Expected true or false: $key');
  }

  String string(String key, {int maxLength = 64}) {
    final v = _m[key];
    if (v is! String || v.length > maxLength) throw ProtocolError('Expected a short text: $key');
    return v;
  }

  String name(String key) => cleanName(string(key)) ?? (throw const ProtocolError('Empty name'));

  /// A chat message, cleaned (see [cleanChat]): one a little too long is
  /// cut; one far too long (4 times the most) is refused.
  String chat(String key) =>
      cleanChat(string(key, maxLength: 4 * chatMaxLength)) ?? (throw const ProtocolError('Empty message'));

  String style(String key) => styleOf(_m[key]);

  static String styleOf(Object? json) =>
      json is String && botStyleNames.contains(json) ? json : throw const ProtocolError('No such style');

  T named<T extends Enum>(String key, List<T> values) {
    final v = _m[key];
    for (final value in values) {
      if (value.name == v) return value;
    }
    throw ProtocolError('Unknown $key');
  }

  _Json object(String key) => _Json(_m[key]);

  List<T> list<T>(String key, T Function(Object?) read) {
    final v = _m[key];
    if (v is! List || v.length > 64) throw ProtocolError('Expected a list: $key');
    return List.unmodifiable([for (final item in v) read(item)]);
  }

  Map<int, T> seatMap<T>(String key, T Function(Object?) read) {
    final bySeat = <int, T>{};
    for (final MapEntry(key: seat, :value) in _Json(_m[key])._m.entries) {
      final s = int.tryParse(seat);
      if (s == null || '$s' != seat || s < 0 || s > 7) throw const ProtocolError('Expected a seat');
      bySeat[s] = read(value);
    }
    return Map.unmodifiable(bySeat);
  }

  static List<PlayingCard> holeCards(Object? json) {
    if (json is! List || json.length != 2) throw const ProtocolError('A hand has 2 cards');
    final cards = [for (final c in json) PlayingCard(wholeNumber(c, min: 0, max: 51))];
    if (cards[0] == cards[1]) throw const ProtocolError('A card is used twice');
    return List.unmodifiable(cards);
  }

  List<GameEvent> events(String key) => eventList(_m[key]);

  static List<GameEvent> eventList(Object? json) {
    try {
      return decodeEvents(json);
    } on FormatException catch (e) {
      throw ProtocolError('Bad events: ${e.message}');
    }
  }
}
