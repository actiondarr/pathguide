import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/outdoor_routes/outdoor_recorder.dart';
import 'package:pathguide/outdoor_routes/outdoor_replay.dart';
import 'package:pathguide/outdoor_routes/outdoor_route_store.dart';
import 'package:pathguide/outdoor_routes/outdoor_track.dart';
import 'package:pathguide/route_memory/encrypted_route_store.dart';
import 'package:pathguide/route_memory/route_package.dart';

import 'encrypted_route_store_test.dart' show MemoryRouteVault, document, fails;
import 'outdoor_route_fixtures.dart';

void main() {
  late OutdoorRecorder recorder;

  void record(
    int second,
    num east,
    num north, {
    double accuracy = 3,
    double? speed = 1.4,
  }) => recorder.fix(
    fix(second, east, north, accuracy: accuracy, speed: speed),
    elapsed(second),
    at(second),
  );

  setUp(() => recorder = OutdoorRecorder());

  test(
    '15 seconds, one GPS fix, two co-located marks and independent undo',
    () {
      record(0, 0, 0, speed: null);
      final direction = recorder.makeMark(
        OutdoorMarkKind.aheadLeft,
        elapsed(10),
      )!;
      expect(recorder.addMark(direction, elapsed(10)), OutdoorMarkResult.added);
      final steps = recorder.makeMark(OutdoorMarkKind.steps, elapsed(15))!;
      expect(recorder.addMark(steps, elapsed(15)), OutdoorMarkResult.added);

      final before = recorder.finish(elapsed(15));
      expect(before.distance, 0);
      expect(before.pointCount, 1);
      expect(before.elapsed, elapsed(15));
      expect(before.marks.map((m) => m.kind), [
        OutdoorMarkKind.aheadLeft,
        OutdoorMarkKind.steps,
      ]);
      expect(before.marks.map((m) => (m.segment, m.pointIndex)).toSet(), {
        (0, 0),
      });
      expect(before.draftReason, OutdoorDraftReason.singlePoint);
      expect(recorder.speed, isNull);
      expect(recorder.undo()?.kind, OutdoorMarkKind.steps);
      expect(recorder.markCount, 1);
      expect(recorder.distance, 0);
      expect(recorder.pointCount, 1);

      recorder.tick(elapsed(20));
      expect(recorder.makeMark(OutdoorMarkKind.steps, elapsed(20)), isNull);
      expect(recorder.state, OutdoorRecordingState.weak);
    },
  );

  test(
    'rejects stale and duplicate first samples, poor precision and GPS jumps',
    () {
      recorder.fix(fix(0, 0, 0, received: 8, ageSeconds: 8), elapsed(8), at(8));
      expect(recorder.pointCount, 0);
      expect(
        recorder.finish(elapsed(8)).draftReason,
        OutdoorDraftReason.noStart,
      );
      record(9, 0, 0, accuracy: 21);
      expect(recorder.state, OutdoorRecordingState.weak);
      record(10, 0, 0);
      record(10, 20, 0);
      record(11, 200, 0);
      record(12, 0, 0);
      expect(recorder.pointCount, 1);
      expect(recorder.distance, 0);
      expect(recorder.finish(elapsed(12)).segments.single.single.time, at(10));
    },
  );

  test('stationary drift never increases distance and credible stillness reports zero', () {
    for (final (index, (x, y)) in [
      (0, 0),
      (4, 1),
      (6, -2),
      (1, 3),
      (-3, 1),
      (0, 0),
      (3, -4),
    ].indexed) {
      record(index, x, y, accuracy: 6, speed: 0.05);
    }
    expect(recorder.speed, 0);
    expect(recorder.distance, 0);
    final track = recorder.finish(elapsed(15));
    expect(track.pointCount, 1);
    expect(track.elapsed, elapsed(15));
    expect(track.speeds.every((s) => s.metresPerSecond == 0), isTrue);
  });

  test('jitter with missing speed does not create a measured walk', () {
    for (final (index, (x, y)) in [
      (0, 0),
      (7, 0),
      (-3, 4),
      (0, 0),
      (0, 9),
      (-3, -3),
    ].indexed) {
      record(index, x, y, accuracy: 6, speed: null);
    }
    expect(recorder.speed, isNull);
    expect(recorder.pointCount, 1);
    expect(recorder.distance, 0);
  });

  test('one-metre GPS updates confirm a slow continuous walk', () {
    for (var second = 0; second <= 45; second++) {
      record(second, second, 0, accuracy: 8, speed: 1);
    }
    final track = recorder.finish(elapsed(45));
    expect(track.pointCount, greaterThanOrEqualTo(3));
    expect(track.distance, greaterThanOrEqualTo(OutdoorTrack.minimumDistance));
    expect(track.segments, hasLength(1));
    expect(track.draftReason, isNull);
  });

  test('normal walking retains a corner and last corroborated endpoint', () {
    for (var i = 0; i <= 15; i++) {
      record(i, i * 2, 0);
    }
    for (var i = 16; i <= 30; i++) {
      record(i, 30, (i - 15) * 2);
    }
    record(31, 30, 30, speed: 0);
    record(32, 30, 30, speed: 0);
    final track = recorder.finish(elapsed(32));
    expect(track.draftReason, isNull);
    expect(
      track.distance,
      closeTo(60, 3),
      reason: track.segments.single
          .map(
            (p) => (
              p.coordinate.longitude * 111195,
              p.coordinate.latitude * 111195,
            ),
          )
          .join(", "),
    );
    expect(
      track.segments.single.any(
        (p) => p.coordinate.distanceTo(metres(30, 0)) <= 2.1,
      ),
      isTrue,
    );
    expect(track.speeds.any((s) => s.metresPerSecond > 0), isTrue);
    expect(
      track.segments.single.last.coordinate.distanceTo(metres(30, 30)),
      lessThan(3),
    );
  });

  test('manual pause freezes timer, invalidates mark and resumes into a new segment', () {
    record(0, 0, 0);
    record(3, 6, 0);
    record(6, 12, 0);
    final pending = recorder.makeMark(OutdoorMarkKind.text, elapsed(6))!;
    recorder.pause(elapsed(7));
    record(10, 20, 0);
    expect(recorder.elapsedAt(elapsed(20)), elapsed(7));
    expect(recorder.makeMark(OutdoorMarkKind.steps, elapsed(20)), isNull);
    recorder.resume(elapsed(21));
    record(22, 120, 0);
    record(25, 126, 0);
    record(28, 132, 0);
    expect(
      recorder.addMark(pending, elapsed(28), text: '舊位置'),
      OutdoorMarkResult.noPosition,
    );
    final track = recorder.finish(elapsed(31));
    expect(track.elapsed, elapsed(17));
    expect(track.segments.map((segment) => segment.length), [2, 2]);
    expect(track.distance, closeTo(12, 0.1));
    expect(track.draftReason, OutdoorDraftReason.gap);
  });

  test('loss, expired updates, background and authorization split the recorded trail', () {
    record(0, 0, 0);
    record(2, 6, 0);
    record(4, 12, 0);
    recorder.tick(elapsed(24));
    expect(recorder.state, OutdoorRecordingState.weak);
    recorder.fix(fix(6, 12, 0, received: 25), elapsed(25), at(25));
    expect(recorder.pointCount, 2);
    record(26, 75, 0);
    recorder.unavailable(permission: true);
    expect(recorder.state, OutdoorRecordingState.permission);
    recorder.resume(elapsed(27));
    record(28, 100, 0);
    recorder.background();
    record(29, 120, 0);
    recorder.resume(elapsed(31));
    record(32, 140, 0);
    record(45, 150, 0);
    final track = recorder.finish(elapsed(46));
    expect(track.segments.length, 5);
    expect(track.distance, closeTo(6, 0.1));
    expect(track.draftReason, OutdoorDraftReason.gap);
  });

  group('replay on the saved track', () {
    late OutdoorReplay replay;
    void walk(
      int time,
      num x,
      num y, {
      double accuracy = 3,
      double? course,
      double? speed = 1.4,
    }) => replay.fix(
      fix(time, x, y, accuracy: accuracy, course: course, speed: speed),
      elapsed(time),
      at(time),
    );

    setUp(() => replay = OutdoorReplay(cornerRoute()));

    test('wrong start and wrong direction cannot start progress', () {
      walk(1, 25, 0);
      expect(replay.state, OutdoorReplayState.wrongStart);
      walk(2, 0, 0);
      expect(replay.state, OutdoorReplayState.checkingDirection);
      walk(5, -5, 0, course: 270);
      expect(replay.state, OutdoorReplayState.reverse);
      expect(replay.along, 0);
    });

    test('matches departure and a recorded left turn, rejects deviation and recovers locally', () {
      walk(1, 0, 0);
      walk(5, 8, 0, course: 90);
      expect(replay.state, OutdoorReplayState.following);
      walk(9, 16, 0, course: 90);
      expect(replay.nextTurn?.left, true);
      walk(12, 22, 0, course: 90);
      expect(replay.nextTurn?.metres, closeTo(8, 1));
      walk(16, 24, -35);
      expect(replay.state, OutdoorReplayState.offRoute);
      expect(replay.nextTurn, isNull);
      walk(20, 24, 0, course: 90);
      expect(replay.state, OutdoorReplayState.following);
      walk(24, 30, 3, course: 0);
      walk(28, 30, 12, course: 0);
      expect(replay.along, closeTo(42, 0.1));
      replay.tick(elapsed(36));
      expect(replay.state, OutdoorReplayState.weak);
    });

    test(
      'near endpoint needs independent fresh fixes and explicit confirmation',
      () {
        walk(1, 0, 0);
        walk(5, 8, 0, course: 90);
        walk(11, 22, 0, course: 90);
        walk(17, 30, 5, course: 0);
        walk(23, 30, 19, course: 0);
        walk(25, 30, 24, course: 0);
        expect(replay.state, OutdoorReplayState.nearEnd);
        expect(replay.confirmEnd(elapsed(25)), isFalse);
        walk(25, 30, 24, course: 0);
        expect(replay.canConfirmEnd, isFalse);
        walk(27, 30, 28, accuracy: 13);
        expect(replay.canConfirmEnd, isFalse);
        walk(29, 30, 29);
        walk(30, 30, 30);
        expect(replay.state, OutdoorReplayState.nearEnd);
        expect(replay.canConfirmEnd, isTrue);
        expect(replay.confirmEnd(elapsed(38)), isFalse);
        walk(39, 30, 30);
        walk(40, 30, 30);
        expect(replay.confirmEnd(elapsed(40)), isTrue);
        expect(replay.state, OutdoorReplayState.arrived);
      },
    );

    test(
      'parallel paths or close entrances suppress location and arrival cues',
      () {
        replay = OutdoorReplay(
          routeWith([(0, 0), (20, 0), (40, 0), (40, 6), (20, 6), (0, 6)]),
        );
        walk(1, 1, 3, accuracy: 5);
        expect(replay.state, OutdoorReplayState.ambiguous);
        expect(replay.nextTurn, isNull);
        expect(replay.canConfirmEnd, isFalse);
      },
    );

    test(
      'co-located landmarks stay distinct and expire when position is lost',
      () {
        final point = OutdoorPoint(metres(10, 0), at(5), 3, 1.4);
        replay = OutdoorReplay(
          cornerRoute(
            marks: [
              OutdoorMark(
                kind: OutdoorMarkKind.aheadLeft,
                point: point,
                segment: 0,
                pointIndex: 1,
              ),
              OutdoorMark(
                kind: OutdoorMarkKind.turnLeft,
                point: point,
                segment: 0,
                pointIndex: 1,
              ),
            ],
          ),
        );
        walk(1, 0, 0);
        walk(5, 8, 0, course: 90);
        expect(replay.takeNewMarks().map((m) => m.kind), [
          OutdoorMarkKind.aheadLeft,
          OutdoorMarkKind.turnLeft,
        ]);
        expect(replay.takeNewMarks(), isEmpty);
        walk(6, 8, 0, accuracy: 25);
        expect(replay.state, OutdoorReplayState.weak);
        expect(replay.nearbyMarks, isEmpty);
      },
    );
  });

  group('encrypted outdoor library', () {
    late Directory root;
    late MemoryRouteVault vault;
    late bool failBeforeCommit, failAfterCommit;
    Future<OutdoorRouteStore> open() async => OutdoorRouteStore(
      await EncryptedRouteStore.open(
        root: root,
        vault: vault,
        outdoor: true,
        checkpoint: (step) async {
          if ((failBeforeCommit && step == 'beforeCatalogCommit') ||
              (failAfterCommit && step == 'afterCatalogCommit')) {
            throw const FileSystemException('injected store failure');
          }
        },
      ),
    );

    setUp(() async {
      root = await Directory.systemTemp.createTemp('pathguide-outdoor-test-');
      vault = MemoryRouteVault();
      failBeforeCommit = failAfterCommit = false;
    });
    tearDown(() => root.delete(recursive: true));

    test('retry keeps stable id and exact track across store reopen and isolates indoor drafts', () async {
      final indoor = await EncryptedRouteStore.open(
        root: root,
        vault: MemoryRouteVault(),
      );
      final old = document(draft: true);
      await indoor.save(
        old,
        token: indoor.capture(old.id),
        expectedRevision: 0,
        activate: false,
      );
      final store = await open();
      final track = cornerRoute();
      failBeforeCommit = true;
      await expectLater(
        store.save('outdoor-a', '實錄路線', track),
        throwsA(isA<RouteStoreFailure>()),
      );
      expect((await store.list()).routes, isEmpty);
      failBeforeCommit = false;
      expect((await store.save('outdoor-a', '實錄路線', track)).published, isTrue);

      final reopened = await open();
      final entry = (await reopened.list()).routes.single;
      final saved = await reopened.read(entry);
      expect(entry.name, '實錄路線');
      expect(entry.activeVersion, 1);
      expect(saved.document.outdoor!.toMap(), track.toMap());
      expect((await indoor.list()).routes.single.id, old.id);
      expect((await indoor.read(old.id)).document.toMap(), old.toMap());
      final wrongVault = await EncryptedRouteStore.open(
        root: root,
        vault: MemoryRouteVault(),
        outdoor: true,
      );
      await expectLater(
        wrongVault.list(),
        throwsA(fails(RouteProblem.keyUnavailable)),
      );
    });

    test(
      'acknowledgement lost after commit does not duplicate a route',
      () async {
        final store = await open();
        final track = cornerRoute();
        failAfterCommit = true;
        expect((await store.save('outdoor-a', '原名', track)).published, isTrue);
        final retry = await store.save('outdoor-a', '新名', track);
        expect(retry.document.name, '原名');
        expect((await store.list()).routes.single.versions, [1]);
      },
    );

    test('one point and interrupted recordings reopen as drafts', () async {
      record(0, 0, 0);
      final store = await open();
      await store.save('one', '起點', recorder.finish(elapsed(15)));
      recorder.tick(elapsed(20));
      record(21, 50, 0);
      await store.save('gap', '缺口', recorder.finish(elapsed(22)));
      final reopened = await open();
      final entries = (await reopened.list()).routes;
      for (final entry in entries) {
        final route = await reopened.read(entry);
        expect(route.published, isFalse);
        expect(
          route.document.outdoor!.draftReason,
          entry.id == 'one'
              ? OutdoorDraftReason.singlePoint
              : OutdoorDraftReason.gap,
        );
      }
    });
  });
}
