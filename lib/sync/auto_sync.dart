import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../harness/app_log.dart';
import 'pull_sync.dart';
import 'push_sync.dart';

/// Whether the phone has a network, and when that changes. An interface so a test can stand in for the phone.
abstract class Connectivity {
  /// True each time the phone gains a network (not each time it loses one).
  Stream<void> get regained;
}

/// The phone's own connectivity, through `connectivity_plus`.
class DeviceConnectivity implements Connectivity {
  DeviceConnectivity();

  @override
  Stream<void> get regained {
    var online = true;
    return plus.Connectivity().onConnectivityChanged
        .map((r) => r.any((x) => x != plus.ConnectivityResult.none))
        .where((now) {
          final gained = now && !online;
          online = now;
          return gained;
        })
        .map((_) {});
  }
}

/// Keeps the phone and the paired server in step without the reader asking, with as little traffic as will do
/// (ADR-0019):
///
/// - **On every change** to the library: a few seconds after it (so a burst of edits is one run), the change is
///   sent and the server is read.
/// - **Once a day**: when the app opens, when it comes back to the front, when the phone gets a network again, or
///   (if the app is simply left on) once a day passes, a run is made if none has finished in the last day.
/// - A change that could not be sent (no network, a sleeping server) is remembered, and goes at the next of
///   those: the next change, the app opening or coming back, or the network returning. There is no timer that
///   retries.
///
/// A run sends what is only here (works first), then reads the server, brings down and sends changes and applies
/// deletions (see [PullSync]). It never stops to ask: a quote or work changed on both sides is left alone and
/// counted in [conflicts] for the Sync conflicts screen.
class AutoSync extends ChangeNotifier with WidgetsBindingObserver {
  AutoSync({
    required this._push,
    required this._pull,
    required this._controller,
    this._log,
    this.debounce = const Duration(seconds: 4),
    this.dailyEvery = const Duration(hours: 24),
    this.checkEvery = const Duration(minutes: 30),
    this.after = const [],
    Connectivity? connectivity,
    DateTime Function()? clock,
  }) : _connectivity = connectivity ?? DeviceConnectivity(),
       _clock = clock ?? DateTime.now;

  final PushSync _push;
  final PullSync _pull;
  final AppController _controller;
  final AppLog? _log;
  final Connectivity _connectivity;
  final DateTime Function() _clock;

  /// How long after a change to the library the run starts.
  final Duration debounce;

  /// How long a finished run holds off the daily run.
  final Duration dailyEvery;

  /// How often an app left open looks at whether a day has passed (this makes no request).
  final Duration checkEvery;

  /// Other things that wait for the server (anthologies edited with no server), sent when a run found the server
  /// answering. A failure in one is its own and does not stop the run.
  final List<Future<Object?> Function()> after;

  static const _enabledKey = 'auto_sync';
  static const _lastKey = 'auto_sync_last';
  static const _dirtyKey = 'auto_sync_dirty';

  bool _enabled = true;
  bool _syncing = false;
  bool _started = false;
  bool _dirty = false;
  DateTime? _lastSynced;
  PullResult? _lastResult;
  ApiFailure? _failure;
  List<SyncConflict> _conflicts = const [];
  Timer? _ticker;
  Timer? _soon;
  StreamSubscription<void>? _changes;
  StreamSubscription<void>? _network;
  bool _wasPaired = false;

  /// Whether runs start by themselves. The reader can still sync by hand.
  bool get enabled => _enabled;
  bool get syncing => _syncing;
  DateTime? get lastSynced => _lastSynced;
  PullResult? get lastResult => _lastResult;

  /// Whether a change is waiting to be sent.
  bool get dirty => _dirty;

  /// Why the last run stopped early, or null if it finished.
  ApiFailure? get failure => _failure;

  /// What changed on both sides and still waits for the reader.
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts);

  /// Whether a day has passed since a run last finished (or none ever has).
  bool get dailyDue {
    final last = _lastSynced;
    return last == null || _clock().difference(last) >= dailyEvery;
  }

  /// Begins watching. [changes] is the library's change stream. Reads what was kept of the last run.
  Future<void> start(Stream<void>? changes) async {
    if (_started) return;
    _started = true;
    try {
      final p = await SharedPreferences.getInstance();
      _enabled = p.getBool(_enabledKey) ?? true;
      _dirty = p.getBool(_dirtyKey) ?? false;
      final ms = p.getInt(_lastKey);
      if (ms != null) _lastSynced = DateTime.fromMillisecondsSinceEpoch(ms);
    } on Object {
      // keep the defaults
    }
    _changes = changes?.listen((_) => _changed());
    _network = _connectivity.regained.listen((_) => _opportunity());
    _ticker = Timer.periodic(checkEvery, (_) {
      // Only a day after a run that finished: a phone that has never managed one waits for a change, the app
      // opening or coming back, or the network, rather than trying every half hour.
      if (_lastSynced != null && dailyDue) _opportunity();
    });
    WidgetsBinding.instance.addObserver(this);
    _wasPaired = _controller.paired;
    _controller.addListener(_pairingChanged);
    notifyListeners();
    _opportunity();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_enabledKey, on);
    } on Object {
      // the choice holds for this run
    }
    if (on) _opportunity();
  }

  void _pairingChanged() {
    final now = _controller.paired;
    if (now && !_wasPaired) {
      _failure = null;
      _markDirty(true);
      scheduleSoon();
    }
    _wasPaired = now;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _opportunity();
  }

  /// Counts the changes announced, so a run can tell whether one arrived while it was running.
  int _changeCount = 0;

  void _changed() {
    _changeCount++;
    _markDirty(true);
    scheduleSoon();
  }

  /// Something other than the library waits for the server (an anthology change, a setting made offline): a
  /// run is due even though no quote changed, so it goes up when the server next answers.
  void queueChanged() => _changed();

  Future<void> _markDirty(bool v) async {
    if (_dirty == v) return;
    _dirty = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_dirtyKey, v);
    } on Object {
      // remembered for this run
    }
  }

  /// A moment when a run may be due: the app opening or coming back, the network returning, or a day passing while
  /// it is open. Runs if a day has passed or a change is waiting; otherwise does nothing.
  void _opportunity() {
    if (dailyDue || _dirty) scheduleSoon();
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

  void _maybe() {
    if (!_enabled || _syncing || !_controller.paired) return;
    // A server that no longer accepts the phone is not asked again until the pairing changes.
    if (_failure == ApiFailure.unauthorised) return;
    syncNow();
  }

  /// Runs now (from the Sync screen, or by itself) and returns what it did. Null when no server is paired. A
  /// call while a run is going joins it.
  Future<PullResult?> syncNow() async {
    if (!_controller.paired) return null;
    if (_syncing) return _pull.sync();
    _syncing = true;
    final changesAtStart = _changeCount;
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
      for (final send in after) {
        try {
          await send();
        } on Object catch (e) {
          _log?.warn('sending what waited for the server failed: $e');
        }
      }
      _lastSynced = _clock();
      _conflicts = result.conflicts;
      // a change announced while this run was out is not covered by it: it stays due
      if (_changeCount == changesAtStart) {
        await _markDirty(false);
      } else {
        scheduleSoon();
      }
      try {
        final p = await SharedPreferences.getInstance();
        await p.setInt(_lastKey, _lastSynced!.millisecondsSinceEpoch);
      } on Object {
        // remembered for this run
      }
    } else {
      // Whatever was waiting is still waiting: it goes at the next change, opening, or network.
      await _markDirty(true);
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
    _network?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _controller.removeListener(_pairingChanged);
    }
    super.dispose();
  }
}
