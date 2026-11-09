import 'package:flutter/material.dart';

import '../capture/photo_source.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';
import '../theme/theme_choice.dart';

/// Chooses where the app's colours come from: the phone's own (Material You, which follows the wallpaper), the colours of a
/// photo, or one of the app's palettes. The change shows at once, and stays on this phone.
class ThemeColoursScreen extends StatefulWidget {
  const ThemeColoursScreen({super.key, required this.choice, this.photos});

  final ThemeChoice choice;

  /// Where a photo comes from; null uses the phone's gallery.
  final PhotoSource? photos;

  @override
  State<ThemeColoursScreen> createState() => _ThemeColoursScreenState();
}

class _ThemeColoursScreenState extends State<ThemeColoursScreen> {
  late final PhotoSource _photos = widget.photos ?? DevicePhotos();
  bool _busy = false;
  String? _problem;

  Future<void> _fromPhoto() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final path = await _photos.choose();
      if (path != null) await widget.choice.usePhoto(path);
    } on Object {
      if (mounted) {
        setState(() => _problem = context.tr('app.theme.photo_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A strip of three colours that stand for a seed.
  Widget _swatch(Color seed) {
    final s = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Theme.of(context).brightness,
    );
    Widget dot(Color c) => Container(width: 18, height: 28, color: c);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [dot(s.primary), dot(s.secondaryContainer), dot(s.tertiary)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.theme.title'))),
      body: ListenableBuilder(
        listenable: widget.choice,
        builder: (context, _) {
          final c = widget.choice;
          Widget tile({
            required String id,
            required String title,
            required String note,
            required Widget lead,
            VoidCallback? onTap,
          }) => ListTile(
            key: ValueKey('theme-$id'),
            leading: lead,
            title: Text(title),
            subtitle: note.isEmpty ? null : Text(note),
            trailing: c.source == id
                ? Icon(Ti.circleCheckFilled, color: scheme.primary)
                : null,
            onTap: onTap ?? () => c.choose(id),
          );
          return ListView(
            children: [
              tile(
                id: 'system',
                title: context.tr('app.theme.system'),
                note: context.tr('app.theme.system_note'),
                lead: const SizedBox(width: 54, child: Icon(Ti.palette)),
              ),
              tile(
                id: 'photo',
                title: context.tr('app.theme.photo'),
                note: _busy
                    ? context.tr('app.theme.reading_photo')
                    : context.tr('app.theme.photo_note'),
                lead: c.photoSeed == null
                    ? const SizedBox(width: 54, child: Icon(Ti.photo))
                    : _swatch(c.photoSeed!),
                onTap: _busy ? null : _fromPhoto,
              ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(_problem!, style: TextStyle(color: scheme.error)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  context.tr('app.theme.palettes'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final e in ThemeChoice.palettes.entries)
                tile(
                  id: e.key,
                  title: context.tr('app.theme.palette_${e.key}'),
                  note: '',
                  lead: _swatch(e.value),
                ),
            ],
          );
        },
      ),
    );
  }
}
