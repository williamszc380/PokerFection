import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart' show Play;
import 'package:pokerfection/src/games/big_two/online/big_two_runner.dart';
import 'package:pokerfection/src/games/big_two/online/big_two_view_codec.dart';
import 'package:pokerfection/src/games/blackjack/online/blackjack_runner.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart' show AllPassRule, BiddingStyle, DdzRules;
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_runner.dart';
import 'package:pokerfection/src/games/doudizhu/online/doudizhu_view_codec.dart';
import 'package:pokerfection/src/games/gomoku/online/gomoku_runner.dart';
import 'package:pokerfection/src/online/games/game_runner.dart';
import 'package:pokerfection/src/online/protocol.dart';

import 'runner_harness.dart';

/// Probes across the four games' online parts: what happens when nobody at
/// the table is there (every turn played by the room's auto move), and
/// moves at the edge of each game's notation at every phase.

/// Plays round 1 of [runner] for [seats] people with nothing but the
/// room's auto move, checking each against the runner; how many moves it
/// took, or null if it hadn't ended after [limit].
int? _autoOnly(GameRunner runner, int seats, {int limit = 3000}) {
  runner.startRound(1, List.filled(seats, false));
  for (var n = 0; n < limit; n++) {
    if (runner.roundOver) return n;
    final seat = runner.seatToAct!;
    final move = runner.autoMove(seat);
    expect(runner.check(seat, move), isNull, reason: 'auto move $move');
    runner.act(seat, move);
  }
  return runner.roundOver ? limit : null;
}

/// Moves at the edges of the four notations (spacing, case, signs, other
/// seats, other games' moves), tried at every turn.
const _edgeMoves = [
  '',
  'pass',
  'PASS',
  ' pass',
  'h8 ',
  'H8',
  's19',
  's99',
  'a0',
  '0:pass',
  '0:PASS',
  '9:pass',
  '-1:pass',
  '0:p',
  '0:b0',
  '0:b4',
  '0:c1',
  '0:r1',
  '0:H',
  '0:h',
  '00:H',
  '4:S',
  '0:I',
  '0:3d',
  '0:3d 3d',
  '0:3d  4d',
  '0:xsolo:3',
  '0:xsolo:3|',
  '0:xsolo:3|0',
  '0:xsolo:3|+0',
  '0:xsolo:3|0,0',
  '0:xsolo:3|99',
  '0:xpair:33|0,1',
  '1:xsolo:3|0',
  '0:xrocket:BR|52,53',
  '\u0000',
];

void _edgeChecks(GameRunner runner, int seats) {
  runner.startRound(1, List.filled(seats, false));
  for (var n = 0; n < 3000 && !runner.roundOver; n++) {
    final seat = runner.seatToAct!;
    for (final move in _edgeMoves) {
      expect(() => runner.check(seat, move), returnsNormally, reason: '"$move" at seat $seat');
    }
    runner.act(seat, runner.autoMove(seat));
  }
}

/// Fight the Landlord's moves for the harness (unused: nobody there plays).
String _ddzPick(Map<String, Object?> view, int seat, Random random) {
  final game = DdzWireView.read(view).replay()!;
  return ddzAutoMove(game);
}

void main() {
  group('a round where nobody at the table is there (every turn the room\'s auto move) still ends', () {
    test('Gomoku, both boards', () {
      for (final rules in [
        GomokuOnline().defaultRules,
        {'size': 19, 'win': 'freestyle', 'black': 'turns'},
        {'size': 15, 'win': 'renju', 'black': 'turns'},
      ]) {
        final game = GomokuOnline();
        expect(
          _autoOnly(game.newRunner(OnlineSetup(rules: rules, seats: 2), Random(1)), 2),
          isNotNull,
          reason: '$rules',
        );
      }
    });

    test('Big Two at 2, 3 and 4 seats', () {
      final game = BigTwoOnline();
      for (final seats in [2, 3, 4]) {
        for (var seed = 0; seed < 20; seed++) {
          final runner = game.newRunner(OnlineSetup(rules: game.defaultRules, seats: seats), Random(seed));
          expect(_autoOnly(runner, seats), isNotNull, reason: '$seats seats, deal $seed');
        }
      }
    });

    test('Blackjack at 7 seats', () {
      const game = BlackjackOnline();
      for (var seed = 0; seed < 20; seed++) {
        final runner = game.newRunner(OnlineSetup(rules: game.defaultRules, seats: 7), Random(seed));
        expect(_autoOnly(runner, 7), isNotNull, reason: 'deal $seed');
      }
    });

    test('Fight the Landlord, both auctions, when everyone passing means a new deal (the default)', () {
      final game = DoudizhuOnline();
      for (final bidding in BiddingStyle.values) {
        final rules = DdzRules(bidding: bidding).toJson();
        final runner = game.newRunner(OnlineSetup(rules: rules, seats: 3), Random(1)) as DoudizhuRunner;
        expect(
          _autoOnly(runner, 3),
          isNotNull,
          reason:
              '${bidding.name}: an auto move that always declines throws the deal in and deals again '
              'without end (${runner.redeals} redeals so far)',
        );
      }
    });
  });

  for (final allPass in AllPassRule.values) {
    test('Fight the Landlord (${allPass.name} when everyone passes): with three people at the table who stop '
        'playing, End game still brings the room back to its lobby', () async {
      final h = RunnerHarness(DoudizhuOnline(), pick: _ddzPick, seed: 5);
      final host = await h.open();
      await h.choose(rules: DdzRules(allPass: allPass).toJson(), turnLimit: 15);
      for (final name in ['Ben', 'Cy', 'Di']) {
        (await h.join(name, seated: true)).autoPlay = false;
      }
      await h.start();
      await h.until(() => host.state?.turn != null, 'the first turn');
      host.send(const EndGame());
      await h.settle();
      await h.until(() => host.room.phase == RoomPhase.lobby, 'the room back in its lobby', limit: 1500);
    });
  }

  test('Big Two: a seat that drops mid-deal and comes back gets its own view again, and someone who joins mid-deal '
      "watches without the bot's hand (the switch off)", () async {
    String pick(Map<String, Object?> view, int seat, Random random) {
      final legal = bigTwoEngineView(view).legalMoves();
      final plays = legal.where((p) => !p.isPass).toList();
      return bigTwoMove(seat, plays.isNotEmpty ? plays[random.nextInt(plays.length)] : Play.pass);
    }

    Set<String> secrets(Map<String, Object?> view, int seat) => (view['winner']! as int) >= 0
        ? const {}
        : {
            for (final card in view['hand']! as List)
              if (card != view['start'] && card != view['extra']) '"$card"',
          };

    final h = RunnerHarness(BigTwoOnline(), pick: pick, secrets: secrets, seatViewFrom: bigTwoSeatViewFrom, seed: 9);
    await h.open();
    await h.choose(seats: 3);
    final ben = await h.join('Ben', seated: true);
    final cy = await h.join('Cy', seated: true);
    // The people wait, so the deal is still on when Ben drops and Di comes.
    ben.autoPlay = cy.autoPlay = false;
    await h.addBots(1);
    await h.start();
    await h.until(
      () => ben.state?.turn != null && ben.state!.view['toMove'] != ben.state!.seats.indexOf(2),
      'a person to act',
    );
    final code = ben.welcome.code, token = ben.welcome.token;
    await h.drop(ben);
    final back = await h.rejoin('Ben', code, token);
    expect(back.state?.you, isNotNull, reason: 'Ben is back at his seat');
    final di = await h.join('Di');
    expect(di.state?.you, isNull);
    expect(di.state?.view['hands'], isA<Map>());
    expect((di.state!.view['hands']! as Map).length, 2, reason: "the two people's hands, not the bot's");
    expect(di.state?.over, isNull, reason: 'the deal is still on');
    back.autoPlay = cy.autoPlay = true;
    back.actNow();
    cy.actNow();
    await h.playRounds(2);
    h.expectClean();
  });

  test('every runner reads moves at the edge of its notation at every turn without throwing', () {
    _edgeChecks(GomokuOnline().newRunner(OnlineSetup(rules: GomokuOnline().defaultRules, seats: 2), Random(2)), 2);
    _edgeChecks(
      GomokuOnline().newRunner(OnlineSetup(rules: {'size': 15, 'win': 'renju', 'black': 'turns'}, seats: 2), Random(2)),
      2,
    );
    final bigTwo = BigTwoOnline();
    for (final seats in [2, 3, 4]) {
      _edgeChecks(bigTwo.newRunner(OnlineSetup(rules: bigTwo.defaultRules, seats: seats), Random(seats)), seats);
    }
    final ddz = DoudizhuOnline();
    _edgeChecks(
      ddz.newRunner(
        OnlineSetup(rules: const DdzRules(allPass: AllPassRule.firstBidderLandlord).toJson(), seats: 3),
        Random(3),
      ),
      3,
    );
    const bj = BlackjackOnline();
    for (var seed = 0; seed < 10; seed++) {
      _edgeChecks(bj.newRunner(OnlineSetup(rules: bj.defaultRules, seats: 7), Random(seed)), 7);
    }
  });
}
