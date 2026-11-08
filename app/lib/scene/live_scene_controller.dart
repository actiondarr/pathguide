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
    this.stableFor = const Duration(milliseconds: 700),
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
  String? preparationCode;
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
  bool get canRequest =>
      available &&
      !busy &&
      attempts < maxSessionAttempts &&
      (_lastAttempt == null || _clock().difference(_lastAttempt!) >= cooldown);
  bool get canDescribe => canRequest && stable;
  bool get _changed =>
      _baseline == null ||
      (_latest != null &&
          (_baseline!.difference(_latest!) >= 0.12 ||
              _baseline!.angle(_latest!) >= 15));

  void setAvailable(bool value) {
    if (_disposed) return;
    available = value;
    if (value) preparationCode = null;
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

  void preparationFailed(String code) {
    setAvailable(false);
    preparationCode = code;
    status = switch (code) {
      'not_running' || 'not_ready' => '場景取相尚未接上辨識相機，請按「重試場景準備」。',
      'missing_plugin' => '場景相機介面尚未接通，請按「重試場景準備」。',
      'timeout' => '場景準備逾時，請按「重試場景準備」。',
      _ => '場景準備未完成，請按「重試場景準備」。',
    };
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

  void observe(LiveSceneSignal? signal, {String? sourceIssue}) {
    if (_disposed || !available) return;
    if (signal == null ||
        (_latest != null && signal.sequence <= _latest!.sequence)) {
      _stable = null;
      _stableSince = null;
      invalidate();
      status = switch (sourceIssue) {
        'waiting-motion' => '正在等候手機轉向感測資料，未有取相或雲端請求。',
        'motion-stale' => '手機轉向資料已過期，等候新資料後再分析。',
        'motion-unavailable' => '手機暫未提供轉向感測，未有取相或雲端請求。',
        _ => '未取得可靠的新畫面或轉向資訊，場景分析暫停。',
      };
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
    // Hand tremor does not invalidate content. Fast panning or accumulated
    // scene/attitude change still fences old replies immediately.
    final moving = signal.rotationRate > 0.45;
    final fastTurn = signal.rotationRate > 0.8;
    final drift =
        _stable != null &&
        (_stable!.difference(signal) > 0.06 || _stable!.angle(signal) > 5);
    final evidenceChanged =
        _evidence != null &&
        (_evidence!.difference(signal) > 0.12 || _evidence!.angle(signal) > 12);
    if (evidenceChanged || (fastTurn && _evidence != null)) invalidate();
    if (moving || drift || _stable == null || _stableSince == null) {
      _stable = signal;
      _stableSince = now;
    }
    if (moving) {
      _stableSince = null;
      if (!busy && text == null) {
        status = automatic ? '等畫面稍為穩定後再分析；自動模式仍然開啟。' : '畫面移動中，可按「描述前方」等穩定後取相。';
      }
    }
    if (automatic && canDescribe && _changed) {
      unawaited(describe(manual: false));
    }
    _notify();
  }

  Future<void> describe({bool manual = true}) async {
    if (!(manual ? canRequest : canDescribe) || (!manual && !automatic)) return;
    busy = true;
    failure = '';
    text = null;
    final generation = ++_generation;
    _evidence = null;
    bool active() => !_disposed && available && generation == _generation;
    bool current() => active() && _fresh;
    status = '等畫面稍為穩定後取相；即時物件辨識繼續運行。';
    _notify();
    var awaitingResult = false;
    try {
      // A manual request can wait locally; no camera photo or paid work is
      // queued. Pause/exit cancels this wait before any upload.
      for (var i = 0; manual && active() && !stable && i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!active()) return;
      if (!stable) throw const SceneFailure('not-stable');
      _evidence = _latest;
      status = '正在分析場景；即時物件辨識繼續運行。';
      _notify();
      final jpeg = await capture();
      if (!current()) return;
      if (jpeg == null || jpeg.isEmpty || jpeg.length > 524288) {
        throw const SceneFailure('no-frame');
      }
      if ((_latest?.rotationRate ?? double.infinity) > 0.45) {
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
      if (!current()) return;
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
      if (!active()) return;
      automatic = false;
      failure = error is SceneFailure ? error.code : 'unavailable';
      text = null;
      status = switch (failure) {
        'not-stable' => '畫面仍在移動，今次未取相或上傳；稍為穩定後可再按。',
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
