import 'package:flutter/material.dart';

import '../route_memory/route_package.dart';
import '../settings/app_settings.dart';
import 'outdoor_replay_page.dart';
import 'outdoor_route_store.dart';

class OutdoorRouteList extends StatefulWidget {
  const OutdoorRouteList({
    super.key,
    required this.settings,
    this.openStore,
    this.replayBuilder,
  });
  final AppSettings settings;
  final Widget Function(RouteSnapshot)? replayBuilder;
  final Future<OutdoorRouteStore> Function()? openStore;

  @override
  State<OutdoorRouteList> createState() => _OutdoorRouteListState();
}

class _OutdoorRouteListState extends State<OutdoorRouteList> {
  OutdoorRouteStore? _store;
  List<RouteLibraryEntry> _entries = const [];
  bool _busy = true, _error = false;
  String? _actionError;

  String tr(String zh, String en) =>
      widget.settings.language == AppLanguage.english ? en : zh;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_busy) setState(() => _busy = true);
    try {
      final store = _store ??=
          await (widget.openStore ?? OutdoorRouteStore.open)();
      final listing = await store.list();
      if (!mounted) return;
      setState(() {
        _entries = listing.routes;
        _error = false;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _busy = false;
        });
      }
    }
  }

  Future<void> _open(RouteLibraryEntry entry) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final snapshot = await _store!.read(entry);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              widget.replayBuilder?.call(snapshot) ??
              OutdoorReplayPage(settings: widget.settings, snapshot: snapshot),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError = tr('暫時未能開啟呢條路線。', 'Could not open this route.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(RouteLibraryEntry entry) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('刪除「${entry.name}」？', 'Delete "${entry.name}"?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('刪除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await _store!.delete(entry);
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError = tr('暫時未能確認刪除結果。', 'Could not confirm deletion.'),
        );
      }
    } finally {
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(
          tr('戶外路線', 'Outdoor routes'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      if (_actionError != null)
        Semantics(liveRegion: true, child: Text(_actionError!)),
      if (_busy && _entries.isEmpty)
        Text(tr('讀取戶外路線中…', 'Loading outdoor routes…'))
      else if (_error) ...[
        Text(
          tr(
            '暫時未能讀取戶外路線。請解鎖裝置再試。',
            'Could not load outdoor routes. Unlock the device and retry.',
          ),
        ),
        OutlinedButton(
          onPressed: _load,
          child: Text(tr('重試讀取戶外路線', 'Retry outdoor routes')),
        ),
      ] else if (_entries.isEmpty)
        Text(tr('未有已保存嘅戶外路線。', 'No saved outdoor routes.'))
      else
        for (final entry in _entries)
          Card(
            child: ListTile(
              title: Text(
                entry.name.isEmpty
                    ? tr('未能讀取名稱', 'Name unavailable')
                    : entry.name,
              ),
              subtitle: Text(
                entry.problem != null
                    ? tr('路線資料未能核對', 'Route data could not be verified')
                    : entry.activeVersion != null
                    ? tr(
                        '資料齊備可試行 · 待實地驗證',
                        'Ready to trial · field verification pending',
                      )
                    : tr('草稿', 'Draft'),
              ),
              onTap: _busy || entry.problem != null ? null : () => _open(entry),
              trailing: IconButton(
                tooltip: tr(
                  '刪除戶外路線「${entry.name}」',
                  'Delete outdoor route "${entry.name}"',
                ),
                onPressed: _busy ? null : () => _delete(entry),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
    ],
  );
}
