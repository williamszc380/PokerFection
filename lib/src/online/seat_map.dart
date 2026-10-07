import '../engine/events.dart';

/// Turns the server's seat numbers into this device's and back. Every
/// device sees itself in seat 0 (where the table screen, the trackers and
/// the help expect the user), so seats are turned around the table:
/// local = server seat - [mySeat], wrapping around. This is the only place
/// seats are converted.
///
/// Turning the table changes nothing else: positions, the order of play
/// and the preflop games (see PreflopAdvisor.specFor, which starts from
/// the seat after the big blind) stay the same.
class SeatMap {
  const SeatMap(this.playerCount, this.mySeat) : assert(mySeat >= 0 && mySeat < playerCount);

  final int playerCount;

  /// This device's seat at the server.
  final int mySeat;

  int toLocal(int serverSeat) => (serverSeat - mySeat) % playerCount;
  int toServer(int localSeat) => (localSeat + mySeat) % playerCount;

  /// A list by server seat (stacks, say), reordered by local seat.
  List<T> listToLocal<T>(List<T> byServerSeat) =>
      List.unmodifiable([for (var s = 0; s < playerCount; s++) byServerSeat[toServer(s)]]);
  List<T> listToServer<T>(List<T> byLocalSeat) =>
      List.unmodifiable([for (var s = 0; s < playerCount; s++) byLocalSeat[toLocal(s)]]);

  Map<int, T> mapToLocal<T>(Map<int, T> byServerSeat) =>
      Map.unmodifiable({for (final MapEntry(:key, :value) in byServerSeat.entries) toLocal(key): value});
  Map<int, T> mapToServer<T>(Map<int, T> byLocalSeat) =>
      Map.unmodifiable({for (final MapEntry(:key, :value) in byLocalSeat.entries) toServer(key): value});

  /// [event] from the server, with every seat in it turned to local.
  GameEvent eventToLocal(GameEvent event) => _turn(event, toLocal, listToLocal, mapToLocal);

  /// [event] with local seats, turned back to the server's.
  GameEvent eventToServer(GameEvent event) => _turn(event, toServer, listToServer, mapToServer);

  List<GameEvent> eventsToLocal(Iterable<GameEvent> events) => [for (final e in events) eventToLocal(e)];

  static GameEvent _turn(
    GameEvent event,
    int Function(int) seat,
    List<T> Function<T>(List<T>) list,
    Map<int, T> Function<T>(Map<int, T>) map,
  ) =>
      switch (event) {
        HandStarted() => HandStarted(
            handNumber: event.handNumber,
            buttonSeat: seat(event.buttonSeat),
            stacks: list(event.stacks),
            positions: map(event.positions),
          ),
        AntesPosted() => AntesPosted(map(event.amounts)),
        BlindPosted() => BlindPosted(seat: seat(event.seat), amount: event.amount, isBigBlind: event.isBigBlind),
        HoleCardsDealt() => HoleCardsDealt(
            dealOrder: List.unmodifiable(event.dealOrder.map(seat)),
            cards: map(event.cards),
          ),
        ActionTaken() => ActionTaken(
            seat: seat(event.seat),
            kind: event.kind,
            chipsAdded: event.chipsAdded,
            streetBet: event.streetBet,
            isAllIn: event.isAllIn,
            street: event.street,
          ),
        UncalledBetReturned() => UncalledBetReturned(seat: seat(event.seat), amount: event.amount),
        BetsCollected() => BetsCollected(List.unmodifiable([
            for (final pot in event.pots) Pot(pot.amount, List.unmodifiable(pot.eligibleSeats.map(seat))),
          ])),
        BoardDealt() => event,
        HandsRevealed() => HandsRevealed(map(event.cards)),
        PotAwarded() => PotAwarded(
            potIndex: event.potIndex,
            amount: event.amount,
            shares: map(event.shares),
            winningHand: event.winningHand,
          ),
        HandEnded() => HandEnded(finalStacks: list(event.finalStacks), netChange: map(event.netChange)),
      };
}
