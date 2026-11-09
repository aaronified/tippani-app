import 'dart:convert';

import 'package:flutter/material.dart';

import '../account/account_service.dart';
import '../account/preferences.dart';
import '../l10n/l10n.dart';
import '../library/models.dart';
import '../theme/app_theme.dart';
import 'prefs_widgets.dart';
import 'quote_form_screen.dart' show quoteColour, quoteColourName;
import '../theme/tabler.dart';

const _sizes = [75, 100, 125, 150, 175, 200];

/// Text size, how quotes are set, and how credits are split into names.
class ReadingScreen extends StatelessWidget {
  const ReadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PrefsScope.of(context);
    final theme = Theme.of(context);
    final faces = p.fontsByLanguage;
    return PrefPage(
      title: context.tr('app.prefs.text_and_quotes'),
      children: [
        // what the choices below do, as they are chosen
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Card(
            color: theme.colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: quoteMeasure(
                context,
                17,
                Text(
                  context.tr('app.prefs.the_only_thing_that_makes_life'),
                  key: const ValueKey('reading-sample'),
                  style: quoteStyle(context, size: 17),
                ),
              ),
            ),
          ),
        ),
        PrefGroup(
          title: context.tr('app.prefs.size'),
          children: [
            StepTile(
              title: context.tr('settings.appearance.text-size.label'),
              icon: Ti.typography,
              steps: _sizes,
              value: p.sizeUi,
              onChanged: (v) => savePrefs(context, {'sizeUi': v}),
            ),
            StepTile(
              title: context.tr('app.prefs.quote_size'),
              icon: Ti.textSize,
              steps: _sizes,
              value: p.sizeDisplay,
              onChanged: (v) => savePrefs(context, {'sizeDisplay': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('app.prefs.setting_a_quote'),
          children: [
            ChoiceTile<int>(
              title: context.tr('app.prefs.line_height'),
              icon: Ti.lineHeight,
              value: p.quoteLeading,
              choices: [
                Choice(0, context.tr('app.prefs.the_app_s_own')),
                const Choice(130, '130%'),
                const Choice(145, '145%'),
                const Choice(155, '155%'),
                const Choice(170, '170%'),
                const Choice(190, '190%'),
              ],
              onChanged: (v) => savePrefs(context, {'quoteLeading': v}),
            ),
            ChoiceTile<int>(
              title: context.tr('app.prefs.line_length'),
              icon: Ti.viewportWide,
              value: p.quoteMeasure,
              choices: [
                Choice(0, context.tr('app.prefs.the_full_width')),
                Choice(
                  45,
                  context.tr('metadata.prune.confirm.characters.other', {
                    'n': 45,
                  }),
                ),
                Choice(
                  55,
                  context.tr('metadata.prune.confirm.characters.other', {
                    'n': 55,
                  }),
                ),
                Choice(
                  66,
                  context.tr('metadata.prune.confirm.characters.other', {
                    'n': 66,
                  }),
                ),
                Choice(
                  80,
                  context.tr('metadata.prune.confirm.characters.other', {
                    'n': 80,
                  }),
                ),
              ],
              onChanged: (v) => savePrefs(context, {'quoteMeasure': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('app.prefs.names_in_a_credit'),
          footer: context.tr('app.prefs.a_credit_such_as_pratchett_gaiman'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (token, label) in [
                    ('comma', context.tr('app.prefs.commas')),
                    ('semicolon', context.tr('app.prefs.semicolons')),
                    ('amp', '&'),
                    ('and', context.tr('app.prefs.the_word_and')),
                  ])
                    FilterChip(
                      key: ValueKey('sep-$token'),
                      label: Text(label),
                      selected: p.creditSeparators.contains(token),
                      onSelected: (on) {
                        final now = {...p.creditSeparators};
                        on ? now.add(token) : now.remove(token);
                        final ordered = [
                          for (final t in ['comma', 'semicolon', 'amp', 'and'])
                            if (now.contains(t)) t,
                        ];
                        savePrefs(context, {
                          'creditSeparators': ordered.isEmpty
                              ? 'none'
                              : ordered.join(','),
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('app.prefs.typeface_by_language'),
          footer: context.tr('app.prefs.quotes_in_a_language_you_list'),
          children: [
            for (final e in faces.entries)
              ListTile(
                title: Text(_title(e.key)),
                subtitle: Text(_faceName(context, e.value)),
                trailing: IconButton(
                  tooltip: context.tr('common.action.remove.label'),
                  icon: const Icon(Ti.x),
                  onPressed: () {
                    final next = {...faces}..remove(e.key);
                    savePrefs(context, {'fontsByLanguage': _blob(next)});
                  },
                ),
                onTap: () => _addFace(context, faces, e.key),
              ),
            ListTile(
              leading: const Icon(Ti.plus),
              title: Text(context.tr('settings.languages.add.label')),
              onTap: () => _addFace(context, faces, null),
            ),
          ],
        ),
      ],
    );
  }

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _blob(Map<String, String> m) => m.isEmpty ? '' : jsonEncode(m);

  static String _faceName(BuildContext context, String token) =>
      switch (token) {
        'newsreader' => context.tr('vocab.face.newsreader.name'),
        'noto-serif-bengali' => context.tr(
          'vocab.face.noto-serif-bengali.name',
        ),
        'noto-serif-devanagari' => context.tr(
          'vocab.face.noto-serif-devanagari.name',
        ),
        'source-serif-4' => context.tr('vocab.face.source-serif-4.name'),
        _ => token,
      };

  Future<void> _addFace(
    BuildContext context,
    Map<String, String> faces,
    String? language,
  ) async {
    final picked = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _FaceDialog(
        language: language,
        face: language == null ? 'source-serif-4' : faces[language]!,
      ),
    );
    if (picked == null || picked.$1.isEmpty || !context.mounted) return;
    await savePrefs(context, {
      'fontsByLanguage': _blob({...faces, picked.$1: picked.$2}),
    });
  }
}

/// The six colours quotes can take: what each is called, which shade it is, and which are offered.
class ColoursScreen extends StatelessWidget {
  const ColoursScreen({super.key});

  static final palette = [
    ('#E5C355', 'Sun'),
    ('#DF9A5B', 'Amber'),
    ('#D98CA6', 'Rose'),
    ('#E8A0C0', 'Blush'),
    ('#C2555F', 'Crimson'),
    ('#A8739E', 'Mauve'),
    ('#8A7BC8', 'Violet'),
    ('#6E8FD0', 'Periwinkle'),
    ('#7FA6C9', 'Sky'),
    ('#5AA8B5', 'Teal'),
    ('#6FBF9F', 'Mint'),
    ('#4FA98A', 'Jade'),
    ('#7CB342', 'Leaf'),
    ('#B5C05A', 'Moss'),
    ('#B0806B', 'Clay'),
    ('#8C7F6E', 'Stone'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = PrefsScope.of(context);
    return PrefPage(
      title: context.tr('metadata.categories.colours.title'),
      children: [
        PrefGroup(
          footer: context.tr('app.prefs.the_first_colour_is_the_one'),
          children: [
            for (var i = 0; i < ServerPrefs.colourSlots.length; i++)
              _slot(context, p, i),
          ],
        ),
      ],
    );
  }

  Widget _slot(BuildContext context, ServerPrefs p, int i) {
    final token = ServerPrefs.colourSlots[i];
    final n = i + 1;
    return ListTile(
      key: ValueKey('slot-$token'),
      leading: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _pick(context, p, n, token),
        child: Semantics(
          button: true,
          label: context.tr('app.prefs.choose_a_shade'),
          child: CircleAvatar(backgroundColor: quoteColour(token), radius: 16),
        ),
      ),
      title: Text(quoteColourName(token)),
      subtitle: Text(
        i == 0
            ? context.tr('settings.colours.fixed.tip')
            : (p.colourHidden(token)
                  ? context.tr('app.prefs.hidden_from_the_pickers')
                  : context.tr('app.prefs.shown_in_the_pickers')),
      ),
      onTap: i == 0 ? null : () => _name(context, p, n, token),
      trailing: i == 0
          ? null
          : Switch(
              value: !p.colourHidden(token),
              onChanged: (on) => savePrefs(context, {'catHidden$n': !on}),
            ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    ServerPrefs p,
    int n,
    String token,
  ) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx.tr('app.prefs.a_shade_for_name', {
                  'name': quoteColourName(token),
                }),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (hex, name) in palette)
                    Tooltip(
                      message: ctx.tr(name),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(ctx, hex),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Color(
                            0xFF000000 | int.parse(hex.substring(1), radix: 16),
                          ),
                          child: p.colourHex(token).toUpperCase() == hex
                              ? const Icon(Ti.check, size: 20)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: Text(ctx.tr('app.prefs.back_to_the_built_in_shade')),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await savePrefs(context, {'catColor$n': chosen});
  }

  Future<void> _name(
    BuildContext context,
    ServerPrefs p,
    int n,
    String token,
  ) async {
    final text = await askText(
      context,
      title: context.tr('app.prefs.name_this_colour'),
      initial: p.colourName(token),
      hint: token,
      helper: context.tr('app.prefs.leave_it_empty_for_the_built'),
      maxLength: 15,
    );
    if (text == null || !context.mounted) return;
    await savePrefs(context, {'catName$n': text});
  }
}

/// Which parts of the library show as sections, and how long the Bin keeps things.
class SectionsScreen extends StatelessWidget {
  const SectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PrefsScope.of(context);
    final lastShown =
        [
          !p.hideLibrary,
          !p.hideCatalogue,
          !p.hideQuotes,
        ].where((b) => b).length ==
        1;
    Widget section(String key, String title, String hint, bool hidden) {
      final onlyOne = lastShown && !hidden;
      return SwitchListTile(
        key: ValueKey('section-$key'),
        title: Text(title),
        subtitle: Text(
          onlyOne ? context.tr('app.prefs.at_least_one_of_these_three') : hint,
        ),
        value: !hidden,
        onChanged: onlyOne ? null : (on) => savePrefs(context, {key: !on}),
      );
    }

    return PrefPage(
      title: context.tr('shell.dock.sections.label'),
      children: [
        PrefGroup(
          title: context.tr('common.action.show.label'),
          children: [
            section(
              'hideLibrary',
              context.tr('nav.tab.library.label'),
              context.tr('nav.section.library.what'),
              p.hideLibrary,
            ),
            section(
              'hideCatalogue',
              context.tr('nav.tab.movies.label'),
              context.tr('nav.section.movies.what'),
              p.hideCatalogue,
            ),
            section(
              'hideQuotes',
              context.tr('nav.tab.quotes.label'),
              context.tr('nav.section.quotes.what'),
              p.hideQuotes,
            ),
            SwitchListTile(
              key: const ValueKey('section-showAnthologies'),
              title: Text(context.tr('nav.tab.anthologies.label')),
              subtitle: Text(context.tr('nav.section.anthologies.what')),
              value: p.showAnthologies || !p.known,
              onChanged: (on) => savePrefs(context, {'showAnthologies': on}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('bin.title'),
          children: [
            ChoiceTile<int>(
              title: context.tr('app.prefs.keep_deleted_things_for'),
              icon: Ti.trash,
              value: p.trashDays,
              choices: [
                Choice(
                  7,
                  context.tr('common.slider.days.format.other', {'n': 7}),
                ),
                Choice(
                  30,
                  context.tr('common.slider.days.format.other', {'n': 30}),
                ),
                Choice(
                  90,
                  context.tr('common.slider.days.format.other', {'n': 90}),
                ),
                Choice(-1, context.tr('app.prefs.for_ever')),
              ],
              onChanged: (v) => savePrefs(context, {'trashDays': v}),
            ),
          ],
        ),
      ],
    );
  }
}

/// How the daily review is drawn and paced. The server keeps these, so a change here reaches the web too.
class ReviewPrefsScreen extends StatelessWidget {
  const ReviewPrefsScreen({super.key});

  static const _media = ['books', 'movies', 'quotes'];

  static List<String> scope(String value) {
    final toks = [
      for (final t in value.toLowerCase().split(','))
        if (t.trim().isNotEmpty) t.trim(),
    ];
    final out = <String>{};
    for (final t in toks) {
      if (t == 'both' || t == 'all') return _media;
      if (t == 'screen') {
        out.add('movies');
      } else if (_media.contains(t)) {
        out.add(t);
      }
    }
    return out.isEmpty
        ? _media
        : [
            for (final m in _media)
              if (out.contains(m)) m,
          ];
  }

  @override
  Widget build(BuildContext context) {
    final p = PrefsScope.of(context);
    final on = scope(p.srReviewScope);
    return PrefPage(
      title: context.tr('app.prefs.daily_review'),
      children: [
        PrefGroup(
          title: context.tr('app.prefs.each_day'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('app.prefs.cards_a_day'),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        context.tr('app.prefs.sr_daily', {
                          'sr_daily': p.srDaily,
                        }),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  Slider(
                    value: p.srDaily.clamp(5, 20).toDouble(),
                    min: 5,
                    max: 20,
                    divisions: 15,
                    label: context.tr('app.prefs.sr_daily', {
                      'sr_daily': p.srDaily,
                    }),
                    onChanged: (v) =>
                        savePrefs(context, {'srDaily': v.round()}),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('settings.review-scope.title'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (m, label) in [
                        ('books', context.tr('nav.tab.library.label')),
                        ('movies', context.tr('nav.tab.movies.label')),
                        ('quotes', context.tr('nav.tab.quotes.label')),
                      ])
                        FilterChip(
                          key: ValueKey('scope-$m'),
                          label: Text(label),
                          selected: on.contains(m),
                          // the deck cannot be emptied of every medium
                          onSelected: on.contains(m) && on.length == 1
                              ? null
                              : (sel) {
                                  final now = {...on};
                                  sel ? now.add(m) : now.remove(m);
                                  savePrefs(context, {
                                    'srReviewScope': [
                                      for (final x in _media)
                                        if (now.contains(x)) x,
                                    ].join(','),
                                  });
                                },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('app.prefs.questions'),
          children: [
            ChoiceTile<String>(
              title: context.tr('settings.quiz.tier.title'),
              value: p.srTier,
              choices: [
                Choice(
                  'easy',
                  context.tr('settings.quiz.tier.easy.label'),
                  context.tr('settings.quiz.tier.easy.note'),
                ),
                Choice(
                  'medium',
                  context.tr('settings.quiz.tier.medium.label'),
                  context.tr('settings.quiz.tier.medium.note'),
                ),
                Choice(
                  'hard',
                  context.tr('settings.quiz.tier.hard.label'),
                  context.tr('settings.quiz.tier.hard.note'),
                ),
                Choice(
                  'random',
                  context.tr('settings.quiz.tier.random.label'),
                  context.tr('settings.quiz.tier.random.note'),
                ),
              ],
              onChanged: (v) => savePrefs(context, {'srTier': v}),
            ),
            ChoiceTile<String>(
              title: context.tr('settings.quiz.start.title'),
              value: p.srStart,
              choices: [
                Choice(
                  'unseen',
                  context.tr('settings.quiz.start.unseen.label'),
                  context.tr('app.prefs.asked_soon_and_often'),
                ),
                Choice(
                  'mastered',
                  context.tr('settings.quiz.start.mastered.label'),
                  context.tr('app.prefs.asked_rarely_for_a_library_you'),
                ),
              ],
              onChanged: (v) => savePrefs(context, {'srStart': v}),
            ),
            SwitchListTile(
              title: Text(context.tr('settings.quiz.submit.aria')),
              subtitle: Text(context.tr('app.prefs.off_a_tap_answers_on_a')),
              value: p.srSubmit,
              onChanged: (v) => savePrefs(context, {'srSubmit': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('settings.quiz.group.schedule.title'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('settings.quiz.seen.label'),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        '${p.srSeen.toStringAsFixed(2)}×',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  Slider(
                    value: p.srSeen.clamp(1.0, 1.5),
                    min: 1.0,
                    max: 1.5,
                    divisions: 10,
                    label: '${p.srSeen.toStringAsFixed(2)}×',
                    onChanged: (v) => savePrefs(context, {
                      'srSeen': double.parse(v.toStringAsFixed(2)),
                    }),
                  ),
                  Text(
                    context.tr(
                      'app.prefs.sharing_favouriting_or_seeing_a_quote',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('settings.quiz.practice-counts.title')),
              subtitle: Text(
                context.tr('app.prefs.off_practice_is_study_only_on'),
              ),
              value: p.srPracticeCounts,
              onChanged: (v) => savePrefs(context, {'srPracticeCounts': v}),
            ),
          ],
        ),
        PrefGroup(
          children: [
            ListTile(
              leading: const Icon(Ti.reload),
              title: Text(context.tr('app.prefs.back_to_the_defaults')),
              subtitle: Text(
                context.tr('app.prefs.puts_the_settings_on_these_pages'),
              ),
              onTap: () => _reset(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _reset(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('app.prefs.put_these_settings_back')),
        content: Text(
          ctx.tr('app.prefs.language_text_size_colours_sections_and'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('app.prefs.put_them_back')),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final source = PrefsScope.sourceOf(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final refusal = await source?.reset();
    if (refusal != null) {
      messenger?.showSnackBar(SnackBar(content: Text(refusal)));
    }
  }
}

/// How many quotes of the source (the lines before and after) show around a quote, for everything.
class ContextRulesScreen extends StatefulWidget {
  const ContextRulesScreen({super.key, required this.rules});

  final ContextRules rules;

  @override
  State<ContextRulesScreen> createState() => _ContextRulesScreenState();
}

class _ContextRulesScreenState extends State<ContextRulesScreen> {
  ContextRule? _rule;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.rules.global();
    if (!mounted) return;
    setState(() {
      _rule = r.value;
      _problem = r.error;
    });
  }

  Future<void> _set(ContextRule next) async {
    final before = _rule;
    setState(() => _rule = next);
    final r = await widget.rules.setGlobal(next);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _rule = before);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rule = _rule;
    return PrefPage(
      title: context.tr('app.prefs.context_around_a_quote'),
      children: [
        if (_problem != null) PrefNote(_problem!),
        if (rule != null)
          PrefGroup(
            footer: context.tr('app.prefs.how_many_lines_of_the_book'),
            children: [
              _half(context, context.tr('app.prefs.before'), rule.before, (v) {
                _set(ContextRule(before: v, after: rule.after));
              }),
              _half(context, context.tr('app.prefs.after'), rule.after, (v) {
                _set(ContextRule(before: rule.before, after: v));
              }),
            ],
          ),
      ],
    );
  }

  Widget _half(
    BuildContext context,
    String label,
    int? value,
    ValueChanged<int?> onChanged,
  ) => Column(
    children: [
      SwitchListTile(
        title: Text(label),
        subtitle: Text(
          value == null
              ? context.tr('app.prefs.the_built_in_amount')
              : context.tr('app.prefs.n_lines', {'n': value}),
        ),
        value: value != null,
        onChanged: (on) => onChanged(on ? 3 : null),
      ),
      if (value != null)
        Slider(
          value: value.toDouble(),
          min: 0,
          max: ContextRules.max.toDouble(),
          divisions: ContextRules.max,
          label: context.tr('app.prefs.value', {'value': value}),
          onChanged: (v) => onChanged(v.round()),
        ),
    ],
  );
}

/// The same rule for one work, with the choice of what to do to quotes already adjusted wider than it.
Future<void> showWorkContextRule(
  BuildContext context,
  ContextRules rules,
  Work work,
) async {
  final id = work.serverId;
  if (id == null) return;
  final scope = work.kind == WorkKind.book || work.kind == WorkKind.other
      ? 'book'
      : 'movie';
  final current = await rules.forWork(scope, id);
  if (!context.mounted) return;
  if (!current.ok) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(current.error!)));
    return;
  }
  var before = current.value?.before;
  var after = current.value?.after;
  var enforce = '';
  final save = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Widget half(String label, int? v, ValueChanged<int?> on) => Column(
          children: [
            SwitchListTile(
              title: Text(label),
              subtitle: Text(
                v == null
                    ? ctx.tr('app.prefs.follows_your_setting_for_everything')
                    : ctx.tr('app.prefs.n_lines', {'n': v}),
              ),
              value: v != null,
              onChanged: (b) => set(() => on(b ? 3 : null)),
            ),
            if (v != null)
              Slider(
                value: v.toDouble(),
                min: 0,
                max: ContextRules.max.toDouble(),
                divisions: ContextRules.max,
                label: '$v',
                onChanged: (x) => set(() => on(x.round())),
              ),
          ],
        );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    ctx.tr('app.prefs.context_for_title', {
                      'title': work.title,
                    }),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                half(ctx.tr('app.prefs.before'), before, (v) => before = v),
                half(ctx.tr('app.prefs.after'), after, (v) => after = v),
                RadioGroup<String>(
                  groupValue: enforce,
                  onChanged: (v) => set(() => enforce = v ?? ''),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: '',
                        title: Text(
                          ctx.tr('app.prefs.leave_quotes_already_adjusted'),
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'clamp',
                        title: Text(
                          ctx.tr('app.prefs.bring_wider_ones_down_to_this'),
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'clear',
                        title: Text(ctx.tr('app.prefs.clear_every_adjustment')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(ctx.tr('common.action.save.label')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (save != true || !context.mounted) return;
  final r = await rules.setForWork(
    scope,
    id,
    ContextRule(before: before, after: after),
    enforce: enforce,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        r.ok
            ? ((r.value ?? 0) > 0
                  ? context.tr('app.prefs.saved_n_quotes_changed', {
                      'n': r.value,
                    })
                  : context.tr('account.notify.saved'))
            : r.error!,
      ),
    ),
  );
}

class _FaceDialog extends StatefulWidget {
  const _FaceDialog({required this.language, required this.face});

  final String? language;
  final String face;

  @override
  State<_FaceDialog> createState() => _FaceDialogState();
}

class _FaceDialogState extends State<_FaceDialog> {
  late final _name = TextEditingController(text: widget.language ?? '');
  late String _face = widget.face;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('app.prefs.typeface_for_a_language')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          textCapitalization: TextCapitalization.none,
          controller: _name,
          enabled: widget.language == null,
          autofocus: widget.language == null,
          decoration: InputDecoration(
            labelText: context.tr('common.field.language.label'),
            hintText: context.tr('vocab.font-role.bengali.label'),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _face,
          decoration: InputDecoration(
            labelText: context.tr('app.prefs.typeface'),
          ),
          items: [
            for (final t in quoteFaces.keys)
              DropdownMenuItem(
                value: t,
                child: Text(ReadingScreen._faceName(context, t)),
              ),
          ],
          onChanged: (v) => setState(() => _face = v ?? _face),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('common.action.cancel.label')),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (_name.text.trim().toLowerCase(), _face)),
        child: Text(context.tr('common.action.save.label')),
      ),
    ],
  );
}
