import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/kit/jobs/jobs.dart';
import 'package:pokerfection/src/ui/kit/card_flights.dart';
import 'package:pokerfection/src/ui/kit/cards.dart';
import 'package:pokerfection/src/ui/kit/felt.dart';
import 'package:pokerfection/src/ui/kit/game_scaffold.dart';
import 'package:pokerfection/src/ui/kit/l10n/game_strings.dart';
import 'package:pokerfection/src/ui/kit/table_pile.dart';
import 'package:pokerfection/src/ui/games/big_two/l10n/big_two_strings.dart';
import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/ui/table_controller.dart' show PlaybackSpeed;

import 'nim.dart';
import 'shots.dart';

/// A table with a hand under it: tapping Play flies the picked cards from
/// the hand to the pile, as a game does in its applyMove.
class _Table extends StatefulWidget {
  const _Table({required this.flights});

  final CardFlights flights;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final hand = [for (var i = 0; i < 10; i++) CardFace.suited(i, i % 4)];
  final plays = <PilePlay>[];
  Future<void>? landed;

  /// Plays [faces] from the hand: the flights first (the hand still shows
  /// them), then the move.
  void play(List<CardFace> faces) {
    landed = widget.flights.fly([
      for (final (k, face) in faces.indexed)
        CardFlight(face: face, from: HandFan.flightTag(face), to: TablePile.flightTag(plays.length, k)),
    ]);
    setState(() {
      hand.removeWhere(faces.contains);
      plays.add(PilePlay(seat: 0, cards: faces, label: 'Pair'));
    });
  }

  /// A bot at seat 1 plays [faces]: they fly from its badge.
  void botPlay(List<CardFace> faces) {
    landed = widget.flights.fly([
      for (final (k, face) in faces.indexed)
        CardFlight(face: face, from: CardFlights.seatTag(1), to: TablePile.flightTag(plays.length, k)),
    ]);
    setState(() => plays.add(PilePlay(seat: 1, cards: faces)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CardFlightLayer(
      flights: widget.flights,
      child: Column(
        children: [
          Expanded(
            child: FeltArea(
              child: Stack(
                children: [
                  const Align(
                    alignment: Alignment.topRight,
                    child: FlightSpot(
                      tag: ('seat', 1),
                      child: SeatBadge(name: 'Ana', cardsLeft: 9),
                    ),
                  ),
                  Center(
                    child: TablePile(plays: plays, names: const ['Player', 'Ana']),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 100, child: HandFan(cards: hand)),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(loadShotFonts);

  Future<_TableState> table(WidgetTester tester, CardFlights flights) async {
    await pumpShot(tester, _Table(flights: flights), size: const Size(568, 320));
    return tester.state<_TableState>(find.byType(_Table));
  }

  Finder flying(int play, int card) => find.byKey(CardFlights.flyingKey(TablePile.flightTag(play, card)));

  testWidgets('a play flies from the hand to its place on the pile, which stays empty until it lands', (tester) async {
    final flights = CardFlights();
    final t = await table(tester, flights);
    final faces = [t.hand[3], t.hand[4]];
    final start = tester.getCenter(find.byKey(ValueKey('${faces[0]}#1')));
    var done = false;
    t.play(faces);
    t.landed!.then((_) => done = true);
    await tester.pump();
    expect(flying(0, 0), findsOneWidget);
    expect(flying(0, 1), findsOneWidget);
    expect(flights.isLanding(TablePile.flightTag(0, 0)), isTrue, reason: 'its place on the pile is drawn empty');
    final end = tester.getCenter(find.byKey(const ValueKey('pile play 0')));
    expect(
      tester.getCenter(flying(0, 0)),
      offsetMoreOrLessEquals(start, epsilon: 2),
      reason: 'it leaves from the hand',
    );

    await tester.pump(); // the flight starts on the next frame
    await tester.pump(const Duration(milliseconds: 150));
    final mid = tester.getCenter(flying(0, 0));
    expect(mid.dy, lessThan(start.dy - 10), reason: 'on its way up to the table');
    expect(mid.dy, greaterThan(end.dy - 60));
    expect(done, isFalse);
    await shot(tester, 'flight_mid_568x320');

    await tester.pump(const Duration(milliseconds: 400));
    expect(flying(0, 0), findsNothing);
    expect(flights.isLanding(TablePile.flightTag(0, 0)), isFalse);
    expect(done, isTrue, reason: 'fly() ends when the cards have landed');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets("a bot's play grows out of its seat", (tester) async {
    final flights = CardFlights();
    final t = await table(tester, flights);
    t.botPlay(const [CardFace.suited(12, 3)]);
    await tester.pump();
    await tester.pump(); // it shows once its landing place is known
    final seat = tester.getCenter(find.byType(SeatBadge));
    expect(tester.getCenter(flying(0, 0)), offsetMoreOrLessEquals(seat, epsilon: 2));
    await tester.pumpAndSettle();
    expect(flying(0, 0), findsNothing);
    expect(find.byKey(const ValueKey('pile play 0')), findsOneWidget);
  });

  testWidgets('the Animations setting sets the speed: Fast is quicker, Instant flies nothing', (tester) async {
    var speed = PlaybackSpeed.fast;
    final flights = CardFlights(speed: () => speed);
    final t = await table(tester, flights);
    t.play([t.hand[0]]);
    await tester.pump();
    expect(flying(0, 0), findsOneWidget);
    await tester.pump();
    await tester.pump(Duration(milliseconds: (CardFlights.duration.inMilliseconds * 0.35).round() + 20));
    expect(flying(0, 0), findsNothing, reason: 'Fast: about a third of the time');

    speed = PlaybackSpeed.instant;
    var done = false;
    t.play([t.hand[0]]);
    t.landed!.then((_) => done = true);
    await Future<void>.value();
    expect(done, isTrue, reason: 'Instant: done at once');
    await tester.pump();
    expect(flying(1, 0), findsNothing);
    expect(flights.isLanding(TablePile.flightTag(1, 0)), isFalse);
    expect(find.byKey(const ValueKey('pile play 1')), findsOneWidget, reason: 'the play is on the pile at once');
  });

  testWidgets('outside a game screen nothing flies, and fly() still ends', (tester) async {
    final flights = CardFlights();
    var done = false;
    flights.fly([const CardFlight(from: 'nowhere', to: 'nowhere either')]).then((_) => done = true);
    await tester.pump();
    expect(done, isTrue);
    flights.dispose();
  });

  testWidgets("the scaffold draws the game's flights, and they never hold up the turns", (tester) async {
    final game = _FlyingNim(jobs: Jobs.inline(extra: nimJobs));
    await game.newGame();
    await pumpShot(
      tester,
      GameScaffold(
        title: 'Big Two',
        strings: BigTwoStrings.forLanguage(AppLanguage.english) as GameStrings,
        controller: game,
        table: FeltArea(
          child: Stack(
            children: [
              const Align(
                alignment: Alignment.topLeft,
                child: FlightSpot(
                  tag: ('seat', 1),
                  child: SeatBadge(name: 'Ana'),
                ),
              ),
              Center(
                child: ListenableBuilder(
                  listenable: game,
                  builder: (context, _) => TablePile(plays: game.plays, names: const ['Player', 'Ana']),
                ),
              ),
            ],
          ),
        ),
        bottom: const HandFan(cards: [CardFace.suited(0, 0), CardFace.suited(1, 1), CardFace.suited(2, 2)]),
        panel: const SizedBox(height: 40),
      ),
      size: const Size(568, 320),
    );
    await tester.pump();
    game.humanMove('1');
    await tester.pump();
    expect(find.byKey(CardFlights.flyingKey(TablePile.flightTag(0, 0))), findsOneWidget);
    expect(game.flights.flying, isTrue);
    expect(game.seatToAct, 1, reason: "the bot's turn is on while the card is in the air");
    await tester.pump(const Duration(milliseconds: 700));
    expect(game.record.moves, hasLength(2), reason: 'the bot played after its usual pause');
    await tester.pumpAndSettle();
    expect(game.flights.flying, isFalse);
    await tester.pumpWidget(const SizedBox());
    game.dispose();
  });
}

/// Nim whose takes fly a card from the hand (the player) or the seat (the
/// bot) to the pile, at Normal speed.
class _FlyingNim extends NimController {
  _FlyingNim({required super.jobs}) : super(pile: 9, speed: PlaybackSpeed.normal);

  final plays = <PilePlay>[];

  @override
  void applyMove(int seat, String move) {
    super.applyMove(seat, move);
    final face = CardFace.suited(plays.length % 13, seat);
    flights.fly([
      CardFlight(
        face: face,
        from: seat == 0 ? HandFan.flightTag(const CardFace.suited(0, 0)) : CardFlights.seatTag(seat),
        to: TablePile.flightTag(plays.length, 0),
      ),
    ]);
    plays.add(PilePlay(seat: seat, cards: [face]));
  }
}
