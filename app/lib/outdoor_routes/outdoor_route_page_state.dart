import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../navigation/navigation_models.dart';
import '../navigation/navigation_services.dart';
import '../navigation/platform_navigation.dart';
import '../settings/app_settings.dart';
import '../tts/announcer.dart';
import '../tts/flutter_tts_speaker.dart';
import 'outdoor_track.dart';

abstract class OutdoorRoutePageState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  AppSettings get settings;
  LocationService? get locationOverride;
  Speaker? get speakerOverride => null;
  Duration Function()? get clockOverride => null;
  DateTime Function()? get wallOverride => null;

  late final _location =
      locationOverride ??
      NativeNavigationServices(MapProvider.apple, recordedTrack: true);
  late final _speaker =
      speakerOverride ??
      FlutterTtsSpeaker(
        language: settings.language,
        speechRate: settings.speechSpeed.rate,
      );
  Duration get now => clockOverride?.call() ?? navigationNow();
  DateTime get wallTime => wallOverride?.call() ?? DateTime.now().toUtc();
  bool get foreground => _foreground;
  bool get english => settings.language == AppLanguage.english;
  String tr(String zh, String en) => english ? en : zh;
  bool liveFallback(BuildContext context) =>
      MediaQuery.accessibleNavigationOf(context) &&
      !MediaQuery.supportsAnnounceOf(context);

  bool _foreground = true;
  bool _wantLocation = false;
  bool _nativeStarted = false;
  bool _closing = false;
  DateTime? _captureStartedAt;
  int _locationEpoch = 0;
  int _speechEpoch = 0;
  late final Timer _heartbeat;
  Future<void> _locationQueue = Future.value();
  StreamSubscription<LocationFix>? _updates;

  void onFix(LocationFix fix);
  void onLocationError(bool permission);
  void onPulse();
  void onForegroundChanged(bool enabled);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground =
        life != AppLifecycleState.hidden &&
        life != AppLifecycleState.paused &&
        life != AppLifecycleState.detached;
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && foreground) onPulse();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission sheets also cause inactive. Actual background invalidates the session.
    if (state == AppLifecycleState.inactive) return;
    final enabled = state == AppLifecycleState.resumed;
    if (_foreground == enabled) return;
    _foreground = enabled;
    if (!enabled) {
      unawaited(setLocating(false));
      unawaited(stopSpeech());
    }
    onForegroundChanged(enabled);
  }

  Future<void> setLocating(bool enabled, {bool restart = false}) {
    if (!restart && enabled == _wantLocation) return _locationQueue;
    _wantLocation = enabled;
    final ticket = ++_locationEpoch;
    bool current() =>
        mounted &&
        foreground &&
        !_closing &&
        ticket == _locationEpoch &&
        _wantLocation;
    _captureStartedAt = null;
    _locationQueue = _locationQueue.then((_) async {
      if (_nativeStarted) {
        _nativeStarted = false;
        await Future.wait([_location.stop(), _location.keepAwake(false)]);
      }
      if (!enabled || !current()) return;
      _updates ??= _location.updates.listen(
        _receiveFix,
        onError: _locationFailed,
      );
      _captureStartedAt = wallTime;
      _nativeStarted = true;
      try {
        await _location.start();
        if (current()) await _location.keepAwake(true);
      } catch (error) {
        if (current()) _locationFailed(error);
      }
    });
    return _locationQueue;
  }

  void _receiveFix(LocationFix fix) {
    final started = _captureStartedAt, sample = fix.sampledAt;
    if (mounted &&
        foreground &&
        started != null &&
        sample != null &&
        !sample.isBefore(started.subtract(const Duration(milliseconds: 1)))) {
      onFix(fix);
    }
  }

  void _locationFailed(Object error) {
    if (!mounted || !foreground || _captureStartedAt == null) return;
    final code = switch (error) {
      NavigationFailure() => error.code,
      PlatformException() => error.code,
      _ => '',
    };
    final permission =
        code == 'location_denied' ||
        code == 'location_disabled' ||
        code == 'location_permission_changed';
    onLocationError(permission);
    if (permission) unawaited(setLocating(false));
  }

  Future<void> closeLocating() async {
    if (_closing) return;
    _closing = true;
    try {
      await setLocating(false);
    } finally {
      await _updates?.cancel();
      _updates = null;
    }
  }

  Future<void> stopSpeech() async {
    ++_speechEpoch;
    await _speaker.stop();
  }

  Future<void> say(String message, {bool Function()? isCurrent}) async {
    if (!mounted || !foreground || isCurrent?.call() == false) return;
    final ticket = ++_speechEpoch;
    try {
      if (MediaQuery.accessibleNavigationOf(context)) {
        if (MediaQuery.supportsAnnounceOf(context)) {
          await SemanticsService.sendAnnouncement(
            View.of(context),
            message,
            Directionality.of(context),
          );
        }
        return;
      }
      await _speaker.stop();
      if (mounted &&
          foreground &&
          ticket == _speechEpoch &&
          isCurrent?.call() != false) {
        await _speaker.speak(message);
      }
    } catch (_) {
      // The current status remains accessible in the page.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat.cancel();
    unawaited(closeLocating());
    unawaited(stopSpeech());
    super.dispose();
  }
}

String outdoorDistanceLabel(double metres, bool english) => metres < 1000
    ? english
          ? '${metres.round()} metres'
          : '${metres.round()} 米'
    : english
    ? '${(metres / 1000).toStringAsFixed(2)} kilometres'
    : '${(metres / 1000).toStringAsFixed(2)} 公里';

String outdoorDurationLabel(Duration duration, bool english) {
  final seconds = duration.inSeconds.remainder(60);
  final minutes = duration.inMinutes.remainder(60);
  final hours = duration.inHours;
  final hour = hours == 0
      ? ''
      : english
      ? '$hours hours, '
      : '$hours 小時 ';
  return english
      ? '$hour$minutes minutes, $seconds seconds'
      : '$hour$minutes 分 $seconds 秒';
}

String outdoorDraftLabel(
  OutdoorDraftReason? reason,
  bool english,
) => switch (reason) {
  OutdoorDraftReason.noStart =>
    english ? 'Draft. No reliable starting fix.' : '草稿。未取得可信嘅起點定位。',
  OutdoorDraftReason.singlePoint =>
    english ? 'Draft. Only one track point was accepted.' : '草稿。只記錄到起點一個軌跡點。',
  OutdoorDraftReason.gap =>
    english ? 'Draft. There is a gap in the recorded track.' : '草稿。錄製軌跡有缺口。',
  OutdoorDraftReason.shortTrack =>
    english
        ? 'Draft. The continuous track is too short to check walking direction.'
        : '草稿。連續軌跡太短，未能核對行進方向。',
  OutdoorDraftReason.capacity =>
    english
        ? 'Draft. The recording reached its storage limit.'
        : '草稿。錄製已達容量上限。',
  null =>
    english ? 'Ready to trial. Field verification pending.' : '資料齊備可試行。仍待實地驗證。',
};

extension OutdoorStatusText on Text {
  Widget withLiveStatus(bool enabled) =>
      Semantics(liveRegion: enabled, child: this);
}
