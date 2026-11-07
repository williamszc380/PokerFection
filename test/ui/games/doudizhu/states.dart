/// Games brought to a given moment inside widget tests (fake time): the
/// player's bid, the player's play with the coach's pick selected, a
/// finished deal, and the player's hand moved about (their own order).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/games/doudizhu/app/doudizhu_record.dart';
import 'package:pokerfection/src/games/doudizhu/doudizhu.dart';
import 'package:pokerfection/src/kit/match.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_cards.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_controller.dart';
import 'package:pokerfection/src/ui/games/doudizhu/doudizhu_screen.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import '../../../kit/shots.dart';
import 'helpers.dart';

/// Pumps until [done] (jobs, bots and forced moves all run on fake time).
Future<void> pumpUntil(WidgetTester tester, bool Function() done, {int rounds = 3000}) async {
  for (var i = 0; i < rounds && !done(); i++) {
    // A duration, even zero, so due timers fire too.
    await tester.pump(Duration.zero);
  }
}

bool _yourTurn(LandlordController c) =>
    !c.isOver &&
    c.seatToAct == LandlordController.you &&
    c.forcedMove(LandlordController.you) == null &&
    (!c.training || c.coach != null);

/// Starts a game and stops at the player's first decision in [phase] with
/// the coach's answer in (Training), playing like an Easy bot until then.
/// Tries seeds from [seed] until a deal gets there. The coach is hidden, as
/// in a fresh game, unless [coach] turns it on (its chip). [leading]: the
/// player leads; [following]: the player follows a play (Pass is legal).
Future<LandlordController> gameAt(
  WidgetTester tester,
  DdzPhase phase, {
  bool coach = false,
  bool training = true,
  DdzRules rules = DdzRules.standard,
  int seed = 1,
  bool leading = false,
  bool following = false,
  MatchTarget match = landlordStandardMatch,
}) async {
  for (var s = seed; s < seed + 40; s++) {
    final c = testController(training: training, rules: rules, seed: s, match: match);
    c.newGame();
    if (coach) c.coachVisible = true;
    for (var guard = 0; guard < 120 && !c.isOver; guard++) {
      await pumpUntil(tester, () => c.isOver || _yourTurn(c));
      if (c.isOver) break;
      if (c.game.phase == phase && (!leading || c.game.isLead) && (!following || !c.game.isLead)) {
        if (phase == DdzPhase.playing && training) c.selectMove(c.coach!.pick);
        return c;
      }
      c.humanMove(easyMove(c));
    }
    c.dispose();
  }
  throw StateError('no deal reached $phase');
}

/// A deal played to its end (the player like an Easy bot), in a match to
/// the standard target unless [match] says otherwise.
Future<LandlordController> finishedGame(
  WidgetTester tester, {
  bool training = true,
  int seed = 1,
  MatchTarget match = landlordStandardMatch,
}) async {
  for (var s = seed; s < seed + 40; s++) {
    final c = testController(training: training, seed: s, match: match);
    c.newGame();
    for (var guard = 0; guard < 150 && !c.isOver; guard++) {
      await pumpUntil(tester, () => c.isOver || _yourTurn(c));
      if (c.isOver) break;
      c.humanMove(easyMove(c));
    }
    if (c.isOver && !c.thrownIn) return c;
    c.dispose();
  }
  throw StateError('no deal finished');
}

/// A deal the player and both bots passed (the default rules throw it in).
Future<LandlordController> thrownInGame(WidgetTester tester) async {
  for (var s = 1; s < 200; s++) {
    final c = testController(seed: s);
    c.newGame();
    for (var guard = 0; guard < 10 && !c.isOver && c.game.phase == DdzPhase.bidding; guard++) {
      await pumpUntil(tester, () => c.isOver || c.game.phase != DdzPhase.bidding || _yourTurn(c));
      if (c.isOver || c.game.phase != DdzPhase.bidding) break;
      c.humanMove(yours(const DdzBid(0)));
    }
    await pumpUntil(tester, () => c.isOver || c.game.phase != DdzPhase.bidding);
    if (c.thrownIn) return c;
    c.dispose();
  }
  throw StateError('nobody threw a deal in');
}

/// A Training game at normal speed stopped where the player can only pass
/// (the pass waits the bots' pause), and how many moves came before it.
Future<(LandlordController, int)> forcedPassGame(WidgetTester tester) async {
  for (var s = 1; s < 40; s++) {
    final c = testController(seed: s, speed: PlaybackSpeed.normal);
    c.newGame();
    for (var guard = 0; guard < 2000 && !c.isOver; guard++) {
      if (c.cantBeat) return (c, c.record.moves.length);
      if (_yourTurn(c)) {
        c.humanMove(easyMove(c));
      } else {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    c.dispose();
  }
  throw StateError('the player always had a choice');
}

/// Shows [c]'s game at [size] in [language].
Future<void> showGame(WidgetTester tester, LandlordController c, Size size, AppLanguage language) async {
  await pumpShot(
    tester,
    LandlordScreen(controller: c),
    size: size,
    language: language,
  );
  await tester.pump();
}

/// Closes the screen and lets the saving timers run out.
Future<void> closeGame(WidgetTester tester, LandlordController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  await tester.pump(const Duration(seconds: 1));
}

/// The record move text of a move for the player.
String yours(DdzMove move) => ddzMoveText(LandlordController.you, move);

/// Card [id] in the player's hand.
Finder handCard(int id) => find.byKey(ValueKey('${ddzFace(id)}#1'));

/// A point on the part of card [id] in view (the next card covers its
/// right side).
Offset onCard(WidgetTester tester, int id) {
  final box = tester.getRect(handCard(id));
  return Offset(box.left + box.width * 0.2, box.center.dy);
}

/// The player's turn to play, their hand moved about: two cards dragged to
/// new places and two picked.
Future<LandlordController> reordered(WidgetTester tester, {int seed = 1}) async {
  final c = await gameAt(tester, DdzPhase.playing, training: false, leading: true, seed: seed);
  c.clearSelection();
  c.reorder(0, 6);
  c.reorder(c.hand.length - 1, 2);
  c.toggle(c.hand[4]);
  c.toggle(c.hand[5]);
  return c;
}

/// The player's turn well into a deal (Free Play), [held] cards or fewer
/// in hand, one of them moved and one picked.
Future<LandlordController> lateGame(WidgetTester tester, {int held = 12}) async {
  for (var s = 1; s < 60; s++) {
    final c = testController(seed: s, training: false);
    c.newGame();
    for (var guard = 0; guard < 150 && !c.isOver; guard++) {
      await pumpUntil(
        tester,
        () => c.isOver || (c.seatToAct == LandlordController.you && c.forcedMove(LandlordController.you) == null),
      );
      if (c.isOver) break;
      if (c.game.phase == DdzPhase.playing && c.hand.length <= held && c.hand.length >= 6) {
        c.reorder(0, 4);
        c.toggle(c.hand[2]);
        return c;
      }
      c.humanMove(easyMove(c));
    }
    c.dispose();
  }
  throw StateError('no deal got there');
}
