import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../harness/app_log.dart';
import 'pull_sync.dart';
import 'push_sync.dart';

/// Keeps the phone and the paired server in step without the reader asking: on open, when the app comes back to
/// the front, a few seconds after the library is changed, and every few minutes while it is open. Each run sends
/// what is only here (works first), then brings down and sends changes and applies deletions (see [PullSync]).
///
/// It never stops to ask. A quote or work changed on both sides is left alone and counted in [conflicts]; the
/// reader settles those from the Sync conflicts screen whenever they like, and the next run finds any that are
/// still open again.
///
/// A run that fails (no network, a sleeping server) is tried again after 30 seconds, then 1, 2 and 5 minutes. A
/// server that no longer accepts the phone is not retried until the pairing changes.
class AutoSync extends ChangeNotifier with WidgetsBindingObserver {
  AutoSync({
    required this._push,
    required this._pull,
    required this._controller,
    this._log,
    this.interval = const Duration(minutes: 3),
    this.debounce = const Duration(seconds: 5),
    this.firstRetry = const Duration(seconds: 30),
    this.longestRetry = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PushSync _push;
  final PullSync _pull;
  final AppController _controller;
  final AppLog? _log;
  final DateTime Function() _clock;

  /// How often a run is started while the app is open and nothing else has triggered one.
  final Duration interval;

  /// How long after a change to the library the run starts (so a burst of edits is one run).
  final Duration debounce;
  final Duration firstRetry;
  final Duration longestRetry;

  static const _prefKey = 'auto_sync';

  bool _enabled = true;
  bool _syncing = false;
  bool _started = false;
  DateTime? _lastSynced;
  PullResult? _lastResult;
  ApiFailure? _failure;
  int _failures = 0;
  DateTime? _nextAllowed;
  DateTime? _lastAttempt;
  List<SyncConflict> _conflicts = const [];
  Timer? _ticker;
  Timer? _soon;
  StreamSubscription<void>? _changes;
  bool _wasPaired = false;

  /// Whether runs start by themselves. The reader can still sync by hand.
  bool get enabled => _enabled;
  bool get syncing => _syncing;
  DateTime? get lastSynced => _lastSynced;
  PullResult? get lastResult => _lastResult;

  /// Why the last run stopped early, or null if it finished.
  ApiFailure? get failure => _failure;

  /// What changed on both sides and still waits for the reader.
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts);

  /// Begins watching. [changes] is the library's change stream. Reads whether the reader turned this off.
  Future<void> start(Stream<void>? changes) async {
    if (_started) return;
    _started = true;
    try {
      final p = await SharedPreferences.getInstance();
      _enabled = p.getBool(_prefKey) ?? true;
    } on Object {
      // keep the default
    }
    _changes = changes?.listen((_) => scheduleSoon());
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    WidgetsBinding.instance.addObserver(this);
    _wasPaired = _controller.paired;
    _controller.addListener(_pairingChanged);
    notifyListeners();
    scheduleSoon();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, on);
    } on Object {
      // the choice holds for this run
    }
    if (on) scheduleSoon();
  }

  void _pairingChanged() {
    final now = _controller.paired;
    if (now && !_wasPaired) {
      _failures = 0;
      _nextAllowed = null;
      scheduleSoon();
    }
    _wasPaired = now;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final last = _lastAttempt;
      if (last == null ||
          _clock().difference(last) > const Duration(seconds: 20)) {
        _nextAllowed = null;
        scheduleSoon();
      }
    }
  }

  /// Asks for a run shortly, folding repeated asks into one.
  void scheduleSoon() {
    if (!_enabled || _syncing) return;
    _soon?.cancel();
    _soon = Timer(debounce, () {
      _soon = null;
      _maybe();
    });
  }

  void _tick() {
    final last = _lastAttempt;
    if (last == null || _clock().difference(last) >= interval) _maybe();
  }

  void _maybe() {
    if (!_enabled || _syncing || !_controller.paired) return;
    if (_failure == ApiFailure.unauthorised) return;
    final next = _nextAllowed;
    if (next != null && _clock().isBefore(next)) return;
    syncNow();
  }

  /// Runs now (from the Sync screen, or by itself) and returns what it did. Null when no server is paired. A
  /// call while a run is going joins it.
  Future<PullResult?> syncNow() async {
    if (!_controller.paired) return null;
    if (_syncing) return _pull.sync();
    _syncing = true;
    _lastAttempt = _clock();
    notifyListeners();
    PullResult result;
    try {
      final sent = await _push.push();
      result = sent.stoppedBy != null
          ? PullResult(stoppedBy: sent.stoppedBy)
          : await _pull.sync();
    } on Object catch (e) {
      _log?.warn('automatic sync failed: $e');
      result = const PullResult(stoppedBy: ApiFailure.server);
    }
    _lastResult = result;
    _failure = result.stoppedBy;
    if (result.stoppedBy == null) {
      _lastSynced = _clock();
      _failures = 0;
      _nextAllowed = null;
      _conflicts = result.conflicts;
    } else {
      _failures++;
      var wait = firstRetry;
      for (var i = 1; i < _failures && wait < longestRetry; i++) {
        wait *= 2;
      }
      if (wait > longestRetry) wait = longestRetry;
      _nextAllowed = _clock().add(wait);
      // What the run found before it stopped still counts.
      if (result.conflicts.isNotEmpty) _conflicts = result.conflicts;
    }
    _syncing = false;
    notifyListeners();
    return result;
  }

  /// Settles one conflict the reader's way. Null when it worked (it is then off the list), or a plain-words
  /// problem and it stays.
  Future<String?> resolve(SyncConflict c, ConflictSide side) async {
    final problem = await _pull.resolve(c, side);
    if (problem == null) resolved(c);
    return problem;
  }

  /// Takes a settled conflict off the list.
  void resolved(SyncConflict c) {
    _conflicts = [
      for (final x in _conflicts)
        if (x != c) x,
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _soon?.cancel();
    _changes?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _controller.removeListener(_pairingChanged);
    }
    super.dispose();
  }
}
