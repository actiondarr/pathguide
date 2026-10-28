import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/depth/depth_page.dart';
import 'package:pathguide/settings/app_settings.dart';
import 'package:pathguide/tts/announcer.dart';
import 'package:pathguide/ui/app_theme.dart';

import 'support/fake_depth.dart';

class DepthSpeaker extends NullSpeaker {
  final words = <String>[];
  Completer<void>? initialized;
  @override
  Future<void> speak(String text) async {
    words.add(text);
  }
}

Future<void> showDepth(
  WidgetTester tester,
  FakeDepthSource source, {
  AppLanguage language = AppLanguage.chinese,
  double scale = 1,
  DepthSpeaker? speaker,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(scale),
          ),
          child: DepthPage(
            settings: AppSettings.memory(language: language),
            source: source,
            speaker: speaker ?? DepthSpeaker(),
            preview: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final language in AppLanguage.values) {
    testWidgets(
      'depth ${language.name} large text retains start/read controls',
      (tester) async {
        final source = FakeDepthSource();
        await showDepth(tester, source, language: language, scale: 2);
        for (final key in ['depth-toggle', 'depth-read']) {
          expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
          expect(
            tester.getSize(find.byKey(ValueKey(key))).height,
            greaterThanOrEqualTo(48),
          );
        }
        await tester.tap(find.byKey(const ValueKey('depth-toggle')));
        await tester.pump();
        source.stable();
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('depth-range')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(
            language == AppLanguage.english ? 'About 2.0 m' : '約 2.0 米',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await source.events.close();
      },
    );
  }
  testWidgets(
    'manual read uses current value; background clears and never auto resumes',
    (tester) async {
      final source = FakeDepthSource();
      final speaker = DepthSpeaker();
      await showDepth(tester, source, speaker: speaker);
      await tester.tap(find.byKey(const ValueKey('depth-toggle')));
      await tester.pump();
      source.stable();
      await tester.pump();
      expect(speaker.words, isEmpty);
      await tester.tap(find.byKey(const ValueKey('depth-read')));
      await tester.pump();
      expect(speaker.words.single, contains('2.0 米'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('距離未知'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(source.starts, 1);
      expect(find.text('開始測距'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await source.events.close();
    },
  );
  testWidgets('unsupported sensor explains and does not offer a distance', (
    tester,
  ) async {
    final source = FakeDepthSource()..result = 'unsupported';
    await showDepth(tester, source);
    await tester.tap(find.byKey(const ValueKey('depth-toggle')));
    await tester.pump();
    expect(find.text('此裝置不支援 LiDAR 場景深度'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('depth-read')),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await source.events.close();
  });
}
