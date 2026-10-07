import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../app/drills.dart';
import '../gto/gto_solutions.dart';
import '../l10n/strings.dart';
import 'format.dart';
import 'glossary.dart';
import 'history_screen.dart' show MiniCards;
import 'strategy_panel.dart' show GradeChip;
import 'table_controller.dart';
import 'table_screen.dart';

/// Drills, from the main menu: the table, dealing the saved spots that are
/// due, then random hands (see DrillController). With nothing saved yet, a
/// page says so first, with a button to play random hands.
class DrillScreen extends StatefulWidget {
  const DrillScreen({super.key, required this.drills, this.solutions});

  final Drills drills;

  /// Where solved preflop games come from (the app-wide cache by default).
  final GtoSolutions? solutions;

  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends State<DrillScreen> {
  /// The table's, once it is on (the table owns it).
  DrillController? _controller;

  DrillController _newController() =>
      DrillController(widget.drills, speed: AppSettings.of(context).speed, solutions: widget.solutions);

  @override
  Widget build(BuildContext context) {
    if (_controller == null && widget.drills.isEmpty) return _empty(context);
    return TableScreen.drills(controller: _controller ??= _newController());
  }

  /// Nothing saved yet: says so, with Play random hands.
  Widget _empty(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.drills)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_repeat, size: 48, color: Colors.white38),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      s.noSavedMistakes,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const HelpButton(section: GlossarySection.modes, terms: [GlossaryTerm.drills]),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('random hands'),
                onPressed: () => setState(() => _controller = _newController()),
                icon: const Icon(Icons.shuffle),
                label: Text(s.playRandomHands),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every saved spot (☰ in the drills), the next due first: the user's
/// cards and position, the board, how it was graded and when it is due.
class SavedSpotsScreen extends StatefulWidget {
  const SavedSpotsScreen({super.key, required this.drills});

  final Drills drills;

  @override
  State<SavedSpotsScreen> createState() => _SavedSpotsScreenState();
}

class _SavedSpotsScreenState extends State<SavedSpotsScreen> {
  /// When each spot is due changes with the time: shown again now and then.
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.drills, builder: _list);

  Widget _list(BuildContext context, Widget? _) {
    final s = S.of(context);
    final drills = widget.drills;
    final spots = [...drills.spots]..sort((a, b) => a.due.compareTo(b.due));
    final now = drills.now();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    return Scaffold(
      appBar: AppBar(
        title: Text('${s.savedSpots} (${spots.length})'),
        actions: const [HelpButton(section: GlossarySection.modes, terms: [GlossaryTerm.drills]), SizedBox(width: 8)],
      ),
      body: spots.isEmpty
          ? Center(child: Text(s.noSavedMistakes))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: spots.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final spot = spots[i];
                    final due = !spot.due.isAfter(now);
                    return ListTile(
                      leading: GradeChip(grade: spot.grade),
                      title: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        // On a narrow phone the cards shrink rather than overflow.
                        children: [
                          FittedBox(fit: BoxFit.scaleDown, child: MiniCards(cards: spot.cards.first)),
                          Text(spot.position.label),
                          if (spot.board.isNotEmpty)
                            FittedBox(fit: BoxFit.scaleDown, child: MiniCards(cards: spot.board)),
                        ],
                      ),
                      subtitle: Text(
                        '${s.street(spot.street)} · ${s.evLoss} ${spot.evLoss.toStringAsFixed(2)} BB',
                        style: muted,
                      ),
                      trailing: Text(
                        due ? s.dueNow : s.reviewIn(formatWait(s, spot.due.difference(now))),
                        style: TextStyle(color: due ? const Color(0xFFFFCC80) : Colors.white70),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
