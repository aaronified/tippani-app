import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/account_service.dart';
import '../capture/photo_source.dart';
import '../l10n/l10n.dart';
import '../library/cover_cache.dart';
import 'prefs_widgets.dart';
import '../theme/tabler.dart';

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
      context.tr('app.account.picture_changed'),
    );
  }

  Future<void> _rename() async {
    final name = await askText(
      context,
      title: context.tr('app.account.your_name'),
      initial: _me?.username ?? '',
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _run(
      () => widget.account.rename(name),
      context.tr('app.account.name_changed'),
    );
  }

  Future<void> _password() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(account: widget.account),
    );
    if (done == true && mounted) {
      _say(context.tr('app.account.password_changed'));
    }
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
      context.tr('app.account.notification_settings_saved'),
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
        title: Text(ctx.tr('app.account.your_widget_key')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ctx.tr('app.account.this_is_shown_once_copy_it')),
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
            child: Text(ctx.tr('common.action.copy.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('common.action.done.label')),
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
      title: context.tr('bin.kind.account.label'),
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
                      icon: const Icon(Ti.camera),
                      label: Text(context.tr('app.account.change_picture')),
                    ),
                    if (me.avatar.isNotEmpty)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                widget.account.clearAvatar,
                                context.tr('app.account.picture_removed'),
                              ),
                        child: Text(context.tr('common.action.remove.label')),
                      ),
                  ],
                ),
              ],
            ),
          ),
          PrefGroup(
            children: [
              ListTile(
                leading: const Icon(Ti.idBadge),
                title: Text(context.tr('app.account.your_name')),
                subtitle: Text(me.username),
                onTap: _rename,
              ),
              ListTile(
                leading: const Icon(Ti.password),
                title: Text(context.tr('account.password.label')),
                subtitle: me.mustChangePassword
                    ? Text(
                        context.tr(
                          'app.account.an_admin_chose_this_password_choose',
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
            title: context.tr('account.notify.label'),
            footer: context.tr('app.account.pushover_sends_a_note_to_your'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  textCapitalization: TextCapitalization.none,
                  controller: _pushUser,
                  decoration: InputDecoration(
                    labelText: context.tr('account.notify.user.label'),
                  ),
                ),
              ),
              if (!_notify!.serverAppToken)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    textCapitalization: TextCapitalization.none,
                    controller: _appToken,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.tr('app.account.pushover_app_token'),
                      helperText: _notify!.hasAppToken
                          ? context.tr('app.account.one_is_saved_type_a_new')
                          : null,
                    ),
                  ),
                ),
              SwitchListTile(
                title: Text(context.tr('app.account.daily_review_is_ready')),
                value: _onDaily,
                onChanged: (v) => setState(() => _onDaily = v),
              ),
              SwitchListTile(
                title: Text(context.tr('app.account.an_import_is_waiting')),
                value: _onImport,
                onChanged: (v) => setState(() => _onImport = v),
              ),
              SwitchListTile(
                title: Text(
                  context.tr('app.account.a_metadata_fetch_finished'),
                ),
                value: _onFetch,
                onChanged: (v) => setState(() => _onFetch = v),
              ),
              SwitchListTile(
                title: Text(context.tr('app.account.a_backup_finished')),
                value: _onBackup,
                onChanged: (v) => setState(() => _onBackup = v),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _saveNotify,
                      child: Text(context.tr('common.action.save.label')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              widget.account.testNotification,
                              context.tr('app.account.a_test_note_was_sent'),
                            ),
                      child: Text(context.tr('account.notify.test.action')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (me != null)
          PrefGroup(
            title: context.tr('app.account.widget_key'),
            footer: context.tr('app.account.a_key_lets_a_home_screen'),
            children: [
              ListTile(
                leading: const Icon(Ti.key),
                title: Text(
                  _hasWidgetKey
                      ? context.tr('app.account.made_when', {
                          'when': _widgetKey ?? '',
                        })
                      : context.tr('app.account.no_key_yet'),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy ? null : _makeKey,
                      child: Text(
                        _hasWidgetKey
                            ? context.tr('app.account.replace')
                            : context.tr('account.widget.make.action'),
                      ),
                    ),
                    if (_hasWidgetKey)
                      IconButton(
                        tooltip: context.tr('common.action.remove.label'),
                        icon: const Icon(Ti.trash),
                        onPressed: _busy
                            ? null
                            : () => _run(
                                widget.account.removeWidgetKey,
                                context.tr('app.account.key_removed'),
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
      setState(() => _error = context.tr('app.account.the_two_do_not_match'));
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
    title: Text(context.tr('account.password.label')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            textCapitalization: TextCapitalization.none,
            key: const ValueKey('password-current'),
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.tr('app.account.current_password'),
            ),
          ),
          TextField(
            textCapitalization: TextCapitalization.none,
            key: const ValueKey('password-new'),
            controller: _next,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.tr('app.account.new_password'),
            ),
          ),
          TextField(
            textCapitalization: TextCapitalization.none,
            key: const ValueKey('password-again'),
            controller: _again,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.tr('app.account.new_password_again'),
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
        child: Text(context.tr('common.action.cancel.label')),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(context.tr('settings.languages.iso.change.label')),
      ),
    ],
  );
}
