import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/server_call.dart';
import '../capture/photo_source.dart';
import '../library/quote_chips.dart';
import '../people/people_console.dart';
import '../people/people_directory.dart';
import '../people/people_service.dart';
import '../people/picture.dart';
import '../theme/app_theme.dart';
import 'people_console_actions.dart';

/// Opens the page of whoever a pill names: a person's, or (for a character in a film, show or game) the character's.
/// A name the server holds no record of still gets a page (their picture, the quotes), with a note saying so.
/// Pressing "Show their quotes" there calls [onFilter] after the page has closed.
Future<void> openPersonPage(
  BuildContext context, {
  required QuoteChip chip,
  required ValueChanged<ChipFilter> onFilter,
  PhotoSource? photos,
}) async {
  final dir = PeopleDirectoryScope.of(context);
  final nav = Navigator.of(context);
  ChipFilter? chosen;
  void pick(ChipFilter f) => chosen = f;
  if (chip.kind == ChipKind.character) {
    final c = dir?.character(chip.name);
    await nav.push<void>(
      MaterialPageRoute(
        builder: (_) => CharacterScreen(
          id: c?.id ?? 0,
          name: chip.name,
          actor: chip.actor,
          onFilter: pick,
          photos: photos,
        ),
      ),
    );
  } else {
    final p = dir?.person(
      chip.kind == ChipKind.author ? 'author' : 'speaker',
      chip.name,
    );
    await nav.push<void>(
      MaterialPageRoute(
        builder: (_) => PersonScreen(
          id: (p ?? dir?.anyPerson(chip.name))?.id ?? 0,
          name: chip.name,
          onFilter: pick,
          photos: photos,
        ),
      ),
    );
  }
  final f = chosen;
  if (f != null) onFilter(f);
}

String _years(String born, String died) {
  if (born.isEmpty && died.isEmpty) return '';
  if (died.isEmpty) return 'Born $born';
  return '${born.isEmpty ? '?' : born} – $died';
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// What the people pages share: the big round picture, a section heading, the quotes and the links.
class _Parts {
  static Widget heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
  );

  static Widget portrait(
    BuildContext context,
    String image,
    String name, {
    double size = 104,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.secondaryContainer,
      child: Text(
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: quoteFont,
          fontSize: size * 0.4,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
    final pic = StoredPicture(
      name: image,
      width: size,
      height: size,
      circle: true,
      fallback: fallback,
    );
    if (image.isEmpty) return fallback;
    return Semantics(
      button: true,
      label: 'Show the picture of $name',
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              child: StoredPicture(
                name: image,
                fit: BoxFit.contain,
                radius: 20,
                fallback: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        child: pic,
      ),
    );
  }

  static Widget links(BuildContext context, String text) {
    final links = parseLinks(text);
    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final l in links)
            ActionChip(
              avatar: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(l.label),
              tooltip: l.url,
              onPressed: () => launchUrl(
                Uri.parse(l.url),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }

  /// The other spellings. With [onSplit] each is pressable, to make it a record of its own.
  static Widget aliases(
    BuildContext context,
    List<String> aliases, {
    ValueChanged<String>? onSplit,
  }) {
    if (aliases.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(context, 'Also written as'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final a in aliases)
                onSplit == null
                    ? Chip(label: Text(a))
                    : ActionChip(
                        label: Text(a),
                        tooltip: 'Make this its own record',
                        onPressed: () => onSplit(a),
                      ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget lines(
    BuildContext context,
    List<LineOf> lines,
    int total,
    int shared,
  ) {
    if (lines.isEmpty && shared == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(context, 'Quotes'),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.text,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: quoteStyle(context),
                    ),
                    if (l.workTitle.isNotEmpty || l.favourite) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (l.favourite)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              l.workTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (total > lines.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Showing ${lines.length} of $total. "Show their quotes" lists them all.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (shared > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              '$shared more ${shared == 1 ? 'quote names' : 'quotes name'} them alongside someone else, so ${shared == 1 ? 'it is' : 'they are'} not listed here.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// A person: portrait, dates, bio, links, signature, other spellings, the works they are credited on, the parts
/// they played and the quotes that name them. Where the server allows, it can also be edited.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.id,
    required this.name,
    required this.onFilter,
    this.photos,
    this.readBytes,
  });

  /// The person's id on the server, or 0 when the server has no record of them.
  final int id;
  final String name;

  /// Pressing "Show their quotes": the page closes and the caller filters.
  final ValueChanged<ChipFilter> onFilter;

  final PhotoSource? photos;

  /// Reads a chosen picture's bytes; null reads the file. A function so a test needs no real file.
  final Future<Uint8List> Function(String path)? readBytes;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  PersonDetail? _p;
  bool _loaded = false;
  String? _error;
  bool _moreBio = false;
  PeopleService? _service;
  PeopleDirectory? _dir;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service == null) {
      _service = PeopleServiceScope.of(context);
      _dir = PeopleDirectoryScope.of(context);
      _load();
    }
  }

  Future<void> _load() async {
    final s = _service;
    if (s == null || !s.available || widget.id == 0) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final p = await s.person(widget.id);
      if (!mounted) return;
      setState(() {
        _p = p;
        _error = null;
        _loaded = true;
      });
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loaded = true;
      });
    }
  }

  Future<void> _run(Future<void> Function(PeopleService s) job) async {
    final s = _service;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await job(s);
      await _dir?.refresh();
      await _load();
    } on ServerException catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _choose({required bool signature}) async {
    final path = await (widget.photos ?? DevicePhotos()).choose();
    if (path == null || !mounted) return;
    final bytes = await (widget.readBytes ?? (p) => File(p).readAsBytes())(
      path,
    );
    final fileName = path.split(RegExp(r'[\\/]')).last;
    await _run(
      (s) => signature
          ? s.uploadSignature(widget.id, bytes, fileName)
          : s.uploadPortrait(widget.id, bytes, fileName),
    );
  }

  PeopleConsole? get _console {
    final c = PeopleConsoleScope.of(context);
    return c != null && c.available ? c : null;
  }

  Future<void> _names() async {
    final c = _console, p = _p;
    if (c == null || p == null) return;
    if (await editSpellings(
      context,
      c,
      character: false,
      id: p.id,
      names: [p.name, ...p.aliases],
    )) {
      await _dir?.refresh();
      await _load();
    }
  }

  Future<void> _split(String alias) async {
    final c = _console, p = _p;
    if (c == null || p == null) return;
    if (await splitSpelling(
      context,
      c,
      character: false,
      id: p.id,
      alias: alias,
    )) {
      await _dir?.refresh();
      await _load();
    }
  }

  Future<void> _mergeInto() async {
    final c = _console, p = _p;
    if (c == null || p == null) return;
    final List<PersonRecord> all;
    try {
      all = await c.people();
    } on ServerException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    final target = await pickRecord(
      context,
      title: 'Merge ${p.name} into…',
      rows: [
        for (final r in all)
          if (r.id != p.id)
            PickRow(
              id: r.id,
              name: r.name,
              hint: countsHint(r.works, r.quotes),
              spellings: r.spellings,
            ),
      ],
    );
    if (target == null || !mounted) return;
    if (await mergeTwo(
      context,
      c,
      character: false,
      a: PickRow(id: p.id, name: p.name),
      b: target,
    )) {
      await _dir?.refresh();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _remove() async {
    final c = _console, p = _p;
    if (c == null || p == null) return;
    if (await removeRecord(
      context,
      c,
      character: false,
      id: p.id,
      name: p.name,
    )) {
      await _dir?.refresh();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _edit() async {
    final p = _p;
    if (p == null) return;
    final name = TextEditingController(text: p.name);
    final born = TextEditingController(text: p.born);
    final died = TextEditingController(text: p.died);
    final bio = TextEditingController(text: p.bio);
    final links = TextEditingController(text: p.links);
    final note = TextEditingController(text: p.note);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: born,
                      decoration: const InputDecoration(labelText: 'Born'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: died,
                      decoration: const InputDecoration(labelText: 'Died'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: bio,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'About'),
              ),
              TextField(
                controller: links,
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Links',
                  helperText: 'One address per line',
                ),
              ),
              TextField(
                controller: note,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Your note'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (go != true || name.text.trim().isEmpty) return;
    await _run(
      (s) => s.save(
        widget.id,
        PersonEdit(
          name: name.text.trim(),
          born: born.text.trim(),
          died: died.text.trim(),
          bio: bio.text.trim(),
          links: links.text.trim(),
          note: note.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = _p;
    final name = p?.name.isNotEmpty == true ? p!.name : widget.name;
    final image = p?.image ?? _dir?.anyPerson(widget.name)?.image ?? '';
    final canEdit = p != null && (_service?.available ?? false);
    final years = _years(p?.born ?? '', p?.died ?? '');
    final credits = [...?p?.credits]
      ..sort((a, b) {
        if (a.year == 0 || b.year == 0) return b.year.compareTo(a.year);
        return a.year.compareTo(b.year);
      });
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canEdit)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit();
                  case 'fetch':
                    final messenger = ScaffoldMessenger.of(context);
                    _run((s) async {
                      final said = await s.fetch(widget.id);
                      messenger.showSnackBar(SnackBar(content: Text(said)));
                    });
                  case 'portrait':
                    _choose(signature: false);
                  case 'noportrait':
                    _run((s) => s.clearPortrait(widget.id));
                  case 'signature':
                    _choose(signature: true);
                  case 'nosignature':
                    _run((s) => s.clearSignature(widget.id));
                  case 'names':
                    _names();
                  case 'merge':
                    _mergeInto();
                  case 'remove':
                    _remove();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                const PopupMenuItem(
                  value: 'fetch',
                  child: Text('Look up portrait and details'),
                ),
                const PopupMenuItem(
                  value: 'portrait',
                  child: Text('Choose a portrait'),
                ),
                if (p.image.isNotEmpty)
                  const PopupMenuItem(
                    value: 'noportrait',
                    child: Text('Remove the portrait'),
                  ),
                const PopupMenuItem(
                  value: 'signature',
                  child: Text('Choose a signature'),
                ),
                if (p.signature.isNotEmpty)
                  const PopupMenuItem(
                    value: 'nosignature',
                    child: Text('Remove the signature'),
                  ),
                if (_console != null) ...const [
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'names',
                    child: Text('Names and spellings'),
                  ),
                  PopupMenuItem(
                    value: 'merge',
                    child: Text('Merge into another person'),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove this person'),
                  ),
                ],
              ],
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _Parts.portrait(context, image, name),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontFamily: quoteFont,
                              ),
                            ),
                            if (p != null && p.kinds.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                p.kinds
                                    .map(
                                      (k) =>
                                          k[0].toUpperCase() + k.substring(1),
                                    )
                                    .join(' · '),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                            if (years.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(years, style: theme.textTheme.bodyMedium),
                            ],
                            if (p != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_plural(p.quotes + p.sharedLines, 'quote', 'quotes')}'
                                '${p.favourites > 0 ? ' · ${p.favourites} favourite${p.favourites == 1 ? '' : 's'}' : ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        widget.onFilter(ChipFilter(widget.name));
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.format_quote_rounded),
                      label: const Text('Show their quotes'),
                    ),
                  ),
                ),
                if (p == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      _error ??
                          (widget.id == 0
                              ? 'Your server has no page for $name yet, or this phone is not paired with it.'
                              : 'The server could not be reached, so only what the phone holds is shown.'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (p != null && p.bio.isNotEmpty) ...[
                  _Parts.heading(context, 'About'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      p.bio,
                      maxLines: _moreBio ? null : 6,
                      overflow: _moreBio ? null : TextOverflow.ellipsis,
                    ),
                  ),
                  if (p.bio.length > 280)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() => _moreBio = !_moreBio),
                          child: Text(_moreBio ? 'Show less' : 'Show more'),
                        ),
                      ),
                    ),
                ],
                if (p != null && p.links.isNotEmpty) ...[
                  _Parts.heading(context, 'Links'),
                  _Parts.links(context, p.links),
                ],
                if (p != null && p.signature.isNotEmpty) ...[
                  _Parts.heading(context, 'Signature'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: StoredPicture(
                      name: p.signature,
                      height: 56,
                      fit: BoxFit.contain,
                      tint: scheme.onSurface,
                    ),
                  ),
                ],
                if (p != null)
                  _Parts.aliases(
                    context,
                    p.aliases,
                    onSplit: _console == null ? null : _split,
                  ),
                if (credits.isNotEmpty) ...[
                  _Parts.heading(context, 'Works'),
                  SizedBox(
                    height: 216,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final c in credits)
                          _WorkCard(
                            title: c.title,
                            cover: c.cover,
                            line: [
                              if (c.role.isNotEmpty) c.role,
                              if (c.year > 0) '${c.year}',
                            ].join(' · '),
                            onTap: () {
                              widget.onFilter(ChipFilter(c.title));
                              Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                if (p != null && p.roles.isNotEmpty) ...[
                  _Parts.heading(context, 'Parts played'),
                  for (final r in p.roles)
                    ListTile(
                      leading: StoredPicture(
                        name: r.characterImage,
                        width: 40,
                        height: 40,
                        circle: true,
                        fallback: CircleAvatar(
                          backgroundColor: scheme.tertiaryContainer,
                          child: Text(
                            r.character.isEmpty
                                ? '?'
                                : r.character.characters.first.toUpperCase(),
                          ),
                        ),
                      ),
                      title: Text(r.character.isEmpty ? '—' : r.character),
                      subtitle: Text(r.workTitle),
                      onTap: () {
                        widget.onFilter(ChipFilter(r.workTitle));
                        Navigator.of(context).pop();
                      },
                    ),
                ],
                if (p != null && p.note.isNotEmpty) ...[
                  _Parts.heading(context, 'Your note'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(p.note),
                  ),
                ],
                if (p != null)
                  _Parts.lines(context, p.lines, p.quotes, p.sharedLines),
              ],
            ),
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    required this.title,
    required this.cover,
    required this.line,
    required this.onTap,
  });

  final String title, cover, line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 100,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoredPicture(
                name: cover,
                width: 100,
                height: 144,
                radius: 10,
                fallback: Container(
                  width: 100,
                  height: 144,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    title.isEmpty ? '?' : title.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontFamily: quoteFont,
                      fontSize: 32,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
              if (line.isNotEmpty)
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A character: picture, description, other names, where they appear and who played them (the same role across
/// adaptations), and the quotes that name them.
class CharacterScreen extends StatefulWidget {
  const CharacterScreen({
    super.key,
    required this.id,
    required this.name,
    required this.onFilter,
    this.actor = '',
    this.photos,
  });

  final int id;
  final String name;

  /// The actor named under the character on the pill that was pressed ('' for none).
  final String actor;
  final ValueChanged<ChipFilter> onFilter;
  final PhotoSource? photos;

  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  CharacterDetail? _c;
  bool _loaded = false;
  String? _error;
  bool _moreText = false;
  PeopleService? _service;
  PeopleDirectory? _dir;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service == null) {
      _service = PeopleServiceScope.of(context);
      _dir = PeopleDirectoryScope.of(context);
      _load();
    }
  }

  Future<void> _load() async {
    final s = _service;
    if (s == null || !s.available || widget.id == 0) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final c = await s.character(widget.id);
      if (!mounted) return;
      setState(() {
        _c = c;
        _loaded = true;
      });
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loaded = true;
      });
    }
  }

  PeopleConsole? get _console {
    final c = PeopleConsoleScope.of(context);
    return c != null && c.available ? c : null;
  }

  Future<void> _afterChange() async {
    await _dir?.refresh();
    await _load();
  }

  Future<void> _editDetails() async {
    final c = _console, ch = _c;
    if (c == null || ch == null) return;
    final e = await characterForm(
      context,
      name: ch.name,
      description: ch.description,
      born: ch.born,
      links: ch.links,
      note: ch.note,
    );
    if (e == null || !mounted) return;
    if (await consoleCall(context, () => c.saveCharacter(ch.id, e))) {
      await _afterChange();
    }
  }

  Future<void> _names() async {
    final c = _console, ch = _c;
    if (c == null || ch == null) return;
    if (await editSpellings(
      context,
      c,
      character: true,
      id: ch.id,
      names: [ch.name, ...ch.aliases],
    )) {
      await _afterChange();
    }
  }

  Future<void> _split(String alias) async {
    final c = _console, ch = _c;
    if (c == null || ch == null) return;
    if (await splitSpelling(
      context,
      c,
      character: true,
      id: ch.id,
      alias: alias,
    )) {
      await _afterChange();
    }
  }

  Future<void> _picture() async {
    final c = _console, ch = _c;
    if (c == null || ch == null) return;
    final path = await (widget.photos ?? DevicePhotos()).choose();
    if (path == null || !mounted) return;
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    if (await consoleCall(
      context,
      () => c.uploadCharacterImage(
        ch.id,
        bytes,
        path.split(RegExp(r'[\\/]')).last,
      ),
    )) {
      await _afterChange();
    }
  }

  Future<void> _noPicture() async {
    final c = _console, ch = _c;
    if (c == null || ch == null) return;
    if (await consoleCall(context, () => c.clearCharacterImage(ch.id))) {
      await _afterChange();
    }
  }

  Future<void> _mergeInto() async {
    final c = _console, ch = _c;
    if (c == null || ch == null) return;
    final List<CharacterRecord> all;
    try {
      all = await c.characters();
    } on ServerException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    final target = await pickRecord(
      context,
      title: 'Merge ${ch.name} into…',
      rows: [
        for (final r in all)
          if (r.id != ch.id)
            PickRow(
              id: r.id,
              name: r.name,
              hint: [
                if (r.worksIn.isNotEmpty)
                  r.worksIn.take(2).map((w) => w.title).join(', '),
                countsHint(r.works, r.quotes),
              ].where((s) => s.isNotEmpty).join(' · '),
            ),
      ],
    );
    if (target == null || !mounted) return;
    if (await mergeTwo(
      context,
      c,
      character: true,
      a: PickRow(id: ch.id, name: ch.name),
      b: target,
    )) {
      await _dir?.refresh();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _remove() async {
    final c = _console, ch = _c;
    if (c == null || ch == null) return;
    if (await removeRecord(
      context,
      c,
      character: true,
      id: ch.id,
      name: ch.name,
    )) {
      await _dir?.refresh();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _openActor(String actor) {
    final info = _dir?.person('actor', actor) ?? _dir?.anyPerson(actor);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PersonScreen(
          id: info?.id ?? 0,
          name: actor,
          onFilter: (f) {
            widget.onFilter(f);
            Navigator.of(context).pop();
          },
          photos: widget.photos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = _c;
    final name = c?.name.isNotEmpty == true ? c!.name : widget.name;
    final image = c?.image ?? _dir?.characterImage(widget.name) ?? '';
    // who plays them: each actor once, in the order of the works
    final actors = <String>[];
    for (final a in c?.appearances ?? const <CastAppearance>[]) {
      if (a.actor.isNotEmpty && !actors.contains(a.actor)) actors.add(a.actor);
    }
    if (actors.isEmpty && widget.actor.isNotEmpty) actors.add(widget.actor);
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (c != null && _console != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _editDetails();
                  case 'names':
                    _names();
                  case 'picture':
                    _picture();
                  case 'nopicture':
                    _noPicture();
                  case 'merge':
                    _mergeInto();
                  case 'remove':
                    _remove();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                const PopupMenuItem(
                  value: 'names',
                  child: Text('Names and spellings'),
                ),
                const PopupMenuItem(
                  value: 'picture',
                  child: Text('Choose a picture'),
                ),
                if (c.image.isNotEmpty)
                  const PopupMenuItem(
                    value: 'nopicture',
                    child: Text('Remove the picture'),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'merge',
                  child: Text('Merge into another character'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove this character'),
                ),
              ],
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Row(
                    children: [
                      _Parts.portrait(context, image, name),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontFamily: quoteFont,
                              ),
                            ),
                            Text(
                              'Character',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                            if (c != null && c.born.isNotEmpty)
                              Text(
                                'Born ${c.born}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            if (c != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_plural(c.quotes + c.sharedLines, 'quote', 'quotes')}'
                                '${c.favourites > 0 ? ' · ${c.favourites} favourite${c.favourites == 1 ? '' : 's'}' : ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        widget.onFilter(ChipFilter(widget.name));
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.format_quote_rounded),
                      label: const Text('Show their quotes'),
                    ),
                  ),
                ),
                if (c == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      _error ??
                          (widget.id == 0
                              ? 'Your server has no page for $name yet, or this phone is not paired with it.'
                              : 'The server could not be reached, so only what the phone holds is shown.'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (c != null && c.description.isNotEmpty) ...[
                  _Parts.heading(context, 'About'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      c.description,
                      maxLines: _moreText ? null : 6,
                      overflow: _moreText ? null : TextOverflow.ellipsis,
                    ),
                  ),
                  if (c.description.length > 280)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _moreText = !_moreText),
                          child: Text(_moreText ? 'Show less' : 'Show more'),
                        ),
                      ),
                    ),
                ],
                if (actors.isNotEmpty) ...[
                  _Parts.heading(
                    context,
                    actors.length == 1
                        ? 'Played by'
                        : 'Played by, across adaptations',
                  ),
                  for (final a in actors)
                    ListTile(
                      leading: StoredPicture(
                        name: _dir?.anyPerson(a)?.image ?? '',
                        width: 40,
                        height: 40,
                        circle: true,
                        fallback: CircleAvatar(
                          backgroundColor: scheme.secondaryContainer,
                          child: Text(a.characters.first.toUpperCase()),
                        ),
                      ),
                      title: Text(a),
                      subtitle: Text(
                        [
                          for (final x
                              in c?.appearances ?? const <CastAppearance>[])
                            if (x.actor == a) x.workTitle,
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openActor(a),
                    ),
                ],
                if (c != null && c.links.isNotEmpty) ...[
                  _Parts.heading(context, 'Links'),
                  _Parts.links(context, c.links),
                ],
                if (c != null)
                  _Parts.aliases(
                    context,
                    c.aliases,
                    onSplit: _console == null ? null : _split,
                  ),
                if (c != null && c.appearances.isNotEmpty) ...[
                  _Parts.heading(context, 'Appears in'),
                  for (final a in c.appearances)
                    ListTile(
                      title: Text(a.workTitle),
                      subtitle: a.actor.isEmpty
                          ? null
                          : Text('Played by ${a.actor}'),
                      onTap: () {
                        widget.onFilter(ChipFilter(a.workTitle));
                        Navigator.of(context).pop();
                      },
                    ),
                ],
                if (c != null && c.note.isNotEmpty) ...[
                  _Parts.heading(context, 'Your note'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(c.note),
                  ),
                ],
                if (c != null)
                  _Parts.lines(context, c.lines, c.quotes, c.sharedLines),
              ],
            ),
    );
  }
}
