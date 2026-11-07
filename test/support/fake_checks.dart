import 'dart:typed_data';

import 'package:tippani/api/server_call.dart';
import 'package:tippani/checks/checks_service.dart';
import 'package:tippani/imports/import_picker.dart';
import 'package:tippani/imports/import_service.dart';

/// A file picker that hands back what the test gives it.
class FakePicker implements ImportPicker {
  ImportFile? next;
  bool tooBig = false;
  final asked = <List<String>?>[];

  @override
  Future<ImportFile?> pick({List<String>? extensions}) async {
    asked.add(extensions);
    if (tooBig) throw const ImportTooBig();
    return next;
  }
}

class FakeImports implements ImportService {
  FakeImports({this.available = true});

  @override
  bool available;

  Staging staging = Staging.empty;
  ImportOutcome outcome = const ImportOutcome(
    ok: true,
    source: 'kindle_clippings',
    staged: 2,
    works: 1,
    pending: 2,
  );
  final imported = <(String name, String? as)>[];
  final approved = <StagedSelector>[];
  final discarded = <StagedSelector>[];
  final edits = <(StagedSelector, StagedEdit)>[];
  final moves = <(StagedSelector, WorkChoice?, int?)>[];
  ApprovalOutcome approval = const ApprovalOutcome(ok: true, added: 1);
  ServerException? fail;
  List<WorkChoice> places = const [];

  void _check() {
    final f = fail;
    if (f != null) throw f;
  }

  @override
  Future<ImportOutcome> importFile(
    String name,
    Uint8List bytes, {
    String? as,
    void Function(int done, int total)? onProgress,
  }) async {
    _check();
    imported.add((name, as));
    onProgress?.call(1, 1);
    return outcome;
  }

  @override
  Future<int> pending() async {
    _check();
    return staging.pending;
  }

  @override
  Future<Staging> staged({
    int batchId = 0,
    int workId = 0,
    int limit = 0,
    int offset = 0,
  }) async {
    _check();
    return staging;
  }

  @override
  Future<ApprovalOutcome> approve(
    StagedSelector selection, {
    void Function(int done, int total)? onProgress,
  }) async {
    _check();
    approved.add(selection);
    onProgress?.call(1, 1);
    return approval;
  }

  @override
  Future<int> discard(StagedSelector selection) async {
    _check();
    discarded.add(selection);
    return 1;
  }

  @override
  Future<int> edit(StagedSelector selection, StagedEdit change) async {
    _check();
    edits.add((selection, change));
    return 1;
  }

  @override
  Future<void> move(
    StagedSelector selection, {
    WorkChoice? onto,
    int? mergeInto,
  }) async {
    _check();
    moves.add((selection, onto, mergeInto));
  }

  @override
  Future<List<WorkChoice>> destinations() async => places;
}

class FakeChecks implements ChecksService {
  FakeChecks({this.available = true});

  @override
  bool available;

  CleanupScan scan = const CleanupScan(
    rules: [],
    items: [],
    open: 0,
    ignored: 0,
    truncated: false,
  );
  CorrectionsScan corrected = CorrectionsScan.empty;
  List<LocatorProposal> located = const [];
  CheckCounts count = const CheckCounts();
  ServerException? fail;
  ChangeResult result = const ChangeResult(applied: 1);

  final accepted = <List<CleanupTarget>>[];
  final ignoredTargets = <(List<CleanupTarget>, bool)>[];
  final correctionsAccepted = <(String, List<Correction>, bool)>[];
  final correctionsIgnored = <List<Correction>>[];
  final locatorsAccepted = <(String, List<LocatorProposal>)>[];
  final locatorsIgnored = <List<LocatorProposal>>[];

  void _check() {
    final f = fail;
    if (f != null) throw f;
  }

  @override
  Future<CleanupScan> cleanup({bool ignored = false}) async {
    _check();
    return scan;
  }

  @override
  Future<ChangeResult> cleanupAccept(List<CleanupTarget> targets) async {
    accepted.add(targets);
    return result;
  }

  @override
  Future<ChangeResult> cleanupIgnore(
    List<CleanupTarget> targets, {
    required bool ignore,
  }) async {
    ignoredTargets.add((targets, ignore));
    return ChangeResult(ignored: targets.length);
  }

  @override
  Future<CorrectionsScan> corrections() async {
    _check();
    return corrected;
  }

  @override
  Future<ChangeResult> correctionsAccept(
    String bucket,
    List<Correction> items, {
    bool bulk = false,
  }) async {
    correctionsAccepted.add((bucket, items, bulk));
    return result;
  }

  @override
  Future<ChangeResult> correctionsIgnore(List<Correction> items) async {
    correctionsIgnored.add(items);
    return ChangeResult(ignored: items.length);
  }

  @override
  Future<List<LocatorProposal>> locators() async {
    _check();
    return located;
  }

  @override
  Future<ChangeResult> locatorsAccept(
    String bucket,
    List<LocatorProposal> items,
  ) async {
    locatorsAccepted.add((bucket, items));
    return result;
  }

  @override
  Future<ChangeResult> locatorsIgnore(List<LocatorProposal> items) async {
    locatorsIgnored.add(items);
    return ChangeResult(ignored: items.length);
  }

  @override
  Future<CheckCounts> counts() async {
    _check();
    return count;
  }
}
