import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../library/models.dart';
import '../tools/quote_context.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// What the server stored around a quote in its source file: a button to show it, then the text before, the quote as the
/// file has it, and the text after, with Show more on each side up to what is stored. It asks the server when pressed (the
/// context is not kept on the phone), says so when the server has none for this quote, and draws nothing for a quote that
/// is not on the server.
class QuoteContextSection extends StatefulWidget {
  const QuoteContextSection({
    super.key,
    required this.quote,
    required this.work,
  });

  final Quote quote;
  final Work? work;

  @override
  State<QuoteContextSection> createState() => _QuoteContextSectionState();
}

/// How many more units each Show more adds.
const contextStep = 3;

class _QuoteContextSectionState extends State<QuoteContextSection> {
  QuoteContext? _context;
  bool _asked = false;
  bool _busy = false;
  String? _problem;

  Future<void> _load({int? before, int? after}) async {
    final source = ContextScope.of(context);
    if (source == null) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final c = await source.fetch(
        widget.quote,
        widget.work,
        before: before,
        after: after,
      );
      if (!mounted) return;
      setState(() {
        _context = c;
        _asked = true;
      });
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ContextScope.of(context);
    if (source == null || widget.quote.serverId == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final c = _context;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('app.quote_context.context'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          if (!_asked && !_busy)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Ti.article),
                label: Text(
                  context.tr('app.quote_context.show_where_it_comes_from'),
                ),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_problem != null) ...[
            Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
            TextButton(
              onPressed: _load,
              child: Text(context.tr('common.source.retry')),
            ),
          ],
          if (_asked && c == null && _problem == null)
            Text(context.tr('app.quote_context.the_server_has_no_context_for')),
          if (c != null) ...[
            if (c.before.isNotEmpty)
              Text(
                c.before,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (c.boundBefore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  context.tr('app.quote_context.the_start_of_the_chapter_or'),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            if (c.canShowMoreBefore)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _load(
                        before: c.shownBefore + contextStep,
                        after: c.shownAfter,
                      ),
                child: Text(context.tr('app.quote_context.show_more_before')),
              ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                c.body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (c.after.isNotEmpty)
              Text(
                c.after,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (c.canShowMoreAfter)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _load(
                        before: c.shownBefore,
                        after: c.shownAfter + contextStep,
                      ),
                child: Text(context.tr('app.quote_context.show_more_after')),
              ),
            if (c.boundAfter)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  context.tr('app.quote_context.the_end_of_the_chapter_scene'),
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
