import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/capabilities.dart';
import '../app_controller.dart';
import '../settings/server_url.dart';
import '../l10n/l10n.dart';

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
        _warning = context.tr(
          'app.connect.connected_but_this_address_uses_plain',
        );
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.connect.your_tippani_server')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr('app.connect.tippani_runs_on_a_server_you'),
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
            decoration: InputDecoration(
              labelText: context.tr('app.connect.server_address'),
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
                : Text(context.tr('app.connect.check_and_connect')),
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
              child: Text(context.tr('home.daily.resume.label')),
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
  if (c.checking) return 'app.connect.asking_the_server';
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
      return 'app.connect.this_tippani_server_is_older_than';
    case Compatibility.appTooOld:
      return 'app.connect.this_tippani_server_is_newer_than';
    case Compatibility.ok:
      return '';
    case null:
      break;
  }
  switch (check.failure) {
    case ApiFailure.timeout:
      return 'app.connect.the_server_did_not_answer_in';
    case ApiFailure.network:
      return 'Could not reach that address. Check it, and that your phone can see the server (the same Wi-Fi, or your VPN).';
    case ApiFailure.badResponse:
      return 'app.connect.something_answered_but_it_is_not';
    case ApiFailure.rateLimited:
      return 'app.connect.the_server_is_asking_you_to';
    case ApiFailure.unauthorised:
    case ApiFailure.forbidden:
    case ApiFailure.server:
      return tok('app.connect.the_server_refused_the_questionx', {
        'x': check.detail.isEmpty ? '' : ': ${check.detail}',
      });
    case null:
      return 'app.connect.could_not_ask_the_server';
  }
}
