// A bot's seed on the host's device: what the host's device uses to play
// the bots of a game other than Hold'em can't be rebuilt by other members.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/seats.dart' show mixSeed;
import 'package:pokerfection/src/online/games/game_envelope.dart';
import 'package:pokerfection/src/online/protocol.dart';
import 'package:pokerfection/src/ui/online/online_game_ui.dart' show OnlineJob;
import 'package:pokerfection/src/ui/online/runner_client.dart';

import '../server/fake_runner.dart';
import 'fake_runner_ui.dart';
import 'room_kit.dart';

void main() {
  testWidgets("a bot's random choices can't be worked out by the other players: its seed isn't made only of what "
      'every member is sent (round, turn, seat)', (tester) async {
    final game = HighCardGame();
    final server = TestServer(games: {game.key: game});
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann'));
    host.send(ChooseGame(game: game.key));
    host.send(const AddBot(style: 'easy'));
    host.send(const AddBot(style: 'easy'));
    await server.wait(tester);
    // The host's device plays the bots, as its app's room would.
    final runner = RunnerClient(host, ui: HighCardUi(game), newJobs: highCardInlineJobs);
    // A guest who only watches, and keeps every view they are sent.
    final guest = server.client();
    await server.open(tester, guest, JoinRoom(code: host.room!.code, name: 'Ben'));
    final seen = <EnvelopeState>[];
    guest.attach((m) {
      if (m case ServerGameMessage(body: final EnvelopeState s)) seen.add(s);
    });
    HighCardBotJob.asked.clear();
    host.send(const StartGame());
    await server.until(tester, () => HighCardBotJob.asked.length >= 4, 'the bots played');
    // Every seed the bots used, worked out by the guest from public views alone.
    final guessed = {
      for (final s in seen)
        if (s.turn case final turn?) mixSeed(s.round, turn.turnId, turn.seat),
    };
    final used = [for (final (_, seed) in HighCardBotJob.asked) seed];
    expect(
      used.where(guessed.contains),
      isEmpty,
      reason: "the guest knows the seed of every bot move ($used), so the bot's choice for each possible hand "
          'can be replayed and matched to what it played',
    );
    runner.dispose();
    unawaited(host.close());
    unawaited(guest.close());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("when the bot's job can't run, its quick fallback move gets the same secret seed, never one the "
      'other players can work out', (tester) async {
    final game = HighCardGame();
    final server = TestServer(games: {game.key: game});
    final host = server.client();
    await server.open(tester, host, const CreateRoom(name: 'Ann'));
    host.send(ChooseGame(game: game.key));
    host.send(const AddBot(style: 'easy'));
    host.send(const AddBot(style: 'easy'));
    await server.wait(tester);
    final ui = _NoWorkerUi(game);
    final runner = RunnerClient(host, ui: ui, newJobs: highCardInlineJobs);
    final guest = server.client();
    await server.open(tester, guest, JoinRoom(code: host.room!.code, name: 'Ben'));
    final seen = <EnvelopeState>[];
    guest.attach((m) {
      if (m case ServerGameMessage(body: final EnvelopeState s)) seen.add(s);
    });
    host.send(const StartGame());
    await server.until(tester, () => ui.fallbackSeeds.length >= 4, 'the bots played their fallback moves');
    final guessed = {
      for (final s in seen)
        if (s.turn case final turn?) mixSeed(s.round, turn.turnId, turn.seat),
    };
    expect(ui.fallbackSeeds.where(guessed.contains), isEmpty, reason: '${ui.fallbackSeeds}');
    expect(ui.fallbackSeeds.toSet(), hasLength(ui.fallbackSeeds.length), reason: 'a seed for each turn');
    runner.dispose();
    unawaited(host.close());
    unawaited(guest.close());
    await server.wait(tester, const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });
}

/// High card on a device whose bot jobs can't start (a worker from another
/// build, say): every bot move is the fallback; the seeds it was given.
class _NoWorkerUi extends HighCardUi {
  _NoWorkerUi(HighCardGame super.game);

  final fallbackSeeds = <int>[];

  @override
  OnlineJob<Object?, Object?> botJob(Map<String, Object?> seatView, String level, {required int seed}) =>
      throw StateError('no worker for the bot job');

  @override
  String fallbackMove(Map<String, Object?> seatView, {required int seed}) {
    fallbackSeeds.add(seed);
    return super.fallbackMove(seatView, seed: seed);
  }
}
