import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../harness/harness.dart';
import 'checks_screen.dart';
import '../l10n/l10n.dart';

/// The Settings row that opens Import and checks, badged with how many imported quotes wait for approval.
class ChecksEntry extends StatefulWidget {
  const ChecksEntry({
    super.key,
    required this.controller,
    required this.harness,
  });

  final AppController controller;
  final Harness harness;

  @override
  State<ChecksEntry> createState() => _ChecksEntryState();
}

class _ChecksEntryState extends State<ChecksEntry> {
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_look);
    _look();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_look);
    super.dispose();
  }

  Future<void> _look() async {
    final s = widget.harness.imports;
    if (s == null || !s.available) {
      if (_pending != 0 && mounted) setState(() => _pending = 0);
      return;
    }
    try {
      final n = await s.pending();
      if (mounted) setState(() => _pending = n);
    } on Object {
      // the badge is a nicety; the screen itself says what is wrong
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.harness;
    return ListTile(
      leading: const Icon(Icons.fact_check_outlined),
      title: Text(context.tr('app.checks_entry.import_and_checks')),
      subtitle: Text(
        _pending > 0
            ? trn('app.checks_entry.waiting', _pending)
            : context.tr(
                'app.checks_entry.bring_in_files_stray_marks_corrections',
              ),
      ),
      trailing: _pending > 0
          ? Badge(
              label: Text(
                context.tr('app.checks_entry.pending', {'pending': _pending}),
              ),
            )
          : null,
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChecksScreen(
              imports: h.imports,
              checks: h.checks,
              library: h.library,
              picker: h.importPicker,
              auto: h.auto,
            ),
          ),
        );
        _look();
      },
    );
  }
}
