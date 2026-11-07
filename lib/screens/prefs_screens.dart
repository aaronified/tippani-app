import 'dart:convert';

import 'package:flutter/material.dart';

import '../account/account_service.dart';
import '../account/preferences.dart';
import '../l10n/l10n.dart';
import '../library/models.dart';
import '../theme/app_theme.dart';
import 'prefs_widgets.dart';
import 'quote_form_screen.dart' show quoteColour, quoteColourName;

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
      title: context.tr('Text and quotes'),
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
                  '“The only thing that makes life possible is permanent, intolerable uncertainty: not knowing what comes next.”',
                  key: const ValueKey('reading-sample'),
                  style: quoteStyle(context, size: 17),
                ),
              ),
            ),
          ),
        ),
        PrefGroup(
          title: context.tr('Size'),
          children: [
            StepTile(
              title: context.tr('Text size'),
              icon: Icons.text_fields_rounded,
              steps: _sizes,
              value: p.sizeUi,
              onChanged: (v) => savePrefs(context, {'sizeUi': v}),
            ),
            StepTile(
              title: context.tr('Quote size'),
              icon: Icons.format_size_rounded,
              steps: _sizes,
              value: p.sizeDisplay,
              onChanged: (v) => savePrefs(context, {'sizeDisplay': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('Setting a quote'),
          children: [
            ChoiceTile<int>(
              title: context.tr('Line height'),
              icon: Icons.format_line_spacing_rounded,
              value: p.quoteLeading,
              choices: [
                Choice(0, context.tr('The app\'s own')),
                const Choice(130, '130%'),
                const Choice(145, '145%'),
                const Choice(155, '155%'),
                const Choice(170, '170%'),
                const Choice(190, '190%'),
              ],
              onChanged: (v) => savePrefs(context, {'quoteLeading': v}),
            ),
            ChoiceTile<int>(
              title: context.tr('Line length'),
              icon: Icons.width_normal_rounded,
              value: p.quoteMeasure,
              choices: [
                Choice(0, context.tr('The full width')),
                Choice(45, context.tr('{n} characters', {'n': 45})),
                Choice(55, context.tr('{n} characters', {'n': 55})),
                Choice(66, context.tr('{n} characters', {'n': 66})),
                Choice(80, context.tr('{n} characters', {'n': 80})),
              ],
              onChanged: (v) => savePrefs(context, {'quoteMeasure': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('Names in a credit'),
          footer: context.tr(
            'A credit such as "Pratchett & Gaiman" becomes two people where it is split on a separator you turn on.',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (token, label) in [
                    ('comma', context.tr('Commas')),
                    ('semicolon', context.tr('Semicolons')),
                    ('amp', '&'),
                    ('and', context.tr('the word "and"')),
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
          title: context.tr('Typeface by language'),
          footer: context.tr(
            'Quotes in a language you list here are set in the face you pick; the rest use the app\'s own.',
          ),
          children: [
            for (final e in faces.entries)
              ListTile(
                title: Text(_title(e.key)),
                subtitle: Text(_faceName(context, e.value)),
                trailing: IconButton(
                  tooltip: context.tr('Remove'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    final next = {...faces}..remove(e.key);
                    savePrefs(context, {'fontsByLanguage': _blob(next)});
                  },
                ),
                onTap: () => _addFace(context, faces, e.key),
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(context.tr('Add a language')),
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
        'newsreader' => 'Newsreader',
        'noto-serif-bengali' => 'Noto Serif Bengali',
        'noto-serif-devanagari' => 'Noto Serif Devanagari',
        'source-serif-4' => 'Source Serif 4',
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

  static const palette = [
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
      title: context.tr('Colours'),
      children: [
        PrefGroup(
          footer: context.tr(
            'The first colour is the one a quote gets when you choose none, so it keeps its place. A colour you hide is no longer offered when you add a quote; quotes that have it keep it.',
          ),
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
          label: context.tr('Choose a shade'),
          child: CircleAvatar(backgroundColor: quoteColour(token), radius: 16),
        ),
      ),
      title: Text(quoteColourName(token)),
      subtitle: Text(
        i == 0
            ? context.tr('The default colour')
            : (p.colourHidden(token)
                  ? context.tr('Hidden from the pickers')
                  : context.tr('Shown in the pickers')),
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
                ctx.tr('A shade for {name}', {'name': quoteColourName(token)}),
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
                              ? const Icon(Icons.check_rounded, size: 20)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: Text(ctx.tr('Back to the built-in shade')),
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
      title: context.tr('Name this colour'),
      initial: p.colourName(token),
      hint: token,
      helper: context.tr('Leave it empty for the built-in name.'),
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
          onlyOne ? context.tr('At least one of these three stays on.') : hint,
        ),
        value: !hidden,
        onChanged: onlyOne ? null : (on) => savePrefs(context, {key: !on}),
      );
    }

    return PrefPage(
      title: context.tr('Sections'),
      children: [
        PrefGroup(
          title: context.tr('Show'),
          children: [
            section(
              'hideLibrary',
              context.tr('Library'),
              context.tr('Books, and the highlights you keep in them.'),
              p.hideLibrary,
            ),
            section(
              'hideCatalogue',
              context.tr('Catalogue'),
              context.tr('Films, shows and games, and the lines from them.'),
              p.hideCatalogue,
            ),
            section(
              'hideQuotes',
              context.tr('Quotes'),
              context.tr(
                'Speeches, letters, proverbs — anything with no work behind it.',
              ),
              p.hideQuotes,
            ),
            SwitchListTile(
              key: const ValueKey('section-showAnthologies'),
              title: Text(context.tr('Anthologies')),
              subtitle: Text(
                context.tr(
                  'Quotes gathered into a reading order, with your own words between them.',
                ),
              ),
              value: p.showAnthologies || !p.known,
              onChanged: (on) => savePrefs(context, {'showAnthologies': on}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('Bin'),
          children: [
            ChoiceTile<int>(
              title: context.tr('Keep deleted things for'),
              icon: Icons.delete_outline,
              value: p.trashDays,
              choices: [
                Choice(7, context.tr('{n} days', {'n': 7})),
                Choice(30, context.tr('{n} days', {'n': 30})),
                Choice(90, context.tr('{n} days', {'n': 90})),
                Choice(-1, context.tr('For ever')),
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
      title: context.tr('Daily review'),
      children: [
        PrefGroup(
          title: context.tr('Each day'),
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
                          context.tr('Cards a day'),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        '${p.srDaily}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  Slider(
                    value: p.srDaily.clamp(5, 20).toDouble(),
                    min: 5,
                    max: 20,
                    divisions: 15,
                    label: '${p.srDaily}',
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
                    context.tr('Drawn from'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (m, label) in [
                        ('books', context.tr('Library')),
                        ('movies', context.tr('Catalogue')),
                        ('quotes', context.tr('Quotes')),
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
          title: context.tr('Questions'),
          children: [
            ChoiceTile<String>(
              title: context.tr('How hard the questions are'),
              value: p.srTier,
              choices: [
                Choice(
                  'easy',
                  context.tr('Easy'),
                  context.tr(
                    'Two clearly different choices instead of four. You miss the close wrong answers, which teach the most.',
                  ),
                ),
                Choice(
                  'medium',
                  context.tr('Medium'),
                  context.tr(
                    'Four choices, some of them close, and typing only for lines short enough to type.',
                  ),
                ),
                Choice(
                  'hard',
                  context.tr('Hard'),
                  context.tr(
                    'Mostly typing the words back; otherwise four choices that all seem right.',
                  ),
                ),
                Choice(
                  'random',
                  context.tr('Random'),
                  context.tr(
                    'A different level on each card, so you don\'t get used to one kind of question.',
                  ),
                ),
              ],
              onChanged: (v) => savePrefs(context, {'srTier': v}),
            ),
            ChoiceTile<String>(
              title: context.tr('New lines start at'),
              value: p.srStart,
              choices: [
                Choice(
                  'unseen',
                  context.tr('Not seen'),
                  context.tr('Asked soon and often.'),
                ),
                Choice(
                  'mastered',
                  context.tr('Mastered'),
                  context.tr(
                    'Asked rarely, for a library you already know. A wrong answer brings it back either way.',
                  ),
                ),
              ],
              onChanged: (v) => savePrefs(context, {'srStart': v}),
            ),
            SwitchListTile(
              title: Text(context.tr('Confirm each answer')),
              subtitle: Text(
                context.tr(
                  'Off: a tap answers. On: a tap selects, and Submit records it, so you can change your mind.',
                ),
              ),
              value: p.srSubmit,
              onChanged: (v) => savePrefs(context, {'srSubmit': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('Schedule'),
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
                          context.tr('Seeing lengthens half-life by'),
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
                      'Sharing, favouriting, or seeing a quote among a card\'s choices lengthens its interval a little. 1.0× turns this off.',
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
              title: Text(context.tr('Practice counts')),
              subtitle: Text(
                context.tr(
                  'Off: Practice is study only. On: correct Practice answers lengthen intervals like the daily review.',
                ),
              ),
              value: p.srPracticeCounts,
              onChanged: (v) => savePrefs(context, {'srPracticeCounts': v}),
            ),
          ],
        ),
        PrefGroup(
          children: [
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: Text(context.tr('Back to the defaults')),
              subtitle: Text(
                context.tr(
                  'Puts the settings on these pages back, here and on the server. Your library is not touched.',
                ),
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
        title: Text(ctx.tr('Put these settings back?')),
        content: Text(
          ctx.tr(
            'Language, text size, colours, sections and the review settings all return to their defaults, on this phone and on the server. How the web looks is not changed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Put them back')),
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
      title: context.tr('Context around a quote'),
      children: [
        if (_problem != null) PrefNote(_problem!),
        if (rule != null)
          PrefGroup(
            footer: context.tr(
              'How many lines of the book or film are shown before and after a quote. A work can have its own, and a single quote can be adjusted on its own page.',
            ),
            children: [
              _half(context, context.tr('Before'), rule.before, (v) {
                _set(ContextRule(before: v, after: rule.after));
              }),
              _half(context, context.tr('After'), rule.after, (v) {
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
              ? context.tr('The built-in amount')
              : context.tr('{n} lines', {'n': value}),
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
          label: '$value',
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
                    ? ctx.tr('Follows your setting for everything')
                    : ctx.tr('{n} lines', {'n': v}),
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
                    ctx.tr('Context for {title}', {'title': work.title}),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                half(ctx.tr('Before'), before, (v) => before = v),
                half(ctx.tr('After'), after, (v) => after = v),
                RadioGroup<String>(
                  groupValue: enforce,
                  onChanged: (v) => set(() => enforce = v ?? ''),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: '',
                        title: Text(ctx.tr('Leave quotes already adjusted')),
                      ),
                      RadioListTile<String>(
                        value: 'clamp',
                        title: Text(ctx.tr('Bring wider ones down to this')),
                      ),
                      RadioListTile<String>(
                        value: 'clear',
                        title: Text(ctx.tr('Clear every adjustment')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(ctx.tr('Save')),
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
                  ? context.tr('Saved; {n} quotes changed.', {'n': r.value})
                  : context.tr('Saved.'))
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
    title: Text(context.tr('Typeface for a language')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          enabled: widget.language == null,
          autofocus: widget.language == null,
          decoration: InputDecoration(
            labelText: context.tr('Language'),
            hintText: 'Bengali',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _face,
          decoration: InputDecoration(labelText: context.tr('Typeface')),
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
        child: Text(context.tr('Cancel')),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (_name.text.trim().toLowerCase(), _face)),
        child: Text(context.tr('Save')),
      ),
    ],
  );
}
