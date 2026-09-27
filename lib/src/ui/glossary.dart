import 'package:flutter/material.dart';

import '../l10n/strings.dart';

export '../l10n/strings.dart' show GlossarySection, GlossaryTerm;

/// A small "?" next to a setting or heading: shows the glossary entries of
/// [section], or just [terms] (from any section), with a link to the whole
/// glossary.
class HelpButton extends StatefulWidget {
  const HelpButton({super.key, required this.section, this.terms});

  final GlossarySection section;
  final List<GlossaryTerm>? terms;

  @override
  State<HelpButton> createState() => _HelpButtonState();
}

class _HelpButtonState extends State<HelpButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // Lights up under the mouse, so it clearly reads as clickable.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        customBorder: const CircleBorder(),
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

  /// Shows the section's entries (or just the chosen terms).
  void _open(BuildContext context) {
    final s = S.of(context);
    final section = widget.section;
    final entries = widget.terms ?? [for (final term in GlossaryTerm.values) if (term.section == section) term];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.section(section)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final term in entries) GlossaryEntry(term: term)],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlossaryScreen()));
            },
            child: Text(s.fullGlossary),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.ok)),
        ],
      ),
    );
  }
}

/// One glossary entry: the term, and what it means.
class GlossaryEntry extends StatelessWidget {
  const GlossaryEntry({super.key, required this.term});

  final GlossaryTerm term;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(s.term(term), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(s.definition(term))),
        ],
      ),
    );
  }
}

/// Every glossary entry, by section.
class GlossaryScreen extends StatelessWidget {
  const GlossaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.glossary)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final section in GlossarySection.values) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text(
                    s.section(section),
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                for (final term in GlossaryTerm.values)
                  if (term.section == section) GlossaryEntry(term: term),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
