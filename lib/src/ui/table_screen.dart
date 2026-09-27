import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_settings.dart';
import '../bots/bot.dart';
import '../engine/actions.dart';
import '../game/table_session.dart';
import '../gto/gto_solutions.dart';
import 'decision_panel.dart';
import 'format.dart';
import '../l10n/strings.dart';
import 'glossary.dart';
import 'history_screen.dart';
import 'range_screen.dart';
import 'table_controller.dart';
import 'table_geometry.dart';
import 'table_view_state.dart';
import 'widgets/card_view.dart';
import 'widgets/chip_stack.dart';
import 'widgets/seat_widget.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({
    super.key,
    required this.config,
    this.speed = PlaybackSpeed.normal,
    this.solutions,
  });

  final TableConfig config;
  final PlaybackSpeed speed;

  /// Where solved preflop games come from (the app-wide cache by default).
  final GtoSolutions? solutions;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  late final TableController _controller =
      TableController(widget.config, speed: widget.speed, solutions: widget.solutions);
  final _panel = GlobalKey<DecisionPanelState>();

  @override
  void initState() {
    super.initState();
    _controller.startNextHand();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _foldOrCheck() {
    final options = _controller.heroOptions;
    // With a strategy to enter, the buttons in the panel decide instead.
    if (options == null || _controller.heroSpot != null) return;
    _controller.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.fold());
  }

  void _checkOrCall() {
    final options = _controller.heroOptions;
    if (options == null || _controller.heroSpot != null) return;
    _controller.heroAct(options.canCheck ? const PlayerAction.check() : const PlayerAction.call());
  }

  /// A player's options (Guess the GTO mode): range, and for bots their
  /// style and whether their cards are shown.
  Future<void> _seatMenu(BuildContext context, int seat) async {
    final session = _controller.session;
    final isHero = seat == TableSession.heroSeat;
    final hand = session.hand;
    final s = S.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(isHero ? s.you : session.players[seat].name),
              subtitle: Text(hand == null ? '' : hand.positionOf(seat).label),
            ),
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: Text(isHero ? s.yourRange : s.showRange),
              enabled: hand != null,
              onTap: () => Navigator.of(context).pop('range'),
            ),
            if (!isHero) ...[
              ListTile(
                leading: const Icon(Icons.psychology_alt_outlined),
                title: Text(s.changeStyle),
                trailing: Text(session.hiddenStyles[seat] ? '' : s.style(session.styles[seat]!)),
                onTap: () => Navigator.of(context).pop('style'),
              ),
              ListTile(
                leading: Icon(session.revealedSeats.contains(seat) ? Icons.visibility_off : Icons.visibility),
                title: Text(session.revealedSeats.contains(seat) ? s.hideTheirCards : s.showTheirCards),
                onTap: () => Navigator.of(context).pop('cards'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'range':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => RangeScreen(session: session, only: seat)),
        );
      case 'style':
        await _pickStyle(context, seat);
      case 'cards':
        _controller.toggleCards(seat);
    }
  }

  /// Lets the user change one bot's style (Guess the GTO mode).
  Future<void> _pickStyle(BuildContext context, int seat) async {
    final session = _controller.session;
    final current = session.hiddenStyles[seat] ? null : session.styles[seat];
    final s = S.of(context);
    final picked = await showModalBottomSheet<(BotStyle?,)>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('${session.players[seat].name} · ${s.changeStyle}'),
              trailing: const HelpButton(section: GlossarySection.styles),
            ),
            for (final style in const [BotStyle.gto, BotStyle.tag, BotStyle.lag, BotStyle.station, BotStyle.nit])
              ListTile(
                leading: Icon(style == current ? Icons.check_circle : Icons.radio_button_unchecked),
                title: Text(s.style(style)),
                onTap: () => Navigator.of(context).pop((style,)),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _controller.setStyle(seat, picked.$1);
  }

  /// Everything the top bar offers, behind one ☰ button.
  Widget _menu(BuildContext context) {
    final session = _controller.session;
    final training = session.config.guessGto;
    final s = S.of(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu),
      onSelected: (choice) {
        switch (choice) {
          case 'cards':
            _controller.toggleAllCards();
          case 'ranges':
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RangeScreen(session: session)));
          case 'history':
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HistoryScreen(session: session)));
          case 'shuffle':
            _controller.shuffleStyles();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.newStylesDealt)),
            );
          case 'glossary':
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlossaryScreen()));
          case 'leave':
            Navigator.of(context).pop();
        }
      },
      itemBuilder: (context) {
        PopupMenuItem<String> item(String value, IconData icon, String text, {bool enabled = true}) =>
            PopupMenuItem(
              value: value,
              enabled: enabled,
              height: 40,
              child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(text)]),
            );
        return [
          if (training) ...[
            item('cards', _controller.allCardsShown ? Icons.visibility_off : Icons.visibility,
                _controller.allCardsShown ? s.hideAllCards : s.showAllCards),
            item('ranges', Icons.grid_view, s.ranges, enabled: session.hand != null),
            item('history', Icons.history, s.history),
            item('shuffle', Icons.shuffle, s.shuffleStyles),
            const PopupMenuDivider(),
          ],
          item('glossary', Icons.help_outline, s.glossary),
          item('leave', Icons.home_outlined, s.mainMenu),
        ];
      },
    );
  }

  /// Enter: deals the next hand, continues after a score, or plays the
  /// choice made in the panel.
  void _nextHand() {
    if (_controller.handOver) {
      _controller.startNextHand();
    } else if (_controller.heroScore != null) {
      _controller.continueHand();
    } else if (_controller.heroMenu != null) {
      _panel.currentState?.submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final session = _controller.session;
        final s = S.of(context);
        return Scaffold(
          backgroundColor: const Color(0xFF0B0F12),
          appBar: AppBar(
            backgroundColor: const Color(0xFF12171B),
            // Phones are played sideways: keep the bar slim when height is short.
            toolbarHeight: MediaQuery.sizeOf(context).height < 500 ? 44 : null,
            // Leaving the table is in the menu (Main Menu), not a back arrow.
            automaticallyImplyLeading: false,
            title: Text(session.config.guessGto ? s.training : s.freePlay),
            actions: [
              if (session.handsFinished > 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    // Training: EV given up against optimal play (chips are mostly luck).
                    child: session.config.guessGto
                        ? Text(
                            '${s.evLoss} '
                            '${session.history.fold(0.0, (sum, h) => sum + h.evLost).toStringAsFixed(2)} BB · '
                            '${s.handsPlayed(session.handsFinished)}',
                            style: const TextStyle(color: Color(0xFFFFE082)),
                          )
                        : Text(
                            '${formatSignedBb(session.heroNet)} · ${s.handsPlayed(session.handsFinished)}',
                            style: TextStyle(
                              color: session.heroNet >= 0 ? const Color(0xFF81C784) : const Color(0xFFE57373),
                            ),
                          ),
                  ),
                ),
              _menu(context),
            ],
          ),
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyF): _foldOrCheck,
              const SingleActivator(LogicalKeyboardKey.keyC): _checkOrCall,
              const SingleActivator(LogicalKeyboardKey.keyN): _nextHand,
              const SingleActivator(LogicalKeyboardKey.enter): _nextHand,
            },
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final table = LayoutBuilder(
                    builder: (context, area) => _TableArea(
                      controller: _controller,
                      geometry: TableGeometry(area.biggest, _controller.playerCount),
                      onSeatMenu: session.config.guessGto ? (seat) => _seatMenu(context, seat) : null,
                    ),
                  );
                  final panel = DecisionPanel(key: _panel, controller: _controller);
                  // Landscape (phones are played sideways): the table on the left
                  // half, the decisions on the right. Portrait: one above the other.
                  if (constraints.maxWidth >= constraints.maxHeight) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: table),
                        SizedBox(width: constraints.maxWidth / 2, child: panel),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: table),
                      SizedBox(height: constraints.maxHeight * 0.5, child: panel),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Places [child] so that its center is at [point].
Widget _centeredAt(Offset point, Widget child, {Key? key}) => Positioned(
      key: key,
      left: point.dx,
      top: point.dy,
      child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: child),
    );

class _TableArea extends StatelessWidget {
  const _TableArea({required this.controller, required this.geometry, this.onSeatMenu});

  final TableController controller;
  final TableGeometry geometry;

  /// Opens a seat's options (Guess the GTO mode).
  final ValueChanged<int>? onSeatMenu;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    final view = controller.view;
    final seatSize = SeatWidget.sizeFor(g);
    final livePots = [for (final (i, amount) in view.pots.indexed) if (amount > 0) (i, amount)];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _FeltPainter(g, AppSettings.of(context).felt))),

        for (final (i, card) in view.board.indexed)
          _centeredAt(g.boardSlot(i), CardView(width: g.cardWidth, card: card), key: ValueKey('board$i')),

        if (livePots.isNotEmpty)
          _centeredAt(
            g.pot,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (_, amount) in livePots)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4 * g.scale),
                    child: ChipStack(amount: amount, chipSize: g.chipSize * 1.1),
                  ),
              ],
            ),
            key: const ValueKey('pot'),
          ),

        for (final (i, seat) in view.seats.indexed)
          if (seat.bet > 0)
            _centeredAt(g.bet(i), ChipStack(amount: seat.bet, chipSize: g.chipSize),
                key: ValueKey('bet$i')),

        for (final (i, seat) in view.seats.indexed)
          Positioned(
            key: ValueKey('seat$i'),
            left: g.seat(i).dx - seatSize.width / 2,
            top: g.seat(i).dy - g.seatBoxSize.height / 2 - g.seatCardsAbove,
            child: _Hoverable(
              onTap: onSeatMenu == null ? null : () => onSeatMenu!(i),
              builder: (hovered) => SeatWidget(
                seat: seat,
                geometry: g,
                isActing: view.actingSeat == i,
                isHero: i == TableSession.heroSeat,
                showStyle: controller.session.config.stylesVisible && !controller.session.hiddenStyles[i],
                onMore: onSeatMenu == null ? null : () => onSeatMenu!(i),
                hovered: hovered,
              ),
            ),
          ),

        if (view.buttonSeat != null)
          AnimatedPositioned(
            key: const ValueKey('dealer'),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            left: g.dealerButton(view.buttonSeat!).dx - 11 * g.scale,
            top: g.dealerButton(view.buttonSeat!).dy - 11 * g.scale,
            child: _DealerButton(size: 22 * g.scale),
          ),

        if (view.results.isNotEmpty)
          _centeredAt(
            g.center + Offset(0, g.cardHeight / 2 + 34 * g.scale),
            Container(
              constraints: BoxConstraints(maxWidth: g.size.width * 0.8),
              padding: EdgeInsets.symmetric(horizontal: 12 * g.scale, vertical: 6 * g.scale),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10 * g.scale),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final result in view.results)
                    Text(
                      _resultLine(S.of(context), result, view),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: const Color(0xFFFFE082), fontSize: 12.5 * g.scale),
                    ),
                ],
              ),
            ),
            key: const ValueKey('results'),
          ),

        for (final item in controller.flying) _Flight(key: ValueKey('flight${item.id}'), item: item, g: g),
      ],
    );
  }
}

/// Chips or a card travelling across the table.
class _Flight extends StatelessWidget {
  const _Flight({super.key, required this.item, required this.g});

  final FlyingItem item;
  final TableGeometry g;

  @override
  Widget build(BuildContext context) {
    final from = g.resolve(item.from);
    final to = g.resolve(item.to);
    final child = item.isCard
        ? CardView(width: g.cardWidth, card: item.card, faceUp: item.faceUp)
        : ChipStack(amount: item.chips, chipSize: g.chipSize, showLabel: false);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: item.duration,
      curve: Curves.easeInOutCubic,
      child: child,
      builder: (context, t, child) {
        // A slight arc looks more like a toss than a slide.
        final point = Offset.lerp(from, to, t)! - Offset(0, sin(pi * t) * 16 * g.scale);
        return _centeredAt(point, Opacity(opacity: item.fadeOut ? 1 - t : 1, child: child));
      },
    );
  }
}

class _DealerButton extends StatelessWidget {
  const _DealerButton({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Text(
        'D',
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: size * 0.55),
      ),
    );
  }
}

class _FeltPainter extends CustomPainter {
  _FeltPainter(this.g, this.felt);

  final TableGeometry g;
  final FeltStyle felt;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Rect.fromCenter(center: g.center, width: g.radiusX * 2 * 0.97, height: g.radiusY * 2 * 0.94);
    canvas.drawOval(
      rail.shift(Offset(0, 6 * g.scale)),
      Paint()
        ..color = Colors.black
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * g.scale),
    );
    canvas.drawOval(
      rail,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6D4C41), Color(0xFF3E2723)],
        ).createShader(rail),
    );
    final cloth = rail.deflate(12 * g.scale);
    canvas.drawOval(
      cloth,
      Paint()
        ..shader = RadialGradient(
          colors: [felt.center, felt.middle, felt.edge],
          stops: const [0, 0.65, 1],
        ).createShader(cloth),
    );
    canvas.drawOval(
      cloth.deflate(20 * g.scale),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * g.scale
        ..color = Colors.white.withValues(alpha: 0.08),
    );
    // Faint outlines where the board cards go.
    final slotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.12);
    for (var i = 0; i < 5; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: g.boardSlot(i), width: g.cardWidth, height: g.cardHeight),
          Radius.circular(g.cardWidth * 0.1),
        ),
        slotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_FeltPainter old) =>
      old.g.size != g.size || old.g.seatCount != g.seatCount || old.felt != felt;
}

/// One pot's result, e.g. "Bob wins 12 BB · Two Pair, Ks and 7s", or with
/// side pots "Side pot 1: Alice wins 30 BB · Flush, A high".
String _resultLine(S s, PotResult result, TableViewState view) {
  final e = result.award;
  String name(int seat) => seat == TableSession.heroSeat ? s.you : view.seats[seat].info.name;
  final amount = formatBb(e.amount, unit: true);
  final pot = e.potIndex > 0 ? '${s.sidePot(e.potIndex)}: ' : (result.sidePots ? '${s.mainPot}: ' : '');
  final winners = e.shares.keys.toList();
  final won = winners.length > 1
      ? s.split(s.listNames([for (final seat in winners) name(seat)]), amount)
      : s.wins(name(winners.single), amount, you: winners.single == TableSession.heroSeat);
  final hand = e.winningHand;
  return '$pot$won${hand == null ? '' : ' · ${s.hand(hand)}'}';
}

/// Something clickable that lights up under the mouse: shows the hand
/// cursor and tells [builder] when it is hovered.
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(bool hovered) builder;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    if (onTap == null) return widget.builder(false);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(onTap: onTap, child: widget.builder(_hovered)),
    );
  }
}
