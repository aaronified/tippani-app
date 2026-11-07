import 'package:flutter/material.dart';

import '../account/preferences.dart';
import '../app_controller.dart';
import '../harness/harness.dart';
import '../l10n/l10n.dart';
import 'account_screen.dart';
import 'prefs_screens.dart';
import 'prefs_widgets.dart';

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
          title: context.tr('You'),
          children: [
            if (account != null && paired)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(context.tr('Account')),
                subtitle: Text(
                  context.tr('Picture, password, notifications, widget key'),
                ),
                onTap: () => _open(
                  context,
                  AccountScreen(account: account, photos: null),
                ),
              ),
            ChoiceTile<String>(
              title: context.tr('Language'),
              icon: Icons.translate_rounded,
              value: p.locale,
              choices: [
                Choice('', context.tr('The phone\'s own language')),
                for (final c in l10n?.choices ?? const <LocaleChoice>[])
                  Choice(c.code, c.name),
              ],
              onChanged: (v) => savePrefs(context, {'locale': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('Reading'),
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: Text(context.tr('Text and quotes')),
              subtitle: Text(
                context.tr('Sizes, line height, typeface, names in a credit'),
              ),
              onTap: () => _open(context, const ReadingScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(context.tr('Colours')),
              subtitle: Text(context.tr('Names, shades and which are offered')),
              onTap: () => _open(context, const ColoursScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.view_carousel_outlined),
              title: Text(context.tr('Sections')),
              subtitle: Text(
                context.tr(
                  'What shows at the bottom, and how long the Bin keeps',
                ),
              ),
              onTap: () => _open(context, const SectionsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(context.tr('Daily review')),
              subtitle: Text(
                context.tr('Cards a day, difficulty and schedule'),
              ),
              onTap: () => _open(context, const ReviewPrefsScreen()),
            ),
            if (rules != null && paired)
              ListTile(
                leading: const Icon(Icons.unfold_more_rounded),
                title: Text(context.tr('Context around a quote')),
                subtitle: Text(
                  context.tr('How much of the source shows before and after'),
                ),
                onTap: () => _open(context, ContextRulesScreen(rules: rules)),
              ),
          ],
        ),
      ],
    );
  }
}
