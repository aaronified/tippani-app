import 'package:flutter/material.dart';

import '../account/preferences.dart';
import '../l10n/l10n.dart';
import '../theme/material_surface.dart';
import '../theme/materials.dart';
import '../theme/tabler.dart';
import 'prefs_widgets.dart';

/// What the app's surfaces are made of, the same as on the web: a material set, a different material for any one of the
/// four surfaces, and how each material catches the light. Saved to the account, so the web wears the same look.
class MaterialsScreen extends StatelessWidget {
  const MaterialsScreen({super.key});

  static String _slotKey(String slot) =>
      'tile${slot[0].toUpperCase()}${slot.substring(1)}';

  String _tileName(BuildContext context, String name) =>
      context.tr('vocab.tile.$name.label');

  @override
  Widget build(BuildContext context) {
    final p = PrefsScope.of(context);
    final look = MaterialLook.fromPrefs(p);
    final scheme = Theme.of(context).colorScheme;
    return PrefPage(
      title: context.tr('app.materials.title'),
      children: [
        _Specimens(look: look, scheme: scheme),
        PrefGroup(
          title: context.tr('settings.appearance.group.material.title'),
          footer: context.tr('settings.appearance.matset.info.body'),
          children: [
            ChoiceTile<String>(
              key: const ValueKey('material-set'),
              title: context.tr('settings.appearance.matset.title'),
              subtitle: context.tr('settings.appearance.matset.hint'),
              icon: Ti.palette,
              value: look.set,
              choices: [
                for (final name in materialSets.keys)
                  Choice(name, context.tr('settings.material.$name.label')),
              ],
              onChanged: (v) => savePrefs(context, {'materialSet': v}),
            ),
          ],
        ),
        PrefGroup(
          title: context.tr('app.materials.each_surface'),
          footer: context.tr('app.materials.each_surface_hint'),
          children: [
            for (final slot in slots)
              ChoiceTile<String>(
                key: ValueKey('slot-$slot'),
                title: context.tr('app.materials.slot.$slot'),
                icon: switch (slot) {
                  'ground' => Ti.layoutBoard,
                  'shell' => Ti.layoutRows,
                  'card' => Ti.layoutDashboard,
                  _ => Ti.book2,
                },
                value: look.overrides[slot] ?? '',
                choices: [
                  Choice(
                    '',
                    context.tr('app.materials.the_sets_own', {
                      'name':
                          textiles[materialSets[look.set]![slots.indexOf(
                                slot,
                              )]]!
                              .isFlat
                          ? context.tr('settings.material.atrium.label')
                          : _tileName(
                              context,
                              materialSets[look.set]![slots.indexOf(slot)],
                            ),
                    }),
                  ),
                  for (final name in pickableTextiles)
                    Choice(name, _tileName(context, name)),
                ],
                onChanged: (v) => savePrefs(context, {_slotKey(slot): v}),
              ),
          ],
        ),
        if (look.materialsInUse.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 24, 16),
            child: Text(context.tr('settings.appearance.phys.none')),
          )
        else
          PrefGroup(
            title: context.tr('settings.appearance.phys.open.tip'),
            footer: context.tr('app.materials.dials_hint'),
            children: [
              for (final name in look.materialsInUse)
                _Dials(
                  key: ValueKey('dials-$name'),
                  name: name,
                  label: _tileName(context, name),
                  phys: look.physFor(name),
                  dirty: physDirty(name, look.tweaks),
                  rawTweaks: p.raw['texTweak'],
                ),
            ],
          ),
      ],
    );
  }
}

/// The four surfaces as they are now, side by side, each on its own material.
class _Specimens extends StatelessWidget {
  const _Specimens({required this.look, required this.scheme});

  final MaterialLook look;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final colours = {
      'ground': scheme.surface,
      'shell': scheme.surfaceContainer,
      'card': scheme.surfaceContainerLow,
      'cover': scheme.surfaceContainerHighest,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          for (final slot in slots)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AspectRatio(
                  aspectRatio: 0.8,
                  child: MaterialSurface(
                    key: ValueKey('specimen-$slot'),
                    slot: slot,
                    color: colours[slot]!,
                    look: look,
                    borderRadius: BorderRadius.circular(14),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          context.tr('app.materials.slot.$slot'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The four dials of one material. A drag changes the numbers on screen and the save happens on release, because the
/// preference is one JSON object and a save per step would be a request per pixel.
class _Dials extends StatefulWidget {
  const _Dials({
    super.key,
    required this.name,
    required this.label,
    required this.phys,
    required this.dirty,
    required this.rawTweaks,
  });

  final String name, label;
  final Phys phys;
  final bool dirty;
  final Object? rawTweaks;

  @override
  State<_Dials> createState() => _DialsState();
}

class _DialsState extends State<_Dials> {
  final Map<String, double> _drag = {};

  @override
  void didUpdateWidget(_Dials old) {
    super.didUpdateWidget(old);
    // The saved value has arrived: stop holding the dragged one, so the slider does not step back while it waits.
    if (old.phys != widget.phys) _drag.clear();
  }

  int _value(String dial) => switch (dial) {
    'hard' => widget.phys.hard,
    'sss' => widget.phys.sss,
    'diff' => widget.phys.diff,
    _ => widget.phys.refl,
  };

  Future<void> _save(Map<String, int>? dials) => savePrefs(context, {
    'texTweak': editedTweaks(widget.rawTweaks, widget.name, dials),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label, style: theme.textTheme.titleSmall),
              ),
              if (widget.dirty)
                TextButton(
                  key: ValueKey('reset-${widget.name}'),
                  onPressed: () {
                    setState(_drag.clear);
                    _save(null);
                  },
                  child: Text(
                    context.tr('settings.appearance.phys.reset.aria', {
                      'name': widget.label,
                    }),
                  ),
                ),
            ],
          ),
          for (final (dial, key) in physDials)
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    context.tr(key),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: ValueKey('dial-${widget.name}-$dial'),
                    value: _drag[dial] ?? _value(dial).toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${(_drag[dial] ?? _value(dial)).round()}%',
                    onChanged: (v) => setState(() => _drag[dial] = v),
                    onChangeEnd: (v) {
                      final now = {
                        for (final (d, _) in physDials)
                          d: d == dial ? v.round() : _value(d),
                      };
                      setState(() => _drag[dial] = v);
                      _save(now);
                    },
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(_drag[dial] ?? _value(dial)).round()}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
