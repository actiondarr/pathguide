import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tts/announcer.dart';
import 'scene_backend.dart';
import 'live_scene_signal.dart';

/// Change-triggered cloud descriptions borrowed from the active camera.
/// No timer uploads, camera ownership, image retention or paid retries.
class LiveSceneController extends ChangeNotifier {
  LiveSceneController({
    required this.capture,
    required this.backend,
    required this.speaker,
    DateTime Function()? clock,
    this.cooldown = const Duration(seconds: 45),
    this.stableFor = const Duration(milliseconds: 1200),
    this.maxSessionAttempts = 3,
  }) : _clock = clock ?? DateTime.now;
  final Future<Uint8List?> Function() capture;
  final SceneBackend backend;
  final Speaker speaker;
  final DateTime Function() _clock;
  final Duration cooldown, stableFor;
  final int maxSessionAttempts;
  bool available = false,
      automatic = false,
      busy = false,
      speaking = false,
      _disposed = false;
  int attempts = 0, _generation = 0;
  String status = '場景分析未啟用', failure = '';
  String? text;
  SceneMetrics? metrics;
  double estimatedUsd = 0;
  bool usageUnknown = false;
  LiveSceneSignal? _latest, _stable, _baseline, _evidence;
  DateTime? _received, _stableSince, _lastAttempt;
  String? _previousFullText;
  Timer? _freshness, _expiry;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get _fresh =>
      _received != null &&
      _clock().difference(_received!) <= const Duration(seconds: 1);
  bool get stable =>
      _fresh &&
      _stableSince != null &&
      _clock().difference(_stableSince!) >= stableFor;
  bool get canDescribe =>
      available &&
      stable &&
      !busy &&
      attempts < maxSessionAttempts &&
      (_lastAttempt == null || _clock().difference(_lastAttempt!) >= cooldown);
  bool get _changed =>
      _baseline == null ||
      (_latest != null &&
          (_baseline!.difference(_latest!) >= 0.12 ||
              _baseline!.angle(_latest!) >= 15));

  void setAvailable(bool value) {
    if (_disposed) return;
    available = value;
    if (!value) {
      automatic = false;
      _latest = _stable = _baseline = null;
      _previousFullText = null;
      _stableSince = _received = null;
      _freshness?.cancel();
      invalidate();
      status = '場景分析已暫停；繼續辨識後可手動啟動。';
    } else {
      status = '保持手機穩定，準備場景分析。';
    }
    _notify();
  }

  void setAutomatic(bool value) {
    if (_disposed) return;
    automatic =
        value && available && attempts < maxSessionAttempts && !usageUnknown;
    if (!automatic) invalidate();
    if (automatic) {
      _baseline = null;
      _previousFullText = null;
    }
    status = automatic ? '已開啟自動場景分析，環境有重要變化且穩定後才取相。' : '自動場景分析已關閉。';
    _notify();
  }

  /// Explicit interruption: no automatic restart after overlays/background.
  void interrupt() {
    automatic = false;
    invalidate();
    _notify();
  }

  void invalidate() {
    ++_generation;
    _expiry?.cancel();
    if (text != null || busy || speaking) {
      unawaited(speaker.stop().catchError((Object _) {}));
    }
    text = null;
    _evidence = null;
    status = '場景已改變或已取消，舊描述已作廢。';
    _notify();
  }

  void observe(LiveSceneSignal? signal) {
    if (_disposed || !available) return;
    if (signal == null ||
        (_latest != null && signal.sequence <= _latest!.sequence)) {
      _stable = null;
      _stableSince = null;
      invalidate();
      status = '未取得可靠的新畫面或轉向資訊，場景分析暫停。';
      _notify();
      return;
    }
    final now = _clock();
    _latest = signal;
    _received = now;
    _freshness?.cancel();
    _freshness = Timer(const Duration(seconds: 1), () {
      if (_disposed) return;
      _stable = null;
      _stableSince = null;
      invalidate();
      status = '畫面已過期，場景描述已作廢。';
      _notify();
    });
    final moving = signal.rotationRate > 0.15;
    final drift =
        _stable != null &&
        (_stable!.difference(signal) > 0.035 || _stable!.angle(signal) > 3);
    final evidenceChanged =
        _evidence != null &&
        (_evidence!.difference(signal) > 0.08 || _evidence!.angle(signal) > 8);
    if (moving || evidenceChanged) invalidate();
    if (moving || drift || _stable == null || _stableSince == null) {
      _stable = signal;
      _stableSince = now;
    }
    if (moving) {
      _stableSince = null;
      status = '手機移動中，穩定後再分析。';
    }
    if (automatic && canDescribe && _changed) {
      unawaited(describe(manual: false));
    }
    _notify();
  }

  Future<void> describe({bool manual = true}) async {
    if (!canDescribe || (!manual && !automatic)) return;
    busy = true;
    failure = '';
    text = null;
    final generation = ++_generation;
    _evidence = _latest;
    bool current() =>
        !_disposed && available && generation == _generation && _fresh;
    status = '正在分析場景；即時物件辨識繼續運行。';
    _notify();
    var awaitingResult = false;
    try {
      final jpeg = await capture();
      if (!current()) return;
      if (jpeg == null || jpeg.isEmpty || jpeg.length > 524288) {
        throw const SceneFailure('no-frame');
      }
      if (!stable) {
        invalidate();
        return;
      }
      // Debit locally only immediately before the one backend attempt.
      attempts++;
      _lastAttempt = _clock();
      _baseline = _latest;
      _expiry = Timer(const Duration(seconds: 20), () {
        if (!_disposed && generation == _generation) {
          final pending = busy;
          invalidate();
          if (pending) automatic = false;
          status = pending ? '場景分析逾時，沒有自動重試。' : '場景描述已過期。';
          _notify();
        }
      });
      awaitingResult = true;
      final reply = await backend.describe(
        jpeg,
        sceneRequestId(),
        isCurrent: current,
      );
      awaitingResult = false;
      if (!_disposed) {
        metrics = reply.metrics;
        if (reply.metrics.estimatedUsd == null ||
            reply.metrics.totalTokens == null) {
          usageUnknown = true;
          automatic = false;
        } else {
          estimatedUsd += reply.metrics.estimatedUsd!;
        }
      }
      if (!current() || !stable) return;
      if (reply.text == null) throw const SceneFailure('rejected');
      final full = validateSceneText(reply.text);
      final previous = _previousFullText;
      _previousFullText = full;
      final sentences = RegExp(r'[^。！？]+[。！？]')
          .allMatches(full)
          .map((m) => m[0]!)
          .toList();
      final spoken = manual || previous == null
          ? full
          : sentences.where((s) => !previous.contains(s)).join();
      if (spoken.isEmpty) {
        status = '場景描述沒有新內容，略過重複播音。';
        return;
      }
      text = spoken;
      status = '場景描述完成。';
      speaking = true;
      _notify();
      try {
        await speaker.speak(spoken);
      } catch (_) {
        if (current()) {
          failure = 'speech-unavailable';
          automatic = false;
          status = '廣東話播音未能開始，可閱讀場景文字。';
        }
      }
    } catch (error) {
      if (!_disposed && awaitingResult) {
        usageUnknown = true;
        automatic = false;
      }
      if (!current()) return;
      automatic = false;
      failure = error is SceneFailure ? error.code : 'unavailable';
      text = null;
      status = switch (failure) {
        'resource-exhausted' => '場景分析額度已停止，請由開發者核對；物件辨識繼續。',
        'app-check-unavailable' ||
        'unauthenticated' ||
        'not-configured' => '場景分析登入或手機驗證未完成；物件辨識繼續。',
        'speech-unavailable' => '廣東話播音未能開始，可閱讀場景文字。',
        _ => '場景分析未完成，自動模式已停止，沒有自動重試。',
      };
    } finally {
      busy = false;
      speaking = false;
      if (!_disposed && attempts >= maxSessionAttempts) {
        automatic = false;
        status += ' 本次使用的分析次數已達上限。';
      }
      _notify();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
    _freshness?.cancel();
    _expiry?.cancel();
    super.dispose();
  }
}
