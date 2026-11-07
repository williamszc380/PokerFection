import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/main.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/bots/bot.dart';
import 'package:pokerfection/src/engine/events.dart';
import 'package:pokerfection/src/engine/rules.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';
import 'package:pokerfection/src/l10n/strings.dart';
import 'package:pokerfection/src/online/protocol.dart' show JoinError;
import 'package:pokerfection/src/online/peer_status.dart';
import 'package:pokerfection/src/ui/games.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

/// Every way the lobby can show the internet (see PeerStatus).
const _peerStatuses = [
  PeerStatus.starting,
  PeerStatus.ready,
  PeerStatus.unavailable(PeerTrouble.unreachable),
  PeerStatus.unavailable(PeerTrouble.codeTaken),
  PeerStatus.unavailable(PeerTrouble.unsupported),
];

void main() {
  for (final language in AppLanguage.values) {
    test('${language.label}: every glossary entry and label has a text', () {
      final s = S.forLanguage(language);
      for (final section in GlossarySection.values) {
        expect(s.section(section), isNotEmpty);
      }
      for (final term in GlossaryTerm.values) {
        expect(s.term(term), isNot(term.name), reason: '$term has no name');
        expect(s.definition(term).length, greaterThan(3), reason: '$term has no definition');
      }
      final texts = [
        for (final reason in Unavailable.values) s.unavailable(reason),
        for (final reason in [...NoAnswer.values, null]) s.noAnswer(reason),
        for (final grade in DecisionGrade.values) s.grade(grade),
        for (final speed in PlaybackSpeed.values) s.speed(speed),
        for (final style in BotStyle.values) s.style(style),
        for (final rule in RaiseRule.values) s.raiseRule(rule),
        for (final street in Street.values) s.street(street),
        s.potShare(0.33),
        s.potShare(1),
        s.potShare(0.4),
        s.noDirectRoute,
        s.roomNotNearby,
        for (final status in _peerStatuses) ...[
          s.internetStatus(status),
          s.internetHelp(status: status, windows: true, phone: true),
          s.internetHelp(status: status, windows: false, phone: false, browser: true),
        ],
        s.sameWifiAppOnly,
        s.cantReachServer,
        s.wsOnWebsite,
        s.cantHostInBrowser,
        for (final style in BoardStyle.values) s.boardStyle(style),
        for (final style in StoneStyle.values) s.stoneStyle(style),
        s.holdem,
        s.gomoku,
        s.bigTwo,
        s.fightTheLandlord,
        s.blackjack,
        s.soon,
        s.general,
        s.cardsAndTable,
        s.boardAndStones,
        s.boardColor,
        s.stoneLook,
        // The room: everyone enters as a spectator and joins the game.
        s.joinGame,
        s.leaveSeat,
        s.spectators,
        s.spectatorsSeeBots,
        s.seatList,
        s.game,
        s.endGame,
        s.nextGameBadge,
        s.updateToWatch,
        // The room docked beside every screen (rooms v2).
        s.leaveRoom,
        s.leaveRoomQuestion,
        s.closeRoomQuestion,
        s.leaveSeatQuestion,
        s.leaveSeatWarning,
        s.pickGame,
        s.waitingForGame,
        s.seatsAfterGame,
        s.inRoom('K7M2Q'),
        s.leaveSeatWarningRound,
        s.needSeats(3),
        s.people,
        s.playingNow,
        s.pickGameOnHome,
        s.onlineSoon,
        s.sit,
        s.openTable,
        s.endGameFirst,
        s.roomSetupNote('K7M2Q'),
        s.about,
        s.versionNumber('2.0.12+'),
        s.buildCommits(12, changed: true),
        s.buildCommits(12, changed: false),
        s.devBuild,
        s.madeBy('Williams Zhang Cen'),
        s.gamesList("Hold'em · Gomoku"),
        s.onlineRooms(8),
        s.runningOn('Windows'),
        s.term(GlossaryTerm.roomStays),
        s.definition(GlossaryTerm.roomStays),
        for (final error in [...JoinError.values, null]) s.joinError(error),
      ];
      expect(texts.every((t) => t.isNotEmpty), isTrue);
    });
  }

  test('a full room says so in every language, and nothing is left of looking at cards', () {
    expect(
      [for (final l in AppLanguage.values) S.forLanguage(l).joinError(JoinError.roomFull)],
      ['Room full', 'Sala llena', '房间已满'],
    );
    expect(GlossaryTerm.values.map((t) => t.name), isNot(contains('seeCards')));
    expect(
      [
        GlossaryTerm.roomGame,
        GlossaryTerm.spectators,
        GlossaryTerm.seeBots,
        GlossaryTerm.roomStays,
      ].map((t) => t.section),
      everyElement(GlossarySection.online),
    );
  });

  test("play doesn't wait for GTO's answer: \"Solving…\" with its glossary entry, late grades by street, "
      'and no "Solving… 37%" before a hand', () {
    expect(
      [for (final l in AppLanguage.values) S.forLanguage(l).solvingDecision],
      ['Solving…', 'Resolviendo…', '计算中…'],
    );
    expect(GlossaryTerm.solving.section, GlossarySection.scoring);
    expect(GlossaryTerm.values.indexOf(GlossaryTerm.solving), GlossaryTerm.values.indexOf(GlossaryTerm.grades) + 1);
    for (final l in AppLanguage.values) {
      final s = S.forLanguage(l);
      expect(s.term(GlossaryTerm.solving), s.solvingDecision);
      expect(s.definition(GlossaryTerm.solving), contains(s.showGto), reason: '${l.label}: Show GTO shows it when it comes');
    }
    expect(
      [for (final l in AppLanguage.values) S.forLanguage(l).lateGrade(DecisionGrade.mistake, Street.flop)],
      ['Mistake on the flop', 'Error en el flop', '翻牌：失误'],
    );
    expect(
      [for (final street in Street.values) S.forLanguage(AppLanguage.english).lateGrade(DecisionGrade.blunder, street)],
      ['Blunder preflop', 'Blunder on the flop', 'Blunder on the turn', 'Blunder on the river'],
    );
    // The hand never waits for its whole game to be solved any more.
    final strings = File('lib/src/l10n/strings.dart').readAsStringSync();
    expect(strings, isNot(contains('solvingTable')));
  });

  testWidgets('the language button switches the whole app', (tester) async {
    final settings = AppSettings();
    await tester.pumpWidget(PokerFectionApp(settings: settings));
    expect(find.text('Multiplayer'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();
    expect(settings.language, AppLanguage.spanish);
    expect(find.text('Multijugador'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Pronto'), findsNWidgets(games.where((g) => !g.ready).length));
    settings.update((s) => s.language = AppLanguage.chinese);
    await tester.pumpAndSettle();
    expect(find.text('斗地主'), findsOneWidget);
    expect(find.text('二十一点'), findsOneWidget);
    // Material's own texts follow too (for example the back button's name).
    expect(MaterialLocalizations.of(tester.element(find.text('斗地主'))).backButtonTooltip, '返回');
  });
}
