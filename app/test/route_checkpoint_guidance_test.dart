import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/route_memory/encrypted_route_store.dart';
import 'package:pathguide/route_memory/recorded_route_controller.dart';
import 'package:pathguide/route_memory/route_journey_page.dart';
import 'package:pathguide/route_memory/route_observation_source.dart';
import 'package:pathguide/route_memory/route_package.dart';
import 'package:pathguide/settings/app_settings.dart';

import 'captured_route_store_test.dart'
    show TestVault, capturedDocument, capturedMedia;
import 'route_camera_fixture.dart';

void main() {
  testWidgets('fresh unmarked checkpoint speaks the next recorded landmark', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          accessibleNavigation: true,
          supportsAnnounce: true,
        );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final native = RouteNativeFixture()..attach();
    var sequence = 0;
    native.changeCapture = (response) => {
      ...response,
      'header': {...response['header'] as Map, 'sequence': ++sequence},
    };
    final messenger = native.messenger;
    const landmark = MethodChannel('hk.pathguide/route_landmark');
    var match = false;
    final spoken = <String>[];
    messenger.setMockDecodedMessageHandler(SystemChannels.accessibility, (
      message,
    ) async {
      if (message is Map && message['type'] == 'announce') {
        spoken.add((message['data'] as Map)['message'] as String);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(landmark, (call) async {
      if (call.method == 'cancel') return null;
      final args = Map<String, Object?>.from(call.arguments as Map);
      final feature = Uint8List.fromList([1]);
      return {
        ...args,
        'status': 'ok',
        if (call.method == 'compare')
          'distances': match ? [0.0, 20.0] : [3.0, 3.5]
        else ...{
          'feature': feature,
          'featureSha': sha256.convert(feature).toString(),
          'text': <String>[],
          'ocrRevision': 3,
          'manualFloorConfirmationRequired': true,
        },
      };
    });
    addTearDown(() {
      native.detach();
      messenger.setMockMethodCallHandler(landmark, null);
      messenger.setMockDecodedMessageHandler(
        SystemChannels.accessibility,
        null,
      );
    });

    late RecordedRouteController controller;
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('route-cue-test-');
      addTearDown(() => root.delete(recursive: true));
      final store = await EncryptedRouteStore.open(
        root: root,
        vault: TestVault(),
      );
      final map = capturedDocument().toMap();
      final points = map['nodes'] as List<Map<String, Object?>>;
      points.last['zh'] = '走廊出口';
      final document = RouteDocument.fromMap(map);
      await store.save(
        document,
        token: store.capture(document.id),
        expectedRevision: 0,
        activate: true,
        media: capturedMedia(),
      );
      controller = RecordedRouteController(
        store: store,
        source: RouteObservationSource(supported: true),
      );
      await controller.open((await store.list()).routes.single);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RouteJourneyPage(
          settings: AppSettings.memory(),
          createController: () async => controller,
          previewBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    final start = find.text('開始重行');
    for (
      var i = 0;
      i < 200 && find.byType(Scrollable).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.tap(start);
    await tester.pumpAndSettle();

    const message = '已確認路標「地下」，G 樓層。下一個已錄路標係「走廊出口」。';
    final cue = find.text(message);
    expect(cue, findsNothing);

    Future<void> reveal(Finder finder, double delta) async {
      await tester.scrollUntilVisible(
        finder,
        delta,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    Future<void> confirm({double floorDelta = 100}) async {
      final floor = find.byType(TextField);
      await reveal(floor, floorDelta);
      await tester.enterText(floor, 'G');
      final direction = find.byType(CheckboxListTile);
      await reveal(direction, 100);
      await tester.tap(direction);
      final capture = find.text('拍攝並確認此路標');
      await reveal(capture, 100);
      await tester.tap(capture);
      await tester.pumpAndSettle();
    }

    await confirm();
    expect(controller.notice, 'ambiguous');
    expect(cue, findsNothing);
    expect(spoken, isEmpty);

    match = true;
    await confirm(floorDelta: -100);
    expect(controller.confirmedReplayPoint?.id, 'g');
    expect(controller.confirmedReplayMark, isNull);
    await reveal(cue, -100);
    expect(cue, findsOneWidget);
    expect(spoken, [message]);

    await tester.tap(find.text('暫停'));
    await tester.pumpAndSettle();
    expect(controller.confirmedReplayPoint, isNull);
    expect(cue, findsNothing);
    expect(spoken, [message]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
