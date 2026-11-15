import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../l10n/l10n.dart';
import '../library/models.dart';
import '../theme/material_surface.dart';
import '../tools/cover_search.dart' show coverSourceName;
import '../tools/work_edit_service.dart';

/// Lists what the server's catalogues say a work might be, and links the one the reader picks. Pops true once the
/// server has taken the link.
class WorkSourceScreen extends StatefulWidget {
  const WorkSourceScreen({
    super.key,
    required this.work,
    required this.service,
  });

  final Work work;
  final WorkEditService service;

  @override
  State<WorkSourceScreen> createState() => _WorkSourceScreenState();
}

class _WorkSourceScreenState extends State<WorkSourceScreen> {
  List<SourceCandidate>? _found;
  String? _error;
  bool _linking = false;

  bool get _isBook =>
      widget.work.kind == WorkKind.book || widget.work.kind == WorkKind.other;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    try {
      final found = await widget.service.findSources(widget.work);
      if (mounted) setState(() => _found = found);
    } on ServerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pick(SourceCandidate c) async {
    final source = coverSourceName(c.source);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.title),
        content: Text(
          context.tr(
            _isBook
                ? 'app.work.source_confirm'
                : 'app.work.source_confirm_screen',
            {'source': source},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('app.work.source_link')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      await widget.service.linkSource(widget.work, c);
      if (mounted) Navigator.of(context).pop(true);
    } on ServerException catch (e) {
      if (mounted) {
        setState(() {
          _linking = false;
          _error = e.message;
        });
      }
    }
  }

  Widget _thumb(SourceCandidate c) => SizedBox(
    width: 40,
    height: 60,
    child: c.cover.isEmpty
        ? const SizedBox.shrink()
        : Image.network(
            c.cover,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Scaffold(
      appBar: ShellAppBar(title: Text(context.tr('app.work.source_title'))),
      body: ListView(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (found == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (found != null && found.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('app.work.source_nothing')),
            ),
          if (found != null)
            for (final c in found)
              ListTile(
                leading: _thumb(c),
                title: Text(c.title),
                subtitle: Text(
                  [
                    if (c.summary.isNotEmpty) c.summary,
                    coverSourceName(c.source),
                  ].join(' · '),
                ),
                enabled: !_linking,
                onTap: () => _pick(c),
              ),
        ],
      ),
    );
  }
}
