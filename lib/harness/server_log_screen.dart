import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import 'log_screen.dart' show ShareText, shareThroughSheet;
import 'server_log.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

final _windows = <(String, Duration)>[
  (tx('settings.logs.range.hour.label'), Duration(hours: 1)),
  (tx('settings.logs.range.day.label'), Duration(days: 1)),
  (tx('settings.logs.range.week.label'), Duration(days: 7)),
  (tx('settings.logs.range.month.label'), Duration(days: 30)),
];

/// The Tippani SERVER's log, for an admin. It is not the app's log (that is this phone's own record, and
/// sits under App log): these are lines the server printed, one per request and one per event, kept there
/// for thirty days. It never goes into the app's log, and the app's lines never appear here.
class ServerLogScreen extends StatefulWidget {
  const ServerLogScreen({
    super.key,
    required this.controller,
    this.share = shareThroughSheet,
  });

  final AppController controller;
  final ShareText share;

  @override
  State<ServerLogScreen> createState() => _ServerLogScreenState();
}

class _ServerLogScreenState extends State<ServerLogScreen> {
  ServerLogFilter _filter = const ServerLogFilter();
  final _query = TextEditingController();
  final _lines = <ServerLogLine>[];
  bool _more = false;
  bool _loading = false;
  int? _from;
  int? _upto;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      _loading = true;
      _problem = null;
      if (reset) {
        _lines.clear();
        _from = null;
        _upto = null;
      }
    });
    try {
      final page = await widget.controller.withClient(
        (c) => fetchServerLog(
          c,
          _filter,
          before: reset || _lines.isEmpty ? null : _lines.last.id,
          from: reset ? null : _from,
          upto: reset ? null : _upto,
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (page == null) {
          _problem = context.tr('app.server_log.this_phone_is_not_paired_with');
          return;
        }
        _lines.addAll(page.lines);
        _more = page.more;
        _from = page.from;
        _upto = page.upto;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = switch (e.failure) {
          ApiFailure.forbidden => "Only an admin can read the server's log. This phone is paired as someone who is not one.",
          ApiFailure.unauthorised => context.tr(
            'app.board_service.the_server_no_longer_accepts_this',
          ),
          ApiFailure.network || ApiFailure.timeout => context.tr(
            'app.server_log.could_not_reach_the_server',
          ),
          _ =>
            'The server could not give its log (${e.detail.isEmpty ? e.failure.name : e.detail}).',
        };
      });
    }
  }

  void _apply(ServerLogFilter next) {
    _filter = next;
    _load(reset: true);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: serverLogText(_lines)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('app.server_log.server_log_copied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.server_log.server_log')),
        actions: [
          IconButton(
            tooltip: context.tr('app.server_log.refresh'),
            icon: const Icon(Ti.refresh),
            onPressed: _loading ? null : () => _load(reset: true),
          ),
          IconButton(
            tooltip: context.tr('common.action.copy.label'),
            icon: const Icon(Ti.copy),
            onPressed: _lines.isEmpty ? null : _copy,
          ),
          IconButton(
            tooltip: context.tr('common.action.share.label'),
            icon: const Icon(Ti.share),
            onPressed: _lines.isEmpty
                ? null
                : () =>
                      widget.share(serverLogText(_lines), 'Tippani server log'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              context.tr('app.server_log.the_server_s_own_log_not'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              textCapitalization: TextCapitalization.none,
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _apply(_filter.copyWith(query: v)),
              decoration: InputDecoration(
                isDense: true,
                labelText: context.tr('app.server_log.search_the_log'),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: context.tr('common.help.topbar.search.term'),
                  icon: const Icon(Ti.search),
                  onPressed: () => _apply(_filter.copyWith(query: _query.text)),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                for (final (label, span) in _windows)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter.since == span,
                      onSelected: (_) => _apply(_filter.copyWith(since: span)),
                    ),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final level in serverLogLevels)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(level),
                      selected: _filter.levels.contains(level),
                      onSelected: (on) {
                        final next = {..._filter.levels};
                        on ? next.add(level) : next.remove(level);
                        // an empty set would ask for "every level" on the server, which is not what an
                        // all-clear row of chips says, so the last one stays on
                        if (next.isNotEmpty) {
                          _apply(_filter.copyWith(levels: next));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 8),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_problem!, style: TextStyle(color: scheme.error)),
            ),
          Expanded(
            child: _lines.isEmpty && !_loading && _problem == null
                ? Center(child: Text(context.tr('settings.logs.empty')))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _lines.length + 1,
                    itemBuilder: (context, i) {
                      if (i == _lines.length) {
                        if (_loading) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: LinearProgressIndicator(),
                          );
                        }
                        if (!_more) return const SizedBox.shrink();
                        return TextButton(
                          onPressed: () => _load(reset: false),
                          child: Text(
                            context.tr('app.server_log.load_older_lines'),
                          ),
                        );
                      }
                      final l = _lines[i];
                      final colour = switch (l.level) {
                        'error' => scheme.error,
                        'warn' => scheme.tertiary,
                        _ => null,
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText(
                          '${l.time.toIso8601String().split('.').first}Z ${l.level}${l.code.isEmpty ? '' : ' ${l.code}'}  ${l.line}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: colour,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
