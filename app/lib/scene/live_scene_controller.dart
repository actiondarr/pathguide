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
  String phase = '未開始', backendStatus = '未送出', lastInvalidation = '無';
  String invalidationDetails = '無';
  String? rejectionReason, lastRequestId;
  int? captureMs, backendMs;
  final List<String> _trace = [];
  String get rejectionDescription => switch (rejectionReason) {
    'sentence-count' => '句數／句末格式不符（sentence-count）',
    'answer-format' => '回覆格式不符（answer-format）',
    'answer-length' => '描述過長（answer-length）',
    'disallowed-content' => '內容含受限字句（disallowed-content）',
    'provider-response' => '供應商回包格式不符（provider-response）',
    'provider-refusal' => '供應商拒答（provider-refusal）',
    'incomplete-answer' => '回覆未完整結束（incomplete-answer）',
    _ => '無／未提供',
  };
  void _record(String event) {
    _trace.add('${_clock().toIso8601String()} $event');
    if (_trace.length > 12) _trace.removeAt(0);
  }

  int get cooldownSeconds {
    if (_lastAttempt == null) return 0;
    final ms = (cooldown - _clock().difference(_lastAttempt!)).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  String get diagnostics => [
    '模式：${automatic ? '自動開啟' : '自動關閉（手動單次）'}；相機來源：${available ? '可用' : '未準備'}',
    '階段：$phase；後端結果：$backendStatus',
    '請求 ID：${lastRequestId ?? '未送出'}',
    '作廢原因：$lastInvalidation；拒絕原因：$rejectionDescription；錯誤碼：${failure.isEmpty ? '無' : failure}',
    '作廢時數值：$invalidationDetails',
    '穩定：${stable ? '是' : '否'}（需 ${stableFor.inMilliseconds} ms）；畫面年齡：${_received == null ? '未知' : '${_clock().difference(_received!).inMilliseconds} ms'}',
    '角速度：${_latest?.rotationRate.toStringAsFixed(3) ?? '未知'} rad/s（取相上限 0.45）',
    '與上次請求相比：畫面差 ${_baseline == null || _latest == null ? '未知' : _baseline!.difference(_latest!).toStringAsFixed(3)}／轉向 ${_baseline == null || _latest == null ? '未知' : _baseline!.angle(_latest!).toStringAsFixed(1)} 度（自動觸發門檻 0.12／15 度）',
    '冷卻剩餘：$cooldownSeconds 秒；本次已嘗試：$attempts／$maxSessionAttempts',
    '取相：${captureMs ?? '未知'} ms；後端往返：${backendMs ?? '未知'} ms；模型：${metrics?.modelMs ?? '未知'} ms',
    'Token 輸入／輸出／合計：${metrics?.promptTokens ?? '未知'}／${metrics?.completionTokens ?? '未知'}／${metrics?.totalTokens ?? '未知'}',
    '最近一次估算：US\$${metrics?.estimatedUsd?.toStringAsFixed(6) ?? '未知'}；本次已知累計：US\$${estimatedUsd.toStringAsFixed(6)}${usageUnknown ? '（另有未知用量）' : ''}；不是帳單硬上限',
    '最近事件（只保留本機數值及狀態，不含照片或描述）：',
    ..._trace,
  ].join('\n');
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
      invalidate(reason: '辨識暫停／來源停止');
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
    if (!automatic) invalidate(reason: '自動模式關閉');
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
    invalidate(reason: '使用者停止／操作中斷');
    _notify();
  }

  void invalidate({String reason = '已取消', String details = '無'}) {
    ++_generation;
    _expiry?.cancel();
    lastInvalidation = reason;
    invalidationDetails = details;
    phase = '已作廢／已取消';
    _record('作廢：$reason${details == '無' ? '' : '；$details'}');
    if (text != null || busy || speaking) {
      unawaited(speaker.stop().catchError((Object _) {}));
    }
    text = null;
    _evidence = null;
    status = automatic
        ? '舊描述已作廢；自動模式仍開啟，等新畫面穩定及冷卻完成後再分析。'
        : '舊描述已作廢；自動模式關閉，不會自行再分析。';
    _notify();
  }

  void observe(LiveSceneSignal? signal, {String? sourceIssue}) {
    if (_disposed || !available) return;
    if (signal == null ||
        (_latest != null && signal.sequence <= _latest!.sequence)) {
      _stable = null;
      _stableSince = null;
      if (failure.isNotEmpty && !busy && text == null) {
        _notify();
        return;
      }
      invalidate(reason: sourceIssue ?? '畫面／轉向訊號無效');
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
      if (failure.isNotEmpty && !busy && text == null) {
        _notify();
        return;
      }
      invalidate(reason: '畫面超過一秒未更新');
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
    if (evidenceChanged || (fastTurn && _evidence != null)) {
      invalidate(
        reason: fastTurn ? '快速轉向' : '相對取相畫面／姿態明顯改變',
        details:
            '角速度 ${signal.rotationRate.toStringAsFixed(3)} rad/s；相對取相畫面差 ${_evidence!.difference(signal).toStringAsFixed(3)}／轉向 ${_evidence!.angle(signal).toStringAsFixed(1)} 度（作廢門檻 0.8 rad/s、0.12／12 度）',
      );
    }
    if (moving || drift || _stable == null || _stableSince == null) {
      _stable = signal;
      _stableSince = now;
    }
    if (moving) {
      _stableSince = null;
      if (!busy && text == null && failure.isEmpty) {
        status = automatic
            ? '等畫面稍為穩定後再分析；自動模式仍然開啟。'
            : '畫面移動中；自動模式關閉。可按「描述前方」等穩定後取相。';
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
    rejectionReason = null;
    lastRequestId = null;
    metrics = null;
    captureMs = backendMs = null;
    backendStatus = '未送出';
    lastInvalidation = '無';
    invalidationDetails = '無';
    phase = '等候穩定';
    _trace.clear();
    _record(
      manual
          ? '手動單次開始'
          : _baseline == null
          ? '自動首次描述'
          : '環境重要變化觸發',
    );
    text = null;
    final generation = ++_generation;
    _evidence = null;
    bool active() => !_disposed && available && generation == _generation;
    bool current() => active() && _fresh;
    status = '等畫面稍為穩定後取相；即時物件辨識繼續運行。';
    _notify();
    var awaitingResult = false;
    DateTime? backendStarted;
    try {
      // A manual request can wait locally; no camera photo or paid work is
      // queued. Pause/exit cancels this wait before any upload.
      for (var i = 0; manual && active() && !stable && i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!active()) return;
      if (!stable) throw const SceneFailure('not-stable');
      _evidence = _latest;
      phase = '取相中';
      _record('開始本機取相');
      status = '正在分析場景；即時物件辨識繼續運行。';
      _notify();
      final captureStarted = _clock();
      final jpeg = await capture();
      captureMs = _clock().difference(captureStarted).inMilliseconds;
      if (!current()) return;
      if (jpeg == null || jpeg.isEmpty || jpeg.length > 524288) {
        throw const SceneFailure('no-frame');
      }
      if ((_latest?.rotationRate ?? double.infinity) > 0.45) {
        invalidate(reason: '編碼後手機仍在移動，未送出');
        return;
      }
      // Debit locally only immediately before the one backend attempt.
      attempts++;
      _lastAttempt = _clock();
      _baseline = _latest;
      phase = '等待後端';
      backendStatus = '等待回覆';
      lastRequestId = sceneRequestId();
      backendStarted = _clock();
      _record('已交後端連接器進行驗證／送出，尚待回覆確認');
      _expiry = Timer(const Duration(seconds: 20), () {
        if (!_disposed && generation == _generation) {
          final pending = busy;
          invalidate(reason: pending ? '分析超過二十秒' : '描述有效期結束');
          if (pending) automatic = false;
          status = pending ? '場景分析逾時，沒有自動重試。' : '場景描述已過期。';
          _notify();
        }
      });
      awaitingResult = true;
      final reply = await backend.describe(
        jpeg,
        lastRequestId!,
        isCurrent: current,
      );
      awaitingResult = false;
      if (!_disposed) {
        backendMs = _clock().difference(backendStarted).inMilliseconds;
        backendStatus = reply.text == null ? '拒絕' : '成功';
        rejectionReason = reply.rejectionReason;
        _record(
          '後端：$backendStatus${rejectionReason == null ? '' : '／$rejectionReason'}',
        );
        metrics = reply.metrics;
        if (reply.metrics.estimatedUsd == null ||
            reply.metrics.totalTokens == null) {
          usageUnknown = true;
          automatic = false;
        } else {
          estimatedUsd += reply.metrics.estimatedUsd!;
        }
      }
      if (reply.text == null) {
        automatic = false;
        failure = 'rejected';
        if (current()) {
          phase = '回覆被拒絕';
          status = '場景回覆未符合格式或內容要求，未有顯示或播音；詳見測試資料。';
          _expiry?.cancel();
          _evidence = null;
        }
        return;
      }
      if (!current()) return;
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
      phase = '文字已顯示／交予播音';
      _record('有效文字已顯示，交予語音協調器');
      status = '場景描述完成。';
      speaking = true;
      _notify();
      try {
        await speaker.speak(spoken);
      } catch (_) {
        if (current()) {
          failure = 'speech-unavailable';
          automatic = false;
          _record('廣東話播音未能開始');
          status = '廣東話播音未能開始，可閱讀場景文字。';
        }
      }
    } catch (error) {
      if (!_disposed) {
        if (awaitingResult) {
          backendStatus = '失敗';
          backendMs = _clock().difference(backendStarted!).inMilliseconds;
        }
        failure = error is SceneFailure ? error.code : 'unavailable';
        _record('失敗：$failure');
      }
      if (!_disposed && awaitingResult) {
        usageUnknown = true;
        automatic = false;
      }
      if (!active()) return;
      automatic = false;
      phase = '失敗';
      _expiry?.cancel();
      _evidence = null;
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
