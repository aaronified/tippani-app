import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../library/models.dart';
import '../tools/cover_search.dart';
import '../l10n/l10n.dart';

/// Finds a cover or poster online: search by title, creator or ISBN (the work's own are filled in), see what the
/// catalogues and picture suppliers have with the name of each, and press one to use it. Pops the chosen picture's
/// bytes and a file name, for the caller to send to the server.
class CoverSearchScreen extends StatefulWidget {
  const CoverSearchScreen({
    super.key,
    required this.search,
    required this.work,
  });

  final CoverSearch search;
  final Work work;

  @override
  State<CoverSearchScreen> createState() => _CoverSearchScreenState();
}

class _CoverSearchScreenState extends State<CoverSearchScreen> {
  late final _title = TextEditingController(text: widget.work.title);
  late final _creator = TextEditingController(text: widget.work.creator);
  final _isbn = TextEditingController();
  List<CoverOption>? _found;
  bool _busy = false;
  String? _problem;
  String _source = '';

  bool get _book =>
      widget.work.kind == WorkKind.book || widget.work.kind == WorkKind.other;

  @override
  void initState() {
    super.initState();
    _go();
  }

  @override
  void dispose() {
    _title.dispose();
    _creator.dispose();
    _isbn.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _problem = null;
      _source = '';
    });
    try {
      final r = await widget.search.find(
        kind: widget.work.kind,
        title: _title.text,
        creator: _book ? _creator.text : '',
        isbn: _isbn.text,
        year: widget.work.year,
      );
      if (mounted) setState(() => _found = r);
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _use(CoverOption o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('app.cover_search.use_this_cover')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 240,
              child: Image.network(
                o.url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 48),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('app.cover_search.from_source', {'source': o.source}),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('app.cover_search.use_it')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final Uint8List bytes = await widget.search.download(o.url);
      final ext = o.url.toLowerCase().contains('.png')
          ? 'png'
          : (o.url.toLowerCase().contains('.webp') ? 'webp' : 'jpg');
      if (mounted) {
        Navigator.of(context).pop((bytes: bytes, name: 'cover.$ext'));
      }
    } on ServerException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final sources = {for (final o in found ?? const <CoverOption>[]) o.source}
        .toList();
    final shown = [
      for (final o in found ?? const <CoverOption>[])
        if (_source.isEmpty || o.source == _source) o,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.cover_search.find_a_cover_online')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: context.tr('common.field.title.label'),
                  ),
                  onSubmitted: (_) => _go(),
                ),
                if (_book) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _creator,
                          decoration: InputDecoration(
                            labelText: context.tr('common.field.author.label'),
                          ),
                          onSubmitted: (_) => _go(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _isbn,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.tr('common.field.isbn.label'),
                          ),
                          onSubmitted: (_) => _go(),
                        ),
                      ),
                    ],
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _go,
                    icon: const Icon(Icons.search),
                    label: Text(context.tr('common.help.topbar.search.term')),
                  ),
                ),
              ],
            ),
          ),
          if (sources.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final s in sources)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(s),
                        selected: _source == s,
                        onSelected: (v) => setState(() => _source = v ? s : ''),
                      ),
                    ),
                ],
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _problem != null
                ? Center(child: Text(_problem!))
                : found == null
                ? const SizedBox.shrink()
                : shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        context.tr(
                          'app.cover_search.no_cover_found_try_the_isbn',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 3,
                    padding: const EdgeInsets.all(16),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                    children: [
                      for (final o in shown)
                        InkWell(
                          onTap: _busy ? null : () => _use(o),
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    o.shown,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                o.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
