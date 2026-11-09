import 'package:flutter/material.dart';

/// Puts [options] in the order they suit what is typed: those that start with it, then those with a word that starts with
/// it, then those that only contain it. Case and accents do not matter, and options keep their own order within a group.
/// An empty [query] keeps them all as they are. [skip] drops options already taken.
List<String> rankOptions(
  String query,
  Iterable<String> options, {
  Set<String> skip = const {},
}) {
  final q = _fold(query);
  final taken = {for (final s in skip) _fold(s)};
  final scored = <(int, int, String)>[];
  var i = 0;
  for (final o in options) {
    final f = _fold(o);
    i++;
    if (f.isEmpty || taken.contains(f)) continue;
    int? score;
    if (q.isEmpty) {
      score = 0;
    } else if (f.startsWith(q)) {
      score = 0;
    } else if (RegExp('(^|[^a-z0-9])${RegExp.escape(q)}').hasMatch(f)) {
      score = 1;
    } else if (f.contains(q)) {
      score = 2;
    }
    if (score != null) scored.add((score, i, o));
  }
  scored.sort((a, b) {
    final s = a.$1.compareTo(b.$1);
    return s != 0 ? s : a.$2.compareTo(b.$2);
  });
  return [for (final s in scored) s.$3];
}

String _fold(String s) {
  var t = s.trim().toLowerCase();
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final r in t.runes) {
    final c = String.fromCharCode(r);
    final at = from.indexOf(c);
    b.write(at >= 0 ? to[at] : c);
  }
  t = b.toString();
  return t;
}

/// A text box that suggests as you type, from [options], and lets the reader type something new all the same. With
/// [multi] the box holds a list ("Rick, Ilsa") and the suggestions are for the name being typed after the last comma. The
/// options are read when the box is used, so they can arrive after the form opens.
class ComboField extends StatefulWidget {
  const ComboField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.options,
    this.helperText,
    this.multi = false,
    this.textCapitalization = TextCapitalization.words,
    this.keyboardType,
    this.maxSuggestions = 6,
    this.onChanged,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;

  /// Everything that can be suggested, in the order to prefer.
  final List<String> Function() options;
  final bool multi;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final int maxSuggestions;
  final ValueChanged<String>? onChanged;

  @override
  State<ComboField> createState() => _ComboFieldState();
}

class _ComboFieldState extends State<ComboField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// The part being typed, and the names already in the box.
  (String, List<String>) _split(String text) {
    if (!widget.multi) return (text, const []);
    final at = text.lastIndexOf(',');
    final done = [
      for (final p in (at < 0 ? '' : text.substring(0, at)).split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    return (at < 0 ? text : text.substring(at + 1), done);
  }

  Iterable<String> _suggest(TextEditingValue v) {
    final (typing, done) = _split(v.text);
    final out = rankOptions(typing, widget.options(), skip: done.toSet());
    // typing exactly an option leaves nothing to suggest
    if (out.length == 1 &&
        out.first.toLowerCase() == typing.trim().toLowerCase()) {
      return const [];
    }
    return out.take(widget.maxSuggestions);
  }

  /// What the box holds once [option] is chosen: the option alone, or in a list the names already there and the option.
  String _shown(String option) => widget.multi
      ? [..._split(widget.controller.text).$2, option].join(', ')
      : option;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: _suggest,
      displayStringForOption: _shown,
      onSelected: (_) => widget.onChanged?.call(widget.controller.text),
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        textCapitalization: widget.textCapitalization,
        keyboardType: widget.keyboardType,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.labelText,
          helperText: widget.helperText,
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final scheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 4,
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 48.0 * widget.maxSuggestions,
                  maxWidth: MediaQuery.sizeOf(context).width - 32,
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        dense: true,
                        title: Text(
                          o,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
