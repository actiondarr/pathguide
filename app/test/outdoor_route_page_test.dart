import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/navigation/navigation_models.dart';
import 'package:pathguide/navigation/navigation_services.dart';
import 'package:pathguide/outdoor_routes/outdoor_recording_page.dart';
import 'package:pathguide/outdoor_routes/outdoor_replay_page.dart';
import 'package:pathguide/outdoor_routes/outdoor_route_list.dart';
import 'package:pathguide/outdoor_routes/outdoor_route_store.dart';
import 'package:pathguide/outdoor_routes/outdoor_track.dart';
import 'package:pathguide/route_memory/route_package.dart';
import 'package:pathguide/route_memory/route_audio_note_dialog.dart';
import 'package:pathguide/settings/app_settings.dart';
import 'package:pathguide/tts/announcer.dart';
import 'package:pathguide/ui/app_shell.dart';

import 'outdoor_route_fixtures.dart';
import 'support/route_audio_fixture.dart';

class TestLocation implements LocationService {
  final events = StreamController<LocationFix>.broadcast(
    sync: true,
    onCancel: () {},
  );
  int starts = 0, stops = 0;
  final awake = <bool>[];

  @override
  Stream<LocationFix> get updates => events.stream;
  @override
  Future<LocationFix> current() async => throw UnimplementedError();
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> keepAwake(bool enabled) async => awake.add(enabled);
  @override
  Future<String?> address(Coordinate coordinate) async =>
      throw UnimplementedError();
}

class RecordingSpeaker extends NullSpeaker {
  final spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
}

class TestStore implements OutdoorRouteStore {
  int writes = 0;
  RouteSnapshot? snapshot;

  @override
  Future<RouteSnapshot> save(String id, String name, OutdoorTrack track) async {
    if (++writes == 1) throw const RouteStoreFailure(RouteProblem.io);
    return snapshot = RouteSnapshot(
      RouteDocument(
        id: id,
        name: name,
        buildingId: 'outdoor',
        nodes: const [],
        edges: const [],
        source: RouteContentSource.outdoor,
        outdoor: track,
      ),
      1,
      track.draftReason == null,
      'fixture',
    );
  }

  @override
  Future<RouteLibraryListing> list() async {
    final saved = snapshot!;
    return RouteLibraryListing([
      RouteLibraryEntry(
        id: saved.document.id,
        name: saved.document.name,
        revision: 1,
        versions: const [1],
        rollbackVersions: const [],
        draftVersion: saved.published ? null : 1,
        activeVersion: saved.published ? 1 : null,
      ),
    ], 0);
  }

  @override
  Future<RouteSnapshot> read(RouteLibraryEntry entry) async => snapshot!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'iPhone navigation entry keeps My routes, indoor recording and outdoor recording',
    (t) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final methods = <String>[];
      const nav = MethodChannel('hk.pathguide/navigation');
      const events = MethodChannel('hk.pathguide/navigation/location');
      messenger.setMockMethodCallHandler(nav, (call) async {
        methods.add(call.method);
        if (call.method == 'startLocation') {
          expect((call.arguments as Map)['recordedTrack'], isTrue);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(nav, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      await t.pumpWidget(
        MaterialApp(
          home: AppShell(
            settings: AppSettings.memory(),
            initialSection: AppSection.navigation,
          ),
        ),
      );
      expect(find.text('我的路線'), findsOneWidget);
      final outdoor = find.widgetWithText(FilledButton, '錄製戶外路線');
      await t.scrollUntilVisible(outdoor, 300);
      await t.pumpAndSettle();
      await t.tap(outdoor);
      await t.pumpAndSettle();
      expect(find.byType(OutdoorRecordingPage), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
      expect(methods, contains('startLocation'));
      await t.pageBack();
      await t.pumpAndSettle();
      expect(methods, contains('stopLocation'));
      final indoor = find.widgetWithText(FilledButton, '錄製新路線');
      await t.scrollUntilVisible(
        indoor,
        250,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('navigation-hub')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(indoor, findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    '15-second VoiceOver flow reports two marks, undo, focus and save retry',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(430, 932);
      addTearDown(t.view.reset);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            accessibleNavigation: true,
            supportsAnnounce: true,
          );
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final semantics = t.ensureSemantics();

      final announcements = <String>[], eventTypes = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler(SystemChannels.accessibility, (
        message,
      ) async {
        if (message is Map) {
          eventTypes.add(message['type'] as String);
          if (message['type'] == 'announce') {
            announcements.add((message['data'] as Map)['message'] as String);
          }
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockDecodedMessageHandler(
          SystemChannels.accessibility,
          null,
        ),
      );
      final location = TestLocation(),
          store = TestStore(),
          settings = AppSettings.memory();
      addTearDown(location.events.close);
      var seconds = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Column(
                children: [
                  FilledButton(
                    onPressed: () => Navigator.push<String>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => OutdoorRecordingPage(
                          settings: settings,
                          location: location,
                          speaker: NullSpeaker(),
                          clock: () => elapsed(seconds),
                          wallClock: () => at(seconds),
                          openStore: () async => store,
                        ),
                      ),
                    ),
                    child: const Text('Open recorder'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.push<void>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          body: OutdoorRouteList(
                            settings: settings,
                            openStore: () async => store,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('我的路線'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String label) async {
        final target = find.text(label).last;
        await t.ensureVisible(target);
        await t.tap(target);
        await t.pumpAndSettle();
      }

      await tap('Open recorder');
      expect(announcements, contains(contains('等緊新鮮')));
      expect(find.byType(UiKitView), findsNothing);
      location.events.add(fix(0, 0, 0, speed: null));
      await t.pump();
      expect(announcements, contains('GPS 定位已確認，錄製中。'));
      await tap('加路標');
      final afterOpen = announcements.length;
      seconds = 10;
      await t.pump(const Duration(seconds: 10));
      expect(announcements.length, afterOpen);
      await tap('左前方');
      seconds = 15;
      await t.pump(const Duration(seconds: 5));
      await tap('台階');
      expect(announcements, containsAllInOrder(['已加路標，左前方。', '已加路標，台階。']));
      await tap('返回錄路');
      expect(find.text('累計距離 0 米'), findsOneWidget);
      expect(find.text('錄製時間 0 分 15 秒'), findsOneWidget);
      expect(find.text('軌跡點 1'), findsOneWidget);
      expect(find.text('路標 2'), findsOneWidget);
      expect(find.text('速度暫未能確定'), findsOneWidget);
      final markButton = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, '加路標'),
      );
      expect(markButton.focusNode?.hasFocus, isTrue);
      expect(eventTypes, contains('focus'));

      await tap('加路標');
      await tap('撤銷上個路標');
      expect(announcements.last, '已撤銷上個路標，台階。');
      await tap('返回錄路');
      expect(find.text('路標 1'), findsOneWidget);
      expect(find.text('累計距離 0 米'), findsOneWidget);
      await tap('結束並保存');
      expect(location.stops, 1);
      expect(find.textContaining('起點一個軌跡點'), findsOneWidget);
      await t.enterText(find.byType(TextField), '原地驗收');
      await tap('保存路線');
      expect(find.textContaining('錄製仍然保留'), findsOneWidget);
      expect(find.text('原地驗收'), findsOneWidget);
      await tap('再試保存');
      expect(store.writes, 2);
      expect(
        store.snapshot!.document.outdoor!.marks.single.kind,
        OutdoorMarkKind.aheadLeft,
      );
      await tap('我的路線');
      await tap('原地驗收');
      expect(find.byType(OutdoorReplayPage), findsOneWidget);
      expect(find.textContaining('起點一個軌跡點'), findsOneWidget);
      expect(find.text('開始重行'), findsNothing);
      expect(t.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'recording pauses and an app background return requests a new fix',
    (t) async {
      final location = TestLocation();
      addTearDown(location.events.close);
      var seconds = 0;
      await t.pumpWidget(
        MaterialApp(
          home: OutdoorRecordingPage(
            settings: AppSettings.memory(),
            location: location,
            speaker: NullSpeaker(),
            clock: () => elapsed(seconds),
            wallClock: () => at(seconds),
          ),
        ),
      );
      await t.pump();
      location.events.add(fix(0, 0, 0));
      await t.pump();
      seconds = 5;
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.text('暫停'));
      await t.pump();
      seconds = 14;
      await t.pump(const Duration(seconds: 9));
      expect(find.text('錄製時間 0 分 5 秒'), findsOneWidget);
      expect(location.stops, 1);
      await t.tap(find.text('繼續'));
      await t.pump();
      expect(location.starts, 2);
      seconds = 15;
      location.events.add(fix(15, 50, 0));
      await t.pump();
      expect(find.text('軌跡點 2'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump();
      expect(location.stops, 2);
      seconds = 16;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(location.starts, 3);
      expect(find.textContaining('等緊新鮮'), findsOneWidget);
      location.events.add(fix(15, 50, 0));
      await t.pump();
      expect(find.text('軌跡點 2'), findsOneWidget);
      seconds = 17;
      location.events.add(fix(17, 150, 0));
      await t.pump();
      expect(find.text('累計距離 0 米'), findsOneWidget);
      expect(find.text('軌跡點 3'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(location.awake.last, isFalse);
    },
  );
  testWidgets(
    'saved route guides, reads marks and withholds arrival until confirmed',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(430, 932);
      addTearDown(t.view.reset);
      final location = TestLocation(), speech = RecordingSpeaker();
      addTearDown(location.events.close);
      final wave = RouteAudioNote.fromBytes(syntheticNoteWav());
      final playing = Completer<void>();
      final messages = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(RouteNoteAudio.channel, (call) async {
        messages.add(call);
        if (call.method == 'play') await playing.future;
        if (call.method == 'cancel' && !playing.isCompleted) playing.complete();
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(RouteNoteAudio.channel, null),
      );
      final point = OutdoorPoint(metres(10, 0), at(5), 3, 1.4);
      final track = cornerRoute(
        marks: [
          OutdoorMark(
            kind: OutdoorMarkKind.text,
            point: point,
            segment: 0,
            pointIndex: 1,
            text: '入口旁有長椅',
          ),
          OutdoorMark(
            kind: OutdoorMarkKind.audio,
            point: point,
            segment: 0,
            pointIndex: 1,
            audio: wave,
          ),
        ],
      );
      var seconds = 0;
      await t.pumpWidget(
        MaterialApp(
          home: OutdoorReplayPage(
            settings: AppSettings.memory(),
            location: location,
            speaker: speech,
            clock: () => elapsed(seconds),
            wallClock: () => at(seconds),
            snapshot: RouteSnapshot(
              RouteDocument(
                id: 'outdoor-test',
                name: '轉角試行',
                buildingId: 'outdoor',
                nodes: const [],
                edges: const [],
                source: RouteContentSource.outdoor,
                outdoor: track,
              ),
              1,
              true,
              'fixture',
            ),
          ),
        ),
      );
      await t.tap(find.text('開始重行'));
      await t.pump();
      Future<void> go(
        int time,
        int x,
        int y, {
        double? course,
        double accuracy = 3,
      }) async {
        seconds = time;
        location.events.add(
          fix(time, x, y, course: course, accuracy: accuracy),
        );
        await t.pump();
      }

      await go(1, 22, 0);
      expect(find.textContaining('未喺錄製起點'), findsOneWidget);
      await go(2, 0, 0);
      await go(5, 8, 0, course: 90);
      expect(find.text('入口旁有長椅'), findsOneWidget);
      expect(speech.spoken.last, contains('文字、錄音'));
      await t.tap(find.text('播放錄音備註'));
      await t.pump();
      expect(messages.last.method, 'play');
      await go(6, 8, 0, accuracy: 29);
      expect(messages.last.method, 'cancel');
      expect(find.text('入口旁有長椅'), findsNothing);
      expect(find.textContaining('定位暫時不足'), findsOneWidget);
      await go(11, 22, 0, course: 90);
      expect(find.textContaining('米後左轉'), findsOneWidget);
      await go(17, 30, 5, course: 0);
      await go(23, 30, 19, course: 0);
      await go(25, 30, 24, course: 0);
      expect(find.textContaining('定位未能分辨入口'), findsOneWidget);
      expect(speech.spoken, isNot(contains(contains('確認到達'))));
      expect(find.text('我已核對終點，結束重行'), findsNothing);
      await go(27, 30, 29);
      await t.tap(find.text('我已核對終點，結束重行'));
      await t.pump();
      expect(speech.spoken.last, '你已確認到達，重行結束。');
      expect(location.stops, 1);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
  testWidgets(
    'recording saves text and on-demand audio at the captured position',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(430, 932);
      addTearDown(t.view.reset);
      final wave = syntheticNoteWav();
      final methods = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(RouteNoteAudio.channel, (call) async {
        methods.add(call.method);
        return switch (call.method) {
          'start' => 10000,
          'finish' => wave,
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(RouteNoteAudio.channel, null),
      );
      final location = TestLocation(), store = TestStore()..writes = 1;
      addTearDown(location.events.close);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => Navigator.push<String>(
                ctx,
                MaterialPageRoute(
                  builder: (_) => OutdoorRecordingPage(
                    settings: AppSettings.memory(),
                    location: location,
                    speaker: NullSpeaker(),
                    clock: () => elapsed(0),
                    wallClock: () => at(0),
                    openStore: () async => store,
                  ),
                ),
              ),
              child: const Text('Open recorder'),
            ),
          ),
        ),
      );
      Future<void> tap(String label) async {
        final target = find.text(label).last;
        await t.ensureVisible(target);
        await t.tap(target);
        await t.pumpAndSettle();
      }

      await tap('Open recorder');
      location.events.add(fix(0, 0, 0, speed: null));
      await t.pump();
      await tap('加路標');
      await tap('文字');
      await t.enterText(find.byType(TextField), '台階旁有欄杆');
      await tap('加文字路標');
      await tap('錄音');
      expect(methods, isEmpty);
      await tap('開始錄音');
      expect(methods, ['start']);
      await tap('停止錄音');
      expect(methods, contains('finish'));
      await tap('套用錄音');
      await tap('返回錄路');
      expect(find.text('路標 2'), findsOneWidget);
      expect(find.text('軌跡點 1'), findsOneWidget);
      expect(find.text('累計距離 0 米'), findsOneWidget);
      await tap('結束並保存');
      await t.enterText(find.byType(TextField), '備註路線');
      await tap('保存路線');
      final marks = store.snapshot!.document.outdoor!.marks;
      expect(marks.first.text, '台階旁有欄杆');
      expect(marks.last.audio!.bytes, orderedEquals(wave));
      expect(marks.map((m) => m.pointIndex), [0, 0]);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
