import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../harness/harness.dart' show BackupPicker;
import '../library/library_store.dart';
import '../library/models.dart';
import 'library_widgets.dart';
import 'quote_screen.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// The quotes that carry one tag, or match one search (a person's name, a work's title), as a plain list: the place
/// a name or a tag on a statistics or tags page leads to.
class FilteredQuotesScreen extends StatefulWidget {
  const FilteredQuotesScreen({
    super.key,
    required this.store,
    required this.picker,
    required this.title,
    this.tag,
    this.query = '',
    this.anthologies,
  });

  final LibraryStore store;
  final BackupPicker picker;

  /// The heading.
  final String title;

  /// Keeps only quotes with this tag.
  final String? tag;

  /// Keeps only quotes matching this search (words, who said it, the work, the tags).
  final String query;
  final AnthologyService? anthologies;

  @override
  State<FilteredQuotesScreen> createState() => _FilteredQuotesScreenState();
}

class _FilteredQuotesScreenState extends State<FilteredQuotesScreen> {
  List<Quote>? _quotes;
  final _works = <int, Work?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final quotes = await widget.store.quotes(
      tag: widget.tag,
      query: widget.query,
      limit: 1000,
    );
    for (final q in quotes) {
      final id = q.workId;
      if (id != null && !_works.containsKey(id)) {
        _works[id] = await widget.store.work(id);
      }
    }
    if (mounted) setState(() => _quotes = quotes);
  }

  @override
  Widget build(BuildContext context) {
    final quotes = _quotes;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: quotes == null
          ? const Center(child: CircularProgressIndicator())
          : quotes.isEmpty
          ? EmptyState(
              icon: Ti.quote,
              title: context.tr('app.filtered_quotes.no_quotes_here'),
              hint: context.tr(
                'app.filtered_quotes.nothing_on_this_phone_matches',
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                for (final q in quotes)
                  QuoteTile(
                    quote: q,
                    work: _works[q.workId],
                    onChip: (_) {},
                    onFavourite: () async {
                      await widget.store.setFavorite(q.id, !q.favorite);
                      await _load();
                    },
                    onTap: () async {
                      await Navigator.of(context).push<Object?>(
                        MaterialPageRoute(
                          builder: (_) => QuoteScreen(
                            store: widget.store,
                            quoteId: q.id,
                            picker: widget.picker,
                            anthologies: widget.anthologies,
                          ),
                        ),
                      );
                      await _load();
                    },
                  ),
              ],
            ),
    );
  }
}
