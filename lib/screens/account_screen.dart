import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/account_service.dart';
import '../capture/photo_source.dart';
import '../l10n/l10n.dart';
import '../library/cover_cache.dart';
import 'prefs_widgets.dart';

/// The reader's account on the server: picture and name, password, notifications and the widget key.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.account, this.photos});

  final AccountService account;

  /// Where a new picture comes from; null uses the phone's own gallery and camera.
  final PhotoSource? photos;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  AccountInfo? _me;
  NotifySettings? _notify;
  String? _widgetKey; // the date it was made, or null
  bool _hasWidgetKey = false;
  String? _problem;
  bool _busy = false;

  final _pushUser = TextEditingController();
  final _appToken = TextEditingController();
  bool _onDaily = false, _onImport = false, _onFetch = false, _onBackup = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pushUser.dispose();
    _appToken.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = await widget.account.me();
    final n = await widget.account.notifications();
    final k = await widget.account.widgetKey();
    if (!mounted) return;
    setState(() {
      _problem = me.error;
      _me = me.value;
      _notify = n.value;
      final s = n.value;
      if (s != null) {
        _pushUser.text = s.pushoverUser;
        _onDaily = s.onDaily;
        _onImport = s.onImport;
        _onFetch = s.onFetch;
        _onBackup = s.onBackup;
      }
      _hasWidgetKey = k.ok && k.value != null;
      _widgetKey = k.value;
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(
    Future<Outcome<Object?>> Function() job,
    String done,
  ) async {
    setState(() => _busy = true);
    final r = await job();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(r.ok ? done : r.error!);
    if (r.ok) await _load();
  }

  Future<void> _newPicture() async {
    final photos = widget.photos ?? DevicePhotos();
    final path = await photos.choose();
    if (path == null || !mounted) return;
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    final name = path.split(RegExp(r'[\\/]')).last;
    await _run(
      () => widget.account.setAvatar(bytes, name),
      context.tr('Picture changed.'),
    );
  }

  Future<void> _rename() async {
    final name = await askText(
      context,
      title: context.tr('Your name'),
      initial: _me?.username ?? '',
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _run(() => widget.account.rename(name), context.tr('Name changed.'));
  }

  Future<void> _password() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(account: widget.account),
    );
    if (done == true && mounted) _say(context.tr('Password changed.'));
  }

  Future<void> _saveNotify() async {
    final patch = <String, Object?>{
      'pushover_user': _pushUser.text.trim(),
      if (_appToken.text.trim().isNotEmpty) 'app_token': _appToken.text.trim(),
      'on_daily': _onDaily,
      'on_import': _onImport,
      'on_fetch': _onFetch,
      'on_backup': _onBackup,
    };
    await _run(
      () => widget.account.saveNotifications(patch),
      context.tr('Notification settings saved.'),
    );
    _appToken.clear();
  }

  Future<void> _makeKey() async {
    setState(() => _busy = true);
    final r = await widget.account.makeWidgetKey();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      _say(r.error!);
      return;
    }
    final key = r.value ?? '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Your widget key')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.tr(
                'This is shown once. Copy it into the widget now; the server keeps only a scrambled copy.',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              key,
              key: const ValueKey('widget-key'),
              style: const TextStyle(fontFamily: 'IBMPlexMono'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: key)),
            child: Text(ctx.tr('Copy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('Done')),
          ),
        ],
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final theme = Theme.of(context);
    return PrefPage(
      title: context.tr('Account'),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_problem != null) PrefNote(_problem!),
        if (me != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                _Avatar(name: me.username, file: me.avatar),
                const SizedBox(height: 12),
                Text(me.username, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _newPicture,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(context.tr('Change picture')),
                    ),
                    if (me.avatar.isNotEmpty)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                widget.account.clearAvatar,
                                context.tr('Picture removed.'),
                              ),
                        child: Text(context.tr('Remove')),
                      ),
                  ],
                ),
              ],
            ),
          ),
          PrefGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(context.tr('Your name')),
                subtitle: Text(me.username),
                onTap: _rename,
              ),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: Text(context.tr('Change password')),
                subtitle: me.mustChangePassword
                    ? Text(
                        context.tr(
                          'An admin chose this password. Choose your own.',
                        ),
                      )
                    : null,
                onTap: _password,
              ),
            ],
          ),
        ],
        if (_notify != null)
          PrefGroup(
            title: context.tr('Notifications'),
            footer: context.tr(
              'Pushover sends a note to your phone for the things you turn on.',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _pushUser,
                  decoration: InputDecoration(
                    labelText: context.tr('Pushover user key'),
                  ),
                ),
              ),
              if (!_notify!.serverAppToken)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _appToken,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.tr('Pushover app token'),
                      helperText: _notify!.hasAppToken
                          ? context.tr(
                              'One is saved. Type a new one to replace it.',
                            )
                          : null,
                    ),
                  ),
                ),
              SwitchListTile(
                title: Text(context.tr('Daily review is ready')),
                value: _onDaily,
                onChanged: (v) => setState(() => _onDaily = v),
              ),
              SwitchListTile(
                title: Text(context.tr('An import is waiting')),
                value: _onImport,
                onChanged: (v) => setState(() => _onImport = v),
              ),
              SwitchListTile(
                title: Text(context.tr('A metadata fetch finished')),
                value: _onFetch,
                onChanged: (v) => setState(() => _onFetch = v),
              ),
              SwitchListTile(
                title: Text(context.tr('A backup finished')),
                value: _onBackup,
                onChanged: (v) => setState(() => _onBackup = v),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _saveNotify,
                      child: Text(context.tr('Save')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              widget.account.testNotification,
                              context.tr('A test note was sent.'),
                            ),
                      child: Text(context.tr('Send a test')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (me != null)
          PrefGroup(
            title: context.tr('Widget key'),
            footer: context.tr(
              'A key lets a home-screen widget show a quote of the day without your password.',
            ),
            children: [
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: Text(
                  _hasWidgetKey
                      ? context.tr('Made {when}', {'when': _widgetKey ?? ''})
                      : context.tr('No key yet'),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy ? null : _makeKey,
                      child: Text(
                        _hasWidgetKey
                            ? context.tr('Replace')
                            : context.tr('Make a key'),
                      ),
                    ),
                    if (_hasWidgetKey)
                      IconButton(
                        tooltip: context.tr('Remove'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy
                            ? null
                            : () => _run(
                                widget.account.removeWidgetKey,
                                context.tr('Key removed.'),
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The reader's picture as a circle, or their initial where there is none.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.file});

  final String name;
  final String file;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = CircleAvatar(
      radius: 48,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(color: scheme.onPrimaryContainer),
      ),
    );
    final covers = CoverScope.of(context);
    if (file.isEmpty || covers == null) return initial;
    return FutureBuilder<File?>(
      future: covers.fileFor(file),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) return initial;
        return ClipOval(
          child: Image.file(
            f,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => initial,
          ),
        );
      },
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.account});

  final AccountService account;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text != _again.text) {
      setState(() => _error = context.tr('The two do not match.'));
      return;
    }
    setState(() => _busy = true);
    final r = await widget.account.changePassword(_current.text, _next.text);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = r.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Change password')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('password-current'),
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.tr('Current password'),
            ),
          ),
          TextField(
            key: const ValueKey('password-new'),
            controller: _next,
            obscureText: true,
            decoration: InputDecoration(labelText: context.tr('New password')),
          ),
          TextField(
            key: const ValueKey('password-again'),
            controller: _again,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.tr('New password again'),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(context.tr('Cancel')),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(context.tr('Change')),
      ),
    ],
  );
}
