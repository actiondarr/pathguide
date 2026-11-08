import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/scene/live_scene_controller.dart';
import 'package:pathguide/scene/live_scene_signal.dart';
import 'package:pathguide/scene/scene_backend.dart';
import 'package:pathguide/tts/announcer.dart';
import 'package:pathguide/tts/speech_coordinator.dart';

const full = '畫面左邊有張木枱。中間見到一道門，右邊有張凳。';

class Backend implements SceneBackend {
  int calls = 0;
  final pending = <Completer<SceneReply>>[], ids = <String>[];
  @override
  Future<SceneReply> describe(
    Uint8List jpeg,
    String requestId, {
    bool Function()? isCurrent,
  }) {
    calls++;
    ids.add(requestId);
    final c = Completer<SceneReply>();
    pending.add(c);
    return c.future;
  }

  void finish({String text = full, bool usage = true}) {
    pending.last.complete(
      SceneReply.fromMap({
        'status': 'complete',
        'requestId': ids.last,
        'text': text,
        'metrics': {
          'modelMs': 50,
          'usage': usage
              ? {
                  'prompt_tokens': 100,
                  'completion_tokens': 20,
                  'total_tokens': 120,
                }
              : null,
          'estimate': usage ? {'usd': 0.000052, 'notBillingCap': true} : null,
        },
      }, ids.last),
    );
  }
}

class Voice implements Speaker {
  final said = <String>[];
  int stops = 0;
  bool hold = false;
  Completer<void>? wait;
  @override
  Future<void> speak(String text) async {
    said.add(text);
    if (hold) wait = Completer<void>();
    await wait?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (wait?.isCompleted == false) wait!.complete();
  }

  @override
  Future<List<String>> languages() async => ['zh-HK'];
}

class Harness {
  Harness(this.tester) {
    controller = LiveSceneController(
      capture: () async {
        captures++;
        return bytes.future;
      },
      backend: backend,
      speaker: voice,
      clock: () => now,
    );
    controller.setAvailable(true);
    bytes.complete(Uint8List.fromList([1]));
  }
  final WidgetTester tester;
  final backend = Backend();
  final voice = Voice();
  int captures = 0, seq = 0;
  Completer<Uint8List?> bytes = Completer<Uint8List?>();
  DateTime now = DateTime(2026, 11, 8);
  late LiveSceneController controller;
  LiveSceneSignal signal({int luma = 40, double yaw = 0, double rate = 0}) =>
      LiveSceneSignal(
        sequence: ++seq,
        luma: List.filled(64, luma),
        attitude: [
          0,
          0,
          math.sin(yaw * math.pi / 360),
          math.cos(yaw * math.pi / 360),
        ],
        rotationRate: rate,
      );
  Future<void> frame({int luma = 40, double yaw = 0, double rate = 0}) async {
    now = now.add(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    controller.observe(signal(luma: luma, yaw: yaw, rate: rate));
    await tester.pump();
  }

  Future<void> stable({int luma = 40, double yaw = 0, int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await frame(luma: luma, yaw: yaw);
    }
  }
}

void main() {
  test('motion parsing rejects stale/missing/malformed evidence instead of guessing stability', () {
    final v = {
      'sequence': 1,
      'luma': List.filled(64, 40),
      'attitude': [0, 0, 0, 1],
      'rotationRate': 0,
      'motionFresh': true,
    };
    expect(LiveSceneSignal.parse(v), isNotNull);
    for (final bad in [
      {'motionFresh': false},
      {'luma': List.filled(64, -1)},
      {
        'attitude': [0, 0, 0, 0],
      },
      {
        'attitude': [0, 0, double.nan, 1],
      },
      {'rotationRate': double.infinity},
      {'sequence': -1},
    ]) {
      expect(LiveSceneSignal.parse({...v, ...bad}), isNull);
    }
  });
  testWidgets(
    'first stable scene triggers once; unchanged video never polls cloud even after cooldown',
    (tester) async {
      final h = Harness(tester);
      addTearDown(h.controller.dispose);
      h.controller.setAutomatic(true);
      await h.frame(rate: 1);
      expect(h.backend.calls, 0);
      await h.stable();
      expect(h.backend.calls, 1);
      h.backend.finish();
      await tester.pump();
      expect(h.voice.said, [full]);
      await h.stable(frames: 240);
      expect(h.backend.calls, 1);
      expect(h.controller.automatic, isTrue);
      h.controller.dispose();
    },
  );
  testWidgets(
    'important visual change waits for stability and cooldown; audio omits identical sentences',
    (tester) async {
      final h = Harness(tester);
      addTearDown(h.controller.dispose);
      h.controller.setAutomatic(true);
      await h.stable();
      h.backend.finish();
      await tester.pump();
      await h.stable(luma: 100);
      expect(h.backend.calls, 1);
      await h.stable(luma: 100, frames: 230);
      expect(h.backend.calls, 2);
      h.backend.finish(text: '畫面左邊有張木枱。右邊見到一個櫃。');
      await tester.pump();
      expect(h.voice.said.last, '右邊見到一個櫃。');
      h.controller.dispose();
    },
  );
  testWidgets(
    'turn invalidates reply and keeps single in flight, then needs stable evidence',
    (tester) async {
      final h = Harness(tester);
      addTearDown(h.controller.dispose);
      h.controller.setAutomatic(true);
      await h.stable();
      expect(h.backend.calls, 1);
      await h.frame(yaw: 30, rate: 1);
      await h.stable(yaw: 30);
      expect(h.backend.calls, 1);
      h.backend.finish();
      await tester.pump();
      expect(h.voice.said, isEmpty);
      expect(h.controller.text, isNull);
      await h.stable(yaw: 30, frames: 230);
      expect(h.backend.calls, 2);
      h.backend.finish();
      await tester.pump();
      h.controller.dispose();
    },
  );
  testWidgets(
    'stop before capture returns prevents upload and does not debit an attempt',
    (tester) async {
      final h = Harness(tester);
      addTearDown(h.controller.dispose);
      h.bytes = Completer<Uint8List?>();
      await h.stable();
      final pending = h.controller.describe();
      await tester.pump();
      h.controller.setAvailable(false);
      h.bytes.complete(Uint8List(1));
      await pending;
      expect(h.backend.calls, 0);
      expect(h.controller.attempts, 0);
      h.controller.setAvailable(true);
      expect(h.controller.automatic, isFalse);
      h.controller.dispose();
    },
  );
  testWidgets('missing usage stops auto; later motion stops speech', (
    tester,
  ) async {
    final h = Harness(tester);
    addTearDown(h.controller.dispose);
    h.controller.setAutomatic(true);
    await h.stable();
    h.voice.wait = Completer<void>();
    h.backend.finish(usage: false);
    await tester.pump();
    expect(h.controller.usageUnknown, isTrue);
    expect(h.controller.automatic, isFalse);
    expect(h.voice.said, [full]);
    await h.frame(rate: 1);
    expect(h.controller.text, isNull);
    expect(h.voice.stops, greaterThan(0));
    h.controller.dispose();
  });
  testWidgets(
    'exhausted backend never auto repeats and leaves local camera availability intact',
    (tester) async {
      final h = Harness(tester);
      addTearDown(h.controller.dispose);
      h.controller.setAutomatic(true);
      await h.stable();
      h.backend.pending.last.completeError(
        const SceneFailure('resource-exhausted'),
      );
      await tester.pump();
      expect(h.controller.automatic, isFalse);
      expect(h.controller.available, isTrue);
      await h.stable(luma: 100, frames: 240);
      expect(h.backend.calls, 1);
      h.controller.dispose();
    },
  );
  testWidgets(
    'stale frame cancels reply; background/overlay need explicit auto re-enable',
    (tester) async {
      final h = Harness(tester);
      addTearDown(h.controller.dispose);
      h.controller.setAutomatic(true);
      await h.stable();
      h.now = h.now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      h.backend.finish();
      await tester.pump();
      expect(h.voice.said, isEmpty);
      h.controller.interrupt();
      expect(h.controller.automatic, isFalse);
      h.controller.setAvailable(false);
      h.controller.setAvailable(true);
      await h.stable(luma: 100, frames: 240);
      expect(h.backend.calls, 1);
      h.controller.dispose();
    },
  );
  testWidgets(
    'three attempts shared by manual and automatic cannot produce a fourth request',
    (tester) async {
      final h = Harness(tester);
      addTearDown(h.controller.dispose);
      h.controller.setAutomatic(true);
      for (var i = 0; i < 3; i++) {
        await h.stable(luma: 40 + i * 60, frames: i == 0 ? 8 : 240);
        expect(h.backend.calls, i + 1);
        h.backend.finish();
        await tester.pump();
      }
      expect(h.controller.automatic, isFalse);
      await h.stable(luma: 240, frames: 240);
      await h.controller.describe();
      expect(h.backend.calls, 3);
      expect(h.controller.canDescribe, isFalse);
      h.controller.dispose();
    },
  );
  testWidgets(
    'scene cannot preempt local alerts or navigation and is never queued',
    (tester) async {
      final output = Voice()..hold = true;
      final voice = SpeechCoordinator(output);
      final local = voice.channel(SpeechChannel.environment).speak('物件提示');
      await tester.pump();
      await voice.channel(SpeechChannel.scene).speak(full);
      expect(output.said, ['物件提示']);
      final nav = voice.channel(SpeechChannel.navigation).speak('導航');
      await tester.pump();
      expect(output.said, ['物件提示', '導航']);
      await voice.stop();
      await local;
      await nav;
    },
  );
}
