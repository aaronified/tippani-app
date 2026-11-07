import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../pairing/devices.dart';
import '../l10n/l10n.dart';

/// The devices paired with this account, so a lost phone can be unpaired from another. This phone is
/// marked and cannot be revoked from here (that is Unpair, in Settings), so a stray tap cannot cut off
/// the phone in your hand.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<DeviceInfo>? _devices;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _problem = null);
    try {
      final list = await widget.controller.devices();
      if (mounted) setState(() => _devices = list ?? const []);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = e.failure == ApiFailure.unauthorised
            ? context.tr('app.board_service.the_server_no_longer_accepts_this')
            : context.tr('app.devices.could_not_load_the_devices_check');
      });
    }
  }

  Future<void> _revoke(DeviceInfo d) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('app.devices.unpair_name', {'name': d.name})),
        content: Text(context.tr('app.devices.that_device_is_signed_out_of')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('app.devices.unpair')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.controller.revoke(d.id);
    } on ApiException catch (e) {
      // 404 is "already gone": the list is about to say so
      if (e.status != 404 && mounted) {
        setState(() => _problem = 'Could not unpair ${d.name}. Try again.');
        return;
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    final scheme = Theme.of(context).colorScheme;
    final anyCurrent = devices?.any((d) => d.current) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.devices.paired_devices'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_problem != null)
              Text(_problem!, style: TextStyle(color: scheme.error)),
            if (devices == null && _problem == null)
              const LinearProgressIndicator(),
            if (devices != null && devices.isEmpty)
              Text(context.tr('app.devices.no_devices_are_paired')),
            if (devices != null && !anyCurrent && devices.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  context.tr('app.devices.this_server_is_too_old_to'),
                ),
              ),
            for (final d in devices ?? const <DeviceInfo>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    title: Text(
                      d.name.isEmpty
                          ? context.tr('app.devices.unnamed_device')
                          : d.name,
                    ),
                    subtitle: Text(
                      d.current
                          ? context.tr('app.devices.this_phone')
                          : d.lastSeenAt.isEmpty
                          ? 'Paired ${d.createdAt}. Not used yet.'
                          : 'Last used ${d.lastSeenAt}',
                    ),
                    trailing: d.current
                        ? const Icon(Icons.smartphone)
                        : TextButton(
                            onPressed: () => _revoke(d),
                            child: Text(context.tr('app.devices.unpair')),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
