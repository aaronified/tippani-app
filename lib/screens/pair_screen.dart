import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../pairing/pairing_code.dart';
import '../pairing/pairing_service.dart';

/// One plain sentence for each way a pairing can fail. Pure, so the words are tested.
String pairFailureText(PairFailure f) => switch (f) {
  PairFailure.invalidCode => "That code did not work. Codes last five minutes and work once. Make a new one in Tippani's Settings on your computer and try again.",
  PairFailure.rateLimited => 'Too many tries. Wait a minute, then try again.',
  PairFailure.unreachable => 'Could not reach the server. Check that your phone can see it, then try again.',
  PairFailure.unexpected => 'The server answered in a way this app does not understand. Update the app and the server, then try again.',
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
  final _name = TextEditingController(text: 'My Android phone');
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
        () => _problem =
            'A pairing code is $pairingCodeLength letters and numbers, like 7K2M9QXD.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final name = _name.text.trim().isEmpty ? 'My Android phone' : _name.text;
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
      appBar: AppBar(title: const Text('Pair this phone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'On a computer, open Tippani, go to Settings, then Server, then Devices, and choose Pair a device. It shows a code. Type it here.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
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
            decoration: const InputDecoration(
              labelText: 'Name for this phone',
              helperText: 'Shown in the device list, so you can tell your phones apart.',
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
                : const Text('Pair'),
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
