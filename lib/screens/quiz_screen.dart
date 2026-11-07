import 'package:flutter/material.dart';

import '../people/file_art.dart';
import '../people/people_directory.dart';
import '../quiz/quiz.dart';
import '../theme/app_theme.dart';
import 'library_widgets.dart' show EmptyState;
import 'quote_form_screen.dart' show quoteColour;
import '../l10n/l10n.dart';

/// Which deck a round is.
enum QuizMode { daily, practice }

/// A round of questions, one at a time: today's Daily Quiz (its answers move the schedule) or Practice (as many as
/// you like, skippable, leaving the schedule alone unless the server is set to count it).
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.service,
    required this.mode,
    this.anthology,
  });

  final QuizService service;
  final QuizMode mode;

  /// Practice only the passages of this anthology (its server id). Null: the whole library.
  final int? anthology;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<QuizCard> _cards = const [];
  int _index = 0;
  bool _loading = true;
  String? _error;

  /// Answered before this round began (today's, for the progress line).
  int _before = 0;
  int _got = 0, _missed = 0, _skipped = 0;

  // the card in hand
  int? _picked;
  bool _graded = false;
  bool _sending = false;
  AnswerOutcome? _outcome;
  bool _kept = false;
  bool _correct = false;
  bool _flipShown = false;
  String _typed = '';
  final _field = TextEditingController();
  bool _finished = false;

  bool get _daily => widget.mode == QuizMode.daily;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_daily) {
        final deck = await widget.service.daily();
        if (!mounted) return;
        setState(() {
          _cards = deck.items;
          _before = deck.answeredToday;
          _loading = false;
        });
      } else {
        final cards = await widget.service.practice(
          anthology: widget.anthology,
        );
        if (!mounted) return;
        setState(() {
          _cards = cards;
          _before = 0;
          _loading = false;
        });
      }
      _index = 0;
      _got = _missed = _skipped = 0;
      _finished = false;
      _reset();
    } on QuizException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _reset() {
    _picked = null;
    _graded = false;
    _sending = false;
    _outcome = null;
    _kept = false;
    _correct = false;
    _flipShown = false;
    _typed = '';
    _field.clear();
  }

  QuizCard get _card => _cards[_index];

  Future<void> _submit(QuizAnswer a, {required bool localCorrect}) async {
    setState(() => _sending = true);
    final out = await widget.service.answer(a);
    if (!mounted) return;
    final card = _card;
    // a typed blank is graded by the server; everything else is graded here
    final correct = card.isCloze && out != null ? out.correct : localCorrect;
    setState(() {
      _sending = false;
      _graded = true;
      _outcome = out;
      _kept = out == null;
      _correct = correct;
      if (a.result == 'skip') {
        _skipped++;
      } else if (card.isCloze && out == null) {
        // waiting to be marked: neither right nor wrong yet
      } else if (correct) {
        _got++;
      } else {
        _missed++;
      }
    });
    if (_daily && card.isChoice) {
      // reading the other options is a real meeting with those quotes
      for (var i = 0; i < card.meta.length; i++) {
        final m = card.meta[i];
        if (i != card.answer && m.itemKind.isNotEmpty && m.itemId != 0) {
          widget.service.seen(m.itemKind, m.itemId);
        }
      }
    }
  }

  void _next() {
    if (_index + 1 >= _cards.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _reset();
    });
  }

  Future<void> _skip() => _submit(
    QuizAnswer(
      kind: _card.kind,
      id: _card.id,
      result: 'skip',
      mode: 'practice',
    ),
    localCorrect: false,
  ).then((_) => _next());

  @override
  Widget build(BuildContext context) {
    final title = _daily ? context.tr('quiz.daily.label') : 'Practice';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!_daily && !_loading && !_finished && _cards.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _finished = true),
              child: Text(context.tr('quiz.practice.end.label')),
            ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: context.tr('app.quiz.could_not_load_the_cards'),
        hint: _error,
      );
    }
    if (_cards.isEmpty) {
      return EmptyState(
        icon: _daily ? Icons.task_alt_rounded : Icons.menu_book_outlined,
        title: _daily
            ? context.tr('app.quiz.nothing_due_today')
            : context.tr('app.quiz.no_quotes_here_to_practise'),
        hint: _daily
            ? context.tr('app.quiz.add_more_quotes_or_come_back')
            : context.tr('app.quiz.save_a_highlight_a_line_or'),
      );
    }
    if (_finished) return _summary(context);
    return _question(context);
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _got + _missed;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle_rounded, size: 64, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          _daily
              ? context.tr('app.quiz.that_is_today_done')
              : context.tr('app.quiz.round_finished'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          total == 0
              ? context.tr('app.quiz.nothing_was_marked')
              : '$_got recalled · $_missed missed'
                    '${_skipped > 0 ? ' · $_skipped skipped' : ''}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (_daily && _missed > 0) ...[
          const SizedBox(height: 8),
          Text(
            context.tr('app.quiz.the_ones_you_missed_come_back'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 32),
        if (!_daily)
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('quiz.round.again.label')),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.done.label')),
        ),
      ],
    );
  }

  String _stem(QuizCard c) => switch (c.direction) {
    'source' => tx('app.quiz.which_noun_is_this_quote_from', {'noun': c.noun}),
    'quote' => tx('app.quiz.which_quote_is_from_this_noun', {'noun': c.noun}),
    'cloze' => context.tr('quiz.question.cloze.label'),
    'cloze-mcq' => context.tr('quiz.question.cloze-mcq.stem'),
    'speaker' => context.tr('quiz.question.speaker.stem'),
    'author' => context.tr('quiz.question.author.label'),
    _ => context.tr('quiz.question.flip.stem'),
  };

  Widget _question(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = _card;
    final done = _before + _index + (_graded ? 1 : 0);
    final total = _before + _cards.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: total == 0 ? 0 : done / total,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                context.tr('app.quiz.x_of_total', {
                  'x': _before + _index + 1,
                  'total': total,
                }),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              Text(
                _stem(c).toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              _prompt(context, c),
              const SizedBox(height: 16),
              if (c.isCloze) _clozeInput(context, c),
              if (c.isChoice) _options(context, c),
              if (c.isFlip) _flip(context, c),
              if (_graded) ...[
                const SizedBox(height: 12),
                _verdict(context, c),
                _reveal(context, c),
              ],
            ],
          ),
        ),
        _bar(context, c),
      ],
    );
  }

  /// What is shown as the question: the quote (with its blank), or for "which quote" the work it is from.
  Widget _prompt(BuildContext context, QuizCard c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (c.direction == 'quote') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              FileArt(
                name: c.art,
                width: 56,
                height: 80,
                fallback: _monogram(context, c.title, 56, 80),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, style: theme.textTheme.titleLarge),
                    if (c.creditLine.isNotEmpty)
                      Text(
                        c.creditLine,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final style = quoteStyle(context, size: 20, height: 1.55);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 4,
              decoration: BoxDecoration(
                color: quoteColour(c.color),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            _clozeText(context, c.shown, style),
            if (c.easyChips.isNotEmpty || c.easyPeople.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final f in c.easyChips)
                    _facePill(context, f.name, f.image),
                  for (final p in c.easyPeople) _facePill(context, p, ''),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clozeText(BuildContext context, String text, TextStyle style) {
    if (!text.contains(clozeBlank)) {
      return Text(text, style: style);
    }
    final scheme = Theme.of(context).colorScheme;
    final parts = text.split(clozeBlank);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            TextSpan(text: parts[i]),
            if (i < parts.length - 1)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Container(
                  width: 72,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: scheme.primary,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _monogram(BuildContext context, String title, double w, double h) {
    final scheme = Theme.of(context).colorScheme;
    final t = title.trim();
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        t.isEmpty ? '?' : t.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: quoteFont,
          fontSize: w * 0.5,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _facePill(BuildContext context, String name, String file) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = Text(
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: scheme.onTertiaryContainer,
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 12, 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FileArt(
            name: file,
            width: 24,
            height: 24,
            circle: true,
            fallback: CircleAvatar(
              radius: 12,
              backgroundColor: scheme.tertiaryContainer,
              child: initial,
            ),
          ),
          const SizedBox(width: 8),
          Text(name, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }

  Widget _options(BuildContext context, QuizCard c) {
    return Column(
      children: [
        for (var i = 0; i < c.options.length; i++) _optionTile(context, c, i),
      ],
    );
  }

  /// The face of a person named in an option, from the phone's copy of the people the server knows.
  String _portraitOf(BuildContext context, QuizOption m, String name) {
    final dir = PeopleDirectoryScope.of(context);
    if (dir == null) return '';
    final kinds = [
      if (m.kind == 'director' || m.kind.isEmpty) 'author' else m.kind,
      'actor',
      'author',
      'speaker',
    ];
    for (final k in kinds) {
      final p = dir.person(k, name.isEmpty ? m.person : name);
      if (p != null && p.image.isNotEmpty) return p.image;
    }
    return '';
  }

  Widget _optionTile(BuildContext context, QuizCard c, int i) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = i < c.meta.length ? c.meta[i] : const QuizOption();
    final text = c.options[i];
    final personOption = c.direction == 'speaker' || c.direction == 'author';
    final isAnswer = _graded && i == c.answer;
    final isWrongPick = _graded && _picked == i && i != c.answer;
    final picked = _picked == i;
    final bg = isAnswer
        ? scheme.primaryContainer
        : isWrongPick
        ? scheme.errorContainer
        : picked
        ? scheme.secondaryContainer
        : scheme.surfaceContainerLow;
    final fg = isAnswer
        ? scheme.onPrimaryContainer
        : isWrongPick
        ? scheme.onErrorContainer
        : scheme.onSurface;
    Widget? leading;
    if (personOption) {
      final file = _portraitOf(context, m, text);
      leading = FileArt(
        name: file,
        width: 40,
        height: 40,
        circle: true,
        fallback: CircleAvatar(
          radius: 20,
          backgroundColor: scheme.tertiaryContainer,
          child: Text(
            text.trim().isEmpty
                ? '?'
                : text.trim().characters.first.toUpperCase(),
            style: TextStyle(color: scheme.onTertiaryContainer),
          ),
        ),
      );
    } else if (c.direction == 'source' && m.art.isNotEmpty) {
      leading = FileArt(
        name: m.art,
        width: 36,
        height: 52,
        fallback: _monogram(context, text, 36, 52),
      );
    }
    final quoteOption = c.direction == 'quote' || c.direction == 'cloze-mcq';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: picked && !_graded ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onTap: _graded || _sending ? null : () => setState(() => _picked = i),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: quoteOption
                            ? quoteStyle(context, size: 16, color: fg)
                            : theme.textTheme.titleMedium?.copyWith(color: fg),
                      ),
                      if (_graded) ..._optionReveal(context, c, i, m, fg),
                    ],
                  ),
                ),
                if (isAnswer)
                  Icon(Icons.check_circle_rounded, color: scheme.primary)
                else if (isWrongPick)
                  Icon(Icons.cancel_rounded, color: scheme.error),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Under an option once the card is graded: where it came from, who made it, who says it.
  List<Widget> _optionReveal(
    BuildContext context,
    QuizCard c,
    int i,
    QuizOption m,
    Color fg,
  ) {
    final theme = Theme.of(context);
    final lines = <String>[
      if (m.source.isNotEmpty && m.source != c.options[i]) 'from ${m.source}',
      [
        if (m.creator.isNotEmpty) m.creator,
        if (m.year != 0) '${m.year}',
        if (m.date.isNotEmpty) m.date,
      ].join(' · '),
      if (m.speaker.isNotEmpty) m.speaker,
    ].where((s) => s.isNotEmpty).toList();
    if (lines.isEmpty && m.who.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      for (final l in lines)
        Text(
          l,
          style: theme.textTheme.bodySmall?.copyWith(
            color: fg.withValues(alpha: 0.75),
          ),
        ),
      if (m.who.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final f in m.who) _facePill(context, f.name, f.image),
          ],
        ),
      ],
    ];
  }

  Widget _clozeInput(BuildContext context, QuizCard c) {
    return TextField(
      controller: _field,
      enabled: !_graded && !_sending,
      textInputAction: TextInputAction.done,
      onChanged: (v) => setState(() => _typed = v),
      onSubmitted: (_) => _checkTyped(c),
      decoration: InputDecoration(
        labelText: context.tr('quiz.cloze.field.label'),
        hintText: context.tr('quiz.cloze.placeholder'),
      ),
    );
  }

  void _checkTyped(QuizCard c) {
    if (_graded || _sending || _typed.trim().isEmpty) return;
    _submit(
      QuizAnswer(
        kind: c.kind,
        id: c.id,
        result: 'forgot',
        mode: widget.mode.name,
        attempt: _typed.trim(),
      ),
      localCorrect: false,
    );
  }

  Widget _flip(BuildContext context, QuizCard c) {
    if (!_flipShown) {
      return FilledButton.tonal(
        onPressed: () => setState(() => _flipShown = true),
        child: Text(context.tr('quiz.flip.reveal.label')),
      );
    }
    return _source(context, c);
  }

  /// Where the card's quote is from, in full.
  Widget _source(BuildContext context, QuizCard c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = <String>[
      if (c.creditLine.isNotEmpty) c.creditLine,
      if (c.character.isNotEmpty)
        c.actor.isEmpty ? c.character : '${c.character} (${c.actor})'
      else if (c.speaker.isNotEmpty)
        c.speaker,
      if (c.chapter.isNotEmpty) c.chapter,
      if (c.location.isNotEmpty) c.location,
      if (c.timestamp.isNotEmpty) c.timestamp,
      if (c.occasionDate.isNotEmpty) c.occasionDate,
    ];
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FileArt(
              name: c.art,
              width: 44,
              height: 62,
              fallback: _monogram(context, c.title, 44, 62),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: theme.textTheme.titleMedium),
                  for (final l in lines)
                    Text(
                      l,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (c.who.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final f in c.who)
                          _facePill(context, f.name, f.image),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verdict(BuildContext context, QuizCard c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = _outcome;
    final String word;
    final Color color;
    if (c.isFlip) {
      word = _correct ? 'recalled' : 'noted';
      color = _correct ? scheme.primary : scheme.onSurfaceVariant;
    } else if (_kept && c.isCloze) {
      word = 'kept, to be marked';
      color = scheme.onSurfaceVariant;
    } else {
      word = _correct ? 'correct' : 'not quite';
      color = _correct ? scheme.primary : scheme.error;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          word,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (c.isCloze && o != null && o.answer.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            context.tr('quiz.cloze.answer.label'),
            style: theme.textTheme.labelMedium,
          ),
          Text(
            o.answer,
            style: quoteStyle(context, size: 18, weight: FontWeight.w600),
          ),
          if (!_correct && _typed.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('app.quiz.what_you_wrote_typed', {'typed': _typed}),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (o.synonym)
            Text(
              context.tr('quiz.cloze.synonym.note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
        if (_kept && !c.isCloze)
          Text(
            context.tr('app.quiz.answer_kept_on_this_phone_it'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        if (o != null && o.leech)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.tr('app.quiz.forgotten_lapses_times', {
                'lapses': o.lapses,
              }),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }

  /// The details of the answer: where the quote is from, shown once graded on the kinds that did not show it.
  Widget _reveal(BuildContext context, QuizCard c) {
    if (c.isFlip || c.direction == 'quote') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _source(context, c),
    );
  }

  Widget _bar(BuildContext context, QuizCard c) {
    final last = _index + 1 >= _cards.length;
    Widget primary;
    if (_graded) {
      primary = FilledButton(
        onPressed: _next,
        child: Text(last ? 'Finish' : 'Next'),
      );
    } else if (c.isFlip) {
      primary = _flipShown
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending
                        ? null
                        : () => _submit(
                            QuizAnswer(
                              kind: c.kind,
                              id: c.id,
                              result: 'forgot',
                              mode: widget.mode.name,
                            ),
                            localCorrect: false,
                          ),
                    child: Text(
                      context.tr('common.recall.result.forgot.label'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _sending
                        ? null
                        : () => _submit(
                            QuizAnswer(
                              kind: c.kind,
                              id: c.id,
                              result: 'got',
                              mode: widget.mode.name,
                            ),
                            localCorrect: true,
                          ),
                    child: Text(context.tr('common.action.got-it.label')),
                  ),
                ),
              ],
            )
          : const SizedBox.shrink();
    } else if (c.isCloze) {
      primary = FilledButton(
        onPressed: _sending || _typed.trim().isEmpty
            ? null
            : () => _checkTyped(c),
        child: Text(_sending ? 'checking…' : 'Check'),
      );
    } else {
      primary = FilledButton(
        onPressed: _picked == null || _sending
            ? null
            : () {
                final right = _picked == c.answer;
                _submit(
                  QuizAnswer(
                    kind: c.kind,
                    id: c.id,
                    result: right ? 'got' : 'forgot',
                    mode: widget.mode.name,
                  ),
                  localCorrect: right,
                );
              },
        child: Text(_picked == null ? 'Choose an answer' : 'Submit'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          if (!_daily && !_graded)
            TextButton(
              onPressed: _sending ? null : _skip,
              child: Text(context.tr('app.quiz.skip')),
            ),
          if (!_daily && !_graded) const SizedBox(width: 8),
          Expanded(child: primary),
        ],
      ),
    );
  }
}
