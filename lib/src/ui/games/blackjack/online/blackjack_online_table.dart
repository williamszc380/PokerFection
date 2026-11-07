import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../../app/app_settings.dart';
import '../../../../games/blackjack/blackjack.dart';
import '../../../../l10n/strings.dart';
import '../../../kit/card_flights.dart';
import '../../../kit/cards.dart';
import '../../../kit/felt.dart';
import '../../../kit/game_sounds.dart';
import '../../../online/runner_client.dart';
import '../../../table_controller.dart' show PlaybackSpeed;
import '../blackjack_dealing.dart' show BlackjackDealing;
import '../blackjack_table.dart' show betsText, blackjackFace;
import '../l10n/blackjack_strings.dart';

/// The room's blackjack felt: the dealer's cards at the top (the hole card
/// face down until the dealer plays; face up for spectators while the
/// host's switch shows them the bots' cards), the shoe in the corner, and
/// along the bottom every seat of the round with its hands (side by side
/// after a split, the one to play outlined), each hand's total and, once
/// the round is over, how it ended; under them the seat's name (this
/// device's own seat says "Player") with its score, lit while it is that
/// seat's turn. This device's seat gets a little more room than the others.
///
/// As in the solo game, the cards of each move fly in from the shoe one by
/// one and the hole card turns over before the dealer draws
/// ([BlackjackFeltPlayback]); the totals count only the cards that have
/// landed, and the results wait for the dealer's last card.
class BlackjackOnlineTable extends StatefulWidget {
  const BlackjackOnlineTable({super.key, required this.client, required this.playback});

  final RunnerClient client;
  final BlackjackFeltPlayback playback;

  /// Space for a label line (a total, a name).
  static const labelHeight = 20.0;

  /// How much of each card shows under the next one.
  static const step = 0.44;

  @override
  State<BlackjackOnlineTable> createState() => _BlackjackOnlineTableState();
}

class _BlackjackOnlineTableState extends State<BlackjackOnlineTable> {
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onClient);
    final s = widget.client.state;
    widget.playback.see(s?.round, s?.view, seq: s?.seq, animate: false);
  }

  @override
  void didUpdateWidget(BlackjackOnlineTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeListener(_onClient);
      widget.client.addListener(_onClient);
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClient);
    widget.playback.finish();
    super.dispose();
  }

  /// A new view: its cards fly in, with the move's sound (on screen only).
  void _onClient() {
    if (!mounted) return;
    final c = widget.client;
    final speed = AppSettings.of(context).speed;
    final s = c.state;
    final news = widget.playback.see(s?.round, s?.view, seq: s?.seq, last: s?.last?.move, lastSeat: s?.last?.seat);
    if (news == null || !c.onScreen) return;
    final effect = switch (news) {
      FeltNews.dealt => SoundEffect.deal,
      FeltNews.hit => SoundEffect.deal,
      FeltNews.chips => SoundEffect.chips,
      FeltNews.stood => SoundEffect.check,
      FeltNews.surrendered => SoundEffect.fold,
    };
    GameSounds.play(effect, speed: speed);
    // This device's own round, once it has played out: its win or loss.
    final you = c.you;
    final nets = c.view?['nets'];
    if (widget.playback.justEnded && you != null && nets is List && you < nets.length && nets[you] is num) {
      final net = nets[you] as num;
      unawaited(
        widget.playback.done.then((_) {
          if (!mounted || !c.onScreen) return;
          if (net > 0) GameSounds.play(SoundEffect.win, speed: speed);
          if (net < 0) GameSounds.play(SoundEffect.lose, speed: speed);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    playback.speed = AppSettings.of(context).speed;
    return CardFlightLayer(
      flights: playback.flights,
      child: FeltArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([playback, playback.flights]),
          builder: (context, _) => LayoutBuilder(builder: (context, constraints) => _felt(context, constraints)),
        ),
      ),
    );
  }

  Widget _felt(BuildContext context, BoxConstraints constraints) {
    final c = widget.client;
    final view = c.view ?? const <String, Object?>{};
    final felt = FeltView.of(view, playback: widget.playback, flights: widget.playback.flights);
    final b = BlackjackStrings.of(context);
    final h = constraints.maxHeight, w = constraints.maxWidth;
    final shoe = (h * 0.09).clamp(16.0, 40.0);
    // Every seat's share of the width (this device's own a little more),
    // and the cards as big as the widest seat, the dealer's row and the
    // height allow.
    final seats = felt.seats.length;
    double flex(int s) => s == c.you && seats > 1 ? 1.5 : 1.0;
    final flexes = [for (var s = 0; s < seats; s++) flex(s)];
    final totalFlex = flexes.fold(0.0, (a, b) => a + b);
    double units(int cards) => 1 + BlackjackOnlineTable.step * (max(cards, 2) - 1);
    var byWidth = (w - 2 * (shoe + 14)) / units(felt.dealer.length + (felt.holeSlot ? 1 : 0));
    for (var s = 0; s < seats; s++) {
      final hands = felt.seats[s];
      final handUnits = hands.isEmpty
          ? units(2)
          : hands.map((hand) => units(hand.cards.length)).reduce((a, b) => a + b) + 0.3 * (hands.length - 1);
      byWidth = min(byWidth, (w * flexes[s] / totalFlex - 8) / handUnits);
    }
    final labels = 3 * BlackjackOnlineTable.labelHeight + 30;
    final byHeight = (h - labels) / 2 / cardAspectRatio;
    final cardWidth = max(14.0, min(min(byHeight, byWidth), 110.0));
    final height = min(h, 2 * cardWidth * cardAspectRatio + labels + 90);
    return Stack(
      children: [
        Center(
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                _DealerRow(felt: felt, cardWidth: cardWidth, strings: b),
                Expanded(
                  child: Center(
                    child: _Middle(felt: felt, client: c, strings: b),
                  ),
                ),
                SizedBox(
                  height: cardWidth * cardAspectRatio + 2 * BlackjackOnlineTable.labelHeight + 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var s = 0; s < seats; s++)
                        Expanded(
                          flex: (flexes[s] * 10).round(),
                          child: _SeatColumn(felt: felt, seat: s, client: c, cardWidth: cardWidth, strings: b),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(right: 6, top: 6, child: _Shoe(width: shoe)),
      ],
    );
  }
}

/// What a view brought to the felt, for its sound.
enum FeltNews { dealt, hit, chips, stood, surrendered }

/// A card's place on the felt, for its flight: the dealer's card [i] of
/// round [round] ...
Object onlineDealerTag(int round, int i) => ('blackjack online dealer', round, i);

/// ... or card [i] of hand [hand] of hand seat [seat].
Object onlineHandTag(int round, int seat, int hand, int i) => ('blackjack online hand', round, seat, hand, i);

/// One beat of a view playing out: a card flying to its place, or the hole
/// card turning over.
class _Beat {
  const _Beat.card(this.to, this.face, {this.from = CardFlights.shoeTag, this.faceUp = true}) : turn = false;
  const _Beat.turn() : to = null, face = null, from = CardFlights.shoeTag, faceUp = true, turn = true;

  final Object? to;
  final Object from;
  final CardFace? face;
  final bool faceUp;
  final bool turn;
}

/// Plays each new view out on the felt, as the solo game's
/// BlackjackDealing does a move: the cards it brought fly in one after
/// another from the shoe (at the Animations setting's speed), each place
/// empty until its card lands, and the hole card stays face down until
/// its turn comes. The views come whole from the room; this only holds
/// back what the felt shows. While a deal or the dealer's play is playing
/// out, the buttons wait ([busy]), as in the solo game.
///
/// One per game on this device (the table and the buttons share it).
class BlackjackFeltPlayback extends ChangeNotifier {
  BlackjackFeltPlayback() {
    flights = CardFlights(speed: () => speed);
  }

  /// The card flights the felt draws.
  late final CardFlights flights;

  /// The Animations setting (the table keeps it up to date).
  PlaybackSpeed speed = PlaybackSpeed.normal;

  int? _round, _seq;
  Map<String, Object?>? _view;

  /// The last view took the round to its end (its results are in).
  bool justEnded = false;

  /// Places whose card hasn't left the shoe yet.
  final Set<Object> _held = {};
  bool _holeHeld = false;
  bool _busy = false;
  int _generation = 0;
  Completer<void> _done = Completer<void>()..complete();
  Timer? _timer;
  Completer<void>? _waiting;
  var _disposed = false;

  /// A deal or the dealer's play is playing out: the buttons wait.
  bool get busy => _busy;

  /// Completes when the view being played out has landed.
  Future<void> get done => _done.future;

  /// Whether the card at [tag] is still held back (its place is empty).
  bool held(Object tag) => _held.contains(tag);

  /// The hole card stays face down though the view has turned it over.
  bool get holeHeld => _holeHeld;

  /// Takes in round [round]'s [view], its [seq]th message (the move before
  /// it: [last], by [lastSeat]); plays out what it brought unless [animate]
  /// is false (the first view seen: shown as it is). Returns what it
  /// brought, for the sound, or null for nothing new.
  FeltNews? see(int? round, Map<String, Object?>? view, {int? seq, String? last, int? lastSeat, bool animate = true}) {
    justEnded = false;
    if (view == null || round == null) return null;
    final oldView = _view, oldRound = _round, oldSeq = _seq;
    if (identical(view, oldView)) return null;
    _view = view;
    _round = round;
    _seq = seq;
    if (!animate || oldView == null) return null;
    // The same message again (the room sends the view whenever someone
    // comes or goes): nothing new to play.
    if (oldRound == round && oldSeq == seq) return null;
    justEnded = view['nets'] != null && (oldView['nets'] == null || oldRound != round);
    final newRound = oldRound != round;
    final beats = _beats(oldView, view, round, newRound: newRound, last: last, lastSeat: lastSeat);
    final dealerPlays = view['nets'] != null && oldView['nets'] == null;
    if (beats.isNotEmpty) _play(beats, busy: newRound || dealerPlays);
    if (newRound) return FeltNews.dealt;
    final letter = last != null && last.length == 3 ? last[2] : null;
    return switch (letter) {
      'H' => FeltNews.hit,
      'D' || 'P' || 'I' => FeltNews.chips,
      'R' => FeltNews.surrendered,
      'S' || 'N' || 'K' => FeltNews.stood,
      _ => null,
    };
  }

  /// The beats from [old] to [view]: in a new round the deal as a dealer
  /// deals it (a card to each seat, the upcard, a second card each, the
  /// hole card face down); then the players' new cards in turn (a split's
  /// second card sliding over to its own hand first); the hole card turning
  /// over; the dealer's draws.
  List<_Beat> _beats(
    Map<String, Object?> old,
    Map<String, Object?> view,
    int round, {
    required bool newRound,
    String? last,
    int? lastSeat,
  }) {
    final now = FeltView.of(view), before = newRound ? null : FeltView.of(old);
    final beats = <_Beat>[];
    final done = <Object>{};
    bool had(int seat, int hand, int i, String card) {
      final hands = before?.seats.elementAtOrNull(seat);
      final cards = hands?.elementAtOrNull(hand)?.cards;
      return cards != null && i < cards.length && cards[i] == card;
    }

    void toHand(int s, int h, int i, {Object? from}) {
      final tag = onlineHandTag(round, s, h, i);
      if (done.add(tag)) {
        beats.add(_Beat.card(tag, faceOf(now.seats[s][h].cards[i]), from: from ?? CardFlights.shoeTag));
      }
    }

    final holeRule = now.rules?.holeCard ?? true;
    if (newRound) {
      for (var i = 0; i < 2; i++) {
        for (var s = 0; s < now.seats.length; s++) {
          if (now.seats[s].isNotEmpty && now.seats[s][0].cards.length > i) toHand(s, 0, i);
        }
        if (i == 0 && now.dealer.isNotEmpty) {
          done.add(onlineDealerTag(round, 0));
          beats.add(_Beat.card(onlineDealerTag(round, 0), faceOf(now.dealer[0])));
        }
      }
      if (holeRule && now.holeSlot) {
        // Face down, or face up for spectators while the host's switch
        // shows them the bots' cards.
        final hole = now.hole;
        done.add(onlineDealerTag(round, 1));
        beats.add(_Beat.card(onlineDealerTag(round, 1), hole == null ? null : faceOf(hole), faceUp: hole != null));
      } else if (holeRule && now.dealer.length > 1) {
        // The round ended at the deal (the dealer's blackjack): the hole
        // card comes face down, then turns over.
        done.add(onlineDealerTag(round, 1));
        beats.add(_Beat.card(onlineDealerTag(round, 1), faceOf(now.dealer[1]), faceUp: false));
        beats.add(const _Beat.turn());
      }
    }
    // A split: the pair's second card slides over to the new hand.
    if (!newRound && last != null && last.endsWith(':P') && lastSeat != null && lastSeat < now.seats.length) {
      final h = int.tryParse(last.substring(0, last.length - 2));
      if (h != null && h + 1 < now.seats[lastSeat].length && now.seats[lastSeat][h + 1].cards.isNotEmpty) {
        toHand(lastSeat, h + 1, 0, from: onlineHandTag(round, lastSeat, h, 1));
      }
    }
    for (var s = 0; s < now.seats.length; s++) {
      for (var h = 0; h < now.seats[s].length; h++) {
        final cards = now.seats[s][h].cards;
        for (var i = 0; i < cards.length; i++) {
          if (!had(s, h, i, cards[i])) toHand(s, h, i);
        }
      }
    }
    // The hole card turns over (a spectator who saw it face up has nothing
    // to turn).
    if (!newRound && before!.holeSlot && before.hole == null && !now.holeSlot && now.dealer.length > 1) {
      beats.add(const _Beat.turn());
    }
    final from = newRound ? (holeRule ? 2 : 1) : (before!.dealer.length + (before.holeSlot ? 1 : 0));
    for (var i = max(from, 1); i < now.dealer.length; i++) {
      final tag = onlineDealerTag(round, i);
      if (done.add(tag)) beats.add(_Beat.card(tag, faceOf(now.dealer[i])));
    }
    return beats;
  }

  void _play(List<_Beat> beats, {required bool busy}) {
    finish();
    if (_disposed || speed.factor <= 0) return;
    for (final beat in beats) {
      if (beat.to case final to?) _held.add(to);
      if (beat.turn) _holeHeld = true;
    }
    _busy = busy;
    _done = Completer<void>();
    notifyListeners();
    unawaited(_run(beats, ++_generation));
  }

  Future<void> _run(List<_Beat> beats, int generation) async {
    final factor = speed.factor;
    Future<void>? lastFlight;
    for (final beat in beats) {
      if (generation != _generation) return;
      if (beat.turn) {
        // The hole card turns over once it is down, not in the air.
        await lastFlight;
        if (generation != _generation) return;
        _holeHeld = false;
        notifyListeners();
        await _wait(BlackjackDealing.turnOver * factor);
        continue;
      }
      _held.remove(beat.to);
      notifyListeners();
      lastFlight = flights.fly([CardFlight(from: beat.from, to: beat.to!, face: beat.face, faceUp: beat.faceUp)]);
      await _wait(BlackjackDealing.gap * factor);
    }
    if (generation != _generation) return;
    await lastFlight;
    if (generation != _generation) return;
    _end();
  }

  void _end() {
    _held.clear();
    _holeHeld = false;
    _busy = false;
    if (!_done.isCompleted) _done.complete();
    if (!_disposed) notifyListeners();
  }

  /// Shows everything now (a new view, the felt closing); cards in the air
  /// still land.
  void finish() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    if (_waiting case final waiting? when !waiting.isCompleted) waiting.complete();
    _waiting = null;
    if (_held.isEmpty && !_holeHeld && !_busy && _done.isCompleted) return;
    _end();
  }

  Future<void> _wait(Duration time) {
    final waiting = _waiting = Completer<void>();
    _timer = Timer(time, () {
      if (!waiting.isCompleted) waiting.complete();
    });
    return waiting.future;
  }

  @override
  void dispose() {
    finish();
    _disposed = true;
    flights.dispose();
    super.dispose();
  }
}

/// A card as the views write it ("As"), drawn by the kit.
CardFace faceOf(String card) => blackjackFace(Card.parse(card));

/// One hand of a view.
class FeltHand {
  const FeltHand({
    required this.cards,
    this.doubled = false,
    this.done = false,
    this.fromSplit = false,
    this.outcome,
    this.net,
  });

  final List<String> cards;
  final bool doubled, done, fromSplit;

  /// How it ended, once the round is over.
  final HandOutcome? outcome;
  final num? net;

  /// A two-card 21 not from a split.
  bool get isBlackjack => !fromSplit && cards.length == 2 && handTotal(cards.map(Card.parse)).value == 21;
}

/// A view read for the felt (anything unreadable left out), with what the
/// playback still holds back.
class FeltView {
  FeltView({
    required this.view,
    required this.round,
    required this.rules,
    required this.seats,
    required this.insured,
    required this.dealer,
    required this.holeSlot,
    required this.hole,
    required this.turn,
    required this.nets,
    this.playback,
    this.flights,
  });

  factory FeltView.of(Map<String, Object?> view, {BlackjackFeltPlayback? playback, CardFlights? flights}) {
    List<String> cards(Object? list) => [
      if (list is List)
        for (final c in list)
          if (c is String && _isCard(c)) c,
    ];
    BlackjackRules? rules;
    try {
      rules = BlackjackRules.fromJson(view['rules']);
    } on Object {
      rules = null;
    }
    final seats = <List<FeltHand>>[], insured = <bool>[];
    if (view['seats'] case final List<Object?> list) {
      for (final seat in list) {
        final hands = <FeltHand>[];
        if (seat is Map && seat['hands'] is List) {
          for (final hand in seat['hands'] as List) {
            if (hand is! Map) continue;
            hands.add(
              FeltHand(
                cards: cards(hand['c']),
                doubled: hand['x2'] == true,
                done: hand['done'] == true,
                fromSplit: hand['sp'] == true,
                outcome: HandOutcome.values.asNameMap()[hand['out']],
                net: hand['net'] is num ? hand['net'] as num : null,
              ),
            );
          }
        }
        seats.add(hands);
        insured.add(seat is Map && seat['ins'] == true);
      }
    }
    final turn = view['turn'];
    final hole = view['hole'];
    return FeltView(
      view: view,
      round: view['round'] is int ? view['round']! as int : 0,
      rules: rules,
      seats: seats,
      insured: insured,
      dealer: cards(view['dealer']),
      holeSlot: view['holeDown'] == true,
      hole: hole is String && _isCard(hole) ? hole : null,
      turn: turn is List && turn.length == 2 && turn[0] is int && turn[1] is int
          ? (seat: turn[0] as int, hand: turn[1] as int)
          : null,
      nets: [
        if (view['nets'] case final List<Object?> nets)
          for (final n in nets) n is num ? n : 0,
      ],
      playback: playback,
      flights: flights,
    );
  }

  static bool _isCard(String text) {
    try {
      Card.parse(text);
      return true;
    } on Object {
      return false;
    }
  }

  final Map<String, Object?> view;
  final int round;
  final BlackjackRules? rules;

  /// Each hand seat's hands.
  final List<List<FeltHand>> seats;
  final List<bool> insured;

  /// The dealer's cards that show; [holeSlot]: a face-down hole card after
  /// them (its face in [hole] for spectators while the host's switch is on).
  final List<String> dealer;
  final bool holeSlot;
  final String? hole;
  final ({int seat, int hand})? turn;

  /// Each seat's net, once the round is over (empty before).
  final List<num> nets;
  final BlackjackFeltPlayback? playback;
  final CardFlights? flights;

  bool get over => nets.isNotEmpty;

  /// The playback is still bringing cards in: results wait.
  bool get settling => playback?.busy ?? false;

  /// The card at [tag] is on the felt: dealt and landed.
  bool shows(Object tag) => !(playback?.held(tag) ?? false) && !(flights?.isLanding(tag) ?? false);

  /// The card at [tag] has been dealt (maybe still in the air).
  bool dealt(Object tag) => !(playback?.held(tag) ?? false);

  /// The dealer's cards in their places: those that show, then the hole
  /// card's place (null: its back) while it lies face down.
  List<String?> get dealerSlots => [...dealer, if (holeSlot) hole];
}

class _Shoe extends StatelessWidget {
  const _Shoe({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final edge = max(1.5, width * 0.06);
    return FlightSpot(
      tag: CardFlights.shoeTag,
      child: SizedBox(
        key: const ValueKey('shoe'),
        width: width + 2 * edge,
        height: width * cardAspectRatio + 2 * edge,
        child: Stack(
          children: [
            for (var i = 2; i >= 0; i--)
              Positioned(
                left: edge * i,
                top: edge * (2 - i),
                child: GameCardView(width: width, face: null, faceUp: false),
              ),
          ],
        ),
      ),
    );
  }
}

/// A short label on the felt, in a dark pill; [lit]: a gold edge (whose
/// turn it is).
class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.color = Colors.white, this.lit = false, super.key});

  final String text;
  final Color color;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xB312171B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: lit ? const Color(0xFFFFD54F) : Colors.transparent, width: 1.5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Color _netColor(num net) => net > 0
    ? const Color(0xFF81C784)
    : net < 0
    ? const Color(0xFFE57373)
    : Colors.white;

/// Cards overlapped from left to right; a null card is a back (the hole
/// card); [faceDown] turns the card at that index over. Each card's place
/// is [tag]ged for the card flying to it; a card still held back leaves its
/// place empty.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.cards, required this.cardWidth, required this.tag, required this.felt, this.faceDown});

  final List<String?> cards;
  final double cardWidth;
  final Object Function(int i) tag;
  final FeltView felt;
  final int? faceDown;

  @override
  Widget build(BuildContext context) {
    final step = cardWidth * BlackjackOnlineTable.step;
    final count = max(cards.length, 1);
    return SizedBox(
      width: cardWidth + step * (count - 1),
      height: cardWidth * cardAspectRatio,
      child: Stack(
        children: [
          for (var i = 0; i < cards.length; i++)
            if (felt.dealt(tag(i)))
              Positioned(
                left: i * step,
                child: GameCardView(
                  width: cardWidth,
                  face: cards[i] == null ? null : faceOf(cards[i]!),
                  faceUp: cards[i] != null && faceDown != i,
                  flightTag: tag(i),
                ),
              ),
        ],
      ),
    );
  }
}

class _DealerRow extends StatelessWidget {
  const _DealerRow({required this.felt, required this.cardWidth, required this.strings});

  final FeltView felt;
  final double cardWidth;
  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    final slots = felt.dealerSlots;
    final held = felt.playback?.holeHeld ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: BlackjackOnlineTable.labelHeight,
          child: Center(
            child: _Pill(key: const ValueKey('dealer total'), text: _label(held)),
          ),
        ),
        SizedBox(
          height: cardWidth * cardAspectRatio,
          child: slots.isEmpty
              ? null
              : _CardRow(
                  cards: slots,
                  cardWidth: cardWidth,
                  tag: (i) => onlineDealerTag(felt.round, i),
                  felt: felt,
                  // The hole card waits face down for its turn to flip.
                  faceDown: held ? 1 : null,
                ),
        ),
      ],
    );
  }

  /// "Dealer", "Dealer · 10" while one card shows (as players name an
  /// upcard), "Dealer · 17", "Dealer · Blackjack".
  String _label(bool held) {
    final landed = [
      for (var i = 0; i < felt.dealer.length; i++)
        if (felt.shows(onlineDealerTag(felt.round, i)) && !(held && i == 1)) Card.parse(felt.dealer[i]),
    ];
    if (landed.isEmpty) return strings.dealer;
    if (landed.length == 1) return '${strings.dealer} · ${BlackjackStrings.upcard(landed.first.rank)}';
    if (landed.length == 2 && felt.dealer.length == 2 && handTotal(landed).value == 21) {
      return '${strings.dealer} · ${strings.blackjackHand}';
    }
    return '${strings.dealer} · ${strings.total(handTotal(landed))}';
  }
}

/// Between the dealer and the seats: "Insured" for this device's seat while
/// it has insurance, and its round's result once played out.
class _Middle extends StatelessWidget {
  const _Middle({required this.felt, required this.client, required this.strings});

  final FeltView felt;
  final RunnerClient client;
  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    final you = client.you;
    if (you == null || you >= felt.seats.length) return const SizedBox.shrink();
    final insured = felt.insured[you];
    if (!felt.over || felt.settling) return insured ? _Pill(text: strings.insured) : const SizedBox.shrink();
    final net = felt.nets[you];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            betsText(net.toDouble()),
            key: const ValueKey('round result'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _netColor(net)),
          ),
          if (insured) _Pill(text: strings.insured),
        ],
      ),
    );
  }
}

/// One seat: its hands side by side (the one to play outlined), each
/// hand's total or outcome, and the seat's name and score.
class _SeatColumn extends StatelessWidget {
  const _SeatColumn({
    required this.felt,
    required this.seat,
    required this.client,
    required this.cardWidth,
    required this.strings,
  });

  final FeltView felt;
  final int seat;
  final RunnerClient client;
  final double cardWidth;
  final BlackjackStrings strings;

  @override
  Widget build(BuildContext context) {
    final hands = felt.seats[seat];
    final turn = felt.over ? null : felt.turn;
    final mine = client.you == seat;
    final primary = Theme.of(context).colorScheme.primary;
    final score = client.seatInfo(seat)?.score;
    final name = mine ? S.of(context).you : client.nameOf(seat);
    return Column(
      key: ValueKey('bj seat $seat'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomCenter,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = 0; h < hands.length; h++) ...[
                  if (h > 0) SizedBox(width: cardWidth * 0.3),
                  Column(
                    key: ValueKey('bj seat $seat hand $h'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(cardWidth * 0.12),
                          border: Border.all(
                            color: turn?.seat == seat && turn?.hand == h ? primary : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: _CardRow(
                            cards: hands[h].cards,
                            cardWidth: cardWidth,
                            tag: (i) => onlineHandTag(felt.round, seat, h, i),
                            felt: felt,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(height: BlackjackOnlineTable.labelHeight, child: _handLabel(h)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: BlackjackOnlineTable.labelHeight,
          child: _Pill(
            key: ValueKey('bj seat $seat name'),
            text: score == null ? name : '$name ${betsText(score.toDouble())}',
            color: mine ? const Color(0xFFFFE082) : Colors.white,
            lit: turn?.seat == seat,
          ),
        ),
      ],
    );
  }

  /// "17", "Soft 18 · ×2", and once played out "20 · Win +1" (a bust or a
  /// blackjack says so once: "Bust −1", "Blackjack +1.5"). While cards
  /// are coming, the total of those that have landed.
  Widget _handLabel(int h) {
    final hand = felt.seats[seat][h];
    final landed = [
      for (var i = 0; i < hand.cards.length; i++)
        if (felt.shows(onlineHandTag(felt.round, seat, h, i))) Card.parse(hand.cards[i]),
    ];
    if (landed.isEmpty) return const SizedBox.shrink();
    final doubled = hand.doubled ? ' · ×2' : '';
    final complete = landed.length == hand.cards.length;
    final total = complete && hand.isBlackjack ? strings.blackjackHand : strings.total(handTotal(landed));
    final key = ValueKey('bj seat $seat hand $h total');
    final outcome = hand.outcome, net = hand.net;
    if (outcome == null || net == null || outcome == HandOutcome.pending || felt.settling) {
      return _Pill(key: key, text: '$total$doubled');
    }
    final said = outcome == HandOutcome.bust || outcome == HandOutcome.blackjack;
    final text = said
        ? '${strings.outcome(outcome)}$doubled ${betsText(net.toDouble())}'
        : '$total$doubled · ${strings.outcome(outcome)} ${betsText(net.toDouble())}';
    return _Pill(key: key, text: text, color: _netColor(net));
  }
}
