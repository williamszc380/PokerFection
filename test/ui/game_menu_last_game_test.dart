import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/app/last_games.dart';
import 'package:pokerfection/src/kit/game_record.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/game_menu.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/kit/kit_scope.dart';
import 'package:pokerfection/src/ui/widgets/game_emblems.dart';

/// Play opens the setup, and the setup becomes the game
/// (pushReplacement, as Gomoku's, Big Two's and Fight the Landlord's
/// setups do). The game saves its record when it starts.
class _Setup extends StatelessWidget {
  const _Setup();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const _Game())),
          child: const Text('Start'),
        ),
      );
}

class _Game extends StatefulWidget {
  const _Game();

  @override
  State<_Game> createState() => _GameState();
}

class _GameState extends State<_Game> {
  @override
  void initState() {
    super.initState();
    KitScope.of(context).lastGames.save(GameRecord(game: 'gomoku', version: 1, seed: 1, rules: const {}));
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('The game')));
}

/// The menu with Play opening [play], and Last game, greyed out until a
/// game of Gomoku is saved.
Future<LastGames> _pumpMenu(WidgetTester tester, WidgetBuilder play) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final lastGames = LastGames();
  final game = GameInfo(
    id: GameId.gomoku,
    name: (s) => s.gomoku,
    emblem: (size) => GomokuEmblem(size: size),
    menu: [
      GameMenuButton(icon: Icons.play_arrow, label: (_) => 'Play', open: play),
      GameMenuButton(
        icon: Icons.history,
        label: (_) => 'Last game',
        open: (_) => const Scaffold(body: Text('The last game')),
        enabled: (c) async => await KitScope.of(c).lastGames.load('gomoku', version: 1) != null,
      ),
    ],
  );
  await tester.pumpWidget(AppSettingsScope(
    settings: AppSettings(),
    child: KitScope(newJobs: Jobs.inline, lastGames: lastGames, child: MaterialApp(home: GameMenu(game: game))),
  ));
  await tester.pumpAndSettle();
  return lastGames;
}

OutlinedButton _lastGame(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Last game'));

void main() {
  testWidgets('a game opened straight from the menu: Last game lights up when it closes', (tester) async {
    await _pumpMenu(tester, (_) => const _Game());
    expect(_lastGame(tester).onPressed, isNull);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_lastGame(tester).onPressed, isNotNull);
  });

  testWidgets('a setup left without starting a game: Last game stays greyed out', (tester) async {
    await _pumpMenu(tester, (_) => const _Setup());
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Start'))).pop();
    await tester.pumpAndSettle();
    expect(_lastGame(tester).onPressed, isNull);
  });

  testWidgets('Last game lights up after the first game, when the setup became the game', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lastGames = LastGames();
    final game = GameInfo(
      id: GameId.gomoku,
      name: (s) => s.gomoku,
      emblem: (size) => GomokuEmblem(size: size),
      menu: [
        GameMenuButton(icon: Icons.play_arrow, label: (_) => 'Play', open: (_) => const _Setup()),
        GameMenuButton(
          icon: Icons.history,
          label: (_) => 'Last game',
          open: (_) => const Scaffold(body: Text('The last game')),
          enabled: (c) async => await KitScope.of(c).lastGames.load('gomoku', version: 1) != null,
        ),
      ],
    );
    await tester.pumpWidget(AppSettingsScope(
      settings: AppSettings(),
      child: KitScope(
        newJobs: Jobs.inline,
        lastGames: lastGames,
        child: MaterialApp(home: GameMenu(game: game)),
      ),
    ));
    await tester.pumpAndSettle();
    OutlinedButton lastGame() => tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Last game'));
    expect(lastGame().onPressed, isNull, reason: 'nothing saved yet');

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('The game'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(await lastGames.load('gomoku', version: 1), isNotNull, reason: 'the game was saved');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(GameMenu), findsOneWidget);
    expect(lastGame().onPressed, isNotNull, reason: 'a game was played: Last game opens it');
  });
}
