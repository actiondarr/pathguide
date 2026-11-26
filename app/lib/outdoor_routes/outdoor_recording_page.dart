import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../navigation/navigation_models.dart';
import '../navigation/navigation_services.dart';
import '../route_memory/route_audio_note_dialog.dart';
import '../route_memory/route_package.dart';
import '../settings/app_settings.dart';
import '../tts/announcer.dart';
import 'outdoor_recorder.dart';
import 'outdoor_route_page_state.dart';
import 'outdoor_route_store.dart';
import 'outdoor_track.dart';

class OutdoorRecordingPage extends StatefulWidget {
  const OutdoorRecordingPage({
    super.key,
    required this.settings,
    this.location,
    this.speaker,
    this.clock,
    this.wallClock,
    this.openStore,
  });

  final AppSettings settings;
  final LocationService? location;
  final Speaker? speaker;
  final Duration Function()? clock;
  final DateTime Function()? wallClock;
  final Future<OutdoorRouteStore> Function()? openStore;

  @override
  State<OutdoorRecordingPage> createState() => _OutdoorRecordingPageState();
}

class _OutdoorRecordingPageState
    extends OutdoorRoutePageState<OutdoorRecordingPage> {
  final _recorder = OutdoorRecorder();
  final _id = OutdoorRouteStore.newId();
  final _name = TextEditingController();
  final _markFocus = FocusNode();
  final _markButton = GlobalKey();
  final _markMessage = ValueNotifier<String?>(null);
  OutdoorTrack? _track;
  String? _saveError;
  bool _panelOpen = false,
      _noteOpen = false,
      _saving = false,
      _confirmingExit = false,
      _exiting = false;

  @override
  AppSettings get settings => widget.settings;
  @override
  LocationService? get locationOverride => widget.location;
  @override
  Speaker? get speakerOverride => widget.speaker;
  @override
  Duration Function()? get clockOverride => widget.clock;
  @override
  DateTime Function()? get wallOverride => widget.wallClock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && foreground) _start();
    });
  }

  void _start() {
    _change(() => _recorder.resume(now), announce: true);
    unawaited(setLocating(true, restart: true));
  }

  String get _status => switch (_recorder.state) {
    OutdoorRecordingState.waiting => tr(
      '等緊新鮮同精確嘅 GPS 定位。請喺開揚位置稍等。',
      'Waiting for a fresh, precise GPS fix. Wait in an open area.',
    ),
    OutdoorRecordingState.recording => tr(
      'GPS 定位已確認，錄製中。',
      'GPS fix confirmed. Recording.',
    ),
    OutdoorRecordingState.weak => tr(
      'GPS 定位不足。已保留可信位置，等緊定位恢復。',
      'GPS is too weak. The last reliable position was kept. Waiting for a new fix.',
    ),
    OutdoorRecordingState.permission => tr(
      '定位權限或精確定位未開啟。請檢查系統設定，再按繼續。',
      'Check location and Precise Location in Settings, then choose Resume.',
    ),
    OutdoorRecordingState.paused => tr('錄製已暫停。', 'Recording paused.'),
    OutdoorRecordingState.background => tr(
      '錄製曾因離開前景中斷。',
      'Recording was interrupted in the background.',
    ),
    OutdoorRecordingState.capacity => tr(
      '錄製已達容量上限。請結束並保存草稿。',
      'Recording limit reached. Finish to save a draft.',
    ),
  };

  void _change(VoidCallback action, {bool announce = false}) {
    if (!mounted || _track != null || _exiting) return;
    final previous = _recorder.state;
    setState(action);
    if (_recorder.atCapacity) unawaited(setLocating(false));
    if ((announce || previous != _recorder.state) && !_noteOpen) {
      unawaited(say(_status));
    }
  }

  @override
  void onFix(LocationFix fix) =>
      _change(() => _recorder.fix(fix, now, wallTime));
  @override
  void onLocationError(bool permission) =>
      _change(() => _recorder.unavailable(permission: permission));
  @override
  void onPulse() => _change(() => _recorder.tick(now));

  @override
  void onForegroundChanged(bool enabled) {
    if (_track != null || _exiting) return;
    if (!enabled) {
      _change(_recorder.background);
    } else if (!_recorder.manuallyPaused && !_recorder.atCapacity) {
      _start();
    }
  }

  void _pauseResume() {
    if (_recorder.manuallyPaused ||
        _recorder.state == OutdoorRecordingState.permission) {
      _start();
      return;
    }
    _change(() => _recorder.pause(now));
    unawaited(setLocating(false));
  }

  String _title(OutdoorMarkKind kind) => tr(kind.zh, kind.en);

  void _markFeedback(String message) {
    _markMessage.value = message;
    unawaited(say(message));
  }

  void _applyMark(
    OutdoorMarkKind kind, {
    OutdoorMark? position,
    String? text,
    RouteAudioNote? audio,
  }) {
    final mark = position ?? _recorder.makeMark(kind, now);
    final result = mark == null || !foreground
        ? OutdoorMarkResult.noPosition
        : _recorder.addMark(mark, now, text: text, audio: audio);
    setState(() {});
    _markFeedback(switch (result) {
      OutdoorMarkResult.added => tr(
        '已加路標，${_title(kind)}。',
        'Landmark added, ${_title(kind)}.',
      ),
      OutdoorMarkResult.noPosition => tr(
        '未能標記位置，請等候精確定位再試。',
        'Could not mark the position. Wait for a precise fix and try again.',
      ),
      OutdoorMarkResult.capacity => tr(
        '路標或錄音容量已滿。',
        'Landmark or audio limit reached.',
      ),
      OutdoorMarkResult.invalid => tr(
        '備註未能保存，請核對輸入。',
        'Could not save the note. Check the entry.',
      ),
    });
  }

  Future<void> _editNote(BuildContext sheet, OutdoorMarkKind kind) async {
    if (_noteOpen) return;
    final position = _recorder.makeMark(kind, now);
    if (position == null) {
      _applyMark(kind);
      return;
    }
    _noteOpen = true;
    await stopSpeech();
    if (!mounted || !sheet.mounted || !foreground) {
      _noteOpen = false;
      return;
    }
    if (kind == OutdoorMarkKind.audio) {
      RouteAudioNote? audio;
      await showDialog<void>(
        context: sheet,
        builder: (_) => RouteAudioNoteDialog(
          markName: tr('目前位置', 'Current position'),
          initial: null,
          translate: tr,
          apply: (clip) {
            if (clip == null) return false;
            audio = clip;
            return true;
          },
        ),
      );
      _noteOpen = false;
      if (mounted && _panelOpen && audio != null) {
        _applyMark(kind, position: position, audio: audio);
      }
      return;
    }
    var text = '';
    final note = await showDialog<String>(
      context: sheet,
      builder: (ctx) => AlertDialog(
        title: Text(tr('文字備註', 'Text note')),
        scrollable: true,
        content: TextField(
          autofocus: true,
          maxLength: RoutePoint.maxTextNoteLength,
          maxLines: 3,
          onChanged: (value) => text = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, text.trim()),
            child: Text(tr('加文字路標', 'Add text landmark')),
          ),
        ],
      ),
    );
    _noteOpen = false;
    if (mounted && _panelOpen && note != null) {
      _applyMark(kind, position: position, text: note);
    }
  }

  Future<void> _openMarks() async {
    if (_panelOpen) return;
    _panelOpen = true;
    _markMessage.value = null;
    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      useSafeArea: true,
      settings: const RouteSettings(name: 'outdoor-marks'),
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  tr('加路標', 'Add landmark'),
                  style: Theme.of(sheet).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: _markMessage,
                builder: (context, message, _) =>
                    Text(message ?? tr('選擇要記低嘅提示。', 'Choose a cue to record.'))
                        .withLiveStatus(liveFallback(context)),
              ),
              _group(
                tr('設施', 'Facilities'),
                OutdoorMarkKind.values.take(8),
                sheet,
              ),
              _group(
                tr('方向', 'Directions'),
                OutdoorMarkKind.values.skip(8).take(6),
                sheet,
              ),
              _group(tr('備註', 'Notes'), [
                if (RouteNoteAudio.supported) OutdoorMarkKind.audio,
                OutdoorMarkKind.text,
              ], sheet),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                onPressed: () {
                  final removed = _recorder.undo();
                  setState(() {});
                  _markFeedback(
                    removed == null
                        ? tr('未有路標可以撤銷。', 'There is no landmark to undo.')
                        : tr(
                            '已撤銷上個路標，${_title(removed.kind)}。',
                            'Last landmark removed, ${_title(removed.kind)}.',
                          ),
                  );
                },
                label: Text(tr('撤銷上個路標', 'Undo last landmark')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(tr('返回錄路', 'Back to recording')),
              ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    _panelOpen = false;
    if (!mounted) return;
    _markFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && MediaQuery.accessibleNavigationOf(context)) {
        _markButton.currentContext?.findRenderObject()?.sendSemanticsEvent(
          const FocusSemanticEvent(),
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _group(
    String title,
    Iterable<OutdoorMarkKind> kinds,
    BuildContext sheet,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title)),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                MediaQuery.textScalerOf(context).scale(14) >= 19 ||
                    constraints.maxWidth < 320
                ? 2
                : 4;
            final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final kind in kinds)
                  SizedBox(
                    width: width,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 64),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        if (kind == OutdoorMarkKind.audio ||
                            kind == OutdoorMarkKind.text) {
                          unawaited(_editNote(sheet, kind));
                        } else {
                          _applyMark(kind);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icons[kind], size: 22),
                          const SizedBox(height: 4),
                          Text(_title(kind), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  void _finish() {
    if (_track != null) return;
    final track = _recorder.finish(now);
    setState(() => _track = track);
    unawaited(setLocating(false));
    unawaited(say(outdoorDraftLabel(track.draftReason, english)));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (_saving || _track == null) return;
    if (name.isEmpty || name.length > 120) {
      final message = tr(
        '請輸入最多 120 字嘅路線名稱。',
        'Enter a route name of up to 120 characters.',
      );
      setState(() => _saveError = message);
      unawaited(say(message));
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final store = await (widget.openStore ?? OutdoorRouteStore.open)();
      final saved = await store.save(_id, name, _track!);
      if (!mounted) return;
      final message = saved.published
          ? tr(
              '已保存「${saved.document.name}」，可喺我的路線試行。',
              'Saved "${saved.document.name}". Find it in My routes.',
            )
          : tr(
              '已保存草稿「${saved.document.name}」。',
              'Saved draft "${saved.document.name}".',
            );
      Navigator.pop(context, message);
    } catch (error) {
      if (!mounted) return;
      final message =
          error is RouteStoreFailure && error.problem == RouteProblem.capacity
          ? tr(
              '本機儲存空間不足。錄製仍然保留，可以再試。',
              'Local storage is full. The recording is retained for retry.',
            )
          : tr(
              '暫時未能保存。錄製仍然保留，可以再試。',
              'Could not save. The recording is retained for retry.',
            );
      setState(() {
        _saving = false;
        _saveError = message;
      });
      unawaited(say(message));
    }
  }

  Future<void> _back() async {
    if (_saving || _exiting || _confirmingExit) return;
    if (_recorder.pointCount != 0 || _track != null) {
      _confirmingExit = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('離開並放棄今次錄製？', 'Leave and discard this recording?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('返回錄製', 'Keep recording')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('放棄錄製', 'Discard recording')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      _confirmingExit = false;
      if (discard != true) return;
    }
    _exiting = true;
    await setLocating(false);
    if (mounted) Navigator.pop(context);
  }

  List<Widget> _summary() {
    final speed = _recorder.speed, accuracy = _recorder.accuracy;
    return [
      Text(_status).withLiveStatus(liveFallback(context)),
      const SizedBox(height: 16),
      Text(
        tr('錄路摘要', 'Recording summary'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Semantics(
        container: true,
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  '累計距離 ${outdoorDistanceLabel(_recorder.distance, english)}',
                  'Distance ${outdoorDistanceLabel(_recorder.distance, english)}',
                ),
              ),
              Text(
                tr(
                  '錄製時間 ${outdoorDurationLabel(_recorder.elapsedAt(now), english)}',
                  'Recording time ${outdoorDurationLabel(_recorder.elapsedAt(now), english)}',
                ),
              ),
              Text(
                speed == null
                    ? tr('速度暫未能確定', 'Speed unavailable')
                    : tr(
                        '目前速度 ${(speed * 3.6).toStringAsFixed(1)} 公里／小時',
                        'Speed ${(speed * 3.6).toStringAsFixed(1)} kilometres per hour',
                      ),
              ),
              Text(
                accuracy == null
                    ? tr('GPS 定位精度暫未能確定', 'GPS accuracy unavailable')
                    : tr(
                        'GPS 定位精度 ${accuracy.round()} 米',
                        'GPS accuracy ${accuracy.round()} metres',
                      ),
              ),
              Text(
                tr(
                  '軌跡點 ${_recorder.pointCount}',
                  'Track points ${_recorder.pointCount}',
                ),
              ),
              Text(
                tr(
                  '路標 ${_recorder.markCount}',
                  'Landmarks ${_recorder.markCount}',
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _recordingActions() => [
    FilledButton.icon(
      key: _markButton,
      focusNode: _markFocus,
      onPressed: _openMarks,
      icon: const Icon(Icons.add_location_alt_outlined),
      label: Text(tr('加路標', 'Add landmark')),
    ),
    OutlinedButton(
      onPressed: _recorder.atCapacity ? null : _pauseResume,
      child: Text(
        _recorder.manuallyPaused ||
                _recorder.state == OutdoorRecordingState.permission
            ? tr('繼續', 'Resume')
            : tr('暫停', 'Pause'),
      ),
    ),
    FilledButton(
      onPressed: _finish,
      child: Text(tr('結束並保存', 'Finish and save')),
    ),
  ];

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_back());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _saving ? () {} : _back),
        title: Text(
          _track == null
              ? tr('錄製戶外路線', 'Record outdoor route')
              : tr('保存戶外路線', 'Save outdoor route'),
        ),
      ),
      bottomNavigationBar: _track == null
          ? SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _recordingActions(),
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: _track == null
              ? _summary()
              : [
                  Text(outdoorDraftLabel(_track!.draftReason, english)),
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: tr('路線名稱', 'Route name'),
                    ),
                  ),
                  if (_saveError != null)
                    Text(_saveError!).withLiveStatus(liveFallback(context)),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(
                      _saving
                          ? tr('保存中', 'Saving')
                          : _saveError == null
                          ? tr('保存路線', 'Save route')
                          : tr('再試保存', 'Retry save'),
                    ),
                  ),
                ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _name.dispose();
    _markFocus.dispose();
    _markMessage.dispose();
    super.dispose();
  }

  static const _icons = {
    OutdoorMarkKind.steps: Icons.stairs,
    OutdoorMarkKind.junction: Icons.alt_route,
    OutdoorMarkKind.door: Icons.door_front_door_outlined,
    OutdoorMarkKind.toilet: Icons.wc,
    OutdoorMarkKind.subway: Icons.directions_walk,
    OutdoorMarkKind.footbridge: Icons.hiking,
    OutdoorMarkKind.busStop: Icons.directions_bus,
    OutdoorMarkKind.parking: Icons.local_parking,
    OutdoorMarkKind.turnLeft: Icons.turn_left,
    OutdoorMarkKind.aheadLeft: Icons.north_west,
    OutdoorMarkKind.aheadRight: Icons.north_east,
    OutdoorMarkKind.turnRight: Icons.turn_right,
    OutdoorMarkKind.bypassLeft: Icons.turn_slight_left,
    OutdoorMarkKind.bypassRight: Icons.turn_slight_right,
    OutdoorMarkKind.audio: Icons.mic_none,
    OutdoorMarkKind.text: Icons.notes,
  };
}
