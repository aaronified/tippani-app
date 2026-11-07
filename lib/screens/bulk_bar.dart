import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../l10n/l10n.dart';
import '../library/bulk_ops.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../sync/fingerprint.dart' show realmOfQuote;
import 'anthologies_screen.dart' show askAnthologyText;
import 'quote_form_screen.dart' show quoteColour, quoteColourName;

/// The bar that replaces a list's title while things are selected: how many, a way out, select everything, and the
/// actions that suit what is selected.
AppBar bulkAppBar(
  BuildContext context, {
  required int count,
  required int total,
  required VoidCallback onClose,
  required VoidCallback onAll,
  required List<Widget> actions,
}) {
  return AppBar(
    leading: IconButton(
      tooltip: context.tr('Cancel'),
      icon: const Icon(Icons.close),
      onPressed: onClose,
    ),
    title: Text(context.tr('{n} selected', {'n': count})),
    actions: [
      if (count < total)
        IconButton(
          tooltip: context.tr('Select all'),
          icon: const Icon(Icons.select_all),
          onPressed: onAll,
        ),
      ...actions,
    ],
  );
}

/// Says what a bulk change did, in a message.
void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String _done(BuildContext context, BulkResult r, String what) {
  var out = r.changed == 0
      ? context.tr('Nothing to change.')
      : context.tr(what, {'n': r.changed});
  if (r.note.isNotEmpty) out = '$out ${context.tr(r.note)}';
  return out;
}

/// The actions on selected quotes. Every one is made on the phone's own library, so none needs a server.
class QuoteBulkActions {
  QuoteBulkActions({
    required this.store,
    required this.anthologies,
    required this.quotes,
    required this.done,
  });

  final LibraryStore store;
  final AnthologyService? anthologies;

  /// The selected quotes, as they are now.
  final List<Quote> quotes;

  /// Called after a change, so the list can read again and leave selecting.
  final VoidCallback done;

  BulkOps get _ops => BulkOps(store);

  List<Widget> bar(BuildContext context) {
    final allFav = quotes.every((q) => q.favorite);
    return [
      IconButton(
        tooltip: allFav
            ? context.tr('Take them off favourites')
            : context.tr('Favourite them'),
        icon: Icon(allFav ? Icons.star : Icons.star_border),
        onPressed: () async {
          final r = await _ops.favourite(quotes, !allFav);
          if (!context.mounted) return;
          _say(
            context,
            _done(
              context,
              r,
              allFav ? '{n} taken off favourites.' : '{n} added to favourites.',
            ),
          );
          done();
        },
      ),
      IconButton(
        tooltip: context.tr('Colour'),
        icon: const Icon(Icons.palette_outlined),
        onPressed: () => _recolour(context),
      ),
      IconButton(
        tooltip: context.tr('Tag'),
        icon: const Icon(Icons.sell_outlined),
        onPressed: () => _tag(context, add: true),
      ),
      PopupMenuButton<String>(
        tooltip: context.tr('More'),
        onSelected: (v) {
          switch (v) {
            case 'untag':
              _tag(context, add: false);
            case 'field':
              _field(context);
            case 'board':
              _board(context);
            case 'anthology':
              _anthology(context);
            case 'delete':
              _delete(context);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'untag',
            child: Text(context.tr('Take a tag off')),
          ),
          PopupMenuItem(
            value: 'field',
            child: Text(context.tr('Set one field…')),
          ),
          PopupMenuItem(
            value: 'board',
            child: Text(context.tr('Move to a board…')),
          ),
          if (anthologies?.available == true)
            PopupMenuItem(
              value: 'anthology',
              child: Text(context.tr('Add to anthology')),
            ),
          PopupMenuItem(value: 'delete', child: Text(context.tr('Delete'))),
        ],
      ),
    ];
  }

  Future<void> _recolour(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final c in quoteColors)
              ListTile(
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: quoteColour(c),
                ),
                title: Text(quoteColourName(c)),
                onTap: () => Navigator.of(context).pop(c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final r = await _ops.recolour(quotes, picked);
    if (!context.mounted) return;
    _say(context, _done(context, r, '{n} recoloured.'));
    done();
  }

  Future<void> _tag(BuildContext context, {required bool add}) async {
    final known = await store.tags();
    if (!context.mounted) return;
    // taking a tag off offers the tags these quotes wear; adding offers every tag there is
    final offer = add
        ? known
        : ({for (final q in quotes) ...q.tags}.toList()..sort());
    final name = await askBulkText(
      context,
      title: add ? 'Add a tag' : 'Take a tag off',
      label: 'Tag',
      offer: offer,
      action: add ? 'Add' : 'Take off',
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final r = add
        ? await _ops.addTag(quotes, name)
        : await _ops.removeTag(quotes, name);
    if (!context.mounted) return;
    _say(
      context,
      _done(context, r, add ? '{n} tagged.' : '{n} had the tag taken off.'),
    );
    done();
  }

  Future<void> _field(BuildContext context) async {
    final field = await showModalBottomSheet<QuoteField>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final f in QuoteField.values)
              ListTile(
                title: Text(context.tr(f.label)),
                onTap: () => Navigator.of(context).pop(f),
              ),
          ],
        ),
      ),
    );
    if (field == null || !context.mounted) return;
    final value = await askBulkText(
      context,
      title: 'Set one field',
      label: field.label,
      offer: const [],
      action: 'Set',
      allowEmpty: true,
    );
    if (value == null || !context.mounted) return;
    final r = await _ops.setQuoteField(quotes, field, value);
    if (!context.mounted) return;
    _say(context, _done(context, r, '{n} changed.'));
    done();
  }

  Future<void> _board(BuildContext context) async {
    final boards = await store.boards();
    if (!context.mounted) return;
    const none = -1;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final b in boards)
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: Text(b.name),
                onTap: () => Navigator.of(context).pop(b.id),
              ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: Text(context.tr('No board')),
              onTap: () => Navigator.of(context).pop(none),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final r = await _ops.moveToBoard(quotes, picked == none ? null : picked);
    if (!context.mounted) return;
    _say(context, _done(context, r, '{n} moved.'));
    done();
  }

  Future<void> _anthology(BuildContext context) async {
    final service = anthologies;
    if (service == null) return;
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
        title: Text(context.tr('Add to anthology')),
        children: [
          for (final a in all)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(a),
              child: Text(a.title),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('new'),
            child: Text(context.tr('A new anthology…')),
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
      var added = 0, already = 0, notOnServer = 0;
      for (final q in quotes) {
        if (q.serverId == null) {
          notOnServer++;
          continue;
        }
        final w = q.workId == null ? null : await store.work(q.workId!);
        final ok = await service.add(
          target.id,
          entryKindOf(realmOfQuote(w)),
          q.serverId!,
        );
        ok ? added++ : already++;
      }
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              [
                '$added added to ${target.title}.',
                if (already > 0) '$already already there.',
                if (notOnServer > 0)
                  '$notOnServer not on the server yet (sync first).',
              ].join(' '),
            ),
          ),
        );
      done();
    } on AnthologyException catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final n = quotes.length;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete {n} quotes?', {'n': n})),
        content: Text(
          context.tr(
            'They are removed from this phone, and from the server at the next sync (its bin keeps them for a while).',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Keep them')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Delete')),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = context.tr('{n} quotes deleted.', {'n': n});
    final undo = context.tr('Undo');
    final drafts = await _ops.delete(quotes);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: SnackBarAction(
            label: undo,
            onPressed: () async {
              await _ops.restore(drafts);
              done();
            },
          ),
        ),
      );
    done();
  }
}

/// The actions on selected works.
class WorkBulkActions {
  WorkBulkActions({
    required this.store,
    required this.works,
    required this.all,
    required this.done,
  });

  final LibraryStore store;
  final List<Work> works;

  /// Every work the list holds, for choosing what to merge into.
  final List<Work> all;
  final VoidCallback done;

  BulkOps get _ops => BulkOps(store);

  List<Widget> bar(BuildContext context) => [
    IconButton(
      tooltip: context.tr('Set one field…'),
      icon: const Icon(Icons.edit_note),
      onPressed: () => _field(context),
    ),
    if (works.length > 1)
      IconButton(
        tooltip: context.tr('Merge into one'),
        icon: const Icon(Icons.merge_type),
        onPressed: () => _merge(context),
      ),
    IconButton(
      tooltip: context.tr('Delete'),
      icon: const Icon(Icons.delete_outline),
      onPressed: () => _delete(context),
    ),
  ];

  Future<void> _field(BuildContext context) async {
    final field = await showModalBottomSheet<WorkField>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final f in WorkField.values)
              ListTile(
                title: Text(context.tr(f.label)),
                onTap: () => Navigator.of(context).pop(f),
              ),
          ],
        ),
      ),
    );
    if (field == null || !context.mounted) return;
    final value = await askBulkText(
      context,
      title: 'Set one field',
      label: field.label,
      offer: const [],
      action: 'Set',
      allowEmpty: field != WorkField.year,
    );
    if (value == null || !context.mounted) return;
    final r = await _ops.setWorkField(works, field, value);
    if (!context.mounted) return;
    _say(context, _done(context, r, '{n} changed.'));
    done();
  }

  Future<void> _merge(BuildContext context) async {
    final target = await showDialog<Work>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('Keep which one?')),
        children: [
          for (final w in works)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(w),
              child: Text(
                w.creator.isEmpty ? w.title : '${w.title} — ${w.creator}',
              ),
            ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    final others = [
      for (final w in works)
        if (w.id != target.id) w,
    ];
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.tr('Merge into “{title}”?', {'title': target.title}),
        ),
        content: Text(
          context.tr(
            'The quotes of the others move onto it, and the others are deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Merge')),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final r = await _ops.mergeWorks(target, others);
    if (!context.mounted) return;
    _say(context, _done(context, r, '{n} merged.'));
    done();
  }

  Future<void> _delete(BuildContext context) async {
    final n = works.length;
    var quotes = 0;
    for (final w in works) {
      quotes += (await store.quotes(workId: w.id, limit: 1 << 30)).length;
    }
    if (!context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete {n} works?', {'n': n})),
        content: Text(
          context.tr(
            'Their {q} quotes are deleted with them. This cannot be undone.',
            {'q': quotes},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Keep them')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Delete')),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    for (final w in works) {
      await store.deleteWork(w.id);
    }
    done();
  }
}

/// Asks for one line of text, with [offer] as chips to fill it in. Returns null if the reader cancels.
Future<String?> askBulkText(
  BuildContext context, {
  required String title,
  required String label,
  required List<String> offer,
  required String action,
  bool allowEmpty = false,
}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.tr(title)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                decoration: InputDecoration(labelText: context.tr(label)),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) {
                  if (allowEmpty || v.trim().isNotEmpty) {
                    Navigator.of(context).pop(v);
                  }
                },
              ),
              if (offer.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final o in offer.take(24))
                      ActionChip(
                        label: Text(o),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => c.text = o),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: allowEmpty || c.text.trim().isNotEmpty
                ? () => Navigator.of(context).pop(c.text)
                : null,
            child: Text(context.tr(action)),
          ),
        ],
      ),
    ),
  );
}
