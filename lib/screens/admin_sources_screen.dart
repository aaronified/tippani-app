import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import 'admin_widgets.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// The name of a metadata source in words.
String sourceName(String s) =>
    {
      'google': tx('vocab.source.google.label'),
      'openlibrary': tx('vocab.source.openlibrary.label'),
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
  'needed' => tx('app.admin_sources.needs_a_key'),
  'optional' => tx('app.admin_sources.works_without_a_key'),
  'builtin' => tx('app.admin_sources.built_in'),
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
  _KeyField(
    'google_books_key',
    tx('app.admin_sources.google_books_key'),
    'google',
  ),
  _KeyField('amazon_cookie', tx('app.admin_sources.amazon_cookie'), 'amazon'),
  _KeyField(
    'amazon_domain',
    tx('app.admin_sources.amazon_domain'),
    'amazon',
    secret: false,
  ),
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
      title: context.tr(f.label),
      label: f.secret
          ? context.tr('app.admin_sources.new_value_kept_secret')
          : 'Value',
      secret: f.secret,
      initial: f.secret ? '' : (_keys?.text(f.field) ?? ''),
      yes: context.tr('common.action.save.label'),
    );
    if (v == null || !mounted) return;
    final ok = await attempt(context, () async {
      _keys = await widget.service.saveMetadataKey(f.field, v.trim());
    });
    if (ok && mounted) {
      say(
        context,
        v.trim().isEmpty ? 'Cleared' : context.tr('settings.keys.saved.tip'),
      );
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
                : const Icon(Ti.wifi),
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
                                tx('app.admin_sources.supplied', {
                                  'works': countWords('work', s.works),
                                  'people': countWords('person', s.people),
                                }),
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
                                  icon: const Icon(Ti.playerPlayFilled),
                                  onPressed: _asking == null
                                      ? () => _test(s.source)
                                      : null,
                                ),
                          leading: Icon(
                            s.state == 'needed' ? Ti.keyOff : Ti.cloudCheck,
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
                          title: Text(context.tr(f.label)),
                          subtitle: Text(
                            f.secret
                                ? (keys.isSet(f.field)
                                      ? context.tr('settings.keys.saved.tip')
                                      : context.tr('app.admin_sources.not_set'))
                                : (keys.text(f.field).isEmpty
                                      ? context.tr('app.admin_sources.not_set')
                                      : keys.text(f.field)),
                            style: text.bodySmall,
                          ),
                          trailing: const Icon(Ti.pencil),
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
                  AdminHeading(context.tr('common.help.topbar.search.term')),
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
