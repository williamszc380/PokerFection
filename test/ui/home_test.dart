import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/build_info.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/ui/charts_screen.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/hand_rankings_screen.dart';
import 'package:pokerfection/src/ui/home_screen.dart';
import 'package:pokerfection/src/ui/online/online_screen.dart';
import 'package:pokerfection/src/ui/settings_screen.dart';
import 'package:pokerfection/src/ui/setup_screen.dart';

import '../../tool/build_label.dart';
import '../kit/shots.dart';

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Phones held sideways (a small iPhone's browser, an Android phone with
/// its buttons bar on the side, bigger phones), a browser on a phone held
/// upright, the smallest PC window and a PC.
const _sizes = [
  // What Home gets at 512x320 with the room's rail beside it.
  Size(456, 320),
  Size(568, 320),
  Size(592, 360),
  Size(800, 360),
  Size(900, 420),
  Size(390, 844),
  Size(900, 656),
  Size(1280, 800),
];

Finder _tile(GameId id) => find.byKey(ValueKey('game ${id.name}'));

/// Whether the screen's page would scroll (it shouldn't need to).
bool _scrolls(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .any((scrollable) => scrollable.position.maxScrollExtent > 0);

void main() {
  // Real fonts, so names take their real width (see shots.dart).
  setUpAll(loadShotFonts);

  for (final language in AppLanguage.values) {
    for (final size in _sizes) {
      final tag = shotTag(size, language);
      testWidgets('Home $tag: the five games, the unbuilt ones greyed out with Soon; every word of every name fits its '
          'tile; nothing overflows or scrolls', (tester) async {
        await pumpShot(tester, const HomeScreen(), size: size, language: language);
        await tester.pumpAndSettle();
        await shot(tester, 'home_$tag');
        expect(tester.takeException(), isNull);
        final s = S.forLanguage(language);
        expect(games, hasLength(5));
        for (final game in games) {
          expect(_tile(game.id), findsOneWidget, reason: '${game.id}');
          final soon = find.descendant(of: _tile(game.id), matching: find.text(s.soon));
          expect(soon, game.ready ? findsNothing : findsOneWidget, reason: '${game.id}');
          final ink = tester.widget<InkWell>(find.descendant(of: _tile(game.id), matching: find.byType(InkWell)));
          expect(ink.onTap == null, !game.ready, reason: '${game.id}: greyed out until it has a menu');
        }
        expect(find.text(s.soon), findsNWidgets(games.where((g) => !g.ready).length));
        expect(find.text(s.multiplayer), findsOneWidget);
        expect(find.text(s.settings), findsOneWidget);
        expect(_scrolls(tester), isFalse);
        for (final game in games) {
          // The tiles never cut a name off: they all fit on screen.
          final box = tester.getRect(_tile(game.id));
          expect(
            box.left >= 0 && box.right <= size.width && box.top >= 0 && box.bottom <= size.height,
            isTrue,
            reason: '${game.id} at $box',
          );
          // Each word fits the tile's width for text, so a name only ever
          // breaks between words (Chinese names count as one word).
          final name = find.descendant(of: _tile(game.id), matching: find.text(game.name(s)));
          final paragraph = tester.renderObject<RenderParagraph>(name);
          final room = box.width - 2 * HomeScreen.tilePadding;
          for (final word in game.name(s).split(' ')) {
            final painter = TextPainter(
              text: TextSpan(text: word, style: paragraph.text.style),
              textDirection: TextDirection.ltr,
              textScaler: paragraph.textScaler,
            )..layout();
            expect(painter.width, lessThanOrEqualTo(room), reason: '"$word" in ${room.toStringAsFixed(0)} px');
            painter.dispose();
          }
          expect(paragraph.didExceedMaxLines, isFalse, reason: game.name(s));
        }
      });
    }
  }

  testWidgets('sideways phones: the games three above two, the second row in the middle, with small emblems', (
    tester,
  ) async {
    await pumpShot(tester, const HomeScreen(), size: const Size(568, 320));
    await tester.pumpAndSettle();
    final rects = [for (final game in games) tester.getRect(_tile(game.id))];
    expect({for (final r in rects.take(3)) r.top}, hasLength(1), reason: 'one row of three');
    expect(rects[3].top, greaterThan(rects[0].bottom));
    expect(rects[3].top, rects[4].top);
    final middle = (rects[0].left + rects[2].right) / 2;
    expect((rects[3].left + rects[4].right) / 2, moreOrLessEquals(middle, epsilon: 0.5));
    for (final game in games) {
      final emblem = tester.getSize(find.byKey(ValueKey('emblem ${game.id.name}')));
      expect(emblem.width, inInclusiveRange(36, 44), reason: '${game.id}');
    }
  });

  testWidgets('a PC: the five games in one row', (tester) async {
    await pumpShot(tester, const HomeScreen(), size: const Size(1280, 800));
    await tester.pumpAndSettle();
    final tops = {for (final game in games) tester.getRect(_tile(game.id)).top};
    expect(tops, hasLength(1));
  });

  for (final size in _sizes) {
    testWidgets("Hold'em's menu at $size fits, with Guides open", (tester) async {
      await pumpShot(tester, const HomeScreen(), size: size);
      await tester.pumpAndSettle();
      await tester.tap(_tile(GameId.holdem));
      await tester.pumpAndSettle();
      expect(find.byType(GameMenu), findsOneWidget);
      expect(_scrolls(tester), isFalse);
      await tester.tap(find.text('Guides'));
      await tester.pumpAndSettle();
      expect(_scrolls(tester), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("a game that isn't built yet does nothing when tapped", (tester) async {
    setScreen(tester, const Size(1280, 800));
    await tester.pumpWidget(PokerFectionApp(settings: AppSettings()));
    final unbuilt = games.firstWhere((g) => !g.ready, orElse: () => games.first);
    if (unbuilt.ready) return; // every game is built
    await tester.tap(_tile(unbuilt.id));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(GameMenu), findsNothing);
  });

  testWidgets("Hold'em opens its game menu: Play (the game setup) and Guides (Hand Rankings, Preflop Charts), "
      'no Drills, Multiplayer or Settings; the back arrow goes Home', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await tester.pumpWidget(PokerFectionApp(settings: AppSettings()));
    await tester.tap(find.text("Hold'em"));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, "Hold'em"), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Guides'), findsOneWidget);
    for (final gone in ['Drills', 'Multiplayer', 'Settings']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    await tester.tap(find.text('Guides'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hand Rankings'));
    await tester.pumpAndSettle();
    expect(find.byType(HandRankingsScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preflop Charts'));
    await tester.pumpAndSettle();
    expect(find.byType(ChartsScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.byType(SetupScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Multiplayer opens Play Online, Settings opens the settings', (tester) async {
    setScreen(tester, const Size(1280, 800));
    await tester.pumpWidget(PokerFectionApp(settings: AppSettings()));
    await tester.tap(find.text('Multiplayer'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  test("the games registry: every game once, in GameId's order; Hold'em is ready with Play first", () {
    expect([for (final game in games) game.id], GameId.values);
    expect(games.first.ready, isTrue);
    final holdem = games.first.menu!;
    expect(holdem.first.icon, Icons.play_arrow);
    expect(holdem.first.open, isNotNull);
    expect(holdem.last.choices, hasLength(2));
  });

  test('version 2: pubspec says 2.0, the label reads back for About', () {
    expect(pubspecMajorMinor(), '2.0');
    expect(pubspecMajorMinor().split('.').first, '$appMajorVersion');
    expect(formatBuildLabel('2.0', 11, changed: false), '2.0.11');
    expect(formatBuildLabel('2.0', 11, changed: true), '2.0.11+');
    expect(buildLabelOptions('2.0.11+'), ['--dart-define=PF_BUILD=2.0.11+']);
    expect(buildLabelOptions(null), isEmpty);
    expect(parseBuildLabel('2.0.11'), (version: '2.0.11', commits: 11, changed: false));
    expect(parseBuildLabel('2.0.11+'), (version: '2.0.11', commits: 11, changed: true));
    expect(parseBuildLabel('dev'), isNull);
    expect(parseBuildLabel('2.0'), isNull);
  });

  /// The About box's checks: it is open, nothing overflows, and every
  /// line of it can be seen (scrolled to when the screen is short).
  Future<void> expectAbout(WidgetTester tester, Size size, List<String> texts) async {
    expect(find.byKey(const ValueKey('about dialog')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '$size');
    final screen = Offset.zero & size;
    for (final text in texts) {
      final line = find.text(text);
      expect(line, findsOneWidget, reason: text);
      await tester.ensureVisible(line);
      await tester.pumpAndSettle();
      final box = tester.getRect(line);
      expect(
        screen.contains(box.topLeft) && screen.contains(box.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
        reason: '$text at $size: $box',
      );
    }
    final close = tester.getRect(find.byKey(const ValueKey('about close')));
    expect(
      screen.contains(close.topLeft) && screen.contains(close.bottomRight - const Offset(0.01, 0.01)),
      isTrue,
      reason: 'Close at $size',
    );
  }

  for (final language in AppLanguage.values) {
    testWidgets('the version in the corner opens About: the version, the build, who made it (${language.code})', (
      tester,
    ) async {
      await loadShotFonts();
      for (final size in const [Size(568, 320), Size(390, 844), Size(1280, 800)]) {
        setScreen(tester, size);
        final settings = AppSettings()..language = language;
        await tester.pumpWidget(PokerFectionApp(settings: settings));
        await tester.pumpAndSettle();
        final s = S.forLanguage(language);
        // A test build has no label: "dev".
        expect(tester.widget<Text>(find.byKey(const ValueKey('version'))).data, 'dev');
        // It reacts to the mouse: the hand, and a highlight.
        final about = find.byKey(const ValueKey('about'));
        expect(tester.widget<InkWell>(about).mouseCursor, SystemMouseCursors.click);
        expect(tester.widget<InkWell>(about).hoverColor, isNotNull);
        await tester.tap(find.byKey(const ValueKey('version')));
        await tester.pumpAndSettle();
        await expectAbout(tester, size, [
          'PokerFection',
          s.versionNumber('2'),
          s.devBuild,
          s.madeBy('Williams Zhang Cen'),
          s.gamesList([for (final game in games) game.name(s)].join(' · ')),
        ]);
        await tester.tap(find.byKey(const ValueKey('about close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('about dialog')), findsNothing);
      }
    });

    testWidgets(
      'About with a label: the version as the corner shows it, commits and local changes (${language.code})',
      (tester) async {
        await loadShotFonts();
        final s = S.forLanguage(language);
        for (final size in const [Size(568, 320), Size(390, 844), Size(1280, 800)]) {
          for (final (label, changed) in const [('2.0.11+', true), ('2.0.11', false)]) {
            await pumpShot(tester, const HomeScreen(), size: size, language: language);
            await tester.pumpAndSettle();
            showAbout(tester.element(find.byType(HomeScreen)), label: label);
            await tester.pumpAndSettle();
            await expectAbout(tester, size, [
              s.versionNumber(label),
              s.buildCommits(11, changed: changed),
              s.madeBy('Williams Zhang Cen'),
            ]);
            // Back to the top for the picture.
            await tester.ensureVisible(find.byKey(const ValueKey('about version')));
            await tester.pumpAndSettle();
            if (changed) await shot(tester, 'about_${shotTag(size, language)}');
            await tester.tap(find.byKey(const ValueKey('about close')));
            await tester.pumpAndSettle();
          }
        }
      },
    );
  }
}
