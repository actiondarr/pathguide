import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../settings/app_settings.dart';
import '../tts/announcer.dart';
import '../tts/flutter_tts_speaker.dart';
import 'depth_session.dart';

class DepthPage extends StatefulWidget {
  const DepthPage({
    super.key,
    required this.settings,
    this.onBack,
    this.source,
    this.speaker,
    this.preview,
  });
  final AppSettings settings;
  final VoidCallback? onBack;
  final DepthSource? source;
  final Speaker? speaker;
  final Widget? preview;
  @override
  State<DepthPage> createState() => _DepthPageState();
}

class _DepthPageState extends State<DepthPage> with WidgetsBindingObserver {
  late final _session = DepthSession(widget.source ?? PlatformDepthSource());
  late final _speaker =
      widget.speaker ??
      FlutterTtsSpeaker(
        language: widget.settings.language,
        speechRate: widget.settings.speechSpeed.rate,
      );
  bool _foreground = true, _reading = false;
  int _speechGeneration = 0;
  String? _speechError;
  bool get _english => widget.settings.language == AppLanguage.english;
  String _t(String zh, String en) => _english ? en : zh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_session.rangeM == null && _reading) unawaited(_stopSpeech());
    setState(() {});
  }

  Future<void> _stopSpeech() async {
    ++_speechGeneration;
    _reading = false;
    try {
      await _speaker.stop();
    } catch (_) {}
  }

  Future<void> _toggle() async {
    await _stopSpeech();
    if (!mounted || !_foreground) return;
    _speechError = null;
    if (_session.running) {
      await _session.stop();
    } else {
      await _session.start();
    }
  }

  String get _status => switch (_session.status) {
    'idle' => _t('未開始測距', 'Measurement not started'),
    'starting' || 'waiting' => _t('正在準備深度資料', 'Preparing depth data'),
    'ready' => _t('中央表面估算距離', 'Estimated range to centre surface'),
    'stabilizing' ||
    'moving' => _t('請保持手機及準星穩定', 'Hold the phone and crosshair steady'),
    'tracking' => _t('追蹤未穩定，距離未知', 'Tracking unstable; range unknown'),
    'permission' => _t(
      '未獲相機權限，請到系統設定允許',
      'Camera access unavailable. Allow it in system settings.',
    ),
    'unsupported' => _t(
      '此裝置不支援 LiDAR 場景深度',
      'This device does not support LiDAR scene depth',
    ),
    'paused' => _t('已暫停，按開始重新量度', 'Paused. Press Start to measure again.'),
    'interrupted' => _t('相機中斷，請重新開始', 'Camera interrupted. Start again.'),
    'stale' => _t('資料過期，距離未知', 'Data expired; range unknown'),
    'failed' => _t('未能測距，請重新開始', 'Measurement unavailable. Start again.'),
    _ => _t('表面資料不足，距離未知', 'Insufficient surface data; range unknown'),
  };
  String get _distance => _session.rangeM == null
      ? _t('距離未知', 'Range unknown')
      : '${_t('約 ', 'About ')}${_session.rangeM!.toStringAsFixed(1)} ${_t('米', 'm')}';

  Future<void> _read() async {
    final stopping = _stopSpeech();
    final generation = _speechGeneration;
    await stopping;
    if (!mounted ||
        !_foreground ||
        _session.rangeM == null ||
        generation != _speechGeneration) {
      return;
    }
    setState(() {
      _reading = true;
      _speechError = null;
    });
    try {
      final speaker = _speaker;
      if (!MediaQuery.accessibleNavigationOf(context) &&
          speaker is FlutterTtsSpeaker) {
        await speaker.setAppLanguage(widget.settings.language);
        await speaker.setSpeechRate(widget.settings.speechSpeed.rate);
        await speaker.initialize();
        if (speaker.resolvedLanguage == null) throw StateError('no voice');
      }
      if (!mounted ||
          !_foreground ||
          generation != _speechGeneration ||
          _session.rangeM == null) {
        return;
      }
      // Read the latest value only after asynchronous voice initialization.
      final message =
          '${_t('準星所指表面，', 'Surface at the crosshair. ')}$_distance';
      if (MediaQuery.accessibleNavigationOf(context)) {
        await SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        );
      } else {
        await speaker.speak(message);
      }
    } catch (_) {
      if (mounted && generation == _speechGeneration) {
        setState(
          () => _speechError = _t(
            '未能朗讀，可用讀屏查看。',
            'Speech unavailable. Use the screen reader.',
          ),
        );
      }
    } finally {
      if (mounted && generation == _speechGeneration) {
        setState(() => _reading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      unawaited(_stopSpeech());
      unawaited(_session.stop());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    unawaited(_stopSpeech());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(_t('返回導航', 'Back to navigation')),
                ),
              ),
              Text(
                _t('LiDAR 測距（試驗）', 'LiDAR range (trial)'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  '站定，將中央準星對準實心表面，再按開始。只量鏡頭至表面的距離；不是物件最近邊緣、行走距離或可通行判斷。',
                  'Stand still, aim the centre crosshair at a solid surface, then press Start. Measures camera-to-surface range; not the nearest object edge, walking distance or free space.',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        child:
                            widget.preview ??
                            (!kIsWeb && Platform.isIOS
                                ? const UiKitView(
                                    viewType: 'hk.pathguide/depth/preview',
                                  )
                                : const ColoredBox(color: Colors.black)),
                      ),
                      const IgnorePointer(
                        child: Center(
                          child: Icon(
                            Icons.add,
                            color: Colors.yellow,
                            size: 42,
                          ),
                        ),
                      ),
                      if (!_session.running)
                        const ColoredBox(color: Color(0xBB000000)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(_status, key: const ValueKey('depth-status')),
              Text(
                _distance,
                key: const ValueKey('depth-range'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                _t(
                  '只在本機處理，不儲存或上傳畫面、深度或行走資料。玻璃、鏡面、細邊及混合表面可能不可靠；這版尚未完成量尺驗證。',
                  'Processed on device. No images, depth or walking data are saved or uploaded. Glass, mirrors, thin edges and mixed surfaces may be unreliable. Ruler validation is pending.',
                ),
              ),
              if (_session.rangeM != null) ...[
                const SizedBox(height: 12),
                Text(
                  _t(
                    '量尺核對：從後置鏡頭位置至準星表面量度，分別試 0.5、1、2、3 米；記錄讀數及「未知」。',
                    'Ruler check: measure from the rear camera to the target surface at 0.5, 1, 2 and 3 metres. Record readings and unknown results.',
                  ),
                ),
              ],
              if (_speechError != null) Text(_speechError!),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('depth-toggle'),
                onPressed: _foreground ? _toggle : null,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                child: Text(
                  _session.running
                      ? _t('暫停測距', 'Pause measurement')
                      : _t('開始測距', 'Start measurement'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('depth-read'),
                onPressed: _reading
                    ? () {
                        unawaited(_stopSpeech());
                        setState(() {});
                      }
                    : _foreground && _session.rangeM != null
                    ? _read
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 52),
                ),
                child: Text(
                  _reading
                      ? _t('停止朗讀', 'Stop reading')
                      : _t('朗讀目前距離', 'Read current range'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
