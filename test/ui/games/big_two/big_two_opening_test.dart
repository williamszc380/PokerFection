// Who goes first: every deal opens with a short step, before the first
// play, at the Animations speed (about two seconds at Normal, 0.7 s at
// Fast, none at Instant, where only its result shows). Nobody moves while
// it plays. With three or four players the starting card turns up in the
// middle and goes to its holder's seat, the headline naming them ("Kai
// starts: 3♦"); with two, low cards are called from the bottom up until
// someone holds one, and only that card is shown. Afterwards the middle
// says who starts until the first play, as the review's first step does.
// Screenshots with --dart-define=SHOTS=<folder>.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/big_two/app/big_two_record.dart';
import 'package:pokerfection/src/games/big_two/big_two.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_controller.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_opening.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_review.dart';
import 'package:pokerfection/src/ui/games/big_two/big_two_table.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'big_two_test_util.dart';

final _step = find.byKey(const ValueKey('opening step'));
final _note = find.byKey(const ValueKey('opening note'));
final _words = find.byKey(const ValueKey('opening words'));
final _status = find.byKey(const ValueKey('status'));
final _mark = find.byKey(const ValueKey('visible mark'));
Finder _seat(int seat) => find.byKey(ValueKey('seat $seat'));
Finder _card(int code) => find.byKey(ValueKey(('opening card', code)));

final _en = BigTwoStrings.forLanguage(AppLanguage.english);

/// A game dealt (not yet on screen) whose first deal [wanted] accepts, at
/// [speed]. Fails when no seed under 200 deals one.
Future<BigTwoController> _game(
  bool Function(BigTwoState state) wanted, {
  BigTwoRules? rules,
  PlaybackSpeed speed = PlaybackSpeed.normal,
}) async {
  for (var seed = 1; seed < 200; seed++) {
    final game = seededGame(rules: rules, seed: seed, training: false, speed: speed);
    await game.newGame();
    if (!game.state.isOver && wanted(game.state)) return game;
    game.dispose();
  }
  fail('no deal like that');
}

String _text(Finder finder) => (finder.evaluate().single.widget as Text).data!;

/// The words inside [finder] (a chip of the step or the note).
String _wordsIn(Finder finder) => _text(find.descendant(of: finder, matching: find.byType(Text)).first);

/// The bot's name at [seat] as the table shows it.
String _name(BigTwoController game, int seat) => game.record.seats[seat].name;

String _label(BigTwoController game, int code) => game.rules.cardOf(code).label;

/// Closes the screen and lets the pauses run out.
Future<void> _close(WidgetTester tester) async {
  await closeGame(tester);
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(loadShotFonts);

  group('the step\'s timing', () {
    testWidgets('Normal: about two seconds in which nobody moves, then the starter acts', (tester) async {
      final game = await _game((s) => s.startSeat != 0);
      final starter = game.state.startSeat;
      final three = game.state.startCode;
      await pumpGame(tester, game);
      expect(game.openingLength, const Duration(milliseconds: 2000));
      expect(game.openingPlaying, isTrue);
      expect(game.seatToAct, isNull, reason: 'nobody acts while it plays');
      expect(game.thinkingSeat, isNull, reason: 'no bot thinks yet');
      expect(_step, findsOneWidget);
      // The headline asks, then names the starter as the card turns up.
      expect(_text(_status), 'Who starts?');

      await tester.pump(const Duration(milliseconds: 1000));
      expect(_text(_status), '${_name(game, starter)} starts: 3♦');
      expect(game.openingPlaying, isTrue);
      expect(game.state.history, isEmpty);
      await tester.pump(const Duration(milliseconds: 980));
      expect(game.openingPlaying, isTrue, reason: 'still showing at 1.98 s');
      expect(_step, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 40));
      expect(game.openingPlaying, isFalse);
      expect(_step, findsNothing);
      expect(game.seatToAct, starter);
      // The result stays in the middle until the first play.
      expect(_wordsIn(_note), '${_name(game, starter)} starts: 3♦');
      expect(_mark, findsOneWidget, reason: 'the card in its holder\'s seat');
      expect(find.descendant(of: _seat(starter), matching: _mark), findsOneWidget);

      // The bot's normal pause, then its play (it holds the 3♦).
      for (var guard = 0; guard < 40 && game.state.history.isEmpty; guard++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game.state.history.first.seat, starter);
      expect(game.state.isPlayed(three), isTrue);
      await settleGame(tester);
      expect(_note, findsNothing);
      await _close(tester);
    });

    testWidgets('Fast: 0.7 s, then the turns go on', (tester) async {
      final game = await _game((s) => s.startSeat != 0, speed: PlaybackSpeed.fast);
      await pumpGame(tester, game);
      expect(game.openingLength, const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 680));
      expect(game.openingPlaying, isTrue);
      expect(_step, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 40));
      expect(game.openingPlaying, isFalse);
      expect(_step, findsNothing);
      expect(game.seatToAct, game.state.startSeat);
      await _close(tester);
    });

    testWidgets('Instant: no step, only its result, and the player may play at once', (tester) async {
      final game = await _game((s) => s.startSeat == 0, speed: PlaybackSpeed.instant);
      await pumpGame(tester, game);
      expect(game.openingLength, Duration.zero);
      expect(game.openingPlaying, isFalse);
      expect(_step, findsNothing);
      expect(game.myTurn, isTrue);
      expect(_wordsIn(_note), 'Player starts: 3♦');
      expect(_text(_status), isNot(contains('start')), reason: 'the headline is the turn\'s');
      await _close(tester);
    });

    testWidgets('the player who starts can\'t play while it shows; the coach and Play wait', (tester) async {
      final game = await _game((s) => s.startSeat == 0);
      await pumpGame(tester, game);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_text(_status), 'Player starts: 3♦');
      expect(game.myTurn, isFalse);
      expect(() => game.humanMove(bigTwoMoveText(0, game.state.legalMoves().first)), throwsStateError);
      final play = tester.widget<FilledButton>(find.byKey(const ValueKey('play')));
      expect(play.onPressed, isNull, reason: 'greyed out');
      await tester.pump(const Duration(milliseconds: 2100));
      expect(game.myTurn, isTrue);
      expect(_text(_status), isNot('Player starts: 3♦'));
      await _close(tester);
    });

    testWidgets('Next deal runs the step again with the new deal\'s starter', (tester) async {
      final game = seededGame(seed: 4, speed: PlaybackSpeed.instant, training: false);
      await pumpGame(tester, game);
      await playToEnd(tester, game);
      // Back to Normal for the next deal.
      final normal = seededGame(seed: 4, speed: PlaybackSpeed.normal, training: false);
      await closeGame(tester);
      await normal.newGame();
      await pumpGame(tester, normal);
      for (var guard = 0; guard < 400 && !normal.isOver; guard++) {
        await tester.pump(const Duration(milliseconds: 300));
        if (normal.myTurn) normal.humanMove(bigTwoMoveText(0, normal.state.legalMoves().first));
      }
      expect(normal.isOver, isTrue);
      final dealBefore = normal.openingDeal;
      await normal.nextRound();
      await tester.pump();
      expect(normal.openingDeal, dealBefore + 1);
      expect(normal.openingPlaying, isTrue);
      expect(_step, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2100));
      expect(normal.openingPlaying, isFalse);
      await _close(tester);
    });
  });

  group('what the step shows', () {
    testWidgets('four players: only the 3♦ turns up, is named, flies to its holder and lands there with the eye', (
      tester,
    ) async {
      final game = await _game((s) => s.startSeat == 2);
      final three = game.state.startCode;
      await pumpGame(tester, game);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_card(three), findsOneWidget);
      expect(
        find.descendant(of: _step, matching: find.byType(GameCardView)),
        findsOneWidget,
        reason: 'one card',
      );
      expect(_words, findsNothing, reason: 'named a moment later');
      expect(
        find.descendant(of: _seat(2), matching: _mark),
        findsNothing,
        reason: 'still in the middle',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_wordsIn(_words), '${_name(game, 2)} starts: 3♦');
      final middle = tester.getCenter(_card(three));
      // Three quarters in, it is on its way to the seat across.
      await tester.pump(const Duration(milliseconds: 1300));
      final flying = tester.getCenter(_card(three));
      expect(flying.dy, lessThan(middle.dy - 10), reason: 'going up to the seat across');
      await tester.pump(const Duration(milliseconds: 320));
      expect(
        find.descendant(of: _seat(2), matching: _mark),
        findsOneWidget,
        reason: 'landed',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_step, findsNothing);
      for (var seat = 0; seat < 4; seat++) {
        if (seat != 2) expect(find.descendant(of: _seat(seat), matching: _mark), findsNothing);
      }
      await _close(tester);
    });

    testWidgets('three players: the starting card and the face-up card both turn up and go to the starter', (
      tester,
    ) async {
      final game = await _game(
        (s) => s.startSeat != 0 && s.extraCode != s.startCode,
        rules: BigTwoRules.standard(players: 3),
      );
      final s = game.state;
      await pumpGame(tester, game);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_card(s.startCode), findsOneWidget);
      expect(_card(s.extraCode), findsOneWidget);
      expect(_wordsIn(_words), '${_name(game, s.startSeat)} starts: ${_label(game, s.startCode)}');
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.descendant(of: _seat(s.startSeat), matching: _mark), findsNWidgets(2));
      await _close(tester);
    });

    testWidgets('two players: low cards are called upward, those nobody holds greyed out, until one is held; '
        'only that one goes to its holder, and the other player shows nothing', (tester) async {
      // A deal where the 3♦ and the 3♣ were not dealt: three calls.
      final game = await _game((s) => s.startCode >= 2 && s.startSeat == 1, rules: BigTwoRules.standard(players: 2));
      final start = game.state.startCode;
      final step = game.opening!;
      expect(step.kind, BigTwoOpeningKind.lowestCalled);
      expect(step.called, [for (var c = 0; c <= start; c++) c]);
      await pumpGame(tester, game);
      GameCardView cardOf(int code) => tester.widget<GameCardView>(_card(code));
      final perCall = step.callAt(1) * 2000;
      await tester.pump(const Duration(milliseconds: 50));
      expect(_card(0), findsOneWidget, reason: 'the lowest card is called first');
      expect(_card(1), findsNothing);
      expect(cardOf(0).dimmed, isFalse, reason: 'being called');
      await tester.pump(Duration(milliseconds: perCall.round()));
      expect(_card(1), findsOneWidget);
      expect(cardOf(0).dimmed, isTrue, reason: 'nobody held it');
      expect(_words, findsNothing);
      expect(_text(_status), 'Who starts?', reason: 'the headline tells nobody before the calls do');
      // Named once the held card is called.
      await tester.pump(Duration(milliseconds: (step.namedAt * 2000 - perCall).round() + 20));
      expect(_card(start), findsOneWidget);
      expect(cardOf(start).dimmed, isFalse);
      expect(cardOf(start).visibleToAll, isTrue);
      expect(_wordsIn(_words), '${_name(game, 1)} starts: ${_label(game, start)}');
      expect(_text(_status), '${_name(game, 1)} starts: ${_label(game, start)}');
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.descendant(of: _seat(1), matching: _mark), findsOneWidget);
      expect(_mark, findsOneWidget, reason: 'the player shows nothing: no eye in the fan');
      await tester.pump(const Duration(milliseconds: 200));
      expect(_wordsIn(_note), '${_name(game, 1)} starts: ${_label(game, start)}');
      await _close(tester);
    });

    testWidgets('a chosen leader: the step only names them, shows no card, and is shorter', (tester) async {
      final rules = BigTwoRules.standard();
      final state = BigTwoState.deal(rules, seed: 11, leader: 2);
      final step = BigTwoOpening.of(state)!;
      expect(step.kind, BigTwoOpeningKind.chosen);
      expect(step.shown, isEmpty);
      expect(step.normalLength, const Duration(milliseconds: 1200));
      final names = ['Player', 'Ana', 'Ben', 'Kai'];
      Widget table(bool playing) => BigTwoOpeningStage(
        id: 1,
        playing: playing,
        length: step.normalLength,
        builder: (context, opening) => BigTwoTable(state: state, names: names, strings: _en, opening: opening),
      );
      await pumpShot(tester, Scaffold(body: table(true)), size: const Size(900, 420));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_wordsIn(_words), 'Ben starts');
      expect(find.descendant(of: _step, matching: find.byType(GameCardView)), findsNothing);
      expect(_mark, findsNothing, reason: 'nobody shows anything');
      await pumpShot(tester, Scaffold(body: table(false)), size: const Size(900, 420));
      expect(_wordsIn(_note), 'Ben starts');
      expect(_step, findsNothing);
    });

    testWidgets('a deal a dragon won has no step', (tester) async {
      final rules = BigTwoRules.hongKong();
      final dragon = [for (var r = 0; r < 13; r++) Card.of(r, r.isEven ? Suit.spades : Suit.hearts)];
      final rest = [
        for (final c in [
          for (var r = 0; r < 13; r++)
            for (final s in Suit.values) Card.of(r, s),
        ])
          if (!dragon.contains(c)) c,
      ];
      final state = BigTwoState.fromHands(rules, [dragon, rest.sublist(0, 13), rest.sublist(13, 26), rest.sublist(26)]);
      expect(state.isOver, isTrue);
      expect(state.openingNow, isNull);
      expect(BigTwoOpening.of(state), isNull);
    });
  });

  group('the result', () {
    for (final language in AppLanguage.values) {
      testWidgets('reads in the words players use, with a "?" on the Starting card (${language.code})', (tester) async {
        final game = await _game((s) => s.startSeat == 1);
        await pumpGame(tester, game, language: language, size: const Size(900, 420));
        await tester.pump(const Duration(milliseconds: 2050));
        final strings = BigTwoStrings.forLanguage(language);
        expect(_wordsIn(_note), strings.starts('Ana', '3♦'));
        await tester.tap(find.descendant(of: _note, matching: find.byIcon(Icons.help_outline)).first);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.textContaining(strings.definition(BigTwoTerm.startingCard)), findsOneWidget);
        await _close(tester);
      });
    }

    testWidgets('the review\'s first step shows the starter and the starting card, with no step to watch', (
      tester,
    ) async {
      final record = await savedDeal(tester, training: false, seed: 9);
      final start = BigTwoRecord.replay(record.upTo(0));
      await pumpShot(
        tester,
        BigTwoReview(record: record),
        size: const Size(1280, 800),
        wrap: bigTwoKit(LastGamesForTests.store),
      );
      await settleGame(tester);
      expect(_step, findsNothing);
      final name = start.startSeat == 0 ? 'Player' : record.seats[start.startSeat].name;
      expect(_wordsIn(_note), _en.starts(name, start.rules.cardOf(start.startCode).label));
      if (start.startSeat != 0) {
        expect(find.descendant(of: _seat(start.startSeat), matching: _mark), findsOneWidget);
      }
    });
  });

  group('screenshots', () {
    // Mid-step and its result, for 4, 3 and 2 players.
    final cases = <(String, BigTwoRules, bool Function(BigTwoState))>[
      ('4p', BigTwoRules.standard(), (s) => s.startSeat == 2),
      ('3p', BigTwoRules.standard(players: 3), (s) => s.startSeat == 1 && s.extraCode != s.startCode),
      ('2p', BigTwoRules.standard(players: 2), (s) => s.startCode >= 2 && s.startSeat == 1),
      ('2p_you', BigTwoRules.standard(players: 2), (s) => s.startCode >= 1 && s.startSeat == 0),
    ];
    for (final (name, rules, wanted) in cases) {
      testWidgets('solo $name at every size and language, nothing overflowing', (tester) async {
        for (final language in AppLanguage.values) {
          for (final size in const [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)]) {
            final game = await _game(wanted, rules: rules);
            await pumpGame(tester, game, size: size, language: language);
            final tag = shotTag(size, language);
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull, reason: '$name $tag');
            await shot(tester, 'b2s_${name}_mid_$tag');
            await tester.pump(const Duration(milliseconds: 1150));
            await shot(tester, 'b2s_${name}_fly_$tag');
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull, reason: '$name $tag');
            expect(_note, findsOneWidget);
            await shot(tester, 'b2s_${name}_result_$tag');
            await _close(tester);
          }
        }
      });
    }

    testWidgets('the review\'s first step', (tester) async {
      final record = await savedDeal(tester, training: false, seed: 9);
      for (final language in AppLanguage.values) {
        for (final size in const [Size(568, 320), Size(900, 420), Size(1280, 800), Size(390, 844)]) {
          await pumpShot(
            tester,
            BigTwoReview(record: record),
            size: size,
            language: language,
            wrap: bigTwoKit(LastGamesForTests.store),
          );
          await settleGame(tester);
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(_note, findsOneWidget);
          await shot(tester, 'b2s_review_${shotTag(size, language)}');
        }
      }
    });
  });
}

/// A records store for the review tests (they pass their record in).
abstract final class LastGamesForTests {
  static final store = LastGames();
}
