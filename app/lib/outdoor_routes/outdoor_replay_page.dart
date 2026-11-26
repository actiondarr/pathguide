import 'dart:async';

import 'package:flutter/material.dart';

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
  });

  final AppSettings settings;
  final RouteSnapshot snapshot;
  final LocationService? location;
  final Speaker? speaker;
  final Duration Function()? clock;
  final DateTime Function()? wallClock;

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
    if (_playing != null && !replay.nearbyMarks.contains(_playing)) {
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
              (turn == null || replay.nextTurn != null) &&
              newMarks.every(replay.nearbyMarks.contains),
        ),
      );
    }
  }

  void _begin() {
    _replay ??= OutdoorReplay(_track);
    _change(() => _replay!.suspend(OutdoorReplayState.waiting), announce: true);
    unawaited(setLocating(true, restart: true));
  }

  @override
  void onFix(LocationFix fix) =>
      _change(() => _replay!.fix(fix, now, wallTime));
  @override
  void onLocationError(bool permission) => _change(
    () => _replay!.suspend(
      permission ? OutdoorReplayState.permission : OutdoorReplayState.weak,
    ),
  );
  @override
  void onPulse() {
    if (_replay != null) _change(() => _replay!.tick(now));
  }

  @override
  void onForegroundChanged(bool enabled) {
    if (!enabled && _replay != null) {
      _change(() => _replay!.suspend(OutdoorReplayState.paused));
    }
  }

  void _pause() {
    _change(() => _replay!.suspend(OutdoorReplayState.paused));
    unawaited(setLocating(false));
  }

  void _confirmEnd() {
    _change(() => _replay!.confirmEnd(now));
    if (_replay!.state == OutdoorReplayState.arrived) {
      unawaited(setLocating(false));
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
    await stopSpeech();
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
      stopSpeech(),
      if (_playing != null) _stopAudio(),
    ]);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
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
                Semantics(
                  liveRegion: liveFallback(context),
                  child: Text(_status(state)),
                ),
                if (state == OutdoorReplayState.following ||
                    state == OutdoorReplayState.nearEnd)
                  Text(
                    tr(
                      '餘下約 ${outdoorDistanceLabel(replay.remaining, english)}',
                      'About ${outdoorDistanceLabel(replay.remaining, english)} remaining',
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
                if (state != OutdoorReplayState.arrived)
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
