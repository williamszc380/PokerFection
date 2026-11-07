import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'l10n/game_strings.dart';

/// A "?" that opens [terms] in a dialog: the games' explanations live here,
/// never in their panels or setup. Looks like poker's HelpButton.
class TermsHelpButton extends StatefulWidget {
  const TermsHelpButton({super.key, required this.title, required this.terms, this.all});

  final String title;
  final List<GameTerm> terms;

  /// The whole glossary, opened from the dialog's Glossary button (none: no button).
  final List<GameTerm>? all;

  /// Screens shorter than this (a phone held sideways) get the compact
  /// dialog, its buttons beside the title.
  static const compactBelow = 500.0;

  @override
  State<TermsHelpButton> createState() => _TermsHelpButtonState();
}

class _TermsHelpButtonState extends State<TermsHelpButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // Lights up under the mouse, so it clearly reads as clickable.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        customBorder: const CircleBorder(),
        mouseCursor: WidgetStateMouseCursor.clickable,
        hoverColor: accent.withValues(alpha: 0.2),
        onHover: (hovered) => setState(() => _hovered = hovered),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(Icons.help_outline, size: 18, color: _hovered ? accent : Colors.white60),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final s = S.of(context);
    final all = widget.all;
    showDialog<void>(
      context: context,
      builder: (context) {
        final glossary = all == null
            ? null
            : TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => GameGlossaryScreen(title: s.glossary, terms: all)),
                  );
                },
                child: Text(s.glossary),
              );
        final ok = FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.ok));
        final content = SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final term in widget.terms) TermEntry(term: term)],
            ),
          ),
        );
        // A phone held sideways (320-360 px high): a stock dialog's margins,
        // big title and row of buttons underneath leave the words a slot
        // about five lines high, and Big Two's presets take a page. So the
        // margins shrink and the buttons move up beside a smaller title,
        // giving the words most of the screen.
        if (MediaQuery.sizeOf(context).height < TermsHelpButton.compactBelow) {
          return AlertDialog(
            key: const ValueKey('terms help'),
            insetPadding: const EdgeInsets.all(8),
            titlePadding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                ?glossary,
                const SizedBox(width: 4),
                ok,
              ],
            ),
            content: content,
          );
        }
        return AlertDialog(
          key: const ValueKey('terms help'),
          title: Text(widget.title),
          content: content,
          actions: [?glossary, ok],
        );
      },
    );
  }
}

/// One glossary entry: the term, and what it means (poker's GlossaryEntry's look).
class TermEntry extends StatelessWidget {
  const TermEntry({super.key, required this.term});

  final GameTerm term;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Text(term.term, style: const TextStyle(fontWeight: FontWeight.w700));
          // Narrow (a phone held upright): the term above its meaning.
          if (constraints.maxWidth < 360) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, Text(term.definition)]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SizedBox(width: 130, child: title), Expanded(child: Text(term.definition))],
          );
        },
      ),
    );
  }
}

/// A game's whole glossary (☰ Glossary).
class GameGlossaryScreen extends StatelessWidget {
  const GameGlossaryScreen({super.key, required this.title, required this.terms});

  final String title;
  final List<GameTerm> terms;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        toolbarHeight: MediaQuery.sizeOf(context).height < 500 ? 44 : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [for (final term in terms) TermEntry(term: term)],
            ),
          ),
        ),
      ),
    );
  }
}
