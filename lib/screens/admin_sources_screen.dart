import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import 'admin_widgets.dart';
import '../l10n/l10n.dart';

/// The name of a metadata source in words.
String sourceName(String s) =>
    const {
      'google': 'Google Books',
      'openlibrary': 'Open Library',
      'amazon': 'Amazon',
      'tmdb': 'TMDB',
      'tvdb': 'TheTVDB',
      'igdb': 'IGDB',
      'wikipedia': 'Wikipedia',
      'wikidata': 'Wikidata',
      'imdb': 'IMDb',
      'fandom': 'Fandom',
    }[s] ??
    s;

String _stateWords(String s) => switch (s) {
  'needed' => 'Needs a key',
  'optional' => 'Works without a key',
  'builtin' => 'Built in',
  'ok' => 'Working',
  _ => s,
};

class _KeyField {
  const _KeyField(this.field, this.label, this.source, {this.secret = true});
  final String field, label, source;
  final bool secret;
}

final _keyFields = [
  _KeyField('tmdb_key', 'TMDB key', 'tmdb'),
  _KeyField('tvdb_key', 'TheTVDB key', 'tvdb'),
  _KeyField('tvdb_pin', 'TheTVDB PIN', 'tvdb'),
  _KeyField('igdb_client_id', 'IGDB client id', 'igdb'),
  _KeyField('igdb_secret', 'IGDB secret', 'igdb'),
  _KeyField('google_books_key', 'Google Books key', 'google'),
  _KeyField('amazon_cookie', 'Amazon cookie', 'amazon'),
  _KeyField('amazon_domain', 'Amazon domain', 'amazon', secret: false),
];

/// Who the server asks for details (books, films, people, pictures) and the keys it asks with. Each source can be
/// tested, a key can be set or cleared (a secret is never shown back), and Google Books' page reading switched on.
class AdminSourcesScreen extends StatefulWidget {
  const AdminSourcesScreen({super.key, required this.service});

  final AdminService service;

  @override
  State<AdminSourcesScreen> createState() => _AdminSourcesScreenState();
}

class _AdminSourcesScreenState extends State<AdminSourcesScreen> {
  List<MetadataSourceRow>? _sources;
  MetadataKeys? _keys;
  String? _problem;
  String? _asking;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final s = await widget.service.metadataSources();
      final k = await widget.service.metadataKeys();
      if (mounted) {
        setState(() {
          _sources = s;
          _keys = k;
          _problem = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _problem = '$e');
    }
  }

  Future<void> _test([String? source]) async {
    setState(() => _asking = source ?? 'all');
    final ok = await attempt(context, () => widget.service.testSources(source));
    if (ok) await _read();
    if (mounted) setState(() => _asking = null);
  }

  Future<void> _set(_KeyField f) async {
    final v = await askText(
      context,
      title: f.label,
      label: f.secret ? 'New value (kept secret)' : 'Value',
      secret: f.secret,
      initial: f.secret ? '' : (_keys?.text(f.field) ?? ''),
      yes: 'Save',
    );
    if (v == null || !mounted) return;
    final ok = await attempt(context, () async {
      _keys = await widget.service.saveMetadataKey(f.field, v.trim());
    });
    if (ok && mounted) {
      say(context, v.trim().isEmpty ? 'Cleared' : 'Saved');
      await _read();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sources = _sources, keys = _keys;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('metadata.help.metadata-sources.term')),
        actions: [
          IconButton(
            tooltip: context.tr('app.admin_sources.test_every_source'),
            icon: _asking == 'all'
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.network_check_rounded),
            onPressed: _asking == null ? () => _test() : null,
          ),
        ],
      ),
      body: _problem != null && sources == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _read,
                      child: Text(context.tr('common.source.retry')),
                    ),
                  ],
                ),
              ),
            )
          : sources == null || keys == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _read,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  AdminHeading(
                    context.tr('app.admin_sources.who_the_server_asks'),
                  ),
                  for (final s in sources)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(sourceName(s.source)),
                          subtitle: Text(
                            [
                              _stateWords(s.state),
                              if (s.areas.isNotEmpty) s.areas.join(', '),
                              if (s.works > 0 || s.people > 0)
                                '${s.works} works, ${s.people} people supplied',
                            ].join(' · '),
                          ),
                          trailing: _asking == s.source
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : IconButton(
                                  tooltip: context.tr(
                                    'app.admin_sources.test_x',
                                    {'x': sourceName(s.source)},
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  onPressed: _asking == null
                                      ? () => _test(s.source)
                                      : null,
                                ),
                          leading: Icon(
                            s.state == 'needed'
                                ? Icons.key_off_outlined
                                : Icons.cloud_done_outlined,
                            color: s.state == 'needed'
                                ? scheme.error
                                : scheme.primary,
                          ),
                        ),
                      ),
                    ),
                  AdminHeading(
                    context.tr('app.admin_sources.keys_and_credentials'),
                  ),
                  for (final f in _keyFields)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Card(
                        child: ListTile(
                          title: Text(f.label),
                          subtitle: Text(
                            f.secret
                                ? (keys.isSet(f.field)
                                      ? 'Saved'
                                      : context.tr('app.admin_sources.not_set'))
                                : (keys.text(f.field).isEmpty
                                      ? context.tr('app.admin_sources.not_set')
                                      : keys.text(f.field)),
                            style: text.bodySmall,
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _set(f),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Card(
                      child: SwitchListTile(
                        title: Text(
                          context.tr(
                            'app.admin_sources.read_google_books_pages',
                          ),
                        ),
                        subtitle: Text(
                          context.tr(
                            'app.admin_sources.without_a_key_read_the_public',
                          ),
                        ),
                        value: keys.flag('google_scrape'),
                        onChanged: (v) async {
                          final ok = await attempt(context, () async {
                            _keys = await widget.service.saveMetadataKey(
                              'google_scrape',
                              v,
                            );
                          });
                          if (ok) await _read();
                        },
                      ),
                    ),
                  ),
                  const AdminHeading('Search'),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Card(
                      child: ListTile(
                        title: Text(
                          context.tr(
                            'app.admin_sources.rebuild_the_search_index',
                          ),
                        ),
                        subtitle: Text(
                          context.tr(
                            'app.admin_sources.if_a_quote_does_not_turn',
                          ),
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            final ok = await attempt(
                              context,
                              widget.service.reindexSearch,
                            );
                            if (ok && context.mounted) {
                              say(
                                context,
                                context.tr(
                                  'app.admin_sources.the_search_index_is_rebuilt',
                                ),
                              );
                            }
                          },
                          child: Text(context.tr('account.reindex.action')),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
