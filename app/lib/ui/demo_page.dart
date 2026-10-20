import 'dart:async';

import 'package:flutter/foundation.dart'
    show kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../overlay/box_painter.dart';
import '../settings/app_settings.dart';
import '../tts/announcer.dart';
import '../tts/flutter_tts_speaker.dart';
import '../vision/detection.dart';
import '../vision/mock_vision_source.dart';
import '../vision/platform_vision.dart';
import '../vision/vision_preview.dart';
import '../vision/vision_source.dart';
import 'app_theme.dart';

/// 界面可切换的检测来源种类。
///
/// 这个枚举只用来渲染「相机 / 假数据」两个按钮，**不参与运行期分派**——
/// 分派由 [_DemoPageState._makeSource] 完成，之后 UI 只持有一个
/// [VisionSource]。曾经 UI 里通篇是 `_platform.xxx` 与 `_mock?.xxx` 两套
/// 并行分支，换平台要把每个分支抄一遍，且两个实现的行为无一致性保证。
enum SourceMode {
  /// 真实相机，Android 走原生 CameraX。
  camera,

  /// 按已知规律运动的假框，用来校验坐标映射与演示防抖，不需要模型。
  mock,
}

/// M3 最小可见 Demo 的主界面。
///
/// 验收目标（见毕设设计 §9.1）：相机实时画面 + 检测框 + 中文标签 +
/// FPS 与推理耗时 + 阈值滑条 + 粤语播报。
class DemoPage extends StatefulWidget {
  const DemoPage({
    super.key,
    this.initialMode = SourceMode.camera,
    required this.settings,
  });

  /// Tests and demo tooling can start in mock mode without racing native setup.
  /// The shipped app keeps the camera default.
  final SourceMode initialMode;
  final AppSettings settings;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> with WidgetsBindingObserver {
  late final FlutterTtsSpeaker _speaker;
  late final Announcer _announcer;

  StreamSubscription<VisionFrame>? _sub;

  SourceMode _mode = SourceMode.camera;

  /// **界面唯一持有的检测来源。**
  ///
  /// 相机与假数据都是 [VisionSource]，UI 不再需要知道用的是哪一个
  /// （只有渲染预览时按 [_mode] 决定显示相机视图还是网格背景）。
  VisionSource? _source;

  double _threshold = 0.30;
  bool _speakEnabled = true;
  bool _showLabels = true;

  List<Detection> _detections = const <Detection>[];

  double _inferenceMs = 0;
  double _fps = 0;
  DateTime _lastFrameAt = DateTime.now();

  String _status = '正在初始化…';
  String? _statusError;

  /// 本次初始化是否成功。用于状态栏配色与错误面板显示。
  bool _sourceReady = false;
  String? _ttsLanguage;
  String? _ttsError;
  bool _speechReady = false;
  bool _active = true;
  int _sourceGeneration = 0;
  Future<void> _transition = Future<void>.value();
  Future<void>? _speechStop;
  bool _controlsOpen = false;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// 原生侧诊断快照，定时轮询后显示在 HUD 上。
  /// 假数据源的 [VisionSource.diagnostics] 返回 null，此时面板自动隐藏。
  VisionDiagnostics? _diagnostics;
  Timer? _diagTimer;

  /// 帧尺寸与旋转角都来自 [VisionSource]，不在 UI 里写常量。
  ///
  /// `frameSize` 已经是**旋转之后**的尺寸，可直接用于 `DisplayFit`。
  Size get _frameSize => _source?.frameSize ?? const Size(1280, 720);

  int get _rotationDegrees => _source?.rotationDegrees ?? 0;

  /// 最近一次布局算出的 fit 与屏幕矩形，**只给 [_logHud] 用**。
  ///
  /// 为什么要在 build 里顺手记下来：判断「屏幕上到底画没画框」需要的是
  /// **映射之后的屏幕矩形**，而它只在 build 里算得出来。这里只做赋值、
  /// 不触发重建，因此不改变 build 的语义。
  DisplayFit? _lastFit;
  List<({Detection detection, Rect rect})> _lastMapped =
      const <({Detection detection, Rect rect})>[];

  @override
  void initState() {
    super.initState();
    _speaker = FlutterTtsSpeaker(speechRate: widget.settings.speechSpeed.rate);
    _announcer = Announcer(
      speaker: _speaker,
      minSpeakScore: widget.settings.speakThreshold,
    );
    widget.settings.addListener(_applySettings);
    _mode = widget.initialMode;
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  void _applySettings() {
    _announcer.minSpeakScore = widget.settings.speakThreshold;
    if (mounted) setState(() {});
    if (_speaker.speechRate != widget.settings.speechSpeed.rate) {
      unawaited(_speaker.setSpeechRate(widget.settings.speechSpeed.rate));
    }
  }

  Future<void> _bootstrap() async {
    // 語音初始化獨立進行，語音服務不可用時仍可操作介面。
    unawaited(_initSpeaker());
    if (!_active) return;
    if (_isIOS || defaultTargetPlatform == TargetPlatform.android) {
      await _switchSource(_mode);
    }
  }

  Future<void> _initSpeaker() async {
    try {
      final lang = await _speaker.initialize();
      if (!mounted) return;
      setState(() {
        _ttsLanguage = lang;
        _speechReady = lang != null;
        _ttsError = lang == null ? '未找到可用語音，請檢查系統語音設定' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechReady = false;
        _ttsError = '語音初始化失敗：$e';
      });
    }
  }

  /// 按种类构造一个检测来源。
  ///
  /// 这是**唯一**出现具体实现类名的地方。新增平台（iOS）或新增来源种类时，
  /// 只改这一处，UI 其余部分不动。
  VisionSource _makeSource(SourceMode mode) {
    switch (mode) {
      case SourceMode.camera:
        return PlatformVision();
      case SourceMode.mock:
        // 假源的原始帧尺寸与旋转角与相机实现保持一致，
        // 这样「假数据下框画对了」才能推出「相机下也会画对」。
        return MockVisionSource(
          frameSize: const Size(1280, 720),
          rotationDegrees: 90,
          threshold: _threshold,
          classIds: _isIOS ? const <int>[6, 11, 7] : null,
        );
    }
  }

  /// 切换检测来源：停旧的、起新的、重接流与诊断轮询。
  Future<void> _switchSource(SourceMode mode) async {
    if (!mounted || !_active) return;
    final generation = ++_sourceGeneration;
    setState(() => _mode = mode);
    _stopSpeech();
    // 串行釋放及啟動來源，快速切換或前後台切換不會建立重複來源。
    _transition = _transition.then((_) => _replaceSource(mode, generation));
    await _transition;
  }

  bool _isCurrent(int generation) =>
      mounted && _active && generation == _sourceGeneration;

  Future<void> _stopVision() async {
    _diagTimer?.cancel();
    _diagTimer = null;
    final sub = _sub;
    final source = _source;
    _sub = null;
    _source = null;
    // 同步要求兩者停止，模擬計時器毋須等待訂閱的非同步清理。
    final cancelled = sub?.cancel();
    final disposed = source?.dispose();
    await cancelled;
    await disposed;
  }

  Future<void> _replaceSource(SourceMode mode, int generation) async {
    try {
      await _stopVision();
      // 視覺來源獨立啟動；未完成的語音停止只阻止新播報。
      if (!_isCurrent(generation)) return;
      _announcer.reset();
      _fps = 0;
      _lastFrameAt = DateTime.now();
      final source = _makeSource(mode);
      _source = source;
      setState(() {
        _detections = const <Detection>[];
        _diagnostics = null;
        _status = '正在初始化（${source.displayName}）…';
        _statusError = null;
        _sourceReady = false;
      });
      _sub = source.frames.listen(
        (frame) {
          if (_isCurrent(generation)) _onFrame(frame);
        },
        onError: (Object e) {
          if (_isCurrent(generation)) {
            setState(() => _status = '辨識資料流出錯：$e');
          }
        },
      );
      final status = await source.initialize();
      if (!_isCurrent(generation)) {
        await _stopVision();
        return;
      }
      // 原生相機啟動後才推送閾值；模擬來源同樣由來源負責過濾。
      source.threshold = _threshold;
      setState(() {
        _sourceReady = status.ok;
        _status = status.message;
        _statusError = status.error;
      });
      if (mode == SourceMode.camera) {
        _diagTimer = Timer.periodic(const Duration(milliseconds: 500), (
          _,
        ) async {
          final d = await source.diagnostics();
          if (!_isCurrent(generation)) return;
          if (d != null) setState(() => _diagnostics = d);
          _logHud();
        });
      }
    } catch (e) {
      await _stopVision();
      if (_isCurrent(generation)) {
        setState(() {
          _sourceReady = false;
          _status = '來源初始化失敗';
          _statusError = '$e';
        });
      }
    }
  }

  void _stopSpeech() {
    _announcer.enabled = false;
    final stopping = _speaker.stop();
    _speechStop = stopping;
    unawaited(
      stopping.then((_) {
        if (identical(_speechStop, stopping)) _speechStop = null;
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _active) return;
    _active = active;
    if (active) {
      unawaited(_switchSource(_mode));
      return;
    }
    ++_sourceGeneration;
    _diagTimer?.cancel();
    _stopSpeech();
    setState(() {
      _sourceReady = false;
      _detections = const <Detection>[];
      _diagnostics = null;
      _status = '辨識已暫停';
      _statusError = null;
    });
    _transition = _transition.then((_) => _stopVision());
  }

  /// 把 HUD 上的关键数字同步打一行到 logcat（仅 Debug 构建）。
  ///
  /// ## 为什么要有这一行
  ///
  /// 诊断信息原本只画在屏幕上，于是「真机验证」只能靠人眼看屏幕复述数字：
  /// 无法无人值守、无法留证、也无法在远程排查时比对。
  /// 截图虽然能留证，但要读屏幕上的小字仍需人工（或 OCR）。
  ///
  /// 这一行让整条链路变成**可被程序读取**的：帧率、耗时至 UI 的检测框数、
  /// 原生分析帧数、最高分、无效值分类、几何输入、张量布局全在同一行里。
  /// 于是「跑一次真机」= 装包 + 抓 logcat，不需要任何人盯屏幕。
  ///
  /// 字段名刻意用 ASCII，方便 grep：
  ///
  ///     HUD fps=.. inf=..ms det=.. analyzed=.. nativeDet=.. maxScore=.. ...
  ///
  /// 其中 `boxes=` 是**映射之后的屏幕矩形**（最多 3 个），
  /// `paint=` 是画布会实际画出的框数——它按 `DetectionBoxPainter` 的规则
  /// （`rect.width/height < 2` 视为噪点而跳过）算出来。
  /// 这一项直接回答最初那句「HUD 有数字、屏幕上一个框都没有」：
  /// `det>0` 而 `paint=0` 就说明矩形退化或被裁掉，而不是「类别没对上」。
  void _logHud() {
    if (!kDebugMode) return;
    final d = _diagnostics;
    final reasons = d == null || d.invalidByReason.isEmpty
        ? '-'
        : d.invalidByReason.entries.map((e) => '${e.key}=${e.value}').join(',');
    final paint = _lastMapped
        .where((m) => m.rect.width >= 2 && m.rect.height >= 2)
        .length;
    final boxes = _lastMapped
        .take(3)
        .map(
          (m) =>
              '(${m.rect.left.round()},${m.rect.top.round()},'
              '${m.rect.width.round()}x${m.rect.height.round()})',
        )
        .join(' ');
    debugPrint(
      'HUD fps=${_fps.toStringAsFixed(1)} '
      'inf=${_inferenceMs.toStringAsFixed(1)}ms '
      'det=${_detections.length} '
      'paint=$paint '
      'speakMin=${_announcer.minSpeakScore.toStringAsFixed(2)} '
      'boxes=[$boxes] '
      'analyzed=${d?.analyzedFrames ?? -1} '
      'nativeDet=${d?.detectionCount ?? -1} '
      'maxScore=${(d?.frameMaxScore ?? 0).toStringAsFixed(3)} '
      'invalid=${d?.invalidDetections ?? -1} '
      'reasons=$reasons '
      'fit=${_lastFit?.scale.toStringAsFixed(3) ?? '-'} '
      'frame=${d?.frameWidth ?? 0}x${d?.frameHeight ?? 0} '
      'rot=$_rotationDegrees '
      'src=${_frameSize.width.toInt()}x${_frameSize.height.toInt()} '
      'decode=${d?.decodeStats ?? '-'} '
      'skip=${(d?.skippedReason.isNotEmpty ?? false) ? d!.skippedReason : '-'} '
      'err=${(d?.analyzeError.isNotEmpty ?? false) ? d!.analyzeError : '-'}',
    );
  }

  void _onFrame(VisionFrame frame) {
    if (!mounted || !_active || !_sourceReady) return;
    final now = DateTime.now();
    final dt = now.difference(_lastFrameAt).inMicroseconds;
    _lastFrameAt = now;

    // **不再按阈值过滤**：阈值已在来源内部生效（原生侧丢弃低分框，
    // 假源同样按 threshold 过滤）。两处各过滤一次时，不一致的表现是
    // 「滑动条不生效」或「框数对不上」，且不报错。
    _announcer.enabled = _speakEnabled && _speechReady && _speechStop == null;
    if (_announcer.enabled && _announcer.onFrame(frame.detections) != null) {
      unawaited(
        _announcer.lastSpeech!.catchError((Object e) {
          if (!mounted) return;
          _stopSpeech();
          setState(() {
            _speechReady = false;
            _ttsError = '語音播報失敗：$e';
          });
        }),
      );
    }

    setState(() {
      _detections = frame.detections;
      _inferenceMs = frame.inferenceMs;
      if (dt > 0) {
        // 指数平滑：瞬时值抖动太大，看不出真实帧率。
        final inst = 1e6 / dt;
        _fps = _fps == 0 ? inst : _fps * 0.8 + inst * 0.2;
      }
    });
  }

  @override
  void dispose() {
    widget.settings.removeListener(_applySettings);
    WidgetsBinding.instance.removeObserver(this);
    _active = false;
    ++_sourceGeneration;
    _diagTimer?.cancel();
    _stopSpeech();
    _transition = _transition.then((_) => _stopVision());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: Colors.black, child: _previewArea()),
            Positioned(left: 12, top: 12, child: _statusPill()),
            Positioned(
              right: 16,
              bottom: 18,
              child: Semantics(
                button: true,
                label: '開啟辨識設定',
                child: FloatingActionButton(
                  key: const ValueKey<String>('vision-settings-button'),
                  heroTag: 'vision-settings',
                  tooltip: '開啟辨識設定',
                  onPressed: _showControls,
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  child: const Icon(Icons.tune_rounded, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill() {
    final hasError = !_sourceReady && _statusError != null;
    final paused = _status == '辨識已暫停';
    final color = _sourceReady
        ? AppColors.success
        : (hasError ? AppColors.danger : AppColors.warning);
    final label = _sourceReady
        ? '辨識中'
        : (hasError ? '需要處理' : (paused ? '已暫停' : '準備中'));

    return Semantics(
      key: const ValueKey<String>('vision-status-pill'),
      button: hasError,
      label: '辨識狀態：$label${hasError ? '，點擊查看詳情' : ''}',
      child: Material(
        color: AppColors.background.withValues(alpha: 0.78),
        shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: 0.78)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hasError ? _showControls : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    _sourceReady
                        ? Icons.check_circle_rounded
                        : (hasError
                              ? Icons.error_rounded
                              : (paused
                                    ? Icons.pause_circle_rounded
                                    : Icons.hourglass_top_rounded)),
                    color: color,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showControls() async {
    if (_controlsOpen || !mounted) return;
    _controlsOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: AppColors.surface,
        barrierColor: Colors.black.withValues(alpha: 0.58),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (sheetContext) => _LiveControlsSheet(
          contentBuilder: (refresh) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _statusBar(),
              _metricStrip(),
              _controlPanel(refresh: refresh),
            ],
          ),
        ),
      );
    } finally {
      _controlsOpen = false;
    }
  }

  // ------------------------------------------------------------- 预览区域

  Widget _previewArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        // [VisionSource.frameSize] 与检测框坐标同属一个**已转正**的坐标系
        // （旋转已由原生在采样时逐像素完成），所以这里直接用，
        // 映射时也不再施加旋转——见 [mapDetectionsToScreen] 的说明。
        final fit = DisplayFit.contain(frame: _frameSize, view: viewSize);
        final mapped = mapDetectionsToScreen(detections: _detections, fit: fit);
        // 供 _logHud 报告「映射后的屏幕矩形」——只赋值，不触发重建。
        _lastFit = fit;
        _lastMapped = mapped;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_mode == SourceMode.camera)
              const VisionPreview()
            else
              _mockScene(),
            // 叠加层不能拦截手势，否则下方的预览收不到事件。
            IgnorePointer(
              child: CustomPaint(
                painter: DetectionBoxPainter(
                  mapped: mapped,
                  showLabels: _showLabels,
                ),
              ),
            ),
            if (!_sourceReady)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.80),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (_statusError == null)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.danger,
                          size: 20,
                        ),
                      const SizedBox(width: 10),
                      Text(_statusError == null ? '正在準備辨識' : '辨識暫時不可用'),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _metricStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _metricCard(
              icon: Icons.speed_rounded,
              value: _fps.toStringAsFixed(1),
              label: _mode == SourceMode.mock ? '模擬 FPS' : '更新 FPS',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metricCard(
              icon: Icons.bolt_rounded,
              value: '${_inferenceMs.toStringAsFixed(0)} ms',
              label: '推理耗時',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metricCard(
              icon: Icons.center_focus_strong_rounded,
              value: '${_detections.length}',
              label: '辨識物件',
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// 假数据模式下的背景：网格 + 十字线，让框的位移更容易看出来。
  Widget _mockScene() {
    return CustomPaint(painter: _GridPainter());
  }

  /// 几何一致性检查：**分析流尺寸**与**预览流尺寸**是否一致。
  ///
  /// ## 为什么需要这条
  ///
  /// 预览由 CameraX 自己缩放显示，而框的位置由 Dart 用分析流的尺寸算出。
  /// 两条流的宽高比若不同，画面与框就会**系统性错位**——而且不报错。
  /// 这是「预览和框对不上」这类问题最难查的一种成因，所以显式检查。
  ///
  /// 返回 null 表示一致（或无数据可判）。
  String? _geometryWarning() {
    final d = _diagnostics;
    if (d == null || d.frameWidth <= 0 || d.frameHeight <= 0) return null;
    // d.frameWidth/Height 是**原始**帧尺寸；来源报的 frameSize 已是旋转后，
    // 所以比较时把来源的也转回原始尺寸。
    final raw = rotatedFrameSize(_frameSize, _rotationDegrees);
    final same =
        raw.width.round() == d.frameWidth &&
        raw.height.round() == d.frameHeight;
    if (same) return null;
    return '幾何不一致：畫框用 ${raw.width.round()}x${raw.height.round()}，'
        '分析流實際 ${d.frameWidth}x${d.frameHeight} → 框會整體偏移';
  }

  Widget _perfPanel() {
    final style = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    final geo = _geometryWarning();
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${_mode == SourceMode.mock ? "模擬更新率" : "更新率"}  ${_fps.toStringAsFixed(1)} FPS',
            style: style,
          ),
          Text(
            '${_mode == SourceMode.mock ? "模擬耗時" : "推理耗時"}  ${_inferenceMs.toStringAsFixed(1)} ms',
            style: style,
          ),
          Text('檢測框   ${_detections.length}', style: style),
          if (geo != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 210,
                child: SelectableText(
                  geo,
                  style: style.copyWith(color: Colors.redAccent, fontSize: 9),
                ),
              ),
            ),
          // ---- 诊断计数：这几个数字直接指出链路卡在哪一环 ----
          // 「分析帧」为 0（红色）说明相机分析回路根本没跑起来；
          // 「最高分」低于阈值（橙色）说明模型没给出高分，问题在模型或输入；
          // 「跳过」非空则直接写出被跳过的原因。
          if (_diagnostics != null) ...<Widget>[
            Text(
              '分析幀   ${_diagnostics!.analyzedFrames}',
              style: style.copyWith(
                color: _diagnostics!.analyzedFrames == 0
                    ? Colors.redAccent
                    : Colors.white,
              ),
            ),
            if (_diagnostics!.analyzeErrors > 0)
              Text(
                '分析錯誤 ${_diagnostics!.analyzeErrors}',
                style: style.copyWith(color: Colors.redAccent),
              ),
            Text(
              '分數     ${_diagnostics!.frameMinScore.toStringAsFixed(2)}'
              '~${_diagnostics!.frameMaxScore.toStringAsFixed(2)}',
              style: style.copyWith(
                // 模型最后一层是 sigmoid，分数必在 [0,1]。超过 1 就是解码错了。
                color: _diagnostics!.frameMaxScore > 1.0
                    ? Colors.redAccent
                    : (_diagnostics!.frameMaxScore >= _threshold
                          ? Colors.greenAccent
                          : Colors.orangeAccent),
              ),
            ),
            if (_diagnostics!.invalidDetections > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 200,
                  child: SelectableText(
                    // 分类计数：三种原因指向完全不同的故障，只有总数时无法区分。
                    '無效 ${_diagnostics!.invalidDetections}\n'
                    '${_invalidReasonText()}\n'
                    '${_diagnostics!.invalidSample}',
                    style: style.copyWith(color: Colors.redAccent, fontSize: 9),
                  ),
                ),
              ),
            // 任何诊断都显示时，一并显示解码统计（raw vs decoded 的范围对照）。
            if (_diagnostics!.decodeStats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 210,
                  child: SelectableText(
                    _diagnostics!.decodeStats,
                    style: style.copyWith(
                      color: Colors.lightGreenAccent,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
            // 输入/输出缓冲的真实内容。只在出现无效检测时显示，避免平时刷屏。
            if (_diagnostics!.invalidDetections > 0) ...<Widget>[
              if (_diagnostics!.inputStats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 200,
                    child: SelectableText(
                      '輸入 ${_diagnostics!.inputStats}',
                      style: style.copyWith(color: Colors.cyan, fontSize: 9),
                    ),
                  ),
                ),
              if (_diagnostics!.outputStats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 200,
                    child: SelectableText(
                      '輸出 ${_diagnostics!.outputStats}',
                      style: style.copyWith(color: Colors.cyan, fontSize: 9),
                    ),
                  ),
                ),
            ],
            // 缓冲指针快照：一直显示。异常发生在推理中途时，
            // 只有初始化时记下的这份数值还能看。
            if (_diagnostics!.bufferState.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 200,
                  child: SelectableText(
                    _diagnostics!.bufferState,
                    style: style.copyWith(
                      color: Colors.cyanAccent,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
            if (_diagnostics!.analyzeErrors > 0 &&
                _diagnostics!.analyzeError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 190,
                  child: SelectableText(
                    // 异常的完整类型与消息直接摆在屏幕上。
                    // 真机上没有 logcat 可用，这行文字是唯一的线索来源。
                    _diagnostics!.analyzeError,
                    style: style.copyWith(color: Colors.redAccent, fontSize: 9),
                  ),
                ),
              ),
            if (_diagnostics!.skippedReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 190,
                  child: SelectableText(
                    _diagnostics!.skippedReason,
                    style: style.copyWith(
                      color: Colors.orangeAccent,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
          ],
          Text(
            '語音     ${_ttsLanguage ?? "尚未就緒"}',
            style: style.copyWith(
              color: _speaker.isCantonese
                  ? Colors.greenAccent
                  : Colors.orangeAccent,
            ),
          ),
          // 两个阈值分开展示，因为它们管的事不同：
          // 上面那根滑条决定**画不画**，这一行是**说不说**的下限。
          // 不写出来，用户会以为「滑条拉低了怎么还不念」是坏了。
          Text(
            '播報門檻 ≥ ${_announcer.minSpeakScore.toStringAsFixed(2)}（低分只畫框）',
            style: style.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  /// 显示这一帧的坐标假设。框画偏时**第一眼**要看这里：
  /// 帧尺寸或旋转角错了，映射必然错，而且不会有任何报错。
  Widget _fitDebug(DisplayFit fit) {
    final style = const TextStyle(color: Colors.white70, fontSize: 10);
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '幀 ${_frameSize.width.toInt()}x${_frameSize.height.toInt()}',
            style: style,
          ),
          Text('旋轉 $_rotationDegrees°', style: style),
          Text('scale ${fit.scale.toStringAsFixed(3)}', style: style),
          Text(
            '留邊 ${fit.dx.toStringAsFixed(0)},${fit.dy.toStringAsFixed(0)}',
            style: style,
          ),
        ],
      ),
    );
  }

  /// 把无效检测的分类计数渲染成一行短文本，例如 `score_out_of_range=8400`。
  ///
  /// 单独成方法而不是写成嵌套插值：嵌套引号极易出错，而这里又只是字符串拼接。
  String _invalidReasonText() {
    final m = _diagnostics?.invalidByReason ?? const <String, int>{};
    if (m.isEmpty) return '(未分類)';
    return m.entries.map((e) => '${e.key}=${e.value}').join(' ');
  }

  Widget _glass({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  // ------------------------------------------------------------- 状态条

  Widget _statusBar() {
    final hasError = !_sourceReady && _statusError != null;
    final color = _sourceReady
        ? AppColors.success
        : (hasError ? AppColors.danger : AppColors.warning);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.visibility_rounded,
                  size: 24,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '即時環境辨識',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _mode == SourceMode.camera ? '後置相機・裝置端 AI' : '模擬資料・介面測試',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  border: Border.all(color: color.withValues(alpha: 0.65)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _sourceReady
                          ? Icons.check_circle_rounded
                          : (hasError
                                ? Icons.error_rounded
                                : Icons.hourglass_top_rounded),
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _sourceReady ? '辨識中' : (hasError ? '需要處理' : '準備中'),
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_sourceReady)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status,
                style: TextStyle(color: color, fontSize: 12),
                softWrap: true,
              ),
            ),
          // 失败原因单独一块，**完整**显示，且长按可复制。
          // 理由：这类错误只在真机上出现，用户没有 logcat 可用；
          // 把完整文本摆在屏幕上、允许复制，比让他去翻日志现实得多。
          if (!_sourceReady && _statusError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onLongPress: () async {
                  await Clipboard.setData(ClipboardData(text: _statusError!));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('錯誤詳情已複製'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${_source?.displayName ?? "來源"}初始化失敗（長按複製）',
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(Icons.copy, size: 13, color: color),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _statusError!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 控制面板

  Widget _controlPanel({VoidCallback? refresh}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.tune_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '辨識信心門檻',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _threshold.toStringAsFixed(2),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Semantics(
                  label: '辨識信心門檻',
                  value: _threshold.toStringAsFixed(2),
                  child: Slider(
                    key: const ValueKey<String>('detection-threshold'),
                    value: _threshold,
                    min: 0.05,
                    max: 0.95,
                    divisions: 18,
                    label: _threshold.toStringAsFixed(2),
                    onChanged: (v) {
                      setState(() => _threshold = v);
                      _source?.threshold = v;
                      refresh?.call();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '語音播報門檻 · ${widget.settings.speakThreshold.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '較低會播報更多物件；較高會減少播報。物件亦須達到上方辨識門檻。',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                Slider(
                  key: const ValueKey<String>('speech-threshold'),
                  semanticFormatterCallback: (v) =>
                      '語音播報門檻 ${(v * 100).round()}%',
                  value: widget.settings.speakThreshold,
                  min: 0.05,
                  max: 0.95,
                  divisions: 18,
                  label: widget.settings.speakThreshold.toStringAsFixed(2),
                  onChanged: (value) {
                    _stopSpeech();
                    unawaited(widget.settings.setSpeakThreshold(value));
                    refresh?.call();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: SegmentedButton<SourceMode>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<SourceMode>>[
                    ButtonSegment<SourceMode>(
                      value: SourceMode.camera,
                      label: Text('相機'),
                      icon: Icon(Icons.photo_camera, size: 16),
                    ),
                    ButtonSegment<SourceMode>(
                      value: SourceMode.mock,
                      label: Text('模擬資料'),
                      icon: Icon(Icons.grid_on, size: 16),
                    ),
                  ],
                  selected: <SourceMode>{_mode},
                  onSelectionChanged: (s) async {
                    // 不再按种类写两个分支去调各自的启动函数：
                    // 切换来源统一走 _switchSource，它内部同等地处理
                    // 「停旧的、起新的、重接流与诊断」。
                    if (s.first == _mode) return;
                    await _switchSource(s.first);
                    refresh?.call();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _controlToggle(
                  tooltip: _speakEnabled ? '關閉播報' : '開啟播報',
                  label: '粵語播報',
                  icon: _speakEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  enabled: _speakEnabled,
                  onTap: () {
                    setState(() => _speakEnabled = !_speakEnabled);
                    if (!_speakEnabled) _stopSpeech();
                    refresh?.call();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _controlToggle(
                  tooltip: _showLabels ? '隱藏標籤' : '顯示標籤',
                  label: '物件標籤',
                  icon: _showLabels
                      ? Icons.label_rounded
                      : Icons.label_off_rounded,
                  enabled: _showLabels,
                  onTap: () {
                    setState(() => _showLabels = !_showLabels);
                    refresh?.call();
                  },
                ),
              ),
            ],
          ),
          if (_ttsError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _ttsError!,
                style: const TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            )
          else if (_ttsLanguage != null && !_speaker.isCantonese)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '目前使用 $_ttsLanguage，並非粵語',
                style: const TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
          if (_announcer.history.isNotEmpty) _announceLog(),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const PageStorageKey<String>('technical-details'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              collapsedBackgroundColor: AppColors.surface,
              backgroundColor: AppColors.surface,
              collapsedShape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(
                Icons.developer_mode_rounded,
                color: AppColors.textMuted,
              ),
              title: const Text(
                '技術資料',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                '答辯及問題診斷使用',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              children: <Widget>[
                _perfPanel(),
                if (!_isIOS)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _fitDebug(
                      _lastFit ??
                          DisplayFit.contain(
                            frame: _frameSize,
                            view: _frameSize,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlToggle({
    required String tooltip,
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      toggled: enabled,
      label: label,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.14)
              : AppColors.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: enabled ? AppColors.primary : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: 21,
                      color: enabled ? AppColors.primary : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled
                              ? AppColors.primary
                              : AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 播报决策日志。展示「为什么播/为什么跳过」，
  /// 是两级防抖真的在工作的直接证据。
  Widget _announceLog() {
    final recent = _announcer.history.reversed.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final a in recent)
            Text(
              '${a.at.hour.toString().padLeft(2, '0')}:'
              '${a.at.minute.toString().padLeft(2, '0')}:'
              '${a.at.second.toString().padLeft(2, '0')}  '
              '${a.label.nameZh}  ${a.reason}',
              style: TextStyle(
                fontSize: 11,
                color: a.reason.contains('跳過')
                    ? Colors.white38
                    : Colors.greenAccent,
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps the modal controls in sync with camera diagnostics without rebuilding
/// or resizing the preview behind it.
class _LiveControlsSheet extends StatefulWidget {
  const _LiveControlsSheet({required this.contentBuilder});

  final Widget Function(VoidCallback refresh) contentBuilder;

  @override
  State<_LiveControlsSheet> createState() => _LiveControlsSheetState();
}

class _LiveControlsSheetState extends State<_LiveControlsSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '辨識控制',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '關閉辨識設定',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey<String>('vision-controls-scroll'),
              padding: const EdgeInsets.only(bottom: 12),
              child: widget.contentBuilder(_refresh),
            ),
          ),
        ],
      ),
    );
  }
}

/// 假数据模式的背景网格，让框的位移幅度可直接目视比较。
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF23303C)
      ..strokeWidth = 1;
    const step = 40.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final c = Paint()
      ..color = const Color(0xFF2F4256)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      c,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      c,
    );
    // 四角标记，用来核对框的边界夹紧是否正确
    final corner = Paint()
      ..color = const Color(0xFF3E566E)
      ..strokeWidth = 3;
    const l = 18.0;
    canvas.drawLine(Offset.zero, const Offset(l, 0), corner);
    canvas.drawLine(Offset.zero, const Offset(0, l), corner);
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - l, size.height),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - l),
      corner,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      3,
      Paint()..color = const Color(0xFF4C6B87),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
