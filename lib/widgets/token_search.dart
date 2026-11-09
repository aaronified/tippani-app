import 'package:flutter/material.dart';

import '../theme/tabler.dart';
import 'combo_field.dart';

/// What a search box holds, taken apart: the free words, and the tokens `tag:sea`, `by:"Herman Melville"` and
/// `in:Walden` (a token's value is one word, or several in quotes).
class SearchQuery {
  const SearchQuery({this.text = '', this.tag, this.by, this.inWork});

  /// The words that are not tokens, in order.
  final String text;
  final String? tag, by, inWork;

  bool get isEmpty =>
      text.isEmpty && tag == null && by == null && inWork == null;
}

/// The keys a token can start with, and what each narrows to.
const searchTokens = ['tag', 'by', 'in'];

final _token = RegExp(
  r'(?:^|\s)(tag|by|in):("([^"]*)"?|\S*)',
  caseSensitive: false,
);

/// Takes [raw] apart. A token with no value yet is ignored; the last of a repeated token wins.
SearchQuery parseSearch(String raw) {
  String? tag, by, inWork;
  final rest = StringBuffer();
  var at = 0;
  for (final m in _token.allMatches(raw)) {
    final value = (m.group(3) ?? m.group(2) ?? '').trim();
    final lead = raw.substring(at, m.start);
    rest.write(lead);
    at = m.end;
    if (value.isEmpty) continue;
    switch (m.group(1)!.toLowerCase()) {
      case 'tag':
        tag = value;
      case 'by':
        by = value;
      case 'in':
        inWork = value;
    }
  }
  rest.write(raw.substring(at));
  return SearchQuery(
    text: rest.toString().trim().replaceAll(RegExp(r'\s+'), ' '),
    tag: tag,
    by: by,
    inWork: inWork,
  );
}

/// What a token's value can be, for the suggestions.
class SearchSources {
  const SearchSources({
    this.tags = const [],
    this.people = const [],
    this.works = const [],
  });

  final List<String> tags, people, works;

  List<String> of(String key) => switch (key) {
    'tag' => tags,
    'by' => people,
    'in' => works,
    _ => const [],
  };
}

/// One thing the box can offer: a token's key (`tag:`), or a whole token (`tag:sea`).
class SearchSuggestion {
  const SearchSuggestion(this.key, this.value);

  final String key;

  /// Null when this is only the key.
  final String? value;

  String get token => value == null
      ? '$key:'
      : '$key:${value!.contains(' ') ? '"$value"' : value}';
}

final _tail = RegExp(r'(?:^|\s)(?:(\w+):("[^"]*|\S*)|(\S+))$');

/// The suggestions for the end of [raw]: the keys that start with the last word, or the values of the token being typed.
List<SearchSuggestion> suggestFor(
  String raw,
  SearchSources sources, {
  int limit = 6,
}) {
  final m = _tail.firstMatch(raw);
  if (m == null) return const [];
  final key = m.group(1)?.toLowerCase();
  if (key != null && searchTokens.contains(key)) {
    var typed = m.group(2) ?? '';
    if (typed.startsWith('"')) typed = typed.substring(1);
    final options = rankOptions(typed, sources.of(key));
    if (options.length == 1 &&
        options.first.toLowerCase() == typed.toLowerCase() &&
        !(m.group(2) ?? '').startsWith('"')) {
      return const [];
    }
    return [for (final o in options.take(limit)) SearchSuggestion(key, o)];
  }
  final word = (m.group(3) ?? '').toLowerCase();
  if (word.isEmpty || word.contains(':')) return const [];
  return [
    for (final k in searchTokens)
      if (k.startsWith(word) && k != word) SearchSuggestion(k, null),
  ];
}

/// The text with the last word (or the token being typed) replaced by [s].
String applySuggestion(String raw, SearchSuggestion s) {
  final m = _tail.firstMatch(raw);
  if (m == null) return raw;
  final start = raw.length - (m.group(0)!.trimLeft().length);
  final keep = raw.substring(0, start);
  return '$keep${s.token}${s.value == null ? '' : ' '}';
}

/// The search box of Home and of each board: a pill that suggests tokens as you type (`tag:`, `by:`, `in:`), then the
/// values a token can take, as a combobox does. [sources] are read when the box is used.
class TokenSearchField extends StatefulWidget {
  const TokenSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.sources,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final String hintText;
  final SearchSources Function() sources;
  final VoidCallback? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Buttons at the end of the pill (widening to the server's results, say).
  final Widget? trailing;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  State<TokenSearchField> createState() => _TokenSearchFieldState();
}

class _TokenSearchFieldState extends State<TokenSearchField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  static OutlineInputBorder _pill([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: side,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RawAutocomplete<SearchSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (v) => suggestFor(v.text, widget.sources()),
      displayStringForOption: (s) => applySuggestion(widget.controller.text, s),
      onSelected: (_) {
        // the box now holds the token; carry on at the end of it
        final c = widget.controller;
        c.selection = TextSelection.collapsed(offset: c.text.length);
        widget.onChanged?.call();
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        readOnly: widget.readOnly,
        onTap: widget.onTap,
        textCapitalization: TextCapitalization.none,
        textInputAction: TextInputAction.search,
        onChanged: (_) => widget.onChanged?.call(),
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Ti.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Ti.x),
                  onPressed: () {
                    controller.clear();
                    widget.onChanged?.call();
                  },
                ),
              ?widget.trailing,
            ],
          ),
          border: _pill(),
          enabledBorder: _pill(),
          focusedBorder: _pill(BorderSide(color: scheme.primary, width: 2)),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Material(
            elevation: 4,
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 48.0 * 6,
                maxWidth: MediaQuery.sizeOf(context).width - 24,
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      dense: true,
                      leading: Icon(switch (o.key) {
                        'tag' => Ti.tag,
                        'by' => Ti.user,
                        _ => Ti.book2,
                      }, size: 20),
                      title: Text(
                        o.value ?? '${o.key}:',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: o.value == null
                          ? null
                          : Text(
                              '${o.key}:',
                              style: const TextStyle(fontSize: 12),
                            ),
                      onTap: () => onSelected(o),
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
