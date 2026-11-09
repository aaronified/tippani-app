import 'package:flutter/material.dart';

import '../account/preferences.dart';
import '../app_controller.dart';
import '../harness/harness.dart';
import '../l10n/l10n.dart';
import 'account_screen.dart';
import 'prefs_screens.dart';
import 'prefs_widgets.dart';
import '../theme/tabler.dart';

/// The Settings entries for the account's own preferences: who you are, the language, how text and quotes are
/// set, colours, sections, the daily review and the context around a quote.
class PrefsEntries extends StatelessWidget {
  const PrefsEntries({
    super.key,
    required this.controller,
    required this.harness,
  });

  final AppController controller;
  final Harness harness;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    if (harness.prefs == null) return const SizedBox.shrink();
    final p = PrefsScope.of(context);
    final l10n = L10nScope.of(context);
    final account = harness.account;
    final rules = harness.contextRules;
    final paired = controller.paired;
    return Column(
      children: [
        PrefGroup(
          title: context.tr('vocab.source.manual.label'),
          children: [
            if (account != null && paired)
              ListTile(
                leading: const Icon(Ti.userCircle),
                title: Text(context.tr('bin.kind.account.label')),
                subtitle: Text(
                  context.tr(
                    'app.prefs.picture_password_notifications_widget_key',
                  ),
                ),
                onTap: () => _open(
                  context,
                  AccountScreen(account: account, photos: null),
                ),
              ),
            ChoiceTile<String>(
              title: context.tr('common.field.language.label'),
              icon: Ti.language,
              value: p.locale,
              choices: [
                Choice('', context.tr('app.prefs.the_phone_s_own_language')),
                for (final c in l10n?.choices ?? const <LocaleChoice>[])
                  Choice(c.code, c.name),
              ],
              onChanged: (v) => savePrefs(context, {'locale': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('common.shelf.reading.book.label'),
          children: [
            ListTile(
              leading: const Icon(Ti.typography),
              title: Text(context.tr('app.prefs.text_and_quotes')),
              subtitle: Text(
                context.tr('app.prefs.sizes_line_height_typeface_names_in'),
              ),
              onTap: () => _open(context, const ReadingScreen()),
            ),
            ListTile(
              leading: const Icon(Ti.palette),
              title: Text(context.tr('metadata.categories.colours.title')),
              subtitle: Text(
                context.tr('app.prefs.names_shades_and_which_are_offered'),
              ),
              onTap: () => _open(context, const ColoursScreen()),
            ),
            ListTile(
              leading: const Icon(Ti.carouselHorizontal),
              title: Text(context.tr('shell.dock.sections.label')),
              subtitle: Text(
                context.tr('app.prefs.what_shows_at_the_bottom_and'),
              ),
              onTap: () => _open(context, const SectionsScreen()),
            ),
            ListTile(
              leading: const Icon(Ti.school),
              title: Text(context.tr('app.prefs.daily_review')),
              subtitle: Text(
                context.tr('app.prefs.cards_a_day_difficulty_and_schedule'),
              ),
              onTap: () => _open(context, const ReviewPrefsScreen()),
            ),
            if (rules != null && paired)
              ListTile(
                leading: const Icon(Ti.selector),
                title: Text(context.tr('app.prefs.context_around_a_quote')),
                subtitle: Text(
                  context.tr('app.prefs.how_much_of_the_source_shows'),
                ),
                onTap: () => _open(context, ContextRulesScreen(rules: rules)),
              ),
          ],
        ),
      ],
    );
  }
}
