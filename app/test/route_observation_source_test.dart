import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/route_memory/route_observation_source.dart';

import 'route_camera_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hk.pathguide/route_camera');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'disposing an older source listener preserves newer camera events',
    () async {
      final native = RouteNativeFixture()..attach();
      final old = RouteObservationSource(supported: true);
      final next = RouteObservationSource(supported: true);
      final oldSubscription = old.events.listen((_) {});
      final received = <RouteCaptureStatus>[];
      final nextSubscription = next.events.listen(received.add);
      await next.start(routeId: 'route-new', routeVersion: 1);
      await oldSubscription.cancel();
      native.sendEvent('paused');
      await Future<void>.delayed(Duration.zero);
      expect(received, contains(RouteCaptureStatus.paused));
      await next.stop();
      await nextSubscription.cancel();
      native.detach();
    },
  );

  for (final problem in [
    'hash',
    'jpegDimensions',
    'clock',
    'age',
    'sequence',
    'orientation',
    'byteCount',
  ]) {
    test('rejects native keyframe with invalid $problem', () async {
      final native = RouteNativeFixture();
      native.changeCapture = (value) {
        final header = value['header'] as Map<String, Object?>;
        switch (problem) {
          case 'hash':
            value['sha256'] = '0' * 64;
          case 'jpegDimensions':
            value['width'] = 7;
          case 'clock':
            header['clockMapping'] = 'unknown';
          case 'age':
            header['ageMs'] = 2000.0;
          case 'sequence':
            header['sequence'] = 0;
          case 'orientation':
            value['orientation'] = 'right';
          case 'byteCount':
            value['byteCount'] = 0;
        }
        return value;
      };
      native.attach();
      final source = RouteObservationSource(supported: true);
      await source.start(routeId: 'route-a', routeVersion: 3);
      final result = await source.capture();
      expect(result.status, RouteCaptureStatus.invalid);
      expect(result.keyframe, isNull);
      await source.stop();
      native.detach();
    });
  }

  test(
    'stop cancels a pending photo before its late native response arrives',
    () async {
      final native = RouteNativeFixture()..delayCapture = true;
      native.attach();
      final source = RouteObservationSource(supported: true);
      await source.start(routeId: 'route-a', routeVersion: 3);
      final pending = source.capture();
      await Future<void>.delayed(Duration.zero);
      await source.stop();
      expect((await pending).status, RouteCaptureStatus.cancelled);
      native.captureReply!.complete(native.capturedResponse);
      await Future<void>.delayed(Duration.zero);
      expect((await source.capture()).status, RouteCaptureStatus.paused);
      native.detach();
    },
  );

  test('a keyframe carrying another route identity is rejected', () async {
    final jpeg = File('test/fixtures/route_camera/keyframe-8x4.jpg')
        .readAsBytesSync();
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      if (call.method != 'captureKeyframe') {
        return {...args, 'status': 'running'};
      }
      return {
        'status': 'captured',
        'jpeg': jpeg,
        'width': 8,
        'height': 4,
        'sha256': sha256.convert(jpeg).toString(),
        'header': {...args, 'routeId': 'another-route'},
      };
    });
    final source = RouteObservationSource(supported: true);
    await source.start(routeId: 'route-a', routeVersion: 3);
    final result = await source.capture();
    expect(result.status, RouteCaptureStatus.invalid);
    expect(result.keyframe, isNull);
    await source.stop();
  });

  test('explicit native capture returns the verified upright JPEG and route identity', () async {
    final jpeg = File('test/fixtures/route_camera/keyframe-8x4.jpg')
        .readAsBytesSync();
    Map<Object?, Object?>? session;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      if (call.method == 'start') session = args;
      if (call.method != 'captureKeyframe') {
        return {
          ...args,
          'status': call.method == 'start' ? 'running' : 'stopped',
        };
      }
      return {
        'status': 'captured',
        'jpeg': jpeg,
        'sha256': sha256.convert(jpeg).toString(),
        'width': 8,
        'height': 4,
        'byteCount': jpeg.length,
        'orientation': 'up',
        'header': {
          ...session!,
          'requestId': args['requestId'],
          'startRequestId': session!['requestId'],
          'sequence': 1,
          'captureClockId': 'avcapture-session-clock-a',
          'clockEpoch': 'clock-a',
          'rawTimestampValue': 500000,
          'rawTimestampTimescale': 1000,
          'rawTimestampEpoch': 0,
          'clockMapping': 'coremedia-host',
          'capturedHostSeconds': 99.9,
          'nativeNowHostSeconds': 100.0,
          'ageMs': 100.0,
          'source': 'avfoundation-back-wide',
          'profile': 'route-camera-engineering-v1',
          'walkingValidated': false,
          'mirrored': false,
          'rotationDegrees': 90,
          'rawWidth': 4,
          'rawHeight': 8,
          'uprightWidth': 8,
          'uprightHeight': 4,
        },
      };
    });
    final source = RouteObservationSource(supported: true);
    expect(
      await source.start(routeId: 'route-a', routeVersion: 3),
      RouteCaptureStatus.running,
    );
    final result = await source.capture();
    expect(result.status, RouteCaptureStatus.captured);
    expect(result.keyframe!.bytes, jpeg);
    expect(result.keyframe!.observation['routeId'], 'route-a');
    expect(result.keyframe!.observation['routeVersion'], 3);
    expect(await source.stop(), RouteCaptureStatus.stopped);
  });
}
