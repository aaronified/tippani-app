import 'package:flutter/material.dart';

import '../library/models.dart';
import '../library/quote_chips.dart';
import '../people/people_directory.dart';
import '../people/people_service.dart';
import 'person_screen.dart';

/// What the server knows about a work, laid out under its title: description, genres, the small facts (publisher,
/// pages, ISBN, series) and the cast or characters. Draws nothing for a work with nothing to show.
class WorkDetailsSection extends StatefulWidget {
  const WorkDetailsSection({super.key, required this.work, this.onFilter});

  final Work work;

  /// Called when a person's page asks for the library filtered by a name; null makes a cast row do nothing.
  final ValueChanged<ChipFilter>? onFilter;

  @override
  State<WorkDetailsSection> createState() => _WorkDetailsSectionState();
}

/// How many cast members show before "Show all".
const castShown = 8;

class _WorkDetailsSectionState extends State<WorkDetailsSection> {
  bool _moreText = false;
  bool _allCast = false;

  /// One cast row: the character's picture (or the actor's), then "Actor as Character". A press opens the page of
  /// the character, or of the actor where the part has no character.
  Widget _castRow(BuildContext context, CastMember c) {
    final scheme = Theme.of(context).colorScheme;
    final label = c.actor.isEmpty
        ? c.character
        : c.character.isEmpty
        ? c.actor
        : '${c.actor} as ${c.character}';
    final chip = c.character.isEmpty
        ? QuoteChip(ChipKind.speaker, c.actor)
        : QuoteChip(ChipKind.character, c.character, c.actor);
    final initial = (c.character.isEmpty ? c.actor : c.character).trim();
    final opens =
        widget.onFilter != null && PeopleServiceScope.of(context) != null;
    return InkWell(
      onTap: opens
          ? () =>
                openPersonPage(context, chip: chip, onFilter: widget.onFilter!)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            PersonFace(
              chip: chip,
              radius: 16,
              fallback: CircleAvatar(
                radius: 16,
                backgroundColor: scheme.tertiaryContainer,
                child: Text(
                  initial.isEmpty
                      ? '?'
                      : initial.characters.first.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.work.details;
    if (d.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isBook =
        widget.work.kind == WorkKind.book || widget.work.kind == WorkKind.other;
    final facts = <(String, String)>[
      if (d.subtitle.isNotEmpty) ('Subtitle', d.subtitle),
      if (d.series.isNotEmpty) ('Series', d.series),
      if (d.publisher.isNotEmpty) ('Publisher', d.publisher),
      if (d.pages > 0) ('Pages', '${d.pages}'),
      if (d.isbn.isNotEmpty) ('ISBN', d.isbn),
    ];
    final cast = _allCast ? d.cast : d.cast.take(castShown).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.description.isNotEmpty) ...[
            Text(
              d.description,
              maxLines: _moreText ? null : 6,
              overflow: _moreText ? null : TextOverflow.ellipsis,
            ),
            if (d.description.length > 280)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _moreText = !_moreText),
                  child: Text(_moreText ? 'Show less' : 'Show more'),
                ),
              ),
          ],
          if (d.genres.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final g in d.genres) Chip(label: Text(g))],
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final f in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(f.$1, style: theme.textTheme.labelLarge),
                    ),
                    Expanded(child: Text(f.$2)),
                  ],
                ),
              ),
          ],
          if (d.cast.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              isBook ? 'Characters' : 'Cast',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final c in cast) _castRow(context, c),
            if (d.cast.length > castShown)
              TextButton(
                onPressed: () => setState(() => _allCast = !_allCast),
                child: Text(
                  _allCast ? 'Show fewer' : 'Show all ${d.cast.length}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
