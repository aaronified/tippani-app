import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../library/library_store.dart';
import '../theme/tabler.dart';
import 'add_kind.dart';
import 'quote_form_screen.dart';

export 'add_kind.dart';

/// Opens the sheet that offers every kind of quote to add. [onImport] opens the import screen for a file.
Future<void> showAddQuoteSheet(
  BuildContext context, {
  required LibraryStore store,
  VoidCallback? onImport,
}) async {
  final pick = await showModalBottomSheet<AddKind>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      Widget tile(AddKind k, IconData icon, String title, String note) =>
          ListTile(
            key: ValueKey('add-${k.name}'),
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(note),
            onTap: () => Navigator.of(context).pop(k),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  context.tr('app.add.title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              tile(
                AddKind.book,
                Ti.book2,
                context.tr('app.add.book'),
                context.tr('app.add.book_note'),
              ),
              tile(
                AddKind.screen,
                Ti.movie,
                context.tr('app.add.screen'),
                context.tr('app.add.screen_note'),
              ),
              tile(
                AddKind.loose,
                Ti.quote,
                context.tr('app.add.loose'),
                context.tr('app.add.loose_note'),
              ),
              tile(
                AddKind.scan,
                Ti.camera,
                context.tr('app.add.scan'),
                context.tr('app.add.scan_note'),
              ),
              tile(
                AddKind.voice,
                Ti.microphone,
                context.tr('app.add.voice'),
                context.tr('app.add.voice_note'),
              ),
              if (onImport != null)
                tile(
                  AddKind.file,
                  Ti.fileImport,
                  context.tr('app.add.file'),
                  context.tr('app.add.file_note'),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (pick == null || !context.mounted) return;
  if (pick == AddKind.file) {
    onImport?.call();
    return;
  }
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => QuoteFormScreen(
        store: store,
        kind: switch (pick) {
          AddKind.book => AddKind.book,
          AddKind.screen => AddKind.screen,
          AddKind.loose => AddKind.loose,
          _ => null,
        },
        startWith: switch (pick) {
          AddKind.scan => AddKind.scan,
          AddKind.voice => AddKind.voice,
          _ => null,
        },
      ),
    ),
  );
}
