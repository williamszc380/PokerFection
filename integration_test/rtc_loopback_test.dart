// Two real direct connections (WebRTC, through flutter_webrtc) inside one
// app, joined by passing the offer, answer and candidates in memory instead
// of through the meeting service. It shows the app's WebRTC works on this
// device: it connects, carries the game's messages whole and in order, and
// notices a close at the other end.
//
//   flutter test integration_test/rtc_loopback_test.dart -d windows
//   flutter test --platform chrome integration_test/rtc_loopback_test.dart
//   flutter drive --profile -d windows --driver integration_test/driver.dart --target integration_test/rtc_loopback_test.dart
//
// Lines starting with "RTC:" are measurements (setup time, message times,
// memory), for the record.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pokerfection/src/online/channel_link.dart';
import 'package:pokerfection/src/online/rtc.dart';

import 'support/footprint.dart';
import 'support/loopback.dart';

void main() {
  // The apps reach the plugin through the real app's binding; a browser
  // needs none.
  if (!kIsWeb) IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final rtc = platformRtc();
  final pairs = <LoopbackPair>[];
  tearDown(() async {
    for (final p in pairs) {
      await p.close();
    }
    pairs.clear();
  });

  Future<LoopbackPair> connect({bool candidatesFirst = false}) async {
    final pair = await LoopbackPair.connect(rtc, candidatesFirst: candidatesFirst);
    _log('connected in ${pair.setupMs} ms');
    pairs.add(pair);
    return pair;
  }

  test('a guest and a host connect, with only a data channel in the offer', () async {
    final before = residentMb();
    final p = await connect();
    _log('setup ${p.setupMs} ms (create to both channels open)');
    expect(p.guest.state, RtcState.connected);
    expect(p.host.state, RtcState.connected);
    expect(p.guestChannel.isOpen && p.hostChannel.isOpen, isTrue);

    // One part, the data channel's: no audio or video.
    expect(RegExp(r'^m=', multiLine: true).allMatches(p.offerSdp).length, 1);
    expect(p.offerSdp, contains('m=application'));
    expect(RegExp(r'^m=', multiLine: true).allMatches(p.answerSdp).length, 1);
    // Each candidate says which part it is for, as the meeting service
    // needs: the first, '0'.
    expect(p.guestCandidates, isNotEmpty);
    expect(p.hostCandidates, isNotEmpty);
    for (final c in [...p.guestCandidates, ...p.hostCandidates]) {
      expect(c.candidate, startsWith('candidate:'));
      expect(c.sdpMid, '0');
      expect(c.sdpMLineIndex, 0);
    }
    _log('candidates: guest ${p.guestCandidates.length}, host ${p.hostCandidates.length}');
    _log('memory ${_mb(before)} before, ${_mb(residentMb())} with one connection');
  });

  test('candidates that come before the description wait for it', () async {
    final p = await connect(candidatesFirst: true);
    expect(p.guestChannel.isOpen && p.hostChannel.isOpen, isTrue);
  });

  test('text goes both ways whole: a 16 KB message and non-English text', () async {
    final p = await connect();
    final messages = sampleMessages(ChannelLink.maxMessage);
    expect(utf8.encode(messages[1]).length, ChannelLink.maxMessage);

    for (final (from, to, name) in [
      (p.guestChannel, p.hostInbox, 'guest to host'),
      (p.hostChannel, p.guestInbox, 'host to guest'),
    ]) {
      final start = Stopwatch()..start();
      messages.forEach(from.send);
      final got = await to.take(messages.length);
      _log('$name: 4 messages (one of 16 KB) in ${start.elapsedMilliseconds} ms');
      expect(got, messages);
    }
  });

  test('a burst of 500 messages arrives, all of them, in order', () async {
    final p = await connect();
    final burst = burstMessages();
    for (final (from, to, name) in [
      (p.guestChannel, p.hostInbox, 'guest to host'),
      (p.hostChannel, p.guestInbox, 'host to guest'),
    ]) {
      final start = Stopwatch()..start();
      burst.forEach(from.send);
      final got = await to.take(burst.length);
      _log('$name: 500 messages in ${start.elapsedMilliseconds} ms');
      expect(got, burst);
    }
  });

  for (final guestCloses in [true, false]) {
    final who = guestCloses ? 'guest' : 'host';
    test('the $who closing is seen at the other end', () async {
      final p = await connect();
      final (closer, other, otherChannel) = guestCloses
          ? (p.guest, p.host, p.hostChannel)
          : (p.host, p.guest, p.guestChannel);
      // What was sent just before the close still arrives.
      (guestCloses ? p.guestChannel : p.hostChannel).send('{"t":"last"}');
      final start = Stopwatch()..start();
      final closing = closer.close();
      await otherChannel.onClosed.timeout(const Duration(seconds: 10));
      _log('$who closed: other end saw its channel close after ${start.elapsedMilliseconds} ms');
      await closing;
      expect(closer.state, RtcState.closed);
      expect(await (guestCloses ? p.hostInbox : p.guestInbox).take(1), ['{"t":"last"}']);
      // Closing again does nothing, at either end.
      await closer.close();
      await other.close();
      await other.close();
      expect(otherChannel.isOpen, isFalse);
    });
  }

  test('a closed peer connection takes no part any more', () async {
    final peer = rtc.create();
    await peer.close();
    expect(peer.state, RtcState.closed);
    await expectLater(peer.offer(), throwsStateError);
    peer.addRemoteCandidate(const RtcCandidate('candidate:1 1 udp 1 10.0.0.1 1 typ host', sdpMid: '0'));
    await peer.close();
  });

  test('footprint: memory for 10 connections, processor time while idle', () async {
    // The app alone first, for comparison.
    final idleBefore = await cpuMs();
    final alone = Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds: 3));
    final idleAfter = await cpuMs();
    if (idleBefore != null && idleAfter != null) {
      final share = (idleAfter - idleBefore) / alone.elapsedMilliseconds * 100;
      _log('processor: ${share.toStringAsFixed(1)}% of one core with no connection');
    }
    final start = residentMb();
    final ten = [for (var i = 0; i < 10; i++) await connect()];
    final connected = residentMb();
    final cpuBefore = await cpuMs();
    final idle = Stopwatch()..start();
    // A game sends little: a few messages a second on each connection.
    for (var s = 0; s < 10; s++) {
      for (final p in ten) {
        p.guestChannel.send('{"t":"_rtc","op":"ping"}');
        p.hostChannel.send('{"t":"_rtc","op":"ping"}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final cpuAfter = await cpuMs();
    for (final p in ten) {
      await p.close();
    }
    pairs.removeWhere(ten.contains);
    await Future<void>.delayed(const Duration(seconds: 1));
    _log('memory ${_mb(start)} before, ${_mb(connected)} with 10 connections '
        '(20 ends), ${_mb(residentMb())} after closing them');
    if (cpuBefore != null && cpuAfter != null) {
      final share = (cpuAfter - cpuBefore) / idle.elapsedMilliseconds * 100;
      _log('processor: ${share.toStringAsFixed(1)}% of one core over '
          '${idle.elapsedMilliseconds} ms with 10 connections nearly idle');
    }
  });
}

String _mb(double? mb) => mb == null ? 'unknown' : '${mb.toStringAsFixed(1)} MB';

void _log(String line) => debugPrint('RTC: $line');
