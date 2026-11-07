import 'package:flutter/material.dart';

/// A guide (Rules, Threats, Hand ranks, Basic strategy...): titled
/// sections of short text, then any figures or tables, in a column no
/// wider than 640, as the Hand Rankings guide.
class GuidePage extends StatelessWidget {
  const GuidePage({super.key, required this.title, this.sections = const [], this.children = const []});

  final String title;
  final List<(String title, String body)> sections;

  /// Figures, tables or anything else, after the sections.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        toolbarHeight: MediaQuery.sizeOf(context).height < 500 ? 44 : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final (heading, body) in sections)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(heading, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                        const SizedBox(height: 4),
                        Text(body),
                      ],
                    ),
                  ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small table for guides: a header row of [columns], then [rows] of
/// cells (text or anything else). Scrolls sideways when it is wider than
/// the screen.
class GuideTable extends StatelessWidget {
  const GuideTable({super.key, required this.columns, required this.rows, this.cellWidth});

  final List<String> columns;
  final List<List<Widget>> rows;

  /// A fixed width for every column (charts); null: each fits its content.
  final double? cellWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: child);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: cellWidth == null ? const IntrinsicColumnWidth() : FixedColumnWidth(cellWidth!),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: const TableBorder(horizontalInside: BorderSide(color: Colors.white12)),
        children: [
          TableRow(
            children: [
              for (final column in columns)
                cell(Text(column, style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70))),
            ],
          ),
          for (final row in rows) TableRow(children: [for (final c in row) cell(c)]),
        ],
      ),
    );
  }
}
