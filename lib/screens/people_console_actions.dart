import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../people/people_console.dart';
import '../l10n/l10n.dart';

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [job] and says what the server refused with. True when it worked.
Future<bool> consoleCall(
  BuildContext context,
  Future<void> Function() job,
) async {
  try {
    await job();
    return true;
  } on ServerException catch (e) {
    if (context.mounted) _say(context, e.message);
    return false;
  }
}

/// A record in the pickers: a name, a line of counts, and what it is to the picker's caller.
class PickRow {
  const PickRow({
    required this.id,
    required this.name,
    this.hint = '',
    this.spellings = const [],
  });
  final int id;
  final String name, hint;
  final List<String> spellings;
}

String countsHint(int works, int quotes) {
  String n(int c, String one, String many) => '$c ${c == 1 ? one : many}';
  return [
    if (works > 0) n(works, 'work', 'works'),
    if (quotes > 0) n(quotes, 'quote', 'quotes'),
  ].join(' · ');
}

/// Edits every spelling of a record in one box, one per line; the first line is the name it prints under.
/// True when saved.
Future<bool> editSpellings(
  BuildContext context,
  PeopleConsole console, {
  required bool character,
  required int id,
  required List<String> names,
}) async {
  final c = TextEditingController(text: names.join('\n'));
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('app.people_console_actions.names_and_spellings')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr(
              'app.people_console_actions.one_name_per_line_the_first',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.tr('common.action.save.label')),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  final lines = [
    for (final l in c.text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) {
    _say(context, 'A record needs at least one name.');
    return false;
  }
  return consoleCall(
    context,
    () => console.setNames(character: character, id: id, names: lines),
  );
}

/// Turns a spelling into a record of its own (the record it was a spelling of loses it). True when it was.
Future<bool> splitSpelling(
  BuildContext context,
  PeopleConsole console, {
  required bool character,
  required int id,
  required String alias,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        context.tr('app.people_console_actions.make_alias_its_own_record', {
          'alias': alias,
        }),
      ),
      content: Text(
        context.tr('app.people_console_actions.it_stops_being_a_spelling_of'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.tr('app.people_console_actions.split_it_out')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return consoleCall(
    context,
    () => console.splitSpelling(character: character, id: id, alias: alias),
  );
}

/// Asks which of two records survives a merge; true when merged. The other's name becomes a spelling of it.
Future<bool> mergeTwo(
  BuildContext context,
  PeopleConsole console, {
  required bool character,
  required PickRow a,
  required PickRow b,
}) async {
  var keep = a.id;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: Text(context.tr('app.bulk_bar.merge_into_one')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                'app.people_console_actions.everything_that_points_at_one_points',
              ),
            ),
            RadioGroup<int>(
              groupValue: keep,
              onChanged: (v) => set(() => keep = v ?? keep),
              child: Column(
                children: [
                  for (final r in [a, b])
                    RadioListTile<int>(
                      value: r.id,
                      title: Text(r.name),
                      subtitle: r.hint.isEmpty ? null : Text(r.hint),
                    ),
                ],
              ),
            ),
            Text(
              context.tr(
                'app.people_console_actions.the_merge_can_be_undone_from',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('staging.move.merge.button.label')),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return false;
  final drop = keep == a.id ? b.id : a.id;
  return consoleCall(
    context,
    () => character
        ? console.mergeCharacters(keep, drop)
        : console.mergePeople(keep, drop),
  );
}

/// Lets the reader search the records and pick one; null when they back out.
Future<PickRow?> pickRecord(
  BuildContext context, {
  required String title,
  required List<PickRow> rows,
}) {
  return showModalBottomSheet<PickRow>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      var query = '';
      return StatefulBuilder(
        builder: (context, set) {
          final shown = [
            for (final r in rows)
              if (query.isEmpty ||
                  r.name.toLowerCase().contains(query) ||
                  r.spellings.any((s) => s.toLowerCase().contains(query)))
                r,
          ];
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: context.tr('common.help.topbar.search.term'),
                    ),
                    onChanged: (v) => set(() => query = v.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final r in shown)
                        ListTile(
                          title: Text(r.name),
                          subtitle: r.hint.isEmpty ? null : Text(r.hint),
                          onTap: () => Navigator.pop(context, r),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Asks before removing a record; true when removed.
Future<bool> removeRecord(
  BuildContext context,
  PeopleConsole console, {
  required bool character,
  required int id,
  required String name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('cast.remove.confirm.prose', {'name': name})),
      content: Text(
        character
            ? context.tr(
                'app.people_console_actions.the_character_is_removed_from_every',
              )
            : context.tr(
                'app.people_console_actions.the_person_is_removed_and_credits',
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.tr('common.action.remove.label')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return consoleCall(
    context,
    () => character ? console.deleteCharacter(id) : console.deletePerson(id),
  );
}

/// The form for a new or changed character; null when cancelled.
Future<CharacterEdit?> characterForm(
  BuildContext context, {
  String title = 'Edit the character',
  String name = '',
  String description = '',
  String born = '',
  String links = '',
  String note = '',
  String yes = 'Save',
}) {
  final n = TextEditingController(text: name);
  final d = TextEditingController(text: description);
  final b = TextEditingController(text: born);
  final l = TextEditingController(text: links);
  final o = TextEditingController(text: note);
  return showDialog<CharacterEdit>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
              autofocus: name.isEmpty,
              decoration: InputDecoration(
                labelText: context.tr('common.field.name.label'),
              ),
            ),
            TextField(
              controller: d,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: context.tr(
                  'app.people_console_actions.who_they_are',
                ),
              ),
            ),
            TextField(
              controller: b,
              decoration: InputDecoration(
                labelText: context.tr(
                  'app.people_console_actions.born_in_the_story',
                ),
              ),
            ),
            TextField(
              controller: l,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: context.tr('common.field.links.label'),
                helperText: context.tr(
                  'app.people_console_actions.one_address_per_line',
                ),
              ),
            ),
            TextField(
              controller: o,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.tr('identity.field.note'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          onPressed: () {
            if (n.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              CharacterEdit(
                name: n.text.trim(),
                description: d.text.trim(),
                born: b.text.trim(),
                links: l.text.trim(),
                note: o.text.trim(),
              ),
            );
          },
          child: Text(yes),
        ),
      ],
    ),
  );
}
