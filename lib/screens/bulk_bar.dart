import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../l10n/l10n.dart';
import '../library/bulk_ops.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../sync/fingerprint.dart' show realmOfQuote;
import 'anthologies_screen.dart' show askAnthologyText;
import 'quote_form_screen.dart' show quoteColour, quoteColourName;
import '../theme/tabler.dart';

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
      tooltip: context.tr('common.action.cancel.label'),
      icon: const Icon(Ti.x),
      onPressed: onClose,
    ),
    title: Text(context.tr('common.selection.count.one', {'n': count})),
    actions: [
      if (count < total)
        IconButton(
          tooltip: context.tr('search.table.select-all.aria'),
          icon: const Icon(Ti.selectAll),
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
      ? context.tr('app.bulk_bar.nothing_to_change')
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
            ? context.tr('app.bulk_bar.take_them_off_favourites')
            : context.tr('app.bulk_bar.favourite_them'),
        icon: Icon(allFav ? Ti.starFilled : Ti.star),
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
        tooltip: context.tr('common.field.colour.label'),
        icon: const Icon(Ti.palette),
        onPressed: () => _recolour(context),
      ),
      IconButton(
        tooltip: context.tr('common.field.tag.label'),
        icon: const Icon(Ti.tag),
        onPressed: () => _tag(context, add: true),
      ),
      PopupMenuButton<String>(
        tooltip: context.tr('settings.appearance.contrast.more.label'),
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
            child: Text(context.tr('app.bulk_bar.take_a_tag_off')),
          ),
          PopupMenuItem(
            value: 'field',
            child: Text(context.tr('app.bulk_bar.set_one_field')),
          ),
          PopupMenuItem(
            value: 'board',
            child: Text(context.tr('app.bulk_bar.move_to_a_board')),
          ),
          if (anthologies?.available == true)
            PopupMenuItem(
              value: 'anthology',
              child: Text(context.tr('common.action.anthology.label')),
            ),
          PopupMenuItem(
            value: 'delete',
            child: Text(context.tr('common.action.delete.label')),
          ),
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
      title: add
          ? context.tr('app.bulk_bar.add_a_tag')
          : context.tr('app.bulk_bar.take_a_tag_off'),
      label: context.tr('common.field.tag.label'),
      offer: offer,
      action: add
          ? context.tr('common.action.add.label')
          : context.tr('app.bulk_bar.take_off'),
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
      title: context.tr('app.bulk_bar.set_one_field_2'),
      label: context.tr(field.label),
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
                leading: const Icon(Ti.layoutDashboard),
                title: Text(b.name),
                onTap: () => Navigator.of(context).pop(b.id),
              ),
            ListTile(
              leading: const Icon(Ti.layersOff),
              title: Text(context.tr('app.bulk_bar.no_board')),
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
        title: Text(context.tr('common.action.anthology.label')),
        children: [
          for (final a in all)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(a),
              child: Text(a.title),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('new'),
            child: Text(context.tr('app.anthologies.a_new_anthology')),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    try {
      Anthology target;
      if (chosen == 'new') {
        if (!context.mounted) return;
        final text = await askAnthologyText(
          context,
          heading: context.tr('anthologies.list.new.label'),
        );
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
                tx('app.bulk_bar.added_to', {
                  'n': added,
                  'title': target.title,
                }),
                if (already > 0)
                  tx('app.bulk_bar.already_there', {'n': already}),
                if (notOnServer > 0)
                  tx('app.bulk_bar.not_on_server', {'n': notOnServer}),
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
        title: Text(context.tr('app.bulk_bar.delete_n_quotes', {'n': n})),
        content: Text(
          context.tr('app.bulk_bar.they_are_removed_from_this_phone'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('app.bulk_bar.keep_them')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('common.action.delete.label')),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final text = context.tr('app.bulk_bar.n_quotes_deleted', {'n': n});
    final undo = context.tr('common.action.undo.label');
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
      tooltip: context.tr('app.bulk_bar.set_one_field'),
      icon: const Icon(Ti.notes),
      onPressed: () => _field(context),
    ),
    if (works.length > 1)
      IconButton(
        tooltip: context.tr('app.bulk_bar.merge_into_one'),
        icon: const Icon(Ti.arrowsJoin),
        onPressed: () => _merge(context),
      ),
    IconButton(
      tooltip: context.tr('common.action.delete.label'),
      icon: const Icon(Ti.trash),
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
      title: context.tr('app.bulk_bar.set_one_field_2'),
      label: context.tr(field.label),
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
        title: Text(context.tr('app.bulk_bar.keep_which_one')),
        children: [
          for (final w in works)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(w),
              child: Text(
                w.creator.isEmpty
                    ? w.title
                    : context.tr('app.bulk_bar.title_creator', {
                        'title': w.title,
                        'creator': w.creator,
                      }),
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
          context.tr('app.bulk_bar.merge_into_title', {'title': target.title}),
        ),
        content: Text(context.tr('app.bulk_bar.the_quotes_of_the_others_move')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('staging.move.merge.button.label')),
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
        title: Text(context.tr('app.bulk_bar.delete_n_works', {'n': n})),
        content: Text(
          context.tr('app.bulk_bar.their_q_quotes_are_deleted_with', {
            'q': quotes,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('app.bulk_bar.keep_them')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('common.action.delete.label')),
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
                textCapitalization: TextCapitalization.words,
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
            child: Text(context.tr('common.action.cancel.label')),
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
