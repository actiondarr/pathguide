import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:url_launcher/url_launcher.dart';

import '../menu/menu_reader.dart';
import '../settings/app_settings.dart';
import '../tts/announcer.dart';
import '../tts/flutter_tts_speaker.dart';
import 'destination_store.dart';
import 'navigation_controller.dart';
import 'navigation_models.dart';
import 'navigation_services.dart';
import 'platform_navigation.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({
    super.key,
    required this.settings,
    this.controller,
    this.speech,
    this.speaker,
    this.mapBuilder,
    this.onTaskChanged,
  });
  final AppSettings settings;
  final NavigationController? controller;
  final SpeechInputService? speech;
  final Speaker? speaker;
  final Widget Function(WalkingRoute?, Place?)? mapBuilder;
  final ValueChanged<bool>? onTaskChanged;
  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage>
    with WidgetsBindingObserver {
  late final _platform = NavigationPlatform.create();
  late final _nav =
      widget.controller ??
      NavigationController(
        searchService: _platform.services,
        routeService: _platform.services,
        location: _platform.services,
        store: SecureDestinationStore(),
        clock: navigationNow,
      );
  late final _speech = widget.speech ?? _platform.speech;
  late final Speaker _speaker =
      widget.speaker ??
      FlutterTtsSpeaker(speechRate: widget.settings.speechSpeed.rate);
  final _query = TextEditingController();
  int _outputGeneration = 0, _voiceGeneration = 0, _lastAnnouncement = 0;
  bool _foreground = true, _listening = false;
  bool _confirmingEnd = false;
  String? _speechStatus, _pending;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nav.addListener(_changed);
    unawaited(_nav.initialize());
  }

  void _changed() {
    if (!mounted) return;
    widget.onTaskChanged?.call(_nav.hasTask);
    if (_lastAnnouncement != _nav.announcementId) {
      _lastAnnouncement = _nav.announcementId;
      final text = _nav.announcement;
      if (text != null && !_listening && !_confirmingEnd) unawaited(_say(text));
    }
    setState(() {});
  }

  Future<void> _stop() async {
    ++_outputGeneration;
    await _speaker.stop();
  }

  Future<void> _say(String text) async {
    final stopping = _stop();
    final generation = _outputGeneration;
    await stopping;
    if (!mounted || generation != _outputGeneration || _listening) return;
    if (!_foreground) {
      _pending = text;
      return;
    }
    try {
      if (MediaQuery.accessibleNavigationOf(context)) {
        await SemanticsService.sendAnnouncement(
          View.of(context),
          text,
          Directionality.of(context),
        );
      } else {
        final tts = _speaker;
        if (tts is FlutterTtsSpeaker) {
          await tts.setSpeechRate(widget.settings.speechSpeed.rate);
          await tts.initialize();
          if (!mounted || generation != _outputGeneration || !_foreground) {
            return;
          }
          if (tts.resolvedLanguage == null) throw StateError('tts unavailable');
          if (!tts.isCantonese) {
            setState(() => _speechStatus = '此裝置未提供粵語，正使用其他中文語音。');
          }
        }
        await _speaker.speak(text);
      }
    } catch (_) {
      if (mounted) setState(() => _speechStatus = '未能朗讀，可用讀屏或畫面查看指示。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _nav.foreground();
      final text = _pending;
      _pending = null;
      if (text != null) unawaited(_say(text));
    } else {
      unawaited(_stop());
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached) {
        _pending = null;
        ++_voiceGeneration;
        _listening = false;
        unawaited(_speech.cancel());
        unawaited(_nav.pause(background: true));
      }
    }
  }

  Future<void> _voice({bool allowNetwork = false}) async {
    final generation = ++_voiceGeneration;
    await _stop();
    if (!mounted || generation != _voiceGeneration) return;
    setState(() {
      _listening = true;
      _speechStatus = '正在準備咪高峰，震動後請講出目的地。';
    });
    try {
      final result = await _speech.listen(
        allowNetwork: allowNetwork,
        onPartial: (text) {
          if (mounted && generation == _voiceGeneration) {
            setState(() => _query.text = text);
          }
        },
        onPhase: (phase) {
          if (mounted && generation == _voiceGeneration) {
            setState(
              () => _speechStatus = switch (phase) {
                MenuSpeechPhase.preparing => '正在準備咪高峰。',
                MenuSpeechPhase.listening => '正在聆聽，講完稍停便會搜尋。',
                MenuSpeechPhase.finishing => '正在整理語音。',
              },
            );
          }
        },
      );
      if (!mounted || generation != _voiceGeneration) return;
      setState(() => _listening = false);
      if (result.outcome == MenuSpeechOutcome.cancelled) return;
      if (result.text.trim().isEmpty) {
        await _say('未聽清楚，請重試或輸入目的地。');
        return;
      }
      _query.text = destinationQuery(result.text);
      await _search(_query.text);
    } on MenuFailure catch (e) {
      if (!mounted || generation != _voiceGeneration) return;
      setState(() {
        _listening = false;
        _speechStatus = e.message;
      });
      if (e.code == 'offline_speech_unavailable') {
        final agreed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('使用線上語音辨識？'),
            content: const Text('此裝置未提供可確認的離線粵語收音。系統語音服務可能經網絡處理你的聲音；也可以用文字搜尋。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('使用文字'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('同意這次使用'),
              ),
            ],
          ),
        );
        if (agreed == true && mounted && generation == _voiceGeneration) {
          await _voice(allowNetwork: true);
        }
      } else {
        await _say(e.message);
      }
    } catch (_) {
      if (mounted && generation == _voiceGeneration) {
        setState(() {
          _listening = false;
          _speechStatus = '未能收音，請用文字搜尋。';
        });
      }
    }
  }

  Future<String?> _name(String initial) async {
    var name = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('收藏名稱'),
        content: TextFormField(
          initialValue: initial,
          onChanged: (value) => name = value,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '請輸入收藏名稱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _end() async {
    if (_confirmingEnd) return;
    _confirmingEnd = true;
    await _stop();
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('結束導航？'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('繼續導航'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認結束'),
          ),
        ],
      ),
    );
    _confirmingEnd = false;
    if (!mounted) return;
    if (yes == true) {
      await _stop();
      await _nav.end();
    } else if (_foreground &&
        (_nav.state == NavigationState.navigating ||
            _nav.state == NavigationState.nearby)) {
      await _say(_nav.nextInstruction());
    }
  }

  Future<void> _privacy() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('導航服務說明'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '搜尋及路線查詢會把查詢字詞、起點和目的地傳送至 Apple 或 Google。Android 路線會經本專案的代理服務；不保存行走軌跡。收藏只保存在此手機。步行路線的樓梯、升降機及入口未經實地核實。',
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://maps.google.com/help/terms_maps/'),
              ),
              child: const Text('Google Maps 使用條款'),
            ),
            TextButton(
              onPressed: () =>
                  launchUrl(Uri.parse('https://policies.google.com/privacy')),
              child: const Text('Google 私隱政策'),
            ),
            if (const String.fromEnvironment('NAVIGATION_PRIVACY_URL')
                .isNotEmpty)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    const String.fromEnvironment('NAVIGATION_PRIVACY_URL'),
                  ),
                ),
                child: const Text('領路通導航私隱政策'),
              ),
            if (const String.fromEnvironment('NAVIGATION_TERMS_URL').isNotEmpty)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    const String.fromEnvironment('NAVIGATION_TERMS_URL'),
                  ),
                ),
                child: const Text('領路通導航使用條款'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_voiceGeneration;
    _pending = null;
    _nav.removeListener(_changed);
    _nav.dispose();
    unawaited(_stop());
    unawaited(_speech.cancel());
    _speech.dispose();
    _query.dispose();
    super.dispose();
  }

  Widget _button(String text, VoidCallback? action, {bool primary = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: primary
            ? FilledButton(
                onPressed: action,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(text),
              )
            : OutlinedButton(
                onPressed: action,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(text),
              ),
      );
  Widget _saved(SavedDestination saved, {required bool favorite}) => ListTile(
    title: Text(saved.label),
    onTap: _nav.busy || _listening
        ? null
        : () {
            FocusManager.instance.primaryFocus?.unfocus();
            _nav.selectSaved(saved);
          },
    trailing: favorite
        ? PopupMenuButton<String>(
            tooltip: '管理 ${saved.label}',
            onSelected: (action) async {
              if (action == 'delete') {
                await _nav.removeFavorite(saved);
              } else {
                final name = await _name(saved.label);
                if (name != null) await _nav.renameFavorite(saved, name);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('改名')),
              PopupMenuItem(value: 'delete', child: Text('刪除')),
            ],
          )
        : null,
  );

  Future<void> _search(String text) {
    FocusManager.instance.primaryFocus?.unfocus();
    return _nav.search(text);
  }

  Future<void> _position() async {
    final generation = _outputGeneration;
    final text = await _nav.currentPosition();
    if (mounted && generation == _outputGeneration && _foreground) {
      await _say(text);
    }
  }

  Future<void> _pause() async {
    await _stop();
    await _nav.pause();
  }

  Future<void> _retryGuidance() async {
    await _pause();
    if (mounted && _foreground) await _nav.start();
  }

  Widget _taskPanel() {
    final nav = _nav;
    final paused = nav.state == NavigationState.paused;
    final failed = nav.state == NavigationState.failed;
    final poor = nav.state == NavigationState.locationPoor;
    final nearby = nav.state == NavigationState.nearby;
    final guiding = nav.state == NavigationState.navigating;
    final instruction = guiding ? nav.progress!.instruction : nav.message;
    return Material(
      key: const ValueKey('navigation-controls'),
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                instruction,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (guiding)
                Text(
                  '下一步約 ${nav.progress!.nextDistance.round()} 米，剩餘約 ${nav.progress!.remaining.round()} 米。',
                ),
              Text(
                nav.locationStatus,
                key: const ValueKey('navigation-location-status'),
              ),
              if (paused || failed)
                _button(
                  paused ? '繼續導航' : '重新定位並繼續',
                  nav.busy ? null : nav.start,
                  primary: true,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _button(
                        poor
                            ? '重新定位'
                            : nearby
                            ? '重播到達提示'
                            : '重播下一步',
                        nav.busy
                            ? null
                            : poor
                            ? _retryGuidance
                            : () => _say(nav.nextInstruction()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _button('目前位置', nav.busy ? null : _position),
                    ),
                  ],
                ),
              Row(
                children: [
                  if (!paused && !failed) ...[
                    Expanded(child: _button('暫停導航', _pause)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: _button(nearby ? '確認入口並結束' : '結束導航', _end)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = _nav, route = nav.route, place = nav.destination;
    final hasTask = nav.hasTask;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              key: const ValueKey('navigation-home'),
              padding: const EdgeInsets.all(20),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    '路線導航',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const Text('香港戶外步行輔助；樓梯、升降機及入口未經核實。'),
                if (nav.searchService.provider == MapProvider.google)
                  const Text('Google Maps 步行路線仍屬測試功能，可能缺少行人路或步行通道資料。'),
                TextButton(onPressed: _privacy, child: const Text('導航服務及私隱說明')),
                Text(nav.message),
                if (_speechStatus != null) Text(_speechStatus!),
                if (nav.busy) const LinearProgressIndicator(),
                if (!hasTask) ...[
                  TextField(
                    controller: _query,
                    enabled: !_listening && !nav.busy,
                    decoration: const InputDecoration(
                      labelText: '搜尋目的地',
                      hintText: '輸入香港地點或地址',
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                  ),
                  _button(
                    '搜尋',
                    !nav.busy && !_listening
                        ? () => _search(_query.text)
                        : null,
                    primary: true,
                  ),
                  if (nav.busy) _button('取消查詢', () => nav.end()),
                  _button(
                    _listening ? '取消收音' : '講出目的地',
                    nav.busy
                        ? null
                        : _listening
                        ? () async {
                            ++_voiceGeneration;
                            await _speech.cancel();
                            if (mounted) setState(() => _listening = false);
                          }
                        : _voice,
                  ),
                  if (nav.searchService.provider == MapProvider.google)
                    const Text('搜尋資料：Google Maps'),
                  for (final result in nav.results)
                    ListTile(
                      title: Text(result.name),
                      subtitle: Text(result.address),
                      onTap: nav.busy || _listening
                          ? null
                          : () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              nav.select(result);
                            },
                    ),
                ],
                if (place != null) ...[
                  Semantics(
                    header: true,
                    child: Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(place.address),
                  if (route != null) ...[
                    Text(
                      '全程約 ${route.distance.round()} 米，出發預估約 ${(route.duration / 60).ceil()} 分鐘。',
                    ),
                    (widget.mapBuilder ?? _platform.map)(route, place),
                    for (final notice in route.notices) Text(notice),
                    if (nav.progress != null && hasTask) ...[
                      Text(
                        nav.state == NavigationState.navigating
                            ? nav.progress!.instruction
                            : nav.message,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                    if (!hasTask) ...[
                      for (final step in route.steps)
                        if (step.instructions.trim().isNotEmpty)
                          ListTile(
                            title: Text(step.instructions),
                            subtitle: step.notice.isEmpty
                                ? null
                                : Text(step.notice),
                          ),
                    ],
                  ],
                  if (!hasTask)
                    _button(
                      nav.state == NavigationState.preview && route != null
                          ? '開始導航'
                          : '重新取得路線',
                      nav.busy || _listening
                          ? null
                          : nav.state == NavigationState.preview &&
                                route != null
                          ? nav.start
                          : nav.retryPreview,
                      primary: true,
                    ),
                  _button(
                    '收藏目的地',
                    nav.busy
                        ? null
                        : () async {
                            final label = await _name(
                              nav.searchService.provider == MapProvider.google
                                  ? ''
                                  : place.name,
                            );
                            if (label != null) await nav.favorite(label);
                          },
                  ),
                  if (!hasTask) _button('修改目的地', () => nav.end()),
                ],
                if (!hasTask) ...[
                  Semantics(header: true, child: const Text('此手機收藏')),
                  for (final p in nav.favorites) _saved(p, favorite: true),
                  Semantics(header: true, child: const Text('最近使用')),
                  for (final p in nav.recent) _saved(p, favorite: false),
                  TextButton(
                    onPressed: () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('清除收藏及最近使用？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('確認清除'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true) await nav.clearSaved();
                    },
                    child: const Text('清除此手機地點'),
                  ),
                  const Text('錄製路線（開發中）'),
                ],
              ],
            ),
          ),
          if (hasTask) _taskPanel(),
        ],
      ),
    );
  }
}
