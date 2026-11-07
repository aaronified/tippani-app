import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../pairing/pairing_code.dart';
import '../pairing/pairing_service.dart';
import '../l10n/l10n.dart';

/// One plain sentence for each way a pairing can fail. Pure, so the words are tested.
String pairFailureText(PairFailure f) => switch (f) {
  PairFailure.invalidCode => tx('app.pair.that_code_did_not_work_codes'),
  PairFailure.rateLimited => tx('app.pair.too_many_tries_wait_a_minute'),
  PairFailure.unreachable => tx('app.pair.could_not_reach_the_server_check'),
  PairFailure.unexpected => tx('app.pair.the_server_answered_in_a_way'),
};

/// Pairs this phone with the server: the reader makes a code in Tippani's Settings on a computer, and types
/// it here. The code is good for five minutes and once; the phone gets a device token that the reader can
/// revoke from Settings, and no password ever touches the phone.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController(text: tx('app.pair.my_android_phone'));
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = normalisePairingCode(_code.text);
    if (code == null) {
      setState(
        () => _problem = context.tr('app.pair.a_pairing_code_is_pairing_code', {
          'pairing_code_length': pairingCodeLength,
        }),
      );
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final name = _name.text.trim().isEmpty
        ? context.tr('app.pair.my_android_phone')
        : _name.text;
    final result = await widget.controller.pair(code, name);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _problem = pairFailureText(result.failure!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.home.pair_this_phone'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('app.pair.on_a_computer_open_tippani_go')),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.tr('settings.devices.code.info.title'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 64,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _pair(),
            decoration: InputDecoration(
              labelText: context.tr('app.pair.name_for_this_phone'),
              helperText: context.tr('app.pair.shown_in_the_device_list_so'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('app.pair.pair')),
          ),
          if (_problem != null) ...[
            const SizedBox(height: 16),
            Text(_problem!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
