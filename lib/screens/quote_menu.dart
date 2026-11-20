import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../anthologies/anthologies.dart';
import '../harness/harness.dart' show BackupPicker;
import '../l10n/l10n.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../library/quote_chips.dart' show ChipFilter;
import '../library/share_format.dart';
import '../speech/quote_speech.dart';
import '../sync/fingerprint.dart' show realmOfQuote;
import '../theme/tabler.dart';
import 'anthologies_screen.dart' show addToAnthologyDialog;
import 'bulk_bar.dart' show QuoteBulkActions;
import 'quote_form_screen.dart';
import 'quote_context_section.dart';
import '../share/share_subject.dart';
import 'share_screen.dart';
import 'work_screen.dart';

/// Everything a quote can be made to do, from anywhere it is drawn. The card shows [quoteCardButtons] as buttons;
/// the rest are in its menu.
enum QuoteAction {
  open,
  select,
  favourite,
  copy,
  speak,
  share,
  edit,
  colour,
  tag,
  untag,
  board,
  anthology,
  work,
  context,
  delete,
}

/// What a card draws as buttons of its own. The menu leaves these out where the card has them, so a reader
/// never sees the same action twice, and puts them in where the quote is drawn without them (a search result).
const quoteCardButtons = {
  QuoteAction.favourite,
  QuoteAction.copy,
  QuoteAction.speak,
  QuoteAction.share,
};

/// The menu of one quote, and what each item does. ONE builder for every place a quote is drawn as a card (the
/// library, a work, a board, a filtered list, Home, a search result): the items and what they do are the same
/// everywhere, which is the repo's "two things that look the same behave the same". An action that needs the
/// server is left out where it is not available, and one that makes no sense where the quote is drawn (Open work,
/// on the work's own page) is left out there.
class QuoteMenu {
  const QuoteMenu({
    required this.store,
    required this.quote,
    required this.picker,
    required this.onChanged,
    this.work,
    this.chipWork,
    this.anthologies,
    this.onFilter,
  });

  final LibraryStore store;
  final Quote quote;
  final BackupPicker picker;

  /// Called after the quote was changed (or deleted), so the screen reads its list again.
  final VoidCallback onChanged;

  /// The work the card's header names. Null where the card does not name one.
  final Work? work;

  /// The work the card sits under on that work's own page; it is where the words are credited to.
  final Work? chipWork;

  /// The server's anthologies; null (or not available) leaves Add to anthology out.
  final AnthologyService? anthologies;

  /// What a name chosen in the context viewer does (the library filters on it).
  final ValueChanged<ChipFilter>? onFilter;

  Work? get source => chipWork ?? work;

  bool get _canAnthology =>
      anthologies?.available == true && quote.serverId != null;

  /// Whether Add to anthology is in the menu (and is what a long press does where nothing is being selected).
  bool get canAddToAnthology => _canAnthology;

  QuoteBulkActions get _bulk => QuoteBulkActions(
    store: store,
    anthologies: anthologies,
    quotes: [quote],
    picker: picker,
    done: onChanged,
  );

  /// The menu's items. [onCard] are the actions the card already draws as buttons; [onOpen] and [onSelect] are
  /// the screen's own (null leaves the item out).
  List<PopupMenuEntry<QuoteAction>> items(
    BuildContext context, {
    Set<QuoteAction> onCard = const {},
    VoidCallback? onOpen,
    VoidCallback? onSelect,
  }) {
    PopupMenuItem<QuoteAction> item(QuoteAction a, String label) =>
        PopupMenuItem(value: a, child: Text(label));
    final speaking = QuoteSpeech.instance.speaking == quote.id;
    return [
      if (onOpen != null)
        item(QuoteAction.open, context.tr('app.quote_card.open')),
      if (onSelect != null)
        item(
          QuoteAction.select,
          context.tr('common.selection.menu.select.label'),
        ),
      if (!onCard.contains(QuoteAction.favourite))
        item(
          QuoteAction.favourite,
          quote.favorite
              ? context.tr('common.action.favourite.off.label')
              : context.tr('common.field.favourite.label'),
        ),
      if (!onCard.contains(QuoteAction.copy))
        item(QuoteAction.copy, context.tr('common.action.copy.label')),
      if (!onCard.contains(QuoteAction.speak))
        item(
          QuoteAction.speak,
          speaking
              ? context.tr('settings.jobs.current.stop.label')
              : context.tr('speech.play.aria'),
        ),
      if (!onCard.contains(QuoteAction.share))
        item(QuoteAction.share, context.tr('common.action.share.label')),
      item(QuoteAction.edit, context.tr('common.action.edit.label')),
      item(QuoteAction.colour, context.tr('common.field.colour.label')),
      item(QuoteAction.tag, context.tr('app.bulk_bar.add_a_tag')),
      if (quote.tags.isNotEmpty)
        item(QuoteAction.untag, context.tr('app.bulk_bar.take_a_tag_off')),
      // a quote of a book or film is filed by its work, as the bulk move says
      if (quote.workId == null)
        item(QuoteAction.board, context.tr('app.bulk_bar.move_to_a_board')),
      if (_canAnthology)
        item(
          QuoteAction.anthology,
          context.tr('common.action.anthology.label'),
        ),
      if (work != null)
        item(QuoteAction.work, context.tr('app.quote_card.open_work')),
      if (quoteHasContext(context, quote))
        item(
          QuoteAction.context,
          context.tr('app.quote_context.show_where_it_comes_from'),
        ),
      const PopupMenuDivider(),
      item(QuoteAction.delete, context.tr('common.action.delete.label')),
    ];
  }

  /// Does [action]. The same function the card's own buttons call, so a button and its menu item never differ.
  Future<void> run(
    BuildContext context,
    QuoteAction action, {
    VoidCallback? onOpen,
    VoidCallback? onSelect,
  }) async {
    switch (action) {
      case QuoteAction.open:
        onOpen?.call();
      case QuoteAction.select:
        onSelect?.call();
      case QuoteAction.favourite:
        await store.setFavorite(quote.id, !quote.favorite);
        onChanged();
      case QuoteAction.copy:
        await _copy(context);
      case QuoteAction.speak:
        await _speak(context);
      case QuoteAction.share:
        _share(context);
      case QuoteAction.edit:
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => QuoteFormScreen(store: store, quote: quote),
          ),
        );
        onChanged();
      case QuoteAction.colour:
        await _bulk.recolour(context);
      case QuoteAction.tag:
        await _bulk.tag(context, add: true);
      case QuoteAction.untag:
        await _bulk.tag(context, add: false);
      case QuoteAction.board:
        await _bulk.board(context);
      case QuoteAction.anthology:
        if (!_canAnthology) return;
        await addToAnthologyDialog(
          context,
          anthologies!,
          kind: entryKindOf(realmOfQuote(source)),
          itemId: quote.serverId!,
        );
      case QuoteAction.work:
        final w = work;
        if (w == null) return;
        await Navigator.of(context).push<Object?>(
          MaterialPageRoute(
            builder: (_) => WorkScreen(
              store: store,
              workId: w.id,
              picker: picker,
              anthologies: anthologies,
            ),
          ),
        );
        onChanged();
      case QuoteAction.context:
        await openQuoteContext(
          context,
          quote: quote,
          work: source,
          onFilter: onFilter,
        );
      case QuoteAction.delete:
        if (await deleteQuoteWithUndo(context, store, quote)) onChanged();
    }
  }

  Future<void> _copy(BuildContext context) async {
    final on = shareDefaults(shareFieldsOf(quote, source));
    final text = buildShareText(quote, source, on, ShareFormat.plain);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(context.tr('account.widget.copied'))),
      );
  }

  Future<void> _speak(BuildContext context) async {
    final language = quote.language.isNotEmpty
        ? quote.language
        : (source?.language ?? '');
    final ok = await QuoteSpeech.instance.toggle(
      quote.id,
      quote.text,
      language,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.tr('app.quote_card.no_voice', {'language': language}),
            ),
          ),
        );
    }
  }

  void _share(BuildContext context) {
    openShare(context, QuoteShare(quote, source), picker: picker);
  }
}

/// The "more" button of a quote: [QuoteMenu]'s items, minus what [onCard] already draws as buttons.
class QuoteMenuButton extends StatelessWidget {
  const QuoteMenuButton({
    super.key,
    required this.menu,
    this.onCard = const {},
    this.onOpen,
    this.onSelect,
    this.color,
  });

  final QuoteMenu menu;
  final Set<QuoteAction> onCard;
  final VoidCallback? onOpen;
  final VoidCallback? onSelect;
  final Color? color;

  @override
  Widget build(BuildContext context) => PopupMenuButton<QuoteAction>(
    tooltip: context.tr('app.quote_card.more'),
    padding: EdgeInsets.zero,
    icon: Icon(
      Ti.dotsVertical,
      size: 20,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onSelected: (a) => menu.run(context, a, onOpen: onOpen, onSelect: onSelect),
    itemBuilder: (context) =>
        menu.items(context, onCard: onCard, onOpen: onOpen, onSelect: onSelect),
  );
}

/// Asks, deletes, and offers Undo for a moment: the one deletion of a single quote, for its page and its menu.
/// True when it was deleted.
Future<bool> deleteQuoteWithUndo(
  BuildContext context,
  LibraryStore store,
  Quote gone,
) async {
  final deleted = context.tr('app.quote.quote_deleted');
  final undo = context.tr('common.action.undo.label');
  final restoredAsNew = context.tr('app.quote.quote_restored_as_new');
  // the messenger belongs to the app, so the Undo outlives this screen
  final messenger = ScaffoldMessenger.of(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('quotes.delete.confirm')),
      content: Text(context.tr('app.quote_form.it_is_removed_from_this_phone')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('app.anthologies.keep_it')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.tr('common.action.delete.label')),
        ),
      ],
    ),
  );
  if (sure != true) return false;
  await store.deleteQuote(gone.id);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(deleted),
        action: SnackBarAction(
          label: undo,
          onPressed: () async {
            // The same quote comes back when the server has not been told of the delete; otherwise the original is in
            // the server's bin and this is a new quote, which the note says plainly.
            final same = await store.undeleteQuote(gone);
            if (!same) {
              messenger
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(restoredAsNew)));
            }
          },
        ),
      ),
    );
  return true;
}
