import 'package:flutter/material.dart';

import '../library/models.dart';
import '../library/quote_chips.dart';
import '../people/people_directory.dart';
import '../people/people_service.dart';
import 'person_screen.dart';
import '../l10n/l10n.dart';

/// The people on a quote as a row of chips that scrolls sideways rather than wrapping (as on the web, so a long name
/// never pushes the words down): the author of the book, and each character or speaker with the actor under their
/// name. Each is a button; pressing one hands back a [ChipFilter] for the name. Draws nothing for a quote with no one.
class QuoteChipsRow extends StatelessWidget {
  const QuoteChipsRow({
    super.key,
    required this.quote,
    required this.work,
    required this.onTap,
    this.dense = false,
    this.omitAuthor = false,
  });

  final Quote quote;
  final Work? work;
  final ValueChanged<ChipFilter> onTap;

  /// Leave out the author's pill: on the page of the work itself the author is already in the header, and naming
  /// one person twice on a card is noise.
  final bool omitAuthor;

  /// Smaller, for a list.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final chips = chipsFor(quote, work, omitAuthor: omitAuthor);
    if (chips.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PersonChip(
                chip: c,
                dense: dense,
                // where the server's people are known, a press opens the person's page (which can still filter the
                // library); without them it filters at once
                onTap: () => PeopleServiceScope.of(context) == null
                    ? onTap(ChipFilter(c.name))
                    : openPersonPage(context, chip: c, onFilter: onTap),
              ),
            ),
        ],
      ),
    );
  }
}

/// The people credited on a work (its author, director ...) as pills with their portraits, in a row that scrolls
/// sideways. Pressing one opens the person's page where the server's people are known, or filters at once.
class CreatorPills extends StatelessWidget {
  const CreatorPills({super.key, required this.names, required this.onTap});

  final List<String> names;
  final ValueChanged<ChipFilter> onTap;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final n in names)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PersonChip(
                chip: QuoteChip(ChipKind.author, n),
                onTap: () => PeopleServiceScope.of(context) == null
                    ? onTap(ChipFilter(n))
                    : openPersonPage(
                        context,
                        chip: QuoteChip(ChipKind.author, n),
                        onFilter: onTap,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One chip: a circle with the name's first letter (in the place a portrait takes on the web), the name, and for a
/// character the actor under it. A button.
class PersonChip extends StatelessWidget {
  const PersonChip({
    super.key,
    required this.chip,
    required this.onTap,
    this.dense = false,
  });

  final QuoteChip chip;
  final VoidCallback onTap;
  final bool dense;

  String get _initial {
    final t = chip.name.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  String get _what => switch (chip.kind) {
    ChipKind.author => 'Author',
    ChipKind.character => 'Character',
    ChipKind.speaker => tx('app.search.said_by'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = dense ? 11.0 : 14.0;
    return Semantics(
      button: true,
      label: chip.actor.isEmpty
          ? context.tr('app.quote_chips.what_name', {
              'what': _what,
              'name': chip.name,
            })
          : context.tr('app.quote_chips.what_name_actor', {
              'what': _what,
              'name': chip.name,
              'actor': chip.actor,
            }),
      child: Tooltip(
        message: chip.actor.isEmpty
            ? chip.name
            : '${chip.name} — ${chip.actor}',
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                4,
                dense ? 2 : 4,
                dense ? 10 : 14,
                dense ? 2 : 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PersonFace(
                    chip: chip,
                    radius: r,
                    fallback: CircleAvatar(
                      radius: r,
                      backgroundColor: switch (chip.kind) {
                        ChipKind.author => scheme.primaryContainer,
                        ChipKind.character => scheme.tertiaryContainer,
                        ChipKind.speaker => scheme.secondaryContainer,
                      },
                      child: Text(
                        _initial,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: switch (chip.kind) {
                            ChipKind.author => scheme.onPrimaryContainer,
                            ChipKind.character => scheme.onTertiaryContainer,
                            ChipKind.speaker => scheme.onSecondaryContainer,
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: dense ? 160 : 220),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                        if (chip.actor.isNotEmpty)
                          Text(
                            chip.actor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
