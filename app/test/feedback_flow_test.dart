import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/feedback/feedback_page.dart';
import 'package:pathguide/feedback/feedback_store.dart';
import 'package:pathguide/feedback/feedback_trace.dart';
import 'package:pathguide/settings/app_settings.dart';
import 'package:pathguide/tts/flutter_tts_speaker.dart';

import 'encrypted_route_store_test.dart' show MemoryRouteVault;

void main() {
  test(
    'opt-in ring keeps the earlier actual utterance, and disabling clears it',
    () async {
      final settings = AppSettings.memory();
      var now = DateTime.utc(2026);
      final trace = FeedbackTrace(settings, 'outdoorReplay', clock: () => now);
      addTearDown(trace.dispose);
      expect(settings.feedbackEnabled, isFalse);
      trace.queue('關閉時');
      expect(trace.snapshot().events, isEmpty);
      await settings.setFeedbackEnabled(true);
      trace.context = {'lat': 22.3, 'lng': 114.1, 'accuracy': 5, 'segment': 2};
      final turn = trace.queue('左轉');
      trace.submitted('左轉', voiceOver: false, ticket: turn);
      trace.playback(TtsPlaybackEvent.started);
      trace.playback(TtsPlaybackEvent.completed);
      final ignored = trace.queue('右轉');
      trace.event('cancelled', {'utterance': ignored, 'text': '右轉'});
      trace.submitted('停低', voiceOver: true);
      now = now.add(const Duration(seconds: 7));
      final draft = trace.snapshot();
      final spoken = draft.events
          .where((event) => event['kind'] == 'started')
          .single;
      expect(spoken['text'], '左轉');
      expect(spoken['segment'], 2);
      expect(
        draft.events
            .where((e) => e['kind'] == 'voiceOverSubmitted')
            .single['text'],
        '停低',
      );
      await settings.setFeedbackEnabled(false);
      expect(trace.snapshot().events, isEmpty);
      expect(draft.events, isNotEmpty);

      await settings.setFeedbackEnabled(true);
      trace.queue('舊提示');
      now = now.add(const Duration(seconds: 46));
      expect(trace.snapshot().events, isEmpty);
    },
  );

  test('encrypted draft reopens, unsuccessful delivery keeps it, and retry uses the same ID', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pg-feedback-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final vault = MemoryRouteVault();
    Future<FeedbackStore> open() =>
        FeedbackStore.open(root: directory, vault: vault);
    final draft = FeedbackDraft(
      feedbackId(),
      'outdoorReplay',
      DateTime.utc(2026),
      [
        {'kind': 'started', 'text': 'left at a private location', 'lat': 22.3},
      ],
    );
    final store = await open();
    await store.save(draft);
    final raw = await File('${directory.path}/catalog.enc').readAsBytes();
    expect(String.fromCharCodes(raw), isNot(contains('private location')));
    final reopened = await open();
    expect((await reopened.list()).single.events, draft.events);
    expect(await reopened.send(draft, null), isFalse);
    final calls = <String>[];
    Future<bool> sender(FeedbackDraft item) async {
      calls.add(item.id);
      return calls.length > 1;
    }

    expect(await reopened.send(draft, sender), isFalse);
    expect((await reopened.list()).single.sent, isFalse);
    expect(await reopened.send(draft, sender), isTrue);
    expect(await reopened.send(draft, sender), isTrue);
    expect(calls, [draft.id, draft.id]);
    expect((await reopened.list()).single.sent, isTrue);
    await reopened.delete(draft.id);
    expect(await (await open()).list(), isEmpty);
  });
  testWidgets(
    'one tap preserves earlier speech and pending review remains available when disabled',
    (tester) async {
      final settings = AppSettings.memory();
      final trace = FeedbackTrace(settings, 'outdoorReplay');
      addTearDown(trace.dispose);
      final vault = MemoryRouteVault();
      late Directory root;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('pg-feedback-widget-');
      });
      addTearDown(() => root.delete(recursive: true));
      Future<FeedbackStore> open() =>
          FeedbackStore.open(root: root, vault: vault);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: settings,
              builder: (ctx, _) => Column(
                children: [
                  if (settings.feedbackEnabled)
                    CaptureFeedbackButton(trace: trace, openStore: open),
                  TextButton(
                    onPressed: () => Navigator.push<void>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) =>
                            FeedbackPage(settings: settings, openStore: open),
                      ),
                    ),
                    child: const Text('待處理回饋'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final capture = find.text('記錄回饋');
      expect(capture, findsNothing);
      await settings.setFeedbackEnabled(true);
      await tester.pump();
      trace.submitted('向左轉', voiceOver: false);
      trace.playback(TtsPlaybackEvent.started);
      trace.playback(TtsPlaybackEvent.completed);
      await tester.pump(const Duration(seconds: 4));
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 70 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(finder, findsOneWidget);
      }

      await tester.tap(capture);
      await waitFor(find.text('已記低，可以稍後補充'));
      expect(find.byType(AlertDialog), findsNothing);
      await settings.setFeedbackEnabled(false);
      await tester.pump();
      expect(capture, findsNothing);
      await tester.tap(find.text('待處理回饋'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final pending = find.text('待送出');
      await waitFor(pending);
      await tester.tap(pending);
      await tester.pumpAndSettle();
      expect(find.text('向左轉'), findsOneWidget);
      expect(find.text('App 已開始播報'), findsOneWidget);
      await tester.tap(find.text('確認送出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認'));
      await waitFor(find.text('收件服務未開通，回饋已保留待送。'));
      expect(find.text('已送出'), findsNothing);
      expect(pending, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
