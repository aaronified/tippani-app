import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../library/quote_chips.dart';
import '../people/people_console.dart';
import '../people/picture.dart';
import 'people_console_actions.dart';
import 'person_screen.dart';

/// Every person and character the server keeps: search them, see which have no photo, open one, rename its
/// spellings, merge two that are the same, remove one, make a character, and ask the server to fetch the photos
/// that are missing. Press and hold to choose several.
class PeopleConsoleScreen extends StatefulWidget {
  const PeopleConsoleScreen({
    super.key,
    required this.console,
    required this.onFilter,
    this.start = 0,
  });

  final PeopleConsole console;

  /// Pressing "Show their quotes" on a page: the caller filters the library by the name.
  final ValueChanged<ChipFilter> onFilter;

  /// 0 opens People, 1 opens Characters.
  final int start;

  @override
  State<PeopleConsoleScreen> createState() => _PeopleConsoleScreenState();
}

enum _Show { all, noPhoto, noLinks }

class _PeopleConsoleScreenState extends State<PeopleConsoleScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.start,
  );
  List<PersonRecord>? _people;
  List<CharacterRecord>? _characters;
  Orphans _orphans = const Orphans();
  String? _problem;
  String _query = '';
  _Show _show = _Show.all;
  String _kind = '';
  final _picked = <int>{};

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {
        _picked.clear();
        _show = _Show.all;
        _kind = '';
      });
    });
    _read();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _onCharacters => _tabs.index == 1;

  Future<void> _read() async {
    try {
      final p = await widget.console.people();
      final c = await widget.console.characters();
      Orphans o = const Orphans();
      try {
        o = await widget.console.orphans();
      } on ServerException {
        // the tidy-up count is a nicety
      }
      if (mounted) {
        setState(() {
          _people = p;
          _characters = c;
          _orphans = o;
          _problem = null;
          _picked.clear();
        });
      }
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  void _open(String name, int id, {required bool character}) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (_) => character
                ? CharacterScreen(
                    id: id,
                    name: name,
                    onFilter: (f) {
                      widget.onFilter(f);
                      Navigator.of(context).pop();
                    },
                  )
                : PersonScreen(
                    id: id,
                    name: name,
                    onFilter: (f) {
                      widget.onFilter(f);
                      Navigator.of(context).pop();
                    },
                  ),
          ),
        )
        .then((_) => _read());
  }

  Future<void> _merge() async {
    final rows = _onCharacters
        ? [
            for (final c in _characters!)
              if (_picked.contains(c.id))
                PickRow(
                  id: c.id,
                  name: c.name,
                  hint: countsHint(c.works, c.quotes),
                ),
          ]
        : [
            for (final p in _people!)
              if (_picked.contains(p.id))
                PickRow(
                  id: p.id,
                  name: p.name,
                  hint: countsHint(p.works, p.quotes),
                ),
          ];
    if (rows.length != 2) return;
    if (await mergeTwo(
      context,
      widget.console,
      character: _onCharacters,
      a: rows[0],
      b: rows[1],
    )) {
      await _read();
    }
  }

  Future<void> _fetch() async {
    if (await consoleCall(context, widget.console.fetchMissing) && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'The server is fetching photos and details for everyone who lacks them. It can take a while.',
            ),
          ),
        );
    }
  }

  Future<void> _prune() async {
    final n = _orphans.total;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove what nothing uses?'),
        content: Text(
          '${_orphans.people} ${_orphans.people == 1 ? 'person' : 'people'} and ${_orphans.characters} ${_orphans.characters == 1 ? 'character' : 'characters'} are in no work and on no quote. $n in all are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await consoleCall(context, widget.console.prune)) await _read();
  }

  Future<void> _addCharacter() async {
    final e = await characterForm(
      context,
      title: 'A new character',
      yes: 'Add',
    );
    if (e == null || !mounted) return;
    var id = 0;
    final ok = await consoleCall(context, () async {
      id = await widget.console.createCharacter(
        e.name!,
        description: e.description ?? '',
      );
      if (id != 0 &&
          ((e.born ?? '').isNotEmpty ||
              (e.links ?? '').isNotEmpty ||
              (e.note ?? '').isNotEmpty)) {
        await widget.console.saveCharacter(id, e);
      }
    });
    if (ok) await _read();
  }

  Future<void> _rowMenu(
    String v, {
    required int id,
    required String name,
    required List<String> spellings,
    required bool character,
  }) async {
    switch (v) {
      case 'names':
        if (await editSpellings(
          context,
          widget.console,
          character: character,
          id: id,
          names: [name, ...spellings],
        )) {
          await _read();
        }
      case 'delete':
        if (await removeRecord(
          context,
          widget.console,
          character: character,
          id: id,
          name: name,
        )) {
          await _read();
        }
    }
  }

  bool _matches(String name, List<String> spellings) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        spellings.any((s) => s.toLowerCase().contains(q));
  }

  Widget _face(String image, String name) {
    final scheme = Theme.of(context).colorScheme;
    return StoredPicture(
      name: image,
      width: 48,
      height: 48,
      circle: true,
      fallback: CircleAvatar(
        radius: 24,
        backgroundColor: scheme.secondaryContainer,
        child: Text(
          name.trim().isEmpty
              ? '?'
              : name.trim().characters.first.toUpperCase(),
          style: TextStyle(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }

  Widget _row({
    required int id,
    required String name,
    required String image,
    required String sub,
    required List<String> spellings,
    required bool character,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final picked = _picked.contains(id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: picked ? scheme.secondaryContainer : null,
        child: ListTile(
          leading: picked
              ? CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.check_rounded, color: scheme.onPrimary),
                )
              : _face(image, name),
          title: Text(name),
          subtitle: Text(
            [
              if (sub.isNotEmpty) sub,
              if (spellings.isNotEmpty) 'also ${spellings.take(3).join(', ')}',
            ].join('\n'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: sub.isNotEmpty && spellings.isNotEmpty,
          onTap: () {
            if (_picked.isNotEmpty) {
              setState(() => picked ? _picked.remove(id) : _picked.add(id));
            } else {
              _open(name, id, character: character);
            }
          },
          onLongPress: () => setState(() => _picked.add(id)),
          trailing: _picked.isNotEmpty
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) => _rowMenu(
                    v,
                    id: id,
                    name: name,
                    spellings: spellings,
                    character: character,
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'names',
                      child: Text('Names and spellings'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _filters(List<Widget> extra) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: [
        for (final w in extra)
          Padding(padding: const EdgeInsets.only(right: 8), child: w),
      ],
    ),
  );

  Widget _peopleList() {
    final all = _people!;
    final kinds = {for (final p in all) ...p.kinds}.toList()..sort();
    final shown = [
      for (final p in all)
        if (_matches(p.name, p.spellings) &&
            (_show != _Show.noPhoto || p.noPhoto) &&
            (_show != _Show.noLinks || p.noLinks) &&
            (_kind.isEmpty || p.kinds.contains(_kind)))
          p,
    ];
    return Column(
      children: [
        _filters([
          for (final k in kinds)
            FilterChip(
              label: Text(_kindName(k)),
              selected: _kind == k,
              onSelected: (v) => setState(() => _kind = v ? k : ''),
            ),
          FilterChip(
            label: Text('No photo (${all.where((p) => p.noPhoto).length})'),
            selected: _show == _Show.noPhoto,
            onSelected: (v) =>
                setState(() => _show = v ? _Show.noPhoto : _Show.all),
          ),
          FilterChip(
            label: Text('No links (${all.where((p) => p.noLinks).length})'),
            selected: _show == _Show.noLinks,
            onSelected: (v) =>
                setState(() => _show = v ? _Show.noLinks : _Show.all),
          ),
        ]),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _read,
            child: shown.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(48),
                        child: Text(
                          all.isEmpty
                              ? 'No one is saved yet. People appear as quotes and works name them.'
                              : 'No one matches.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final p in shown)
                        _row(
                          id: p.id,
                          name: p.name,
                          image: p.image,
                          sub: [
                            if (p.kinds.isNotEmpty)
                              p.kinds.map(_kindName).join(', '),
                            countsHint(p.works, p.quotes),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          spellings: p.spellings,
                          character: false,
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _charactersList() {
    final all = _characters!;
    final shown = [
      for (final c in all)
        if (_matches(c.name, const []) &&
            (_show != _Show.noPhoto || c.image.isEmpty))
          c,
    ];
    return Column(
      children: [
        _filters([
          FilterChip(
            label: Text(
              'No picture (${all.where((c) => c.image.isEmpty).length})',
            ),
            selected: _show == _Show.noPhoto,
            onSelected: (v) =>
                setState(() => _show = v ? _Show.noPhoto : _Show.all),
          ),
        ]),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _read,
            child: shown.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(48),
                        child: Text(
                          all.isEmpty
                              ? 'No character is saved yet. Add one, or name a speaker on a film\'s quote.'
                              : 'No one matches.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final c in shown)
                        _row(
                          id: c.id,
                          name: c.name,
                          image: c.image,
                          sub: [
                            if (c.worksIn.isNotEmpty)
                              c.worksIn.take(2).map((w) => w.title).join(', '),
                            countsHint(c.works, c.quotes),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          spellings: const [],
                          character: true,
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  String _kindName(String k) => switch (k) {
    'author' => 'Authors',
    'actor' => 'Actors',
    'director' => 'Directors',
    'speaker' => 'Speakers',
    'creator' => 'Creators',
    _ => k.isEmpty ? k : '${k[0].toUpperCase()}${k.substring(1)}',
  };

  @override
  Widget build(BuildContext context) {
    final people = _people, characters = _characters;
    final selecting = _picked.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: 'Clear the choice',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_picked.clear),
              )
            : null,
        title: Text(
          selecting ? '${_picked.length} chosen' : 'People and characters',
        ),
        actions: [
          if (selecting && _picked.length == 2)
            TextButton.icon(
              onPressed: _merge,
              icon: const Icon(Icons.merge_rounded),
              label: const Text('Merge'),
            ),
          if (!selecting)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => v == 'fetch' ? _fetch() : _prune(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'fetch',
                  child: Text('Fetch missing photos and details'),
                ),
                PopupMenuItem(
                  value: 'prune',
                  enabled: _orphans.total > 0,
                  child: Text(
                    _orphans.total > 0
                        ? 'Remove what nothing uses (${_orphans.total})'
                        : 'Nothing unused to remove',
                  ),
                ),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48 + 56),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBar(
                  hintText: 'Search names and spellings',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              TabBar(
                controller: _tabs,
                tabs: [
                  Tab(
                    text: people == null
                        ? 'People'
                        : 'People (${people.length})',
                  ),
                  Tab(
                    text: characters == null
                        ? 'Characters'
                        : 'Characters (${characters.length})',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _onCharacters && !selecting
          ? FloatingActionButton.extended(
              heroTag: 'add-character',
              onPressed: _addCharacter,
              icon: const Icon(Icons.add),
              label: const Text('Add a character'),
            )
          : null,
      body: _problem != null && people == null
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
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : people == null || characters == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_peopleList(), _charactersList()],
            ),
    );
  }
}
