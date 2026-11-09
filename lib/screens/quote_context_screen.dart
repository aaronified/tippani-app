import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../l10n/l10n.dart';
import '../library/models.dart';
import '../library/quote_chips.dart';
import '../people/people_directory.dart';
import '../people/people_service.dart';
import '../theme/app_theme.dart';
import '../theme/tabler.dart';
import '../tools/context_names.dart';
import '../tools/quote_context.dart';
import '../tools/work_details_source.dart';
import '../widgets/edge_fade_row.dart';
import 'person_screen.dart';
import 'quote_form_screen.dart' show quoteColour;

/// How many more paragraphs (or subtitle lines) each edge of the scroller asks for.
const contextWindow = 6;

/// A character of the work, as the context viewer knows it: the name, the other ways it is called, and what the server
/// says about it, once that has arrived.
class _Who {
  _Who(this.name, {this.actor = '', this.image = ''});

  final String name;
  final String actor;
  String image;
  int id = 0;
  String description = '';
  int quotes = 0;
  List<String> aliases = const [];

  List<String> get names => [name, ...aliases];

  QuoteChip get chip => QuoteChip(ChipKind.character, name, actor, image);
}

/// The text around a quote as one scroller: everything the server stored, above and below, with the quote highlighted
/// where the file has it, and the characters named in it each in a colour of their own. Pressing a character opens a sheet
/// about them. Reaching the top or the bottom asks for more until what is stored runs out; both edges fade out.
class QuoteContextScreen extends StatefulWidget {
  const QuoteContextScreen({
    super.key,
    required this.quote,
    required this.work,
  });

  final Quote quote;
  final Work? work;

  @override
  State<QuoteContextScreen> createState() => _QuoteContextScreenState();
}

class _QuoteContextScreenState extends State<QuoteContextScreen> {
  final _center = GlobalKey();
  QuoteContext? _context;
  bool _busy = false;
  bool _asked = false;
  String? _problem;
  var _before = <String>[]; // nearest to the quote first
  var _after = <String>[];
  final _who = <_Who>[];
  final _spans = <String, List<NameSpan>>{};
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _gatherCharacters();
    _load();
  }

  Future<void> _gatherCharacters() async {
    final seen = <String>{};
    void add(String name, String actor, String image) {
      final t = name.trim();
      if (t.isEmpty || !seen.add(foldName(t))) return;
      _who.add(_Who(t, actor: actor, image: image));
    }

    var cast = widget.work?.details.cast ?? const <CastMember>[];
    if (cast.isEmpty && widget.work != null) {
      try {
        cast =
            (await DetailsScope.of(context)?.fetch(widget.work!))?.cast ?? cast;
      } on Object {
        // names from the quote's own speaker still work
      }
    }
    if (!mounted) return;
    for (final c in cast) {
      add(
        c.character,
        c.actor,
        c.characterImage.isNotEmpty ? c.characterImage : c.actorImage,
      );
    }
    for (final s in speakerNames(widget.quote.speaker)) {
      add(s, '', '');
    }
    final dir = PeopleDirectoryScope.of(context);
    final service = PeopleServiceScope.of(context);
    setState(() {
      for (final w in _who) {
        w.id = dir?.character(w.name)?.id ?? 0;
        if (w.image.isEmpty) w.image = dir?.characterImage(w.name) ?? '';
      }
      _spans.clear();
    });
    if (service == null) return;
    for (final w in _who) {
      if (w.id == 0) continue;
      try {
        final d = await service.character(w.id);
        if (!mounted) return;
        if (d == null) continue;
        setState(() {
          w.aliases = d.aliases;
          w.description = d.description;
          w.quotes = d.quotes;
          if (w.image.isEmpty) w.image = d.image;
          _spans.clear();
        });
      } on Object {
        // the name alone is still found
      }
    }
  }

  Future<void> _load({int? before, int? after}) async {
    final source = ContextScope.of(context);
    if (source == null || _busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final c = await source.fetch(
        widget.quote,
        widget.work,
        before: before,
        after: after,
      );
      if (!mounted) return;
      setState(() {
        _context = c;
        _asked = true;
        _before = splitUnits(c?.before ?? '').reversed.toList();
        _after = splitUnits(c?.after ?? '');
        _spans.clear();
      });
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for more at an edge the reader has scrolled near.
  bool _edge(ScrollMetrics m) {
    final c = _context;
    if (c == null || _busy) return false;
    if (m.extentBefore < 260 && c.canShowMoreBefore) {
      _load(before: c.shownBefore + contextWindow, after: c.shownAfter);
    } else if (m.extentAfter < 260 && c.canShowMoreAfter) {
      _load(before: c.shownBefore, after: c.shownAfter + contextWindow);
    }
    return false;
  }

  List<NameSpan> _find(String text) => _spans.putIfAbsent(
    text,
    () => findNames(text, [for (final w in _who) w.names]),
  );

  List<(Color, Color)> _colours(Brightness b) => [
    for (var i = 0; i < _who.length; i++) _characterColours(i, b),
  ];

  /// How many times each character is named in the text on screen.
  List<int> get _counts {
    final n = List.filled(_who.length, 0);
    final all = [..._before, _context?.body ?? '', ..._after];
    for (final t in all) {
      for (final s in _find(t)) {
        n[s.who]++;
      }
    }
    return n;
  }

  Future<void> _openCharacter(int i) async {
    final w = _who[i];
    final colours = _characterColours(i, Theme.of(context).brightness);
    final count = _counts[i];
    final act = await showModalBottomSheet<_SheetAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CharacterSheet(
        who: w,
        work: widget.work,
        colour: colours.$1,
        named: count,
      ),
    );
    if (act == null || !mounted) return;
    switch (act) {
      case _SheetAction.quotes:
        Navigator.of(context).pop(ChipFilter(w.name));
      case _SheetAction.page:
        ChipFilter? chosen;
        await openPersonPage(
          context,
          chip: w.chip,
          onFilter: (f) => chosen = f,
        );
        if (chosen != null && mounted) Navigator.of(context).pop(chosen);
    }
  }

  String get _locator => [
    if (widget.quote.chapter.isNotEmpty) widget.quote.chapter,
    if (widget.quote.location.isNotEmpty) widget.quote.location,
  ].join(' · ');

  void _showLocator() {
    final q = widget.quote;
    final w = widget.work;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('app.context.where_this_is'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (w != null) _row(context, w.title, w.creator),
              if (q.chapter.isNotEmpty)
                _row(
                  context,
                  context.tr('share.field.chapter.label'),
                  q.chapter,
                ),
              if (q.location.isNotEmpty)
                _row(
                  context,
                  context.tr(
                    w != null && w.kind != WorkKind.book
                        ? 'common.field.timestamp.label'
                        : 'common.field.location.label',
                  ),
                  q.location,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colours = _colours(theme.brightness);
    final c = _context;
    final counts = _counts;
    final present = [
      for (var i = 0; i < _who.length; i++)
        if (counts[i] > 0) i,
    ];
    final locator = _locator;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.work?.title ?? context.tr('app.quote_card.note'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            if (widget.work != null && widget.work!.creator.isNotEmpty)
              Text(
                widget.work!.creator,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          if (locator.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Ti.bookmark, size: 16, color: scheme.primary),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    locator,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: _showLocator,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (present.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      context.tr('app.context.in_this_passage'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Expanded(
                    child: EdgeFadeRow(
                      children: [
                        for (final i in present)
                          _Pill(
                            who: _who[i],
                            colour: colours[i].$1,
                            onTap: () => _openCharacter(i),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _scroller(context, c, colours)),
        ],
      ),
    );
  }

  Widget _scroller(
    BuildContext context,
    QuoteContext? c,
    List<(Color, Color)> colours,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (c == null) {
      if (_problem != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _problem!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _load,
                  child: Text(context.tr('common.source.retry')),
                ),
              ],
            ),
          ),
        );
      }
      if (_asked) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr('app.quote_context.the_server_has_no_context_for'),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final base = quoteStyle(
      context,
      size: 16.5,
      language: widget.quote.language,
    ).copyWith(height: 1.7, color: scheme.onSurfaceVariant);
    Widget unit(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: _NamedText(
        text: text,
        spans: _find(text),
        style: base,
        colours: colours,
        onName: _openCharacter,
        underline: false,
      ),
    );
    Widget edge({required bool top}) {
      final stop = top ? !c.canShowMoreBefore : !c.canShowMoreAfter;
      final bound = top ? c.boundBefore : c.boundAfter;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, top ? 56 : 12, 20, top ? 12 : 72),
        child: Center(
          child: _busy && !stop
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : stop && bound
              ? Text(
                  context.tr(
                    top
                        ? 'app.quote_context.the_start_of_the_chapter_or'
                        : 'app.quote_context.the_end_of_the_chapter_scene',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                )
              : const SizedBox(height: 4),
        ),
      );
    }

    final body = c.body.isEmpty ? widget.quote.text : c.body;
    final mark = quoteColour(widget.quote.color);
    final ref = [
      context.tr('app.context.your_quote'),
      if (widget.quote.location.isNotEmpty) widget.quote.location,
    ].join(' · ');

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _edge(n.metrics);
        });
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _edge(n.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) {
            final f = r.height <= 0 ? 0.0 : (56 / r.height).clamp(0.0, 0.3);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, f, 1 - f, 1],
            ).createShader(r);
          },
          child: CustomScrollView(
            center: _center,
            anchor: 0.3,
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) =>
                      i < _before.length ? unit(_before[i]) : edge(top: true),
                  childCount: _before.length + 1,
                ),
              ),
              SliverToBoxAdapter(
                key: _center,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: BoxDecoration(
                    color: mark.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(left: BorderSide(color: mark, width: 5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ref,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _NamedText(
                        text: body,
                        spans: _find(body),
                        style: base.copyWith(color: scheme.onSurface),
                        colours: colours,
                        onName: _openCharacter,
                        underline: true,
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) =>
                      i < _after.length ? unit(_after[i]) : edge(top: false),
                  childCount: _after.length + 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The colours of the character at [i]: the name's own, and the tint behind it. Each index has one hue, spread round the
/// wheel and away from the yellow of a highlighted quote, and the same hue in both themes.
(Color, Color) _characterColours(int i, Brightness b) {
  const hues = [
    212.0,
    340.0,
    168.0,
    268.0,
    24.0,
    130.0,
    190.0,
    300.0,
    8.0,
    90.0,
  ];
  final h = hues[i % hues.length];
  final dark = b == Brightness.dark;
  return (
    HSLColor.fromAHSL(1, h, dark ? 0.6 : 0.55, dark ? 0.72 : 0.36).toColor(),
    HSLColor.fromAHSL(1, h, dark ? 0.35 : 0.5, dark ? 0.22 : 0.9).toColor(),
  );
}

/// A paragraph with the characters' names picked out in their colours; pressing one calls [onName] with its index.
class _NamedText extends StatefulWidget {
  const _NamedText({
    required this.text,
    required this.spans,
    required this.style,
    required this.colours,
    required this.onName,
    required this.underline,
  });

  final String text;
  final List<NameSpan> spans;
  final TextStyle? style;
  final List<(Color, Color)> colours;
  final void Function(int who) onName;
  final bool underline;

  @override
  State<_NamedText> createState() => _NamedTextState();
}

class _NamedTextState extends State<_NamedText> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final t = widget.text;
    final out = <InlineSpan>[];
    var at = 0;
    for (final s in widget.spans) {
      if (s.start > at) out.add(TextSpan(text: t.substring(at, s.start)));
      final (fg, bg) = widget.colours[s.who];
      final tap = TapGestureRecognizer()..onTap = () => widget.onName(s.who);
      _taps.add(tap);
      out.add(
        TextSpan(
          text: t.substring(s.start, s.end),
          recognizer: tap,
          style: TextStyle(
            color: fg,
            backgroundColor: bg,
            fontWeight: FontWeight.w600,
            decoration: widget.underline ? TextDecoration.underline : null,
            decorationColor: fg,
            decorationThickness: 2,
          ),
        ),
      );
      at = s.end;
    }
    if (at < t.length) out.add(TextSpan(text: t.substring(at)));
    return Text.rich(TextSpan(style: widget.style, children: out));
  }
}

/// One character in the row above the text: the round portrait in its colour, and the name.
class _Pill extends StatelessWidget {
  const _Pill({required this.who, required this.colour, required this.onTap});

  final _Who who;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 3, 12, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Face(who: who, colour: colour, radius: 12),
              const SizedBox(width: 7),
              Text(who.name, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.who, required this.colour, required this.radius});

  final _Who who;
  final Color colour;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = who.name.isEmpty
        ? '?'
        : who.name.characters.first.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colour, width: 2),
      ),
      child: PersonFace(
        chip: who.chip,
        radius: radius,
        fallback: CircleAvatar(
          radius: radius,
          backgroundColor: colour,
          child: Text(
            initial,
            style: TextStyle(
              color: Theme.of(context).colorScheme.surface,
              fontSize: radius * 0.9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

enum _SheetAction { page, quotes }

/// What the app knows of a character: the portrait, the description, the other names, how often it is named in the text on
/// screen and how many of the reader's quotes are theirs.
class _CharacterSheet extends StatelessWidget {
  const _CharacterSheet({
    required this.who,
    required this.work,
    required this.colour,
    required this.named,
  });

  final _Who who;
  final Work? work;
  final Color colour;
  final int named;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Face(who: who, colour: colour, radius: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(who.name, style: theme.textTheme.titleLarge),
                      Text(
                        work == null
                            ? context.tr('app.context.character')
                            : context.tr('app.context.character_in', {
                                'work': work!.title,
                              }),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (who.actor.isNotEmpty)
                        Text(
                          context.tr('app.context.played_by', {
                            'actor': who.actor,
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              who.description.isEmpty
                  ? context.tr('app.context.no_description')
                  : who.description,
              style: quoteStyle(context, size: 15).copyWith(
                height: 1.55,
                color: who.description.isEmpty ? scheme.onSurfaceVariant : null,
              ),
            ),
            const SizedBox(height: 14),
            if (who.aliases.isNotEmpty)
              _line(
                context,
                context.tr('app.context.also_called'),
                who.aliases.join(', '),
              ),
            _line(
              context,
              context.tr('app.context.in_this_passage'),
              trn('app.context.named_here', named),
            ),
            if (who.quotes > 0)
              _line(
                context,
                context.tr('app.context.your_quotes'),
                countWords('quote', who.quotes),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_SheetAction.page),
                  child: Text(context.tr('app.context.open_page')),
                ),
                FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(context).pop(_SheetAction.quotes),
                  child: Text(context.tr('app.context.show_their_quotes')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
