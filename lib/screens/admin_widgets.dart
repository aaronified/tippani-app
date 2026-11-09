import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../l10n/l10n.dart';

/// Reads something from the server and draws it: a bar while it loads, the server's own words and a Try again
/// when it cannot be read, and [builder] with the data and a way to read it again when it can.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  bool _have = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _have = true;
          _problem = null;
        });
      }
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _problem = context.tr('app.admin.that_could_not_be_read'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_have) return widget.builder(context, _data as T, _read);
    if (_problem != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_problem!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() => _problem = null);
                  _read();
                },
                child: Text(context.tr('common.source.retry')),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

/// A heading above a group of cards.
class AdminHeading extends StatelessWidget {
  const AdminHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Says [text] in a bar at the bottom of the screen.
void say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [action] and tells the reader what the server said when it refuses. Returns whether it worked.
Future<bool> attempt(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } on ServerException catch (e) {
    if (context.mounted) say(context, e.message);
    return false;
  }
}

/// Asks "are you sure" with a [title] and [body]; true when the reader pressed [yes].
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String yes = 'Yes',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Asks for one line of text; null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  bool secret = false,
  String yes = 'OK',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        textCapitalization: TextCapitalization.none,
        controller: c,
        autofocus: true,
        obscureText: secret,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text),
          child: Text(yes),
        ),
      ],
    ),
  );
}
