import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../route_memory/route_audio_note_dialog.dart';
import '../route_memory/route_package.dart';
import '../settings/app_settings.dart';
import '../tts/flutter_tts_speaker.dart';
import 'feedback_store.dart';
import 'feedback_trace.dart';

String _label(AppSettings settings, String zh, String en) =>
    settings.language == AppLanguage.english ? en : zh;

class CaptureFeedbackButton extends StatefulWidget {
  const CaptureFeedbackButton({super.key, required this.trace, this.openStore});
  final FeedbackTrace trace;
  final Future<FeedbackStore> Function()? openStore;

  @override
  State<CaptureFeedbackButton> createState() => _CaptureFeedbackButtonState();
}

class _CaptureFeedbackButtonState extends State<CaptureFeedbackButton> {
  bool _saving = false;
  Future<void> _save() async {
    if (_saving || !widget.trace.settings.feedbackEnabled) return;
    final draft = widget.trace.snapshot(), settings = widget.trace.settings;
    setState(() => _saving = true);
    var message = _label(
      settings,
      '已記低，可以稍後補充',
      'Recorded. You can add details later.',
    );
    try {
      final store = await (widget.openStore ?? FeedbackStore.open)();
      await store.save(draft);
    } catch (_) {
      message = _label(
        settings,
        '未能保存回饋，請檢查本機空間或再試。',
        'Could not save feedback. Check local storage or try again.',
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _saving ? null : _save,
    icon: const Icon(Icons.flag_outlined),
    label: Text(_label(widget.trace.settings, '記錄回饋', 'Record feedback')),
  );
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({
    super.key,
    required this.settings,
    this.openStore,
    this.transport,
  });
  final AppSettings settings;
  final Future<FeedbackStore> Function()? openStore;
  final FeedbackTransport? transport;
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage>
    with WidgetsBindingObserver {
  FeedbackStore? _store;
  List<FeedbackDraft> _drafts = const [];
  String? _message;
  bool _busy = true;
  late final _tts = FlutterTtsSpeaker(
    language: widget.settings.language,
    speechRate: widget.settings.speechSpeed.rate,
  );
  final _audio = RouteNoteAudio();
  String t(String zh, String en) => _label(widget.settings, zh, en);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() => _run(() async {
    _store ??= await (widget.openStore ?? FeedbackStore.open)();
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      _drafts = await _store!.list();
    } catch (_) {
      _message = t(
        '操作未完成，請解鎖裝置或檢查儲存空間後重試。',
        'Could not complete the action. Unlock the device or check storage, then retry.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('確認', 'Confirm')),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _send(FeedbackDraft draft) => _run(() async {
    try {
      final sent = await _store!.send(draft, widget.transport);
      _message = sent
          ? t('已送出', 'Sent')
          : widget.transport == null
          ? t(
              '收件服務未開通，回饋已保留待送。',
              'Receiving service unavailable. Feedback remains pending.',
            )
          : t(
              '送出未獲確認，回饋已保留，可稍後再試。',
              'Delivery was not confirmed. Feedback remains pending for retry.',
            );
    } catch (_) {
      _message = t(
        '送出未獲確認，請稍後用同一份回饋再試。',
        'Delivery was not confirmed. Retry the same feedback later.',
      );
    }
  });

  Future<void> _listen(String text) async {
    if (MediaQuery.accessibleNavigationOf(context)) {
      if (MediaQuery.supportsAnnounceOf(context)) {
        await SemanticsService.sendAnnouncement(
          View.of(context),
          text,
          Directionality.of(context),
        );
      }
      return;
    }
    await _tts.stop();
    if (mounted) await _tts.speak(text);
  }

  Future<void> _attachAudio(FeedbackDraft draft) async {
    RouteAudioNote? clip;
    var applied = false;
    await _tts.stop();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => RouteAudioNoteDialog(
        markName: t('回饋備註', 'Feedback note'),
        initial: draft.audio == null
            ? null
            : RouteAudioNote.fromBase64(draft.audio!),
        translate: t,
        apply: (value) {
          clip = value;
          applied = true;
          return true;
        },
      ),
    );
    // A dismissed dialog must leave the stored clip unchanged.
    if (!applied || !mounted) return;
    await _run(
      () => _store!.save(
        FeedbackDraft(
          draft.id,
          draft.mode,
          draft.savedAt,
          draft.events,
          audio: clip?.encoded,
          photo: draft.photo,
        ),
      ),
    );
  }

  Future<void> _attachPhoto(FeedbackDraft draft) => _run(() async {
    final photo = await const MethodChannel(
      'hk.pathguide/menu',
    ).invokeMethod<Uint8List>('pickFeedbackPhoto', {'requestId': feedbackId()});
    if (photo == null || !mounted) return;
    await _store!.save(
      FeedbackDraft(
        draft.id,
        draft.mode,
        draft.savedAt,
        draft.events,
        audio: draft.audio,
        photo: base64Encode(photo),
      ),
    );
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_tts.stop());
      unawaited(_audio.cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tts.stop());
    unawaited(_audio.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('待處理回饋', 'Saved feedback'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_message != null)
          Semantics(liveRegion: true, child: Text(_message!)),
        if (_busy)
          const LinearProgressIndicator()
        else if (_store == null)
          OutlinedButton(onPressed: _load, child: Text(t('重新讀取', 'Reload')))
        else if (_drafts.isEmpty)
          Text(t('暫無已保存回饋。', 'No saved feedback.')),
        for (final draft in _drafts)
          ExpansionTile(
            key: ValueKey(draft.id),
            title: Text(
              '${MaterialLocalizations.of(context).formatFullDate(draft.savedAt.toLocal())} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(draft.savedAt.toLocal()))}',
            ),
            subtitle: Text(draft.sent ? t('已送出', 'Sent') : t('待送出', 'Pending')),
            children: [
              Text(
                draft.mode == 'recognition'
                    ? t('即時辨識', 'Live recognition')
                    : t('戶外導航', 'Outdoor navigation'),
              ),
              if (!draft.sent && widget.transport == null)
                Text(
                  t(
                    '收件服務未開通。回饋留喺本機。',
                    'The receiving service is unavailable. Feedback is stored locally.',
                  ),
                ),
              if (draft.events.any((event) => event['lat'] != null))
                ExpansionTile(
                  title: Text(
                    t('查看定位及路段紀錄', 'Review location and segment records'),
                  ),
                  children: [
                    for (final item in draft.events.where(
                      (event) =>
                          event['kind'] == 'location' ||
                          event['kind'] == 'navigation',
                    ))
                      ListTile(
                        title: Text('${item['at']} · ${item['state']}'),
                        subtitle: Text(
                          t(
                            '定位 ${item['lat'] ?? '—'}, ${item['lng'] ?? '—'}，誤差 ${item['accuracy'] ?? '—'} 米，路段 ${item['segment'] ?? '—'}',
                            'Location ${item['lat'] ?? '—'}, ${item['lng'] ?? '—'}, accuracy ${item['accuracy'] ?? '—'} m, segment ${item['segment'] ?? '—'}',
                          ),
                        ),
                      ),
                  ],
                ),
              for (final event in draft.events.where(
                (e) =>
                    e['kind'] == 'started' || e['kind'] == 'voiceOverSubmitted',
              ))
                ListTile(
                  title: Text(event['text'] as String),
                  subtitle: Text(
                    event['kind'] == 'started'
                        ? t('App 已開始播報', 'App playback started')
                        : t(
                            '已交予 VoiceOver，起音未能核實',
                            'Submitted to VoiceOver. Playback start unverified.',
                          ),
                  ),
                  trailing: IconButton(
                    tooltip: t('重聽提示', 'Replay prompt'),
                    icon: const Icon(Icons.volume_up),
                    onPressed: () => _listen(event['text'] as String),
                  ),
                ),
              if (draft.audio != null)
                OutlinedButton(
                  onPressed: () async {
                    await _tts.stop();
                    await _audio.play(RouteAudioNote.fromBase64(draft.audio!));
                  },
                  child: Text(t('播放語音備註', 'Play voice note')),
                ),
              if (draft.photo != null)
                Image.memory(
                  base64Decode(draft.photo!),
                  height: 120,
                  semanticLabel: t('附圖', 'Attached photo'),
                ),
              if (!draft.sent && RouteNoteAudio.supported) ...[
                OutlinedButton(
                  onPressed: _busy ? null : () => _attachAudio(draft),
                  child: Text(t('加語音備註', 'Add voice note')),
                ),
                if (draft.mode == 'recognition')
                  OutlinedButton(
                    onPressed: _busy ? null : () => _attachPhoto(draft),
                    child: Text(t('選擇附圖', 'Choose photo')),
                  ),
              ],
              if (!draft.sent)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm(
                                t(
                                  '送出已保存事件、附圖及語音備註？導航事件可包含位置。',
                                  'Send the saved events and attachments? Navigation events may include location.',
                                ),
                              ) &&
                              mounted) {
                            await _send(draft);
                          }
                        },
                  child: Text(t('確認送出', 'Review and send')),
                ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm(
                              t('刪除本機回饋？', 'Delete local feedback?'),
                            ) &&
                            mounted) {
                          await _run(() => _store!.delete(draft.id));
                        }
                      },
                child: Text(t('刪除回饋', 'Delete feedback')),
              ),
            ],
          ),
      ],
    ),
  );
}
