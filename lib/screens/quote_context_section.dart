import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../library/models.dart';
import '../library/quote_chips.dart';
import '../theme/tabler.dart';
import '../tools/quote_context.dart';
import 'quote_context_screen.dart';

/// On the quote screen: a button that opens the quote's context viewer, where the server's stored text around the quote
/// is one scroller. Draws nothing for a quote that is not on the server or when there is no server to ask. A character or
/// person chosen in the viewer comes back as a [ChipFilter] and is handed on to [onFilter].
class QuoteContextSection extends StatelessWidget {
  const QuoteContextSection({
    super.key,
    required this.quote,
    required this.work,
    this.onFilter,
  });

  final Quote quote;
  final Work? work;
  final ValueChanged<ChipFilter>? onFilter;

  @override
  Widget build(BuildContext context) {
    final source = ContextScope.of(context);
    if (source == null || quote.serverId == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
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
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await Navigator.of(context).push<ChipFilter>(
                  MaterialPageRoute(
                    builder: (_) => ContextScope(
                      source: source,
                      child: QuoteContextScreen(quote: quote, work: work),
                    ),
                  ),
                );
                if (picked != null) onFilter?.call(picked);
              },
              icon: const Icon(Ti.article),
              label: Text(
                context.tr('app.quote_context.show_where_it_comes_from'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
