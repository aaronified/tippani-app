import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../l10n/l10n.dart';
import '../library/models.dart';
import '../theme/material_surface.dart';
import '../tools/work_edit_service.dart';

/// Edits what the server holds about a work beyond its title: description, genres, series, publisher, pages, ISBN
/// and links (the ones its kind has). The record is read from the server when the form opens and written back to
/// it on Save; pops true once the server took it.
class WorkDetailsFormScreen extends StatefulWidget {
  const WorkDetailsFormScreen({
    super.key,
    required this.work,
    required this.service,
  });

  final Work work;
  final WorkEditService service;

  @override
  State<WorkDetailsFormScreen> createState() => _WorkDetailsFormScreenState();
}

class _WorkDetailsFormScreenState extends State<WorkDetailsFormScreen> {
  final _description = TextEditingController();
  final _genres = TextEditingController();
  final _series = TextEditingController();
  final _seriesNo = TextEditingController();
  final _publisher = TextEditingController();
  final _subtitle = TextEditingController();
  final _pages = TextEditingController();
  final _isbn = TextEditingController();
  final _links = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _isBook =>
      widget.work.kind == WorkKind.book || widget.work.kind == WorkKind.other;
  bool get _hasPublisher => _isBook || widget.work.kind == WorkKind.game;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    for (final c in [
      _description,
      _genres,
      _series,
      _seriesNo,
      _publisher,
      _subtitle,
      _pages,
      _isbn,
      _links,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(Object? v) => v is String ? v : '';

  Future<void> _read() async {
    try {
      final r = await widget.service.record(widget.work);
      if (!mounted) return;
      final g = r['genres'];
      final no = r['series_index'];
      final pages = r['pages'];
      setState(() {
        _description.text = _text(r['description']);
        _genres.text = g is List ? g.whereType<String>().join(', ') : '';
        _series.text = _text(r['series']);
        _seriesNo.text = no is num && no > 0
            ? (no == no.truncate() ? '${no.toInt()}' : '$no')
            : '';
        _publisher.text = _text(r['publisher']);
        _subtitle.text = _text(r['subtitle']);
        _pages.text = pages is int && pages > 0 ? '$pages' : '';
        _isbn.text = _text(r['isbn']);
        _links.text = _text(r['links']);
        _loaded = true;
      });
    } on ServerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final pagesText = _pages.text.trim();
    final noText = _seriesNo.text.trim();
    final pages = pagesText.isEmpty ? 0 : int.tryParse(pagesText);
    final no = noText.isEmpty ? 0.0 : double.tryParse(noText);
    if (pages == null || no == null) {
      setState(() => _error = context.tr('app.work.details_number_needed'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final edit = WorkDetailsEdit(
      description: _description.text.trim(),
      genres: [
        for (final g in _genres.text.split(','))
          if (g.trim().isNotEmpty) g.trim(),
      ],
      series: _series.text.trim(),
      seriesIndex: no,
      links: _links.text.trim(),
      publisher: _hasPublisher ? _publisher.text.trim() : null,
      subtitle: _isBook ? _subtitle.text.trim() : null,
      pages: _isBook ? pages : null,
      isbn: _isBook ? _isbn.text.trim() : null,
    );
    try {
      await widget.service.saveDetails(widget.work, edit);
      if (mounted) Navigator.of(context).pop(true);
    } on ServerException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? helper,
    int lines = 1,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 4,
      keyboardType: keyboard ?? (lines == 1 ? null : TextInputType.multiline),
      decoration: InputDecoration(labelText: label, helperText: helper),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellAppBar(
        title: Text(context.tr('app.work.edit_details')),
        actions: [
          TextButton(
            onPressed: _saving || !_loaded ? null : _save,
            child: Text(context.tr('common.action.save.label')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (!_loaded && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_loaded) ...[
            _field(
              _description,
              context.tr('common.field.description.label'),
              lines: 4,
            ),
            _field(
              _genres,
              context.tr('common.field.genres.label'),
              helper: context.tr('app.work.details_genres_hint'),
            ),
            if (_isBook)
              _field(_subtitle, context.tr('common.field.subtitle.label')),
            _field(_series, context.tr('common.field.series.label')),
            _field(
              _seriesNo,
              context.tr('common.field.series-no.label'),
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            if (_hasPublisher)
              _field(_publisher, context.tr('common.field.publisher.label')),
            if (_isBook) ...[
              _field(
                _pages,
                context.tr('common.field.pages.label'),
                keyboard: TextInputType.number,
              ),
              _field(_isbn, context.tr('common.field.isbn.label')),
            ],
            _field(
              _links,
              context.tr('common.field.links.label'),
              helper: context.tr('app.work.details_links_hint'),
              lines: 3,
            ),
          ],
        ],
      ),
    );
  }
}
