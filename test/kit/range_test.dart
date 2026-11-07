import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/range.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/l10n/kit_strings.dart';
import 'package:pokerfection/src/ui/kit/range_sheet.dart';
import 'package:pokerfection/src/ui/kit/turn_controller.dart';

import 'fakes.dart';
import 'nim.dart';
import 'range_fixture.dart';
import 'shots.dart';

/// Nim with a range for the bot's seat (the fake job's: [jokers] for Fight
/// the Landlord's ranks, else Big Two's), as a card game has.
class _RangeNim extends NimController {
  _RangeNim({required super.jobs, super.training, this.jokers = false, this.cards = 13});

  final bool jokers;
  final int cards;

  /// The game has no range to work out any more (as Big Two once its deal
  /// is over): rangeRequest says null.
  bool rangeGone = false;

  @override
  JobRequest? rangeRequest(GameRecord position, int seat, {required int seed}) => rangeGone ? null : JobRequest(
        const FakeRangeJob(),
        {'seat': seat, 'cards': cards, 'jokers': jokers, 'samples': 300, 'seed': seed + position.moves.length},
        JobKind.range,
      );
}

final _rangeJobs = <String, GameJob<Object?, Object?>>{...nimJobs, 'kit.fakeRange': const FakeRangeJob()};

/// A felt with the bot's seat, tappable for its range.
Widget _table(TurnController c, AppLanguage language) => FeltArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: RangeTap(
          controller: c,
          seat: 1,
          look: fakeLook(language),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SeatBadge(name: 'Ana', cardsLeft: 13),
                SizedBox(height: 4),
                SeatHand(count: 13, cardWidth: 30),
              ],
            ),
          ),
        ),
      ),
    );

Future<_RangeNim> _pump(WidgetTester tester, _RangeNim game, {Size size = const Size(900, 420), AppLanguage language = AppLanguage.english}) async {
  await game.newGame();
  await pumpShot(
    tester,
    GameScaffold(
      title: S.forLanguage(language).bigTwo,
      strings: BigTwoStrings.forLanguage(language),
      controller: game,
      table: _table(game, language),
      panel: const SizedBox(height: 48),
      opponentCards: true,
    ),
    size: size,
    language: language,
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  return game;
}

Future<void> _close(WidgetTester tester, NimController game) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  game.dispose();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadShotFonts);

  group('the data', () {
    test('ranks: the share of samples holding at least 1, 2, 3, 4 of each; combos with their likeliest instances', () {
      final range = OpponentRange.tally(
        seat: 2,
        hands: [
          ['3', '3', 'K'],
          ['3', 'K', 'K'],
          ['3', '3', '3'],
          ['4', 'K', 'A'],
        ],
        rankOrder: [('3', 4), ('4', 4), ('K', 4), ('A', 4), ('BJ', 1)],
        kinds: ['pair', 'rocket'],
        combosOf: (hand) => {
          'pair': {
            for (final r in hand.toSet())
              if (hand.where((x) => x == r).length >= 2) '$r-$r',
          },
        },
      );
      expect(range.seat, 2);
      expect(range.cards, 3);
      expect(range.samples, 4);
      expect([for (final r in range.ranks) r.rank], ['3', '4', 'K', 'A', 'BJ']);
      expect(range.ranks[0].atLeast, [0.75, 0.5, 0.25, 0.0]);
      expect(range.ranks[0].expected, 1.5);
      expect(range.ranks[2].chance(1), 0.75);
      expect(range.ranks[2].chance(2), 0.25);
      expect(range.ranks[4].atLeast, [0.0], reason: 'one joker of each colour');
      expect(range.ranks[4].chance(2), 0, reason: 'past what a hand can hold');
      expect(range.combos[0].kind, 'pair');
      expect(range.combos[0].chance, 0.75);
      expect(range.combos[0].examples, [('3-3', 0.5), ('K-K', 0.25)]);
      expect(range.combos[1].chance, 0, reason: 'a kind nobody makes keeps its place, at 0');
    });

    test('weighted hands: the chances by weight, and the deals counted by what they are worth', () {
      // Fight the Landlord weighs each guess by how well it explains the
      // bids and plays; a heavy guess counts for more, and a pool where a
      // few guesses carry the weight rests on fewer deals than it holds.
      final range = OpponentRange.tally(
        seat: 1,
        hands: [
          ['A'],
          ['K'],
          ['K'],
          ['K'],
        ],
        weights: [3, 1 / 3, 1 / 3, 1 / 3],
        rankOrder: [('K', 4), ('A', 4)],
        kinds: ['pair'],
        combosOf: (hand) => const {},
      );
      expect(range.ranks[1].chance(1), closeTo(0.75, 1e-9), reason: 'the ace weighs 3 of 4');
      expect(range.ranks[0].chance(1), closeTo(0.25, 1e-9));
      // (3 + 1)² / (9 + 3 × 1/9) = 16 / 9.33: about 2 deals' worth, not 4.
      expect(range.samples, 2);
      final even = OpponentRange.tally(
        seat: 1,
        hands: [
          ['A'],
          ['K'],
        ],
        weights: [0.3, 0.3],
        rankOrder: [('K', 4), ('A', 4)],
        kinds: ['pair'],
        combosOf: (hand) => const {},
      );
      expect(even.samples, 2, reason: 'equal weights: every hand counts in full');
      expect(even.ranks[1].chance(1), closeTo(0.5, 1e-9));
      expect(
        () => OpponentRange.tally(
          seat: 1,
          hands: [
            ['A'],
          ],
          weights: [1, 2],
          rankOrder: [('A', 4)],
          kinds: const [],
          combosOf: (hand) => const {},
        ),
        throwsArgumentError,
      );
    });

    test('travels as JSON, rounded to 4 decimals, through a job', () {
      final range = const FakeRangeJob().run({'seat': 1, 'cards': 17, 'jokers': true, 'samples': 7, 'seed': 3},
          JobContext(platform: JobPlatform.test));
      final json = range.toJson();
      final back = OpponentRange.fromJson(json);
      expect(back.toJson(), json);
      expect(back.ranks, hasLength(15));
      expect(back.combos.map((c) => c.kind), landlordKinds);
      for (final r in back.ranks) {
        for (final p in r.atLeast) {
          expect((p * 10000 - (p * 10000).round()).abs(), lessThan(1e-6), reason: 'rounded');
        }
      }
      // The same input gives the same range: no timing, no Random().
      final again = const FakeRangeJob().run({'seat': 1, 'cards': 17, 'jokers': true, 'samples': 7, 'seed': 3},
          JobContext(platform: JobPlatform.test));
      expect(again.toJson(), json);
    });
  });

  group('the controller', () {
    late ManualBackend backend;
    late Jobs jobs;

    setUp(() {
      backend = ManualBackend(_rangeJobs);
      jobs = Jobs.using(backend);
    });

    test("only in Training, only for another seat, only in a game that has ranges", () async {
      final training = _RangeNim(jobs: jobs);
      await training.newGame();
      expect(training.canShowRange(1), isTrue);
      expect(training.canShowRange(0), isFalse, reason: "the player's own seat");
      expect(training.canShowRange(5), isFalse);
      final free = _RangeNim(jobs: Jobs.using(backend), training: false);
      await free.newGame();
      expect(free.canShowRange(1), isFalse, reason: 'Free Play');
      final plain = NimController(jobs: Jobs.using(backend));
      await plain.newGame();
      expect(plain.canShowRange(1), isFalse, reason: 'no range job');
      for (final c in [training, free, plain]) {
        c.dispose();
      }
    });

    test('asking starts one range job on the coach lane; the answer is for the position it was asked in', () async {
      final game = _RangeNim(jobs: jobs);
      await game.newGame();
      await settle();
      backend.answer(backend.on(JobLane.coach)!); // the coach's answer
      await settle();
      game.askRange(1);
      game.askRange(1);
      expect(game.coachJobs, ['range:1'], reason: 'asked twice, started once');
      final job = backend.on(JobLane.coach)!;
      expect(job.name, 'kit.fakeRange');
      expect(game.rangeOf(1), isNull);
      backend.answer(job);
      await settle();
      expect(game.rangeOf(1)!.ranks, hasLength(13));
      game.humanMove('3');
      await settle();
      expect(game.rangeOf(1), isNull, reason: 'a move changes what they could hold');
      game.dispose();
    });

    test('a failed range says so; asking again tries again', () async {
      final game = _RangeNim(jobs: jobs);
      await game.newGame();
      await settle();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      game.askRange(1);
      backend.fail(backend.on(JobLane.coach)!);
      await settle();
      expect(game.rangeFailed(1), isTrue);
      game.askRange(1);
      expect(game.coachJobs, ['range:1']);
      game.dispose();
    });

    test('a new deal cancels a range on its way', () async {
      final game = _RangeNim(jobs: jobs);
      await game.newGame();
      await settle();
      backend.answer(backend.on(JobLane.coach)!);
      await settle();
      game.askRange(1);
      final job = backend.started.lastWhere((j) => j.name == 'kit.fakeRange');
      await game.newGame();
      expect(job.token.isCancelled, isTrue);
      expect(game.coachJobs.where((j) => j.startsWith('range')), isEmpty);
      game.dispose();
    });
  });

  group('the sheet', () {
    testWidgets('tapping the seat opens it: working, then every rank and combo; the hand cursor over the seat',
        (tester) async {
      final game = await _pump(tester, _RangeNim(jobs: Jobs.inline(extra: _rangeJobs)));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byKey(const ValueKey('range tap 1'))));
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
      await tester.tap(find.byKey(const ValueKey('range tap 1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('range sheet')), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(find.byType(RankGrid), findsOneWidget);
      expect(find.byKey(const ValueKey('rank A 1')), findsOneWidget);
      expect(find.byKey(const ValueKey('rank 2 4')), findsOneWidget);
      for (final kind in bigTwoKinds) {
        expect(find.byKey(ValueKey('combo $kind')), findsOneWidget, reason: 'never hidden, even at 0');
      }
      expect(find.text('Range · Ana · 13 cards'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sheet close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('range sheet')), findsNothing);
      await _close(tester, game);
    });

    testWidgets(
        'a sheet left open when the game has no range any more (the deal ended behind it) says so, and stops spinning',
        (tester) async {
      final game = await _pump(tester, _RangeNim(jobs: Jobs.inline(extra: _rangeJobs)));
      await tester.tap(find.byKey(const ValueKey('range tap 1')));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(find.byType(RankGrid), findsOneWidget);
      // The game moves on and has nothing left to work out.
      game.rangeGone = true;
      game.humanMove('1');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('range sheet')), findsOneWidget, reason: 'the sheet stays until closed');
      expect(find.text('No range to work out now.'), findsOneWidget);
      expect(find.text('Working it out…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _close(tester, game);
    });

    test("the title gives a seat named for the middle of a sentence its capital (Spanish 'la banca')", () {
      expect(rangeHeadingName('la banca'), 'La banca');
      expect(rangeHeadingName('Ana'), 'Ana');
      expect(rangeHeadingName('庄家'), '庄家');
      expect(rangeHeadingName(''), '');
    });

    testWidgets('in Free Play the seat is only a seat: no hand cursor, no sheet', (tester) async {
      final game = await _pump(tester, _RangeNim(jobs: Jobs.inline(extra: _rangeJobs), training: false));
      expect(find.byKey(const ValueKey('range tap 1')), findsNothing);
      await tester.tap(find.byType(SeatBadge));
      await tester.pump();
      expect(find.byKey(const ValueKey('range sheet')), findsNothing);
      await _close(tester, game);
    });

    testWidgets('the open sheet follows the game: after a move it works the range out again', (tester) async {
      final game = await _pump(tester, _RangeNim(jobs: Jobs.inline(extra: _rangeJobs)));
      await tester.tap(find.byKey(const ValueKey('range tap 1')));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      final first = game.rangeOf(1)!;
      game.humanMove('1');
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      final now = game.rangeOf(1);
      expect(now, isNotNull, reason: 'asked again for the position now');
      expect(identical(now, first), isFalse);
      await _close(tester, game);
    });

    for (final jokers in [false, true]) {
      for (final language in AppLanguage.values) {
        for (final size in [...shotSizes, const Size(900, 420)]) {
          final tag = '${jokers ? 'ddz' : 'b2'}_${shotTag(size, language)}';
          testWidgets('range $tag: everything readable and in sight, nothing overflows', (tester) async {
            final game = await _pump(
              tester,
              _RangeNim(jobs: Jobs.inline(extra: _rangeJobs), jokers: jokers, cards: jokers ? 17 : 13),
              size: size,
              language: language,
            );
            await tester.tap(find.byKey(const ValueKey('range tap 1')));
            for (var i = 0; i < 4; i++) {
              await tester.pump();
            }
            await tester.pump(const Duration(milliseconds: 300));
            final sheet = tester.getRect(find.byKey(const ValueKey('range sheet')));
            expect(sheet.left, greaterThanOrEqualTo(0));
            expect(sheet.right, lessThanOrEqualTo(size.width));
            // The grid fits the width: a column at least 20 px, so "100" reads.
            final cell = tester.getSize(find.byKey(const ValueKey('rank 3 1')));
            expect(cell.width, greaterThanOrEqualTo(RankGrid.minColumn - 0.01));
            expect(cell.height, greaterThanOrEqualTo(18));
            final grid = tester.getRect(find.byType(RankGrid));
            expect(grid.right, lessThanOrEqualTo(sheet.right + 0.5));
            // Every combo's name reads in full, at a size that can be read.
            final look = fakeLook(language);
            for (final kind in jokers ? landlordKinds : bigTwoKinds) {
              final name = find.descendant(of: find.byKey(ValueKey('combo $kind')), matching: find.text(look.comboLabel(kind)));
              final paragraph = tester.renderObject<RenderParagraph>(name);
              expect(paragraph.didExceedMaxLines, isFalse, reason: '${look.comboLabel(kind)} is cut');
              expect(paragraph.text.style?.fontSize ?? 14, greaterThanOrEqualTo(10));
            }
            await shot(tester, 'range_$tag');
            await _close(tester, game);
          });
        }
      }
    }
  });

  group('the seat hand', () {
    testWidgets('backs: at most six, however many they hold; faces: every card, squeezed into the room', (tester) async {
      await pumpShot(
        tester,
        Scaffold(
          body: Column(
            children: [
              const SeatHand(count: 17, cardWidth: 30, key: ValueKey('backs')),
              SizedBox(
                width: 150,
                child: SeatHand(
                  count: 17,
                  cardWidth: 30,
                  faces: [for (var i = 0; i < 17; i++) CardFace.suited(i % 13, i % 4)],
                  key: const ValueKey('faces'),
                ),
              ),
            ],
          ),
        ),
        size: const Size(400, 300),
      );
      expect(find.descendant(of: find.byKey(const ValueKey('backs')), matching: find.byType(GameCardView)), findsNWidgets(6));
      expect(find.descendant(of: find.byKey(const ValueKey('faces')), matching: find.byType(GameCardView)), findsNWidgets(17));
      expect(tester.getSize(find.byKey(const ValueKey('seat faces'))).width, lessThanOrEqualTo(150));
    });
  });

  test('the sheet\'s words exist in every language', () {
    for (final language in AppLanguage.values) {
      final k = KitStrings.forLanguage(language);
      expect(k.rangeTitle('Ana', 7), contains('7'));
      expect(k.rangeSamples(400), contains('400'));
    }
  });
}
