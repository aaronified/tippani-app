import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/offline_writes.dart';
import '../app_controller.dart';
import '../l10n/l10n.dart';

/// The answer to a call: the [value], or the server's [error] in its own words.
class Outcome<T> {
  const Outcome.ok([this.value]) : error = null;
  const Outcome.fail(String this.error) : value = null;

  final T? value;
  final String? error;
  bool get ok => error == null;
}

/// Who the reader is on the server.
class AccountInfo {
  const AccountInfo({
    required this.username,
    required this.avatar,
    required this.mustChangePassword,
  });

  final String username;

  /// The file name of the avatar picture ('' for none); the picture is `GET /covers/<name>`.
  final String avatar;

  /// Set when an admin chose this account's password: the reader should choose their own.
  final bool mustChangePassword;
}

/// Where and how the reader is told about things (Pushover), as the server keeps it. The app token is
/// write-only: the server says whether one is set, never what it is.
class NotifySettings {
  const NotifySettings({
    required this.pushoverUser,
    required this.hasAppToken,
    required this.serverAppToken,
    required this.onDaily,
    required this.onImport,
    required this.onFetch,
    required this.onBackup,
  });

  final String pushoverUser;
  final bool hasAppToken;

  /// Whether the server has an app token of its own, so the reader needs only their user key.
  final bool serverAppToken;
  final bool onDaily, onImport, onFetch, onBackup;
}

/// The reader's account on the server: profile, password, notifications and the widget key. An interface so a
/// test can stand in for the server.
abstract class AccountService {
  /// False on a phone that is not paired: there is no account to show.
  bool get available;

  Future<Outcome<AccountInfo>> me();
  Future<Outcome<void>> rename(String username);
  Future<Outcome<String>> setAvatar(Uint8List bytes, String fileName);
  Future<Outcome<void>> clearAvatar();
  Future<Outcome<void>> changePassword(String current, String next);
  Future<Outcome<NotifySettings>> notifications();
  Future<Outcome<void>> saveNotifications(Map<String, Object?> patch);
  Future<Outcome<void>> testNotification();

  /// The date the widget key was made, or null if there is none.
  Future<Outcome<String?>> widgetKey();

  /// Makes a new key (the old one stops working) and returns it. It is shown once and never kept.
  Future<Outcome<String>> makeWidgetKey();
  Future<Outcome<void>> removeWidgetKey();
}

/// The account read from and written to the paired server.
class PairedAccount implements AccountService {
  PairedAccount(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  static const _offline = 'app.account_service.the_server_could_not_be_reached';

  /// Runs [run] with the device's client. Every failure becomes an [Outcome] with words for the reader.
  /// [wrong401] says a 401 here means "that was wrong" (a wrong password), not "this phone was unpaired",
  /// which is what [AppController.withClient] would take it for.
  Future<Outcome<T>> _call<T>(
    Future<T> Function(ApiClient c) run, {
    String? wrong401,
  }) async {
    try {
      if (wrong401 != null) {
        final c = _controller.authedClient();
        if (c == null) return const Outcome.fail('This phone is not paired.');
        try {
          return Outcome.ok(await run(c));
        } finally {
          c.close();
        }
      }
      final v = await _controller.withClient(run);
      if (v == null && !_controller.paired) {
        return Outcome.fail(tx('app.account_service.this_phone_is_not_paired'));
      }
      return Outcome.ok(v);
    } on ApiException catch (e) {
      if (wrong401 != null && e.failure == ApiFailure.unauthorised) {
        return Outcome.fail(wrong401);
      }
      return switch (e.failure) {
        ApiFailure.network || ApiFailure.timeout => Outcome.fail(tx(_offline)),
        ApiFailure.forbidden => Outcome.fail(
          tx('app.account_service.the_server_does_not_allow_that'),
        ),
        _ => Outcome.fail(
          e.detail.isEmpty
              ? tx('app.account_service.the_server_refused_that')
              : e.detail,
        ),
      };
    }
  }

  @override
  Future<Outcome<AccountInfo>> me() => _call((c) async {
    final j = await c.getJsonKept('/auth/me');
    if (j is! Map) {
      throw const ApiException(ApiFailure.badResponse, 'not an account');
    }
    return AccountInfo(
      username: '${j['username'] ?? ''}',
      avatar: '${j['avatar_path'] ?? ''}',
      mustChangePassword: j['must_change_password'] == true,
    );
  });

  @override
  Future<Outcome<void>> rename(String username) =>
      _call((c) => c.putJson('/auth/me', {'username': username}));

  @override
  Future<Outcome<String>> setAvatar(Uint8List bytes, String fileName) =>
      _call((c) async {
        final j = await c.postFile('/auth/me/avatar', 'file', bytes, fileName);
        return j is Map ? '${j['avatar_path'] ?? ''}' : '';
      });

  @override
  Future<Outcome<void>> clearAvatar() =>
      _call((c) => c.delete('/auth/me/avatar'));

  @override
  Future<Outcome<void>> changePassword(String current, String next) => _call(
    (c) => c.postJson('/auth/password', {'current': current, 'new': next}),
    wrong401: 'The current password is not right.',
  );

  @override
  Future<Outcome<NotifySettings>> notifications() => _call((c) async {
    final j = await c.getJsonKept('/auth/notifications');
    final s = j is Map && j['settings'] is Map ? j['settings'] as Map : {};
    return NotifySettings(
      pushoverUser: '${s['pushover_user'] ?? ''}',
      hasAppToken: j is Map && j['has_app_token'] == true,
      serverAppToken: j is Map && j['server_app_token'] == true,
      onDaily: s['on_daily'] == true,
      onImport: s['on_import'] == true,
      onFetch: s['on_fetch'] == true,
      onBackup: s['on_backup'] == true,
    );
  });

  @override
  Future<Outcome<void>> saveNotifications(Map<String, Object?> patch) =>
      _call((c) => c.putJson('/auth/notifications', patch));

  @override
  Future<Outcome<void>> testNotification() =>
      _call((c) => c.postJson('/auth/notifications/test', const {}));

  @override
  Future<Outcome<String?>> widgetKey() => _call((c) async {
    final j = await c.getJsonKept('/auth/widget-key');
    if (j is Map && j['exists'] == true) return '${j['created_at'] ?? ''}';
    return null;
  });

  @override
  Future<Outcome<String>> makeWidgetKey() => _call((c) async {
    final j = await c.postJson('/auth/widget-key', const {});
    return j is Map ? '${j['key'] ?? ''}' : '';
  });

  @override
  Future<Outcome<void>> removeWidgetKey() =>
      _call((c) => c.delete('/auth/widget-key'));
}

/// How many quotes a "context" of a quote shows around it: the number of lines before and after. A null half
/// follows the next rule up (the work's, then the reader's, then the built-in).
class ContextRule {
  const ContextRule({this.before, this.after});

  final int? before;
  final int? after;
}

/// The reader's rules for how much of the source is shown around a quote: one for everything, and one per work.
abstract class ContextRules {
  bool get available;

  /// The widest a rule may be (the server's ceiling).
  static const max = 15;

  Future<Outcome<ContextRule>> global();
  Future<Outcome<void>> setGlobal(ContextRule rule);

  /// [scope] is 'book' or 'movie', [id] the work's id on the server.
  Future<Outcome<ContextRule>> forWork(String scope, int id);

  /// [enforce] is '' (leave quotes alone), 'clamp' (bring wider adjusted ones down) or 'clear' (drop their
  /// adjustments). Returns how many quotes changed.
  Future<Outcome<int>> setForWork(
    String scope,
    int id,
    ContextRule rule, {
    String enforce = '',
  });
}

/// Gives the screens below it the [ContextRules], so a work's page can offer its own rule.
class ContextRulesScope extends InheritedWidget {
  const ContextRulesScope({
    super.key,
    required this.rules,
    required super.child,
  });

  final ContextRules? rules;

  static ContextRules? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContextRulesScope>()?.rules;

  @override
  bool updateShouldNotify(ContextRulesScope old) => old.rules != rules;
}

class PairedContextRules implements ContextRules {
  PairedContextRules(this._controller, {this.writes});

  final AppController _controller;

  /// Where a saved rule waits when the server cannot be reached.
  final OfflineWrites? writes;

  @override
  bool get available => _controller.paired;

  Future<Outcome<T>> _call<T>(Future<T> Function(ApiClient c) run) async {
    try {
      final v = await _controller.withClient(run);
      if (v == null && !_controller.paired) {
        return Outcome.fail(tx('app.account_service.this_phone_is_not_paired'));
      }
      return Outcome.ok(v);
    } on ApiException catch (e) {
      return Outcome.fail(
        e.failure == ApiFailure.network || e.failure == ApiFailure.timeout
            ? tx('app.account_service.the_server_could_not_be_reached')
            : (e.detail.isEmpty
                  ? tx('app.account_service.the_server_refused_that')
                  : e.detail),
      );
    }
  }

  ContextRule _rule(Object? j) => j is Map
      ? ContextRule(
          before: (j['before'] as num?)?.toInt(),
          after: (j['after'] as num?)?.toInt(),
        )
      : const ContextRule();

  Map<String, Object?> _body(ContextRule r, [String enforce = '']) => {
    'before': r.before,
    'after': r.after,
    if (enforce.isNotEmpty) 'enforce': enforce,
  };

  @override
  Future<Outcome<ContextRule>> global() =>
      _call((c) async => _rule(await c.getJson('/context-rules/global')));

  /// Saves [rule] at [path]: at once, or kept and shown on the copy of the rule the phone holds.
  Future<Outcome<Object?>> _save(String path, Map<String, Object?> body) async {
    final w = writes;
    if (w == null) return _call((c) => c.putJson(path, body));
    if (!_controller.paired) {
      return Outcome.fail(tx('app.account_service.this_phone_is_not_paired'));
    }
    try {
      final r = await w.write(
        'PUT',
        path,
        body,
        local: () => w.patchKept(
          path,
          (j) => {...(j is Map ? Map<String, Object?>.from(j) : {}), ...body},
        ),
      );
      return Outcome.ok(r.answer);
    } on ApiException catch (e) {
      return Outcome.fail(
        e.detail.isEmpty
            ? tx('app.account_service.the_server_refused_that')
            : e.detail,
      );
    }
  }

  @override
  Future<Outcome<void>> setGlobal(ContextRule rule) async {
    final r = await _save('/context-rules/global', _body(rule));
    return r.ok ? Outcome.ok(null) : Outcome.fail(r.error!);
  }

  @override
  Future<Outcome<ContextRule>> forWork(String scope, int id) =>
      _call((c) async => _rule(await c.getJson('/context-rules/$scope/$id')));

  @override
  Future<Outcome<int>> setForWork(
    String scope,
    int id,
    ContextRule rule, {
    String enforce = '',
  }) async {
    final r = await _save('/context-rules/$scope/$id', _body(rule, enforce));
    if (!r.ok) return Outcome.fail(r.error!);
    final j = r.value;
    return Outcome.ok(j is Map ? (j['changed'] as num?)?.toInt() ?? 0 : 0);
  }
}
