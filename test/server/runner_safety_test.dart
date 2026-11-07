// What a game's runner can't do to a room or to the other players: a
// throwing move check never closes the room; the harness finds a view that
// holds another seat's card, a hidden bot's card, or a card nobody was
// dealt; junk moves are refused one by one.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'fake_runner.dart';
import 'runner_harness.dart';

/// High card whose runner can leak in chosen ways, or whose check throws on junk.
class _Game extends HighCardGame {
  _Game({this.seatLeak = false, this.spectatorLeak = false, this.throwingCheck = false});
  final bool seatLeak, spectatorLeak, throwingCheck;

  @override
  GameRunner newRunner(OnlineSetup setup, Random random) =>
      _Runner(super.newRunner(setup, random) as HighCardRunner, this);
}

class _Runner implements GameRunner {
  _Runner(this.inner, this.g);
  final HighCardRunner inner;
  final _Game g;
  List<bool> isBot = const [];

  @override
  void startRound(int round, List<bool> isBot) {
    this.isBot = isBot;
    inner.startRound(round, isBot);
  }

  @override
  bool get roundOver => inner.roundOver;
  @override
  int? get seatToAct => inner.seatToAct;
  @override
  bool get redealt => false;

  @override
  String? check(int seat, String move) {
    // A game's move parser that throws on what it can't read (a plausible bug in a real game's check).
    if (g.throwingCheck && !move.startsWith('$seat:')) throw FormatException('Unreadable move $move');
    return inner.check(seat, move);
  }

  @override
  void act(int seat, String move) => inner.act(seat, move);
  @override
  String autoMove(int seat, {bool absent = false}) => inner.autoMove(seat, absent: absent);
  @override
  int playbackMs(String move) => inner.playbackMs(move);
  @override
  int get openingMs => inner.openingMs;

  @override
  Map<String, Object?> seatView(int seat) {
    final view = inner.seatView(seat);
    if (!g.seatLeak || roundOver) return view;
    final other = (seat + 1) % isBot.length;
    return {...view, 'peek': inner.seatView(other)['card']};
  }

  @override
  Map<String, Object?> spectatorView({required bool seesBots}) =>
      inner.spectatorView(seesBots: seesBots || g.spectatorLeak);
  @override
  Map<String, Object?> roundResult() => inner.roundResult();
  @override
  List<num> get roundScores => inner.roundScores;
}

RunnerHarness _h(_Game game) =>
    RunnerHarness(game, pick: highCardPick, secrets: highCardSecrets, seatViewFrom: highCardSeatViewFrom);

Future<void> _play(RunnerHarness h) async {
  await h.open();
  await h.choose();
  await h.join('Ben', seated: true);
  await h.addBots(1);
  await h.join('Cy');
  await h.start();
  await h.playRounds(3);
}

/// High card whose views also carry the next card of the deck: a card no
/// seat holds (as Fight the Landlord's three bottom cards before the bid,
/// Blackjack's dealer hole card or the shoe's next card).
class _UndealtLeakGame extends HighCardGame {
  @override
  GameRunner newRunner(OnlineSetup setup, Random random) =>
      _UndealtLeakRunner(super.newRunner(setup, random) as HighCardRunner, random);
}

class _UndealtLeakRunner implements GameRunner {
  _UndealtLeakRunner(this.inner, this.random);
  final HighCardRunner inner;
  final Random random;
  String _next = '';

  @override
  void startRound(int round, List<bool> isBot) {
    inner.startRound(round, isBot);
    // An undealt card (one not dealt to anyone this round).
    final dealt = {for (var s = 0; s < isBot.length; s++) inner.seatView(s)['card']};
    _next = highCardDeck.firstWhere((c) => !dealt.contains(c));
  }

  @override
  bool get roundOver => inner.roundOver;
  @override
  int? get seatToAct => inner.seatToAct;
  @override
  bool get redealt => false;
  @override
  String? check(int seat, String move) => inner.check(seat, move);
  @override
  void act(int seat, String move) => inner.act(seat, move);
  @override
  String autoMove(int seat, {bool absent = false}) => inner.autoMove(seat, absent: absent);
  @override
  int playbackMs(String move) => inner.playbackMs(move);
  @override
  int get openingMs => inner.openingMs;
  @override
  Map<String, Object?> seatView(int seat) => {...inner.seatView(seat), 'next': _next};
  @override
  Map<String, Object?> spectatorView({required bool seesBots}) => {
    ...inner.spectatorView(seesBots: seesBots),
    'next': _next,
  };
  @override
  Map<String, Object?> roundResult() => inner.roundResult();
  @override
  List<num> get roundScores => inner.roundScores;
}

void main() {
  test('the harness catches a seat view holding another seat\'s card', () async {
    final h = _h(_Game(seatLeak: true));
    await _play(h);
    expect(h.problems.where((p) => p.contains('view holds seat')), isNotEmpty);
  });

  test('the harness catches a spectators\' view with a bot\'s card, switch off', () async {
    final h = _h(_Game(spectatorLeak: true));
    await _play(h);
    expect(h.problems.where((p) => p.contains('bot seat')), isNotEmpty);
  });

  test('a seated guest\'s unreadable move is refused, and the room goes on (a game check that throws must not '
      'close the room for everyone)', () async {
    final h = _h(_Game(throwingCheck: true));
    await h.open();
    await h.choose();
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy');
    await h.addBots(1);
    ben.autoPlay = false;
    await h.start();
    await h.until(() => ben.state?.turn?.seat == 0, "Ben's turn");
    ben.play('junk');
    await h.settle();
    expect(cy.all<Closing>(), isEmpty, reason: 'one guest\'s junk move closed the room: ${cy.all<Closing>()}');
    expect(ben.lastRejection, Rejection.illegal);
  });

  test("the harness catches a view holding a card nobody was dealt (the deck's next card, a kitty, a dealer's hole "
      'card)', () async {
    final h = RunnerHarness(
      _UndealtLeakGame(),
      pick: highCardPick,
      secrets: highCardSecrets,
      undealt: (runner) => {'"${(runner as _UndealtLeakRunner)._next}"'},
      seatViewFrom: (view, seat) {
        final rebuilt = highCardSeatViewFrom(view, seat);
        return rebuilt == null ? null : {...rebuilt, 'next': view['next']};
      },
    );
    await h.open();
    await h.choose();
    await h.join('Ben', seated: true);
    await h.addBots(1);
    await h.join('Cy');
    await h.start();
    await h.playRounds(5);
    expect(
      h.problems,
      isNotEmpty,
      reason:
          'every seat and every spectator was sent an undealt card in every round, and the harness '
          'found nothing wrong',
    );
  });

  test('the honest High card game passes the undealt-card check (no false alarm)', () async {
    final h = RunnerHarness(
      HighCardGame(),
      pick: highCardPick,
      secrets: highCardSecrets,
      seatViewFrom: highCardSeatViewFrom,
      undealt: (runner) => highCardUndealt(runner as HighCardRunner),
    );
    await _play(h);
    h.expectClean();
  });

  test(
    "junk moves at a seat's turn are refused one by one and never close the room (a check that throws, too)",
    () async {
      for (final game in [_Game(), _Game(throwingCheck: true)]) {
        final h = _h(game);
        await h.open();
        await h.choose();
        final ben = await h.join('Ben', seated: true);
        await h.join('Cy');
        await h.addBots(1);
        await h.start();
        await h.expectJunkRefused(ben);
        await h.playRounds(1);
        h.expectClean();
      }
    },
  );
}
