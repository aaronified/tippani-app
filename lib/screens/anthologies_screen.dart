import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import 'quote_form_screen.dart' show quoteColour;

/// An anthology as plain text to send: its title and introduction, then each passage with where it is from and the
/// reader's commentary on it.
String anthologyShareText(AnthologyDetail d) {
  final out = StringBuffer(d.anthology.title);
  if (d.anthology.intro.trim().isNotEmpty) {
    out.write('\n\n${d.anthology.intro.trim()}');
  }
  for (final e in d.entries) {
    out.write('\n\n“${e.quote.trim()}”');
    if (e.from.isNotEmpty) out.write('\n— ${e.from}');
    if (e.note.trim().isNotEmpty) out.write('\n${e.note.trim()}');
  }
  return out.toString();
}

/// Asks for a title and an introduction. Null if the reader backs out.
Future<({String title, String intro})?> askAnthologyText(
  BuildContext context, {
  String title = '',
  String intro = '',
  required String heading,
}) {
  final t = TextEditingController(text: title);
  final i = TextEditingController(text: intro);
  return showDialog<({String title, String intro})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: t,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: i,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Introduction'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: t.text.trim().isEmpty
                ? null
                : () =>
                      Navigator.of(context)
                          .pop((title: t.text.trim(), intro: i.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Your anthologies on the server: collections of quotes you have gathered and ordered. Needs a paired server.
class AnthologiesScreen extends StatefulWidget {
  const AnthologiesScreen({
    super.key,
    required this.service,
    this.share = shareThroughSheet,
  });

  final AnthologyService service;
  final ShareText share;

  @override
  State<AnthologiesScreen> createState() => _AnthologiesScreenState();
}

class _AnthologiesScreenState extends State<AnthologiesScreen> {
  List<Anthology>? _all;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.service.list();
      if (mounted) {
        setState(() {
          _all = all;
          _problem = null;
        });
      }
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _create() async {
    final text = await askAnthologyText(context, heading: 'New anthology');
    if (text == null) return;
    try {
      await widget.service.create(text.title, text.intro);
      await _load();
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _open(Anthology a) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AnthologyScreen(
          service: widget.service,
          id: a.id,
          share: widget.share,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: const Text('Anthologies')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New anthology'),
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
          ? const Center(child: Text('No anthologies yet.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final a in all)
                  ListTile(
                    leading: const Icon(Icons.collections_bookmark_outlined),
                    title: Text(a.title),
                    subtitle: Text(
                      '${a.entries} ${a.entries == 1 ? 'passage' : 'passages'}',
                    ),
                    onTap: () => _open(a),
                  ),
              ],
            ),
    );
  }
}

/// One anthology: its introduction and passages in order, to read, share, rename, trim or delete.
class AnthologyScreen extends StatefulWidget {
  const AnthologyScreen({
    super.key,
    required this.service,
    required this.id,
    this.share = shareThroughSheet,
  });

  final AnthologyService service;
  final int id;
  final ShareText share;

  @override
  State<AnthologyScreen> createState() => _AnthologyScreenState();
}

class _AnthologyScreenState extends State<AnthologyScreen> {
  AnthologyDetail? _detail;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.service.get(widget.id);
      if (mounted) {
        setState(() {
          _detail = d;
          _problem = null;
        });
      }
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  void _say(String message) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    final a = _detail!.anthology;
    final text = await askAnthologyText(
      context,
      heading: 'Edit anthology',
      title: a.title,
      intro: a.intro,
    );
    if (text == null) return;
    try {
      await widget.service.edit(a, title: text.title, intro: text.intro);
      await _load();
    } on AnthologyException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_detail!.anthology.title}?'),
        content: const Text(
          'The anthology is removed from the server. The quotes in it stay in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.service.delete(widget.id);
      if (mounted) Navigator.of(context).pop(true);
    } on AnthologyException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  Future<void> _remove(AnthologyEntry e) async {
    try {
      await widget.service.removeEntry(widget.id, e.kind, e.itemId);
      await _load();
    } on AnthologyException catch (x) {
      if (mounted) _say(x.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.anthology.title ?? 'Anthology'),
        actions: [
          if (d != null) ...[
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share),
              onPressed: () =>
                  widget.share(anthologyShareText(d), d.anthology.title),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (d.anthology.intro.trim().isNotEmpty) ...[
                  Text(d.anthology.intro, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 16),
                ],
                if (d.entries.isEmpty)
                  const Text(
                    'Nothing in this anthology yet. Open a quote and choose Add to anthology.',
                  ),
                for (final e in d.entries)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: quoteColour(e.color),
                            width: 6,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '“${e.quote.trim()}”',
                                  style: theme.textTheme.titleMedium,
                                ),
                                if (e.from.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '— ${e.from}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                if (e.note.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      e.note.trim(),
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove from anthology',
                            icon: const Icon(Icons.close),
                            onPressed: () => _remove(e),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Lets the reader choose an anthology and adds [kind]/[itemId] to it. Says what happened in a message.
Future<void> addToAnthologyDialog(
  BuildContext context,
  AnthologyService service, {
  required String kind,
  required int itemId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  List<Anthology> all;
  try {
    all = await service.list();
  } on AnthologyException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  final chosen = await showDialog<Object>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add to anthology'),
      children: [
        for (final a in all)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(a),
            child: Text(a.title),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop('new'),
          child: const Text('A new anthology…'),
        ),
      ],
    ),
  );
  if (chosen == null) return;
  try {
    Anthology target;
    if (chosen == 'new') {
      if (!context.mounted) return;
      final text = await askAnthologyText(context, heading: 'New anthology');
      if (text == null) return;
      target = await service.create(text.title, text.intro);
    } else {
      target = chosen as Anthology;
    }
    final added = await service.add(target.id, kind, itemId);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added to ${target.title}.' : 'Already in ${target.title}.',
        ),
      ),
    );
  } on AnthologyException catch (e) {
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
