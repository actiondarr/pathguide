import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../feedback/feedback_page.dart';
import '../feedback/feedback_trace.dart';
import '../l10n/app_language.dart';
import '../overlay/box_painter.dart';
import '../scene/live_scene_controller.dart';
import '../scene/live_scene_signal.dart';
import '../scene/scene_backend.dart';
import '../settings/prompt_settings.dart';
import '../tts/flutter_tts_speaker.dart';
import '../tts/speech_coordinator.dart';
import '../vision/detection.dart';
import '../vision/platform_vision.dart';
import '../vision/recognition_session.dart';
import '../vision/result_summary.dart';
import '../vision/vision_preview.dart';
import '../vision/vision_source.dart';

import '../navigation/navigation_models.dart';
import '../navigation/navigation_services.dart';
import '../route_memory/route_audio_note_dialog.dart';
import '../route_memory/route_package.dart';
import '../settings/app_settings.dart';
import '../tts/announcer.dart';
import 'outdoor_replay.dart';
import 'outdoor_route_page_state.dart';
import 'outdoor_track.dart';

class OutdoorReplayPage extends StatefulWidget {
  const OutdoorReplayPage({
    super.key,
    required this.settings,
    required this.snapshot,
    this.location,
    this.speaker,
    this.clock,
    this.wallClock,
    this.visionFactory,
    this.preview,
  });

  final AppSettings settings;
  final RouteSnapshot snapshot;
  final LocationService? location;
  final Speaker? speaker;
  final Duration Function()? clock;
  final DateTime Function()? wallClock;
  final VisionSource Function()? visionFactory;
  final Widget? preview;

  @override
  State<OutdoorReplayPage> createState() => _OutdoorReplayPageState();
}

class _OutdoorReplayPageState extends OutdoorRoutePageState<OutdoorReplayPage> {
  late final _track = widget.snapshot.document.outdoor!;
  OutdoorReplay? _replay;
  final _audio = RouteNoteAudio();
  OutdoorMark? _playing;
  String? _audioError;
  int _audioEpoch = 0;
  bool _leaving = false;
  bool _recognize = true, _sceneStarting = false, _sceneRequested = false;
  String? _fallbackAnnouncement;
  int _sceneEpoch = 0;
  ({String text, int ticket})? _navigationSubmission;
  String? _cameraError, _pendingCameraNotice;
  StreamSubscription<LiveSceneUpdate>? _sceneUpdates;
  Future<void> _sceneWork = Future.value();
  late final _feedback = FeedbackTrace(settings, 'outdoorReplay');
  late final _voice = SpeechCoordinator(_ReplayOutput(this));
  late final _scene = LiveSceneController(
    capture: _captureScene,
    backend: FirebaseSceneBackend(),
    speaker: _ReplaySceneOutput(this),
    detail: () => settings.sceneDetail,
  )..addListener(_refresh);
  late final _vision = RecognitionSession(
    createSource: widget.visionFactory ?? PlatformVision.new,
    announcer: Announcer(
      speaker: _voice.channel(SpeechChannel.environment),
      minSpeakScore: settings.speakThreshold,
    ),
    speakObjects: () => settings.objectSpeech && _playing == null,
  )..addListener(_visionChanged);

  bool get _cameraSupported =>
      widget.visionFactory != null ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  bool get _sceneSupported =>
      _cameraSupported &&
      const bool.fromEnvironment('SCENE_DESCRIPTION_ENABLED');
  bool get _active =>
      foreground &&
      !_leaving &&
      _replay != null &&
      _replay!.state != OutdoorReplayState.paused &&
      _replay!.state != OutdoorReplayState.arrived;

  @override
  void initState() {
    super.initState();
    settings.addListener(_settingsChanged);
  }

  void _refresh() {
    if (mounted && !_leaving) setState(() {});
  }

  void _settingsChanged() {
    _vision.announcer.minSpeakScore = settings.speakThreshold;
    if (!settings.objectSpeech) {
      unawaited(_voice.stopOwned(SpeechChannel.environment));
    }
    _refresh();
  }

  void _visionChanged() {
    if (!_vision.ready && _sceneRequested) unawaited(_stopScene());
    final status = _vision.status;
    if (_vision.requested &&
        !_vision.ready &&
        status != '正在準備辨識…' &&
        _cameraError != status) {
      _cameraError = status;
      _pendingCameraNotice = status;
      _announceCameraNotice();
    }
    if (_vision.ready || !_vision.requested) {
      _cameraError = _pendingCameraNotice = null;
    }
    _refresh();
  }

  void _announceCameraNotice() {
    final status = _pendingCameraNotice;
    if (status == null || !_active || _voice.owner != null) return;
    _pendingCameraNotice = null;
    unawaited(
      _voice
          .speakStatus(
            appText(status, settings.language),
            isCurrent: () =>
                _active &&
                _vision.requested &&
                !_vision.ready &&
                _vision.status == status,
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _syncVision() async {
    final run = _cameraSupported && _active && _recognize;
    if (!run && _sceneRequested) unawaited(_stopScene());
    await _vision.setRunning(run);
  }

  Future<Uint8List?> _captureScene() async {
    final source = _vision.source, epoch = _sceneEpoch;
    if (!_active ||
        !_sceneRequested ||
        !_vision.ready ||
        source is! PlatformVision) {
      return null;
    }
    final bytes = await source.captureSceneFrame();
    return _active &&
            _sceneRequested &&
            epoch == _sceneEpoch &&
            identical(source, _vision.source)
        ? bytes
        : null;
  }

  Future<void> _stopScene() {
    _sceneRequested = false;
    _sceneEpoch++;
    _scene.setAvailable(false);
    final source = _vision.source;
    final subscription = _sceneUpdates;
    _sceneUpdates = null;
    final cancel = subscription?.cancel();
    return _sceneWork = _sceneWork
        .then((_) async {
          await cancel;
          if (source is PlatformVision &&
              identical(source, _vision.source) &&
              _vision.ready) {
            try {
              await source.setSceneObservation(false);
            } catch (_) {}
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _setScene(bool enabled) async {
    if (!enabled) {
      await _stopScene();
      return;
    }
    final source = _vision.source;
    if (_sceneStarting ||
        !_active ||
        !_vision.ready ||
        source is! PlatformVision) {
      return;
    }
    setState(() => _sceneStarting = true);
    final epoch = _sceneEpoch;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('開啟場景描述？', 'Enable scene descriptions?')),
          content: Text(
            tr(
              '環境有明顯變化時，會從現有相機取一張相片交 Qwen 分析，受帳號試驗額度及費用限制。可以隨時關閉。',
              'When the scene changes, a photo from the active camera is sent to Qwen for analysis, subject to your trial allowance and cost limit. You can turn it off at any time.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('同意並開始', 'Agree and start')),
            ),
          ],
        ),
      );
      bool current() =>
          mounted &&
          _active &&
          epoch == _sceneEpoch &&
          _vision.ready &&
          identical(source, _vision.source);
      if (accepted != true || !current()) return;
      _sceneRequested = true;
      await (_sceneWork = _sceneWork
          .then((_) async {
            if (!current()) return;
            _sceneUpdates = source.sceneUpdates.listen(
              (event) {
                if (current() && _sceneRequested) {
                  _scene.observe(event.signal, sourceIssue: event.issue);
                }
              },
              onError: (Object _) {
                if (current() && _sceneRequested) {
                  unawaited(_stopScene());
                  _scene.preparationFailed('scene_stream');
                }
              },
            );
            await source.setSceneObservation(true);
            if (!current()) return;
            _scene.setAvailable(true);
            _scene.setAutomatic(true);
            unawaited(_scene.refreshStatus());
          })
          .catchError((Object _) {
            if (current()) {
              unawaited(_stopScene());
              _scene.preparationFailed('not_ready');
            }
          }));
    } finally {
      _sceneStarting = false;
      _refresh();
    }
  }

  @override
  void onSpeechSubmitted(String message, {required bool voiceOver}) {
    final submission = _navigationSubmission;
    _navigationSubmission = null;
    _feedback.submitted(
      message,
      voiceOver: voiceOver,
      ticket: submission?.text == message ? submission!.ticket : null,
    );
  }

  @override
  void onSpeechPlayback(TtsPlaybackEvent event) => _feedback.playback(event);

  @override
  Future<void> say(String message, {bool Function()? isCurrent}) async {
    final text = appText(message, settings.language);
    final ticket = _feedback.queue(text);
    try {
      await _voice.speakNavigation(
        text,
        isCurrent: () =>
            mounted && foreground && !_leaving && (isCurrent?.call() ?? true),
        onEvent: (event) {
          if (event == SceneSpeechEvent.submitted) {
            _navigationSubmission = (text: text, ticket: ticket);
          } else if (event == SceneSpeechEvent.cancelled) {
            _feedback.event('cancelled', {'utterance': ticket, 'text': text});
          }
        },
      );
    } catch (_) {}
  }

  Future<void> _output(String text) async {
    if (!mounted || !foreground || _leaving) return;
    if (liveFallback(context)) {
      setState(() => _fallbackAnnouncement = text);
      onSpeechSubmitted(text, voiceOver: true);
      return;
    }
    await super.say(text);
  }

  void _repeat() {
    final replay = _replay!;
    setState(() => replay.tick(now));
    if (_playing != null) unawaited(_stopAudio());
    final turn = replay.nextTurn, state = replay.state;
    final next = replay.nextLandmark;
    unawaited(
      say(
        turn != null
            ? _turnText(turn)
            : next != null
            ? tr(
                '下一個已錄路標係${_markName(next)}。',
                'Next recorded landmark is ${_markName(next)}.',
              )
            : _status(state),
        isCurrent: () =>
            replay.state == state && (turn == null || replay.nextTurn == turn),
      ),
    );
  }

  Widget _cameraControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        title: Text(tr('即時物件辨識', 'Live object recognition')),
        value: _recognize,
        onChanged: !_active
            ? null
            : (enabled) {
                setState(() => _recognize = enabled);
                unawaited(_syncVision());
              },
      ),
      if (_recognize) Text(appText(_vision.status, settings.language)),
      if (_vision.ready && _vision.source != null) ...[
        SizedBox(
          height: 235,
          child: LayoutBuilder(
            builder: (_, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                widget.preview ?? const VisionPreview(),
                CustomPaint(
                  painter: DetectionBoxPainter(
                    mapped: mapDetectionsToScreen(
                      detections: _vision.frame?.detections ?? [],
                      fit: DisplayFit.contain(
                        frame: _vision.source!.frameSize,
                        view: constraints.biggest,
                      ),
                    ),
                    showLabels: false,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          appText(
            resultSummary(
              _vision.frame?.detections ?? [],
              minScore: settings.speakThreshold,
            ),
            settings.language,
          ),
        ),
      ],
    ],
  );

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

  String _status(OutdoorReplayState state) => switch (state) {
    OutdoorReplayState.waiting => tr(
      '等緊精確定位，核對實錄路線。',
      'Waiting for a precise fix to check the recorded route.',
    ),
    OutdoorReplayState.wrongStart => tr(
      '目前未喺錄製起點。請返回當日錄製嘅起點再試。',
      'You are away from the recorded start. Return there and try again.',
    ),
    OutdoorReplayState.checkingDirection => tr(
      '已接近起點。喺安全情況下，沿當日錄製方向行幾步，App 會核對方向。',
      'Near the start. When safe, take a few steps in the recorded direction to check it.',
    ),
    OutdoorReplayState.reverse => tr(
      '你可能沿反方向行緊。請停低，核對當日錄製方向。',
      'You may be walking in reverse. Stop and check the recorded direction.',
    ),
    OutdoorReplayState.following => tr(
      '已對上實錄軌跡，沿錄製方向重行。',
      'Matched the recorded track. Follow the recorded direction.',
    ),
    OutdoorReplayState.offRoute => tr(
      '你可能已偏離實錄路線。請停低，核對所在位置。',
      'You may be off the recorded route. Stop and check your location.',
    ),
    OutdoorReplayState.ambiguous => tr(
      '附近路段或入口未能分辨。請停低核對位置，再試定位。',
      'Nearby paths or entrances cannot be distinguished. Stop, check your position and retry.',
    ),
    OutdoorReplayState.weak => tr(
      '定位暫時不足。請停低，等候精確定位或再試。',
      'Location is uncertain. Stop and wait for a precise fix or retry.',
    ),
    OutdoorReplayState.permission => tr(
      '請喺系統設定開啟使用 App 期間嘅精確定位，再試定位。',
      'Allow Precise Location while using the app in Settings, then retry.',
    ),
    OutdoorReplayState.paused => tr(
      '重行已暫停。按繼續重新核對位置。',
      'Replay paused. Resume to check your position again.',
    ),
    OutdoorReplayState.nearEnd => tr(
      '已接近實錄終點，定位未能分辨入口。請核對你當日到達嘅位置。',
      'Near the recorded endpoint. GPS cannot identify the entrance. Check where the recording ended.',
    ),
    OutdoorReplayState.arrived => tr(
      '你已確認到達，重行結束。',
      'Arrival confirmed. Replay finished.',
    ),
  };

  String _markName(OutdoorMark mark) => tr(mark.kind.zh, mark.kind.en);
  String _turnText(({int metres, bool left}) turn) {
    final direction = turn.left
        ? tr('左轉', 'turn left')
        : tr('右轉', 'turn right');
    return turn.metres <= 3
        ? tr(
            '實錄路線喺附近$direction。',
            'The recorded route turns ${turn.left ? 'left' : 'right'} nearby.',
          )
        : tr(
            '實錄路線約 ${turn.metres} 米後$direction。',
            'The recorded route goes ${turn.metres} metres, then $direction.',
          );
  }

  void _change(VoidCallback action, {bool announce = false}) {
    final replay = _replay!;
    final previous = replay.state, cue = replay.cue;
    final previousTurn = replay.nextTurn;
    setState(action);
    if (settings.feedbackEnabled && previous != replay.state) {
      _feedback.context = {
        ..._feedback.context,
        'state': replay.state.name,
        'segment': replay.matchedSegment,
      };
      if (replay.state == OutdoorReplayState.weak ||
          replay.state == OutdoorReplayState.paused ||
          replay.state == OutdoorReplayState.permission) {
        _feedback.context = {'state': replay.state.name};
      }
      _feedback.event('state');
    }
    if (previousTurn != null && replay.nextTurn == null) {
      unawaited(_voice.stopOwned(SpeechChannel.navigation));
    }
    if (_playing != null &&
        (previous != replay.state ||
            (replay.nextTurn != null && previousTurn == null) ||
            !replay.nearbyMarks.contains(_playing))) {
      unawaited(_stopAudio());
    }
    if (!announce && previous == replay.state && cue == replay.cue) return;
    final newMarks = replay.takeNewMarks();
    final turn = replay.nextTurn;
    final message = [
      if (announce || previous != replay.state) _status(replay.state),
      if (turn != null &&
          (previousTurn == null || previousTurn.left != turn.left))
        _turnText(turn),
      if (newMarks.isNotEmpty)
        tr(
          '附近路標，${newMarks.map(_markName).join('、')}。',
          'Nearby landmarks, ${newMarks.map(_markName).join(', ')}.',
        ),
    ].join(' ');
    if (message.isNotEmpty && _playing == null) {
      final state = replay.state;
      unawaited(
        say(
          message,
          isCurrent: () =>
              replay.state == state &&
              (turn == null || replay.nextTurn?.left == turn.left) &&
              newMarks.every(replay.nearbyMarks.contains),
        ),
      );
    }
  }

  void _begin() {
    _replay ??= OutdoorReplay(_track);
    _change(() => _replay!.suspend(OutdoorReplayState.waiting), announce: true);
    unawaited(setLocating(true, restart: true));
    unawaited(_syncVision());
  }

  @override
  void onFix(LocationFix fix) => _change(() {
    _replay!.fix(fix, now, wallTime);
    if (settings.feedbackEnabled) {
      _feedback.context = {
        if (usableOutdoorFix(fix, now, wallTime)) ...{
          'lat': fix.coordinate.latitude,
          'lng': fix.coordinate.longitude,
          'accuracy': fix.accuracy,
        },
        'state': _replay!.state.name,
        'segment': _replay!.matchedSegment,
      };
      _feedback.event('location');
    }
  });
  @override
  void onLocationError(bool permission) => _change(
    () => _replay!.suspend(
      permission ? OutdoorReplayState.permission : OutdoorReplayState.weak,
    ),
  );
  @override
  void onPulse() {
    if (_replay != null) _change(() => _replay!.tick(now));
    _announceCameraNotice();
  }

  @override
  void onForegroundChanged(bool enabled) {
    if (!enabled && _replay != null) {
      _sceneEpoch++;
      _change(() => _replay!.suspend(OutdoorReplayState.paused));
      unawaited(_syncVision());
      _feedback.clear();
    }
  }

  void _pause() {
    _change(() => _replay!.suspend(OutdoorReplayState.paused));
    unawaited(setLocating(false));
    unawaited(_syncVision());
  }

  void _confirmEnd() {
    _change(() => _replay!.confirmEnd(now));
    if (_replay!.state == OutdoorReplayState.arrived) {
      unawaited(setLocating(false));
      unawaited(_syncVision());
    }
  }

  Future<void> _stopAudio() {
    ++_audioEpoch;
    _playing = null;
    return _audio.cancel();
  }

  Future<void> _playAudio(OutdoorMark mark) async {
    if (_playing != null ||
        !foreground ||
        !_replay!.nearbyMarks.contains(mark)) {
      return;
    }
    final ticket = ++_audioEpoch;
    setState(() {
      _playing = mark;
      _audioError = null;
    });
    await _voice.stop();
    if (!mounted || ticket != _audioEpoch || !foreground) return;
    try {
      await _audio.play(mark.audio!);
    } catch (_) {
      if (mounted && ticket == _audioEpoch) {
        setState(
          () => _audioError = tr('未能播放錄音備註。', 'Could not play the audio note.'),
        );
        await _audio.cancel();
      }
    } finally {
      if (mounted && ticket == _audioEpoch) setState(() => _playing = null);
    }
  }

  Future<void> _back() async {
    if (_leaving) return;
    _leaving = true;
    await Future.wait([
      setLocating(false),
      _voice.stop(),
      _syncVision(),
      if (_playing != null) _stopAudio(),
    ]);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _leaving = true;
    settings.removeListener(_settingsChanged);
    _vision.removeListener(_visionChanged);
    _scene.removeListener(_refresh);
    if (_sceneRequested) unawaited(_stopScene());
    _scene.dispose();
    _vision.dispose();
    unawaited(_voice.stop());
    _feedback.dispose();
    if (_playing != null) unawaited(_stopAudio());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final replay = _replay, state = _replay?.state;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: Text(widget.snapshot.document.name),
          actions: [
            if (replay != null) PromptSettingsButton(settings: settings),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(outdoorDraftLabel(_track.draftReason, english)),
              Text(
                tr(
                  '${outdoorDistanceLabel(_track.distance, english)}，${_track.pointCount} 個軌跡點，${_track.marks.length} 個路標',
                  '${outdoorDistanceLabel(_track.distance, english)}, ${_track.pointCount} track points, ${_track.marks.length} landmarks',
                ),
              ),
              const SizedBox(height: 16),
              if (replay == null &&
                  widget.snapshot.published &&
                  _track.draftReason == null)
                FilledButton(
                  onPressed: _begin,
                  child: Text(tr('開始重行', 'Start replay')),
                ),
              if (replay != null && state != null) ...[
                Text(_status(state)),
                if (_fallbackAnnouncement != null && liveFallback(context))
                  Semantics(
                    liveRegion: true,
                    child: Text(_fallbackAnnouncement!),
                  ),
                if (state != OutdoorReplayState.arrived) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _repeat,
                      icon: const Icon(Icons.replay),
                      label: Text(tr('重聽下一步', 'Repeat next step')),
                    ),
                  ),
                  if (_sceneSupported) ...[
                    SwitchListTile(
                      title: Text(tr('場景描述', 'Scene descriptions')),
                      value: _sceneRequested && _scene.automatic,
                      onChanged:
                          _sceneRequested ||
                              (_active && _vision.ready && !_sceneStarting)
                          ? _setScene
                          : null,
                    ),
                    if (_sceneRequested || _scene.preparationCode != null)
                      Text(appText(_scene.status, settings.language)),
                  ],
                  if (settings.feedbackEnabled)
                    CaptureFeedbackButton(trace: _feedback),
                  if (_cameraSupported) _cameraControls(),
                ],
                if (state == OutdoorReplayState.following ||
                    state == OutdoorReplayState.nearEnd)
                  Text(
                    tr(
                      '餘下約 ${outdoorDistanceLabel(replay.remaining, english)}',
                      'About ${outdoorDistanceLabel(replay.remaining, english)} remaining',
                    ),
                  ),
                if (replay.nextLandmark case final next?)
                  Text(
                    tr(
                      '下一個已錄路標：${_markName(next)}',
                      'Next recorded landmark: ${_markName(next)}',
                    ),
                  ),
                if (replay.nextTurn case final turn?) Text(_turnText(turn)),
                for (final mark in replay.nearbyMarks)
                  if (mark.text case final note?) ...[
                    Text(note),
                    if (!MediaQuery.accessibleNavigationOf(context))
                      OutlinedButton(
                        onPressed: _playing == null
                            ? () => say(
                                note,
                                isCurrent: () =>
                                    replay.nearbyMarks.contains(mark),
                              )
                            : null,
                        child: Text(tr('讀出文字備註', 'Read text note')),
                      ),
                  ] else if (mark.audio != null)
                    if (RouteNoteAudio.supported)
                      OutlinedButton(
                        onPressed: _playing == mark
                            ? () => setState(() => unawaited(_stopAudio()))
                            : _playing == null
                            ? () => _playAudio(mark)
                            : null,
                        child: Text(
                          _playing == mark
                              ? tr('停止播放', 'Stop playback')
                              : tr('播放錄音備註', 'Play audio note'),
                        ),
                      )
                    else
                      const SizedBox.shrink()
                  else
                    Text(
                      tr(
                        '路標，${_markName(mark)}',
                        'Landmark, ${_markName(mark)}',
                      ),
                    ),
                if (_audioError != null) Text(_audioError!),
                if (replay.canConfirmEnd)
                  FilledButton(
                    onPressed: _confirmEnd,
                    child: Text(
                      tr(
                        '我已核對終點，結束重行',
                        'I have checked the endpoint. Finish replay.',
                      ),
                    ),
                  ),
                if (state != OutdoorReplayState.arrived) ...[
                  OutlinedButton(
                    onPressed: _back,
                    child: Text(tr('結束重行', 'End replay')),
                  ),
                  OutlinedButton(
                    onPressed: state == OutdoorReplayState.paused
                        ? _begin
                        : _pause,
                    child: Text(
                      state == OutdoorReplayState.paused
                          ? tr('繼續重行', 'Resume replay')
                          : tr('暫停', 'Pause'),
                    ),
                  ),
                ],
                if (const {
                  OutdoorReplayState.wrongStart,
                  OutdoorReplayState.reverse,
                  OutdoorReplayState.offRoute,
                  OutdoorReplayState.ambiguous,
                  OutdoorReplayState.weak,
                  OutdoorReplayState.permission,
                }.contains(state))
                  FilledButton(
                    onPressed: _begin,
                    child: Text(tr('再試定位', 'Retry location')),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplayOutput implements Speaker {
  _ReplayOutput(this.page);
  final _OutdoorReplayPageState page;
  @override
  Future<void> speak(String text) =>
      page._output(appText(text, page.settings.language));
  @override
  Future<void> stop() => page.stopSpeech();
  @override
  Future<List<String>> languages() async => const [];
}

class _ReplaySceneOutput implements Speaker {
  _ReplaySceneOutput(this.page);
  final _OutdoorReplayPageState page;
  @override
  Future<void> speak(String text) => page._voice.speakScene(
    text,
    isCurrent: () =>
        page._active &&
        page._sceneRequested &&
        page._playing == null &&
        page._scene.canDeliverText(text),
    onEvent: page._scene.speechEvent,
  );
  @override
  Future<void> stop() => page._voice.stopOwned(SpeechChannel.scene);
  @override
  Future<List<String>> languages() async => const [];
}
