import '../engine/events.dart';

/// How long the table takes to show each event at Normal speed. The table
/// screen plays events back with these; online, the server also uses them
/// to give everyone time to watch an action before the next player's clock
/// starts (see [playbackMs]).
abstract final class Playback {
  static const chipMove = Duration(milliseconds: 380);
  static const cardMove = Duration(milliseconds: 260);
  static const dealGap = Duration(milliseconds: 70);

  /// How long a bot seems to think before it acts.
  static const botThink = Duration(milliseconds: 650);

  /// The pause after a hand starts, before antes and blinds.
  static const handStart = Duration(milliseconds: 250);

  /// The extra pause once the bets are in the middle.
  static const potSettle = Duration(milliseconds: 150);

  /// The gap between board cards, and the extra pause after them.
  static const boardGap = Duration(milliseconds: 120);
  static const boardSettle = Duration(milliseconds: 250);

  /// How long shown hands stay up before the pot is paid.
  static const reveal = Duration(milliseconds: 800);

  /// The extra pause after a pot is paid.
  static const awardSettle = Duration(milliseconds: 400);

  /// Paying a pot moves the chips a little slower than betting them
  /// (1.4 [chipMove]).
  static const awardMove = Duration(milliseconds: 532);

  /// The pause after a blind, a little shorter than after a bet (0.7
  /// [chipMove]).
  static const blindPause = Duration(milliseconds: 266);

  /// How long [event] takes to show at Normal speed.
  static Duration of(GameEvent event) => switch (event) {
        HandStarted() => handStart,
        AntesPosted() => chipMove,
        BlindPosted() => blindPause,
        HoleCardsDealt() => dealGap * (2 * event.dealOrder.length) + cardMove,
        ActionTaken() => chipMove,
        UncalledBetReturned() => chipMove,
        BetsCollected() => chipMove + potSettle,
        BoardDealt() => boardGap * event.cards.length + cardMove + boardSettle,
        HandsRevealed() => reveal,
        PotAwarded() => awardMove + awardSettle,
        HandEnded() => Duration.zero,
      };
}

/// Milliseconds the table takes to show [events] at Normal speed.
int playbackMs(Iterable<GameEvent> events) =>
    events.fold(Duration.zero, (sum, e) => sum + Playback.of(e)).inMilliseconds;

/// The clocks of an online table. Every limit is sent as time remaining,
/// so the devices' clocks don't need to agree.
abstract final class OnlineTiming {
  /// The time limits the host can pick for a decision, in seconds; 0 is
  /// no limit (the default). Players who are away or leaving, and bots,
  /// still act on their own clocks below.
  static const turnLimits = [0, 15, 30, 60, 90, 120];
  static const defaultTurnLimit = 0;

  /// Unshown extra time on every limit, for the network.
  static const grace = Duration(seconds: 1);

  /// Most time given to watch the actions before a turn's clock starts.
  static const maxWatch = Duration(seconds: 4);

  /// How long a player who is away (their link dropped) gets to act.
  static const awayLimit = Duration(seconds: 3);

  /// How long the host's device gets to play a bot's turn, and how long
  /// the bots wait while the host is away.
  static const botLimit = Duration(seconds: 12);
  static const hostAwayBotLimit = Duration(seconds: 1);

  /// How long a seat is kept for a player whose link dropped (for the
  /// host, how long the room waits for them before it closes).
  static const hold = Duration(seconds: 120);

  /// How long a device keeps trying to reconnect before it gives up (the
  /// hold, and a little more).
  static const giveUp = Duration(seconds: 150);

  /// A device that can't reconnect this many times in a row because nobody
  /// listens at the address any more (the host's app stopped) gives up at
  /// once: the room is gone.
  static const refusalsToGiveUp = 3;

  /// Devices say they're still there this often; a link that is silent
  /// for longer than the device's or the server's limit counts as dropped.
  static const ping = Duration(seconds: 10);
  static const clientSilence = Duration(seconds: 20);
  static const serverSilence = Duration(seconds: 25);

  /// Waits before each try to reconnect (the last one repeats), plus up to
  /// [backoffJitter] at random.
  static const backoff = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];
  static const backoffJitter = Duration(milliseconds: 250);

  /// Between hands: the least time to see the result, and how much longer
  /// the server waits for devices still solving the next hand (more when
  /// they give help).
  static const betweenHands = Duration(seconds: 3);
  static const readyWait = Duration(seconds: 3);
  static const readyWaitWithHelp = Duration(seconds: 10);

  /// A device asks for a fresh copy of the hand at most this often.
  static const resyncGap = Duration(seconds: 2);

  /// A player may send [chatBurst] chat messages in this long (the server
  /// refuses more).
  static const chatWindow = Duration(seconds: 8);

  /// A room where no hand is dealt for this long (in the lobby, or while
  /// it waits for players) closes.
  static const roomIdle = Duration(minutes: 30);
}
