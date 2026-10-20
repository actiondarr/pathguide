import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/main.dart';
import 'package:pathguide/overlay/box_painter.dart';
import 'package:pathguide/settings/app_settings.dart';
import 'package:pathguide/ui/app_shell.dart';
import 'package:pathguide/ui/demo_page.dart';
import 'package:pathguide/vision/vision_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final visionCalls = <String>[];
  final speechCalls = <MethodCall>[];
  var failSpeechSetup = false;
  var speechLanguages = <String>['zh-HK', 'yue-HK'];
  Completer<Object?>? speechSetup;
  Completer<Object?>? speechStop;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    visionCalls.clear();
    speechCalls.clear();
    failSpeechSetup = false;
    speechLanguages = <String>['zh-HK', 'yue-HK'];
    speechSetup = null;
    speechStop = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      speechCalls.add(call);
      if (call.method == 'stop' && speechStop != null) {
        return speechStop!.future;
      }
      if (call.method == 'setSpeechRate') {
        if (failSpeechSetup) throw PlatformException(code: 'voice_unavailable');
        if (speechSetup != null) return speechSetup!.future;
      }
      if (call.method == 'getLanguages') return speechLanguages;
      return 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('hk.pathguide/vision'),
      (call) async {
        visionCalls.add(call.method);
        return switch (call.method) {
          'startPreview' => <String, Object>{'started': true},
          'modelDir' => '/models',
          'fileSize' => -1,
          'loadModel' => <String, Object>{
            'loaded': true,
            'classes': 9,
            'inputSize': 640,
          },
          'status' => <String, Object>{'ready': true},
          _ => null,
        };
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('hk.pathguide/vision/frame'),
      (_) async => null,
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'flutter_tts',
      'hk.pathguide/vision',
      'hk.pathguide/vision/frame',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  Future<void> flushAsync(WidgetTester tester) async {
    // PlatformVision materializes the bundled model through multiple real async
    // hops. A plain fake-clock pump can observe the UI before that chain finishes.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> start(
    WidgetTester tester, {
    SourceMode initialMode = SourceMode.camera,
    AppSection initialSection = AppSection.explore,
    AppSettings? settings,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      PathGuideApp(
        initialMode: initialMode,
        initialSection: initialSection,
        settings: settings,
      ),
    );
    await tester.pump();
    await flushAsync(tester);
    await tester.pump(const Duration(milliseconds: 240));
  }

  Future<void> openControls(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('vision-settings-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('辨識控制'), findsOneWidget);
  }

  Future<void> closeControls(WidgetTester tester) async {
    await tester.tap(find.byTooltip('關閉辨識設定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('辨識控制'), findsNothing);
  }

  DetectionBoxPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<DetectionBoxPainter>()
      .single;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // 廣播流取消的完成通知可能在測試假時鐘以外的 zone。
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets(
    'app opens on the future navigation hub before requesting camera access',
    (tester) async {
      await start(tester, initialSection: AppSection.navigation);
      expect(find.text('想去哪裡？'), findsOneWidget);
      expect(find.text('搜尋目的地'), findsOneWidget);
      expect(find.text('我的路線'), findsOneWidget);
      expect(find.text('錄製新路線'), findsOneWidget);
      expect(find.text('開發中'), findsOneWidget);
      expect(visionCalls, isNot(contains('startPreview')));

      await tester.tap(find.text('搜尋目的地'));
      await tester.pumpAndSettle();
      expect(find.text('先使用即時辨識'), findsOneWidget);
      await tester.tap(find.text('先使用即時辨識'));
      await tester.pump();
      await flushAsync(tester);
      expect(find.byType(VisionPreview), findsOneWidget);
      expect(visionCalls, contains('startPreview'));
      await close(tester);
    },
  );

  testWidgets('bottom navigation leaves camera view and opens settings', (
    tester,
  ) async {
    await start(tester);
    expect(visionCalls, contains('startPreview'));

    await tester.tap(find.text('導航'));
    await tester.pumpAndSettle();
    expect(find.text('想去哪裡？'), findsOneWidget);
    expect(find.byType(VisionPreview), findsNothing);

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(find.text('播報速度'), findsOneWidget);
    expect(find.text('1 倍速'), findsOneWidget);
    await close(tester);
  });

  testWidgets('settings exposes a persistent-style speech speed picker', (
    tester,
  ) async {
    final settings = AppSettings.memory();
    await start(
      tester,
      initialSection: AppSection.settings,
      settings: settings,
    );

    expect(find.text('播報速度'), findsOneWidget);
    expect(find.text('1 倍速'), findsOneWidget);
    expect(visionCalls, isNot(contains('startPreview')));

    await tester.tap(find.byKey(const ValueKey<String>('speech-speed-row')));
    await tester.pumpAndSettle();
    expect(find.text('0.8 倍速'), findsOneWidget);
    expect(find.text('1.2 倍速'), findsOneWidget);

    await tester.tap(find.text('0.8 倍速'));
    await tester.pumpAndSettle();
    expect(settings.speechSpeed, SpeechSpeed.slow);
    expect(find.text('0.8 倍速'), findsOneWidget);

    await tester.tap(find.text('即時辨識設定'));
    await tester.pump();
    await flushAsync(tester);
    expect(
      speechCalls
          .where((call) => call.method == 'setSpeechRate')
          .last
          .arguments,
      0.35,
    );
    await close(tester);
  });

  testWidgets(
    'future settings only explain requirements without starting a service',
    (tester) async {
      await start(tester, initialSection: AppSection.settings);
      expect(find.text('懸空障礙物偵測'), findsOneWidget);

      await tester.tap(find.text('懸空障礙物偵測'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不會要求新的系統權限'), findsOneWidget);
      expect(visionCalls, isNot(contains('startPreview')));
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('即時物件辨識模型'), 180);
      await tester.pump();
      expect(find.text('已安裝 · 2.87 MB'), findsOneWidget);
      expect(find.text('未提供'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('technical diagnostics stay collapsed until requested', (
    tester,
  ) async {
    await start(tester, initialMode: SourceMode.mock);
    expect(find.textContaining('播報門檻 ≥'), findsNothing);
    expect(find.text('技術資料'), findsNothing);
    await openControls(tester);
    await tester.ensureVisible(find.text('技術資料'));
    await tester.tap(find.text('技術資料'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('播報門檻 ≥'), findsOneWidget);
    await close(tester);
  });

  testWidgets('slow speech stop does not block mock startup', (tester) async {
    speechStop = Completer<Object?>();
    await start(tester, initialMode: SourceMode.mock);
    try {
      expect(painter(tester).mapped, hasLength(3));
      expect(speechCalls.where((c) => c.method == 'speak'), isEmpty);
    } finally {
      speechStop!.complete(1);
      await tester.pump();
      await close(tester);
    }
  });

  testWidgets(
    'iPhone boots into the native camera and keeps mock mode available',
    (tester) async {
      await start(tester);
      expect(find.text('介面演示・模擬資料'), findsNothing);
      expect(find.byType(VisionPreview), findsOneWidget);
      expect(visionCalls, contains('startPreview'));
      expect(find.text('更新 FPS'), findsNothing);
      expect(find.textContaining('推理耗時'), findsNothing);
      expect(find.text('技術資料'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('vision-status-pill')),
        findsOneWidget,
      );
      final settingsSize = tester.getSize(
        find.byKey(const ValueKey<String>('vision-settings-button')),
      );
      expect(settingsSize.width, greaterThanOrEqualTo(56));
      expect(settingsSize.height, greaterThanOrEqualTo(56));
      final previewHeight = tester.getSize(find.byType(VisionPreview)).height;
      final pageHeight = tester.getSize(find.byType(DemoPage)).height;
      expect(previewHeight, greaterThan(pageHeight * 0.90));

      await openControls(tester);
      expect(find.text('更新 FPS'), findsOneWidget);
      expect(find.textContaining('推理耗時'), findsOneWidget);
      expect(find.text('技術資料'), findsOneWidget);
      final selector = tester.widget<SegmentedButton<SourceMode>>(
        find.byType(SegmentedButton<SourceMode>),
      );
      expect(selector.segments.first.enabled, isTrue);
      expect(find.text('相機辨識尚未支援'), findsNothing);
      expect(
        Localizations.localeOf(tester.element(find.byType(Scaffold).first))
            .toLanguageTag(),
        'zh-Hant-HK',
      );
      expect(find.text('模擬資料'), findsOneWidget);
      final startsBeforeClose = visionCalls
          .where((method) => method == 'startPreview')
          .length;
      await closeControls(tester);
      expect(find.byType(VisionPreview), findsOneWidget);
      expect(
        visionCalls.where((method) => method == 'startPreview').length,
        startsBeforeClose,
      );
      await close(tester);
    },
  );

  testWidgets('threshold and label controls affect the real overlay', (
    tester,
  ) async {
    await start(tester, initialMode: SourceMode.mock);
    expect(painter(tester).mapped, hasLength(3));
    await openControls(tester);
    await tester.ensureVisible(find.byTooltip('隱藏標籤'));
    await tester.tap(find.byTooltip('隱藏標籤'));
    await tester.pump();
    expect(painter(tester).showLabels, isFalse);
    tester
        .widget<Slider>(
          find.byKey(const ValueKey<String>('detection-threshold')),
        )
        .onChanged!(0.95);
    await tester.pump(const Duration(milliseconds: 240));
    expect(painter(tester).mapped, isEmpty);
    await closeControls(tester);
    expect(painter(tester).showLabels, isFalse);
    await close(tester);
  });

  testWidgets('speech threshold changes announcements without hiding boxes', (
    tester,
  ) async {
    final settings = AppSettings.memory();
    await settings.setSpeakThreshold(0.95);
    await start(tester, initialMode: SourceMode.mock, settings: settings);
    await openControls(tester);
    final slider = find.byKey(const ValueKey<String>('speech-threshold'));
    await tester.ensureVisible(slider);
    tester.widget<Slider>(slider).onChanged!(0.95);
    await tester.pump();
    speechCalls.clear();
    await tester.pump(const Duration(seconds: 6));
    expect(settings.speakThreshold, 0.95);
    expect(painter(tester).mapped, hasLength(3));
    expect(speechCalls.where((c) => c.method == 'speak'), isEmpty);
    tester.widget<Slider>(slider).onChanged!(0.30);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(speechCalls.where((c) => c.method == 'speak'), isNotEmpty);
    await close(tester);
  });

  testWidgets('speech switch stops speech and disables future announcements', (
    tester,
  ) async {
    await start(tester, initialMode: SourceMode.mock);
    expect(speechCalls.where((c) => c.method == 'speak'), isNotEmpty);
    speechCalls.clear();
    await openControls(tester);
    await tester.ensureVisible(find.byTooltip('關閉播報'));
    await tester.tap(find.byTooltip('關閉播報'));
    await tester.pump();
    expect(speechCalls.where((c) => c.method == 'stop'), isNotEmpty);
    speechCalls.clear();
    await tester.pump(const Duration(seconds: 6));
    expect(speechCalls.where((c) => c.method == 'speak'), isEmpty);
    await close(tester);
  });

  testWidgets(
    'background stops mock updates and speech; foreground restarts demo',
    (tester) async {
      await start(tester, initialMode: SourceMode.mock);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      expect(find.text('已暫停'), findsOneWidget);
      expect(speechCalls.where((c) => c.method == 'stop'), isNotEmpty);
      speechCalls.clear();
      await tester.pump(const Duration(seconds: 6));
      expect(speechCalls.where((c) => c.method == 'speak'), isEmpty);
      expect(painter(tester).mapped, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(painter(tester).mapped, hasLength(3));
      await close(tester);
    },
  );

  testWidgets(
    'speech failure cannot prevent the simulated scene from starting',
    (tester) async {
      failSpeechSetup = true;
      await start(tester, initialMode: SourceMode.mock);
      expect(painter(tester).mapped, hasLength(3));
      await openControls(tester);
      expect(find.textContaining('語音初始化失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'non-Cantonese fallback remains visible after source initialization',
    (tester) async {
      speechLanguages = <String>['zh-TW'];
      await start(tester, initialMode: SourceMode.mock);
      await openControls(tester);
      expect(find.textContaining('目前使用 zh-TW，並非粵語'), findsOneWidget);
      expect(painter(tester).mapped, hasLength(3));
      await close(tester);
    },
  );

  testWidgets(
    'slow speech initialization does not block demo or restart it in background',
    (tester) async {
      speechSetup = Completer<Object?>();
      await start(tester, initialMode: SourceMode.mock);
      expect(painter(tester).mapped, hasLength(3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      speechSetup!.complete(1);
      await tester.pump();
      // 背景不排程新畫面；強制繪製一次以檢查初始化完成後的狀態。
      tester.binding.scheduleForcedFrame();
      await tester.pump(const Duration(milliseconds: 240));
      expect(painter(tester).mapped, isEmpty);
      expect(find.text('已暫停'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('Android still initializes the native camera path', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await start(tester);
    expect(visionCalls, contains('startPreview'));
    expect(find.text('介面演示・模擬資料'), findsNothing);
    await close(tester);
  });

  testWidgets(
    'small iPhone with larger text keeps controls usable without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await start(tester, initialMode: SourceMode.mock);
      expect(find.text('介面演示・模擬資料'), findsNothing);
      expect(tester.takeException(), isNull);
      await openControls(tester);
      await tester.ensureVisible(find.byTooltip('關閉播報'));
      await tester.tap(find.byTooltip('關閉播報'));
      await tester.pump();
      expect(find.byTooltip('開啟播報'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'small iPhone with larger text keeps native settings scrollable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await start(tester, initialSection: AppSection.settings);
      expect(find.text('播報速度'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('即時物件辨識模型'), 180);
      expect(find.text('已安裝 · 2.87 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
