import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/capabilities.dart';
import '../app_controller.dart';
import '../settings/server_url.dart';

/// Where the reader says which Tippani server is theirs. It asks the server what it is before it keeps
/// anything, so a typo, a sleeping NAS, a web page that is not Tippani and a server too old or too new
/// for this app each get their own sentence rather than a silent failure later.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.serverUrl ?? '',
  );
  bool _busy = false;
  String? _problem;
  String? _warning;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final url = normaliseServerUrl(_text.text);
    if (url == null) {
      setState(() {
        _problem = 'That is not an address. Try something like 192.168.1.20:8124 or https://quotes.example.org.';
        _warning = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _warning = null;
    });
    final check = await widget.controller.probe(url);
    if (!mounted) return;
    if (!check.usable) {
      setState(() {
        _busy = false;
        _problem = describeCheck(check);
      });
      return;
    }
    await widget.controller.connect(url, check);
    if (!mounted) return;
    if (isRiskyCleartext(url)) {
      // Kept, but said plainly: pairing will send a credential, and over plain http across the internet
      // anyone on the path can read it.
      setState(() {
        _busy = false;
        _warning = 'Connected, but this address uses plain http outside your own network. Anyone on the way can read what the app sends. Use https if you can.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your Tippani server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tippani runs on a server you own. Enter its address, the one you open in a browser.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _check(),
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: '192.168.1.20:8124',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Check and connect'),
          ),
          if (_problem != null) ...[
            const SizedBox(height: 16),
            Text(_problem!, style: TextStyle(color: scheme.error)),
          ],
          if (_warning != null) ...[
            const SizedBox(height: 16),
            Text(_warning!),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One plain sentence for each way asking a server can go wrong. Pure, so the words are tested.
/// One line on how the server is: being asked, not asked yet, connected (and its version), or why it is not.
String serverStatusLine(AppController c) {
  if (c.checking) return 'Asking the server…';
  final check = c.check;
  if (check == null) return 'Not checked yet.';
  final caps = check.capabilities;
  if (caps == null) return describeCheck(check);
  final detail = caps.version.isEmpty ? '' : ' (version ${caps.version})';
  return check.usable ? 'Connected$detail.' : describeCheck(check);
}

String describeCheck(ServerCheck check) {
  switch (check.verdict) {
    case Compatibility.serverTooOld:
      return 'This Tippani server is older than this app needs. Update the server, then try again.';
    case Compatibility.appTooOld:
      return 'This Tippani server is newer than this app understands. Update the app, then try again.';
    case Compatibility.ok:
      return '';
    case null:
      break;
  }
  switch (check.failure) {
    case ApiFailure.timeout:
      return 'The server did not answer in time. If it was asleep, wait a moment and try again.';
    case ApiFailure.network:
      return 'Could not reach that address. Check it, and that your phone can see the server (the same Wi-Fi, or your VPN).';
    case ApiFailure.badResponse:
      return 'Something answered, but it is not a Tippani server. Check the address and the port.';
    case ApiFailure.rateLimited:
      return 'The server is asking you to slow down. Wait a moment and try again.';
    case ApiFailure.unauthorised:
    case ApiFailure.forbidden:
    case ApiFailure.server:
      return 'The server refused the question${check.detail.isEmpty ? '' : ': ${check.detail}'}.';
    case null:
      return 'Could not ask the server.';
  }
}
