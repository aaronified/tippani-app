import 'package:flutter/material.dart';

import '../library/quote_chips.dart';
import 'people_directory.dart';

/// Round faces laid over one another, the first on top (as the web's face cluster), each ringed in the card's colour
/// so they read apart. Shows only the people the server has a picture for; draws nothing when there is none.
/// [more] is how many further faces were left out, shown as a count.
class FaceStack extends StatelessWidget {
  const FaceStack({
    super.key,
    required this.names,
    this.kind = ChipKind.author,
    this.radius = 12,
    this.max = 3,
    this.ringColor,
  });

  final List<String> names;
  final ChipKind kind;
  final double radius;
  final int max;

  /// The colour of the ring between faces; the surface the stack sits on by default.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final dir = PeopleDirectoryScope.of(context);
    if (dir == null || names.isEmpty) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: dir,
      builder: (context, _) {
        final faced = [
          for (final n in names)
            if (dir.faceOf(QuoteChip(kind, n)).isNotEmpty) n,
        ];
        if (faced.isEmpty) return const SizedBox.shrink();
        final shown = faced.take(max).toList();
        final ring = ringColor ?? Theme.of(context).colorScheme.surface;
        final step = radius * 1.3;
        final width = step * (shown.length - 1) + radius * 2 + 4;
        return Semantics(
          label: faced.join(', '),
          excludeSemantics: true,
          child: SizedBox(
            width: width + (faced.length > max ? radius * 2 : 0),
            height: radius * 2 + 4,
            child: Stack(
              children: [
                // the first credited is on top, so draw from the last
                for (var i = shown.length - 1; i >= 0; i--)
                  Positioned(
                    left: step * i,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: ring,
                        shape: BoxShape.circle,
                      ),
                      child: PersonFace(
                        chip: QuoteChip(kind, shown[i]),
                        radius: radius,
                        fallback: SizedBox(
                          width: radius * 2,
                          height: radius * 2,
                        ),
                      ),
                    ),
                  ),
                if (faced.length > max)
                  Positioned(
                    left: width - 2,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Text(
                        '+${faced.length - max}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
