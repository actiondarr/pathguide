import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:pathguide/route_memory/encrypted_route_store.dart';
import 'package:pathguide/route_memory/recorded_route_controller.dart';
import 'package:pathguide/route_memory/cross_floor_contract.dart';
import 'package:pathguide/route_memory/route_observation_source.dart';

import 'route_camera_fixture.dart';

class Vault implements RouteKeyVault {
  List<int>? bytes;
  @override
  Future<List<int>?> read() async => bytes;
  @override
  Future<void> write(List<int> b) async {
    bytes = List.of(b);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late RecordedRouteController c;
  late EncryptedRouteStore store;
  late RouteNativeFixture native;
  var ordinal = 0, match = 0;
  var ambiguous = false;
  Completer<void>? analysisGate;
  const channel = MethodChannel('hk.pathguide/route_landmark');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('record-route-');
    native = RouteNativeFixture()..attach();
    ordinal = 0;
    match = 0;
    ambiguous = false;
    analysisGate = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final a = Map<String, Object?>.from(call.arguments as Map);
      if (call.method == 'cancel') return null;
      if (call.method == 'compare') {
        return {
          ...a,
          'status': 'ok',
          'distances': [
            for (var i = 0; i < (a['references'] as List).length; i++)
              ambiguous || i == match ? 0.0 : 20.0,
          ],
        };
      }
      await analysisGate?.future;
      final f = Uint8List.fromList([++ordinal]);
      return {
        ...a,
        'status': 'ok',
        'feature': f,
        'featureSha': sha256.convert(f).toString(),
        'text': <String>[],
        'ocrRevision': 3,
        'manualFloorConfirmationRequired': true,
      };
    });
    store = await EncryptedRouteStore.open(root: root, vault: Vault());
    c = RecordedRouteController(
      store: store,
      source: RouteObservationSource(supported: true),
    );
  });
  tearDown(() async {
    await c.pause();
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    native.detach();
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  Future<void> record() async {
    await c.startRecording('G to classroom');
    await c.recordLandmark('Entrance', 'G', confirmed: true);
    await c.recordLandmark('Lift', 'G', confirmed: true);
    await c.recordLandmark(
      'Lift exit',
      '3F',
      mode: ConnectorMode.elevator,
      confirmed: true,
    );
    await c.recordLandmark('Room', '3F', confirmed: true);
    await c.save(activate: true);
  }

  Future<void> replay() async {
    await record();
    await c.open((await store.list()).routes.single);
    await c.resume();
  }

  void useDetailedFrame() {
    final jpeg = File('test/fixtures/route_camera/synthetic-detail-grid.jpg')
        .readAsBytesSync();
    native.changeCapture = (v) {
      v['jpeg'] = jpeg;
      v['sha256'] = sha256.convert(jpeg).toString();
      v['byteCount'] = jpeg.length;
      v['width'] = 64;
      v['height'] = 64;
      (v['header'] as Map<String, Object?>).addAll({
        'rawWidth': 64,
        'rawHeight': 64,
        'uprightWidth': 64,
        'uprightHeight': 64,
      });
      return v;
    };
  }

  testWidgets(
    'start once creates an automatic draft and pause prevents later additions',
    (t) async {
      useDetailedFrame();
      await c.startRecording('automatic', automatic: true);
      await t.pump(const Duration(seconds: 5));
      for (var i = 0; i < 30; i++) {
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await t.pump();
      }
      expect(c.nodes.length, 1);
      expect(c.nodes.first.floor, isNull);
      await c.pause();
      await t.pump(const Duration(seconds: 15));
      expect(c.nodes.length, 1);
      expect(c.running, isFalse);
    },
  );
  test('low detail candidate is not added and manual pending input suspends sampling', () async {
    await c.startRecording('automatic', automatic: true);
    c.setManualEntryPending(true);
    await c.sampleAutomatically();
    expect(c.nodes, isEmpty);
    c.setManualEntryPending(false);
    await c.sampleAutomatically();
    // Existing tiny camera fixture has insufficient detail at the engineering screen.
    expect(c.nodes, isEmpty);
    expect(c.notice, 'automaticLowDetail');
    await c.pause();
  });
  test(
    'automatic recording adds numbered unknown drafts without a landmark form',
    () async {
      useDetailedFrame();
      await c.startRecording('automatic', automatic: true);
      await c.sampleAutomatically();
      expect(
        c.nodes.length,
        1,
        reason: '${c.notice}/${c.problem} candidates=${c.automaticCandidates}',
      );
      expect(c.nodes.first.nameZh, '路標 1');
      expect(c.nodes.first.floor, isNull);
      await c.sampleAutomatically();
      expect(c.nodes.length, 1); // repeated photo is not a new landmark.
      await c.save(activate: false);
      final entry = (await store.list()).routes.single;
      expect(entry.activeVersion, isNull);
      await c.open(entry, recording: true);
      expect(c.nodes.length, 1);
      expect(c.document!.complete, isFalse);
    },
  );
  test('empty library records G lift 3F room, saves and reopens for confirmed replay', () async {
    await replay();
    expect(c.document!.complete, isTrue);
    match = 1;
    await c.checkPosition('n-2', 'G', directionConfirmed: true);
    expect(c.actualNodeId, 'n-2');
    expect(c.enterConnector(), isTrue);
    expect(c.actualFloor, isNull);
    match = 2;
    await c.checkPosition('n-3', '3F', directionConfirmed: true);
    expect(c.actualFloor!.label, '3F');
    match = 3;
    await c.checkPosition('n-4', '3F', directionConfirmed: true);
    expect(c.finished, isFalse);
    await c.confirmArrival();
    expect(c.finished, isTrue);
  });
  test(
    'unknown floor or unconfirmed segment stays draft and cannot start replay',
    () async {
      await c.startRecording('draft');
      await c.recordLandmark('G', 'G', confirmed: true);
      await c.recordLandmark('unknown', '3F');
      expect(c.document!.complete, isFalse);
      await c.save(activate: false);
      final entry = (await store.list()).routes.single;
      expect(entry.activeVersion, isNull);
      await c.open(entry);
      await c.resume();
      expect(c.running, isFalse);
      expect(c.replayAvailable, isFalse);
      await c.open(entry, recording: true);
      c.updateNode(1, 'Exit', '3F', ConnectorMode.elevator, true);
      expect(c.document!.complete, isTrue);
      await c.save(activate: true);
      expect(c.notice, 'saved');
    },
  );
  test('wrong floor, wrong direction, ambiguous match and wrong requested node hold position', () async {
    await replay();
    await c.checkPosition('n-1', '3F', directionConfirmed: true);
    expect(c.actualFloor, isNull);
    await c.checkPosition('n-1', 'G', directionConfirmed: false);
    expect(c.actualFloor, isNull);
    ambiguous = true;
    await c.checkPosition('n-1', 'G', directionConfirmed: true);
    expect(c.actualNodeId, isNull);
    ambiguous = false;
    match = 1;
    await c.checkPosition('n-1', 'G', directionConfirmed: true);
    expect(c.actualNodeId, isNull);
    match = 2;
    await c.checkPosition('n-3', '3F', directionConfirmed: true);
    expect(c.actualNodeId, 'n-3'); // Explicit mid-route recovery.
    await c.pause();
    expect(c.actualFloor, isNull);
    await c.resume();
    expect(c.actualFloor, isNull);
  });
  test('floor transition is bound to recorded exit and cannot certify another node', () async {
    await replay();
    match = 1;
    await c.checkPosition('n-2', 'G', directionConfirmed: true);
    expect(c.enterConnector(), isTrue);
    match = 3;
    await c.checkPosition('n-4', '3F', directionConfirmed: true);
    expect(c.notice, 'wrongNode');
    expect(c.actualFloor, isNull);
  });
  test(
    'background during analysis rejects late capture and does not restart',
    () async {
      await c.startRecording('late');
      analysisGate = Completer<void>();
      final pending = c.recordLandmark('Entrance', 'G', confirmed: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.setForeground(false);
      analysisGate!.complete();
      await pending;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.nodes, isEmpty);
      expect(c.running, isFalse);
      c.setForeground(true);
      expect(c.running, isFalse);
    },
  );
  test('editing a floor withdraws outgoing connection and never reuses floor identity', () async {
    await record();
    final old = c.nodes[2].floor;
    c.updateNode(2, 'Exit', '4F', ConnectorMode.elevator, true);
    expect(c.nodes[2].floor, isNot(old));
    expect(c.incomingConfirmed(3), isFalse);
    expect(c.document!.complete, isFalse);
  });
  test(
    'replay writes no photos or versions, delete removes all route media',
    () async {
      await replay();
      final before = await root
          .list(recursive: true)
          .where((f) => f is File)
          .map((f) => f.path)
          .toList();
      match = 0;
      await c.checkPosition('n-1', 'G', directionConfirmed: true);
      final after = await root
          .list(recursive: true)
          .where((f) => f is File)
          .map((f) => f.path)
          .toList();
      expect(after.toSet(), before.toSet());
      final entry = (await store.list()).routes.single;
      await c.delete(entry);
      expect((await store.list()).routes, isEmpty);
      expect(c.document, isNull);
    },
  );
  test(
    'failed open clears prior route so it cannot replay the wrong selection',
    () async {
      await replay();
      final stale = (await store.list()).routes.single;
      await store.delete(stale.id, expectedRevision: stale.revision);
      await c.open(stale);
      expect(c.document, isNull);
      expect(c.replayAvailable, isFalse);
      await c.resume();
      expect(c.running, isFalse);
    },
  );
}
