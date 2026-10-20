import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pathguide/tts/flutter_tts_speaker.dart';
import 'package:flutter_tts/flutter_tts.dart';

// flutter_tts 的音訊設定用 dart:io 判斷宿主；Windows 測試只記錄 API 邊界。
class _AudioSessionTts extends FlutterTts {
  IosTextToSpeechAudioCategory? category;
  @override
  Future<dynamic> setIosAudioCategory(
    IosTextToSpeechAudioCategory category,
    List<IosTextToSpeechAudioCategoryOptions> options, [
    IosTextToSpeechAudioMode mode = IosTextToSpeechAudioMode.defaultMode,
  ]) async {
    this.category = category;
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var available = <String>['zh-HK', 'yue-HK', 'zh-TW', 'zh-CN'];
  final rejected = <String>{};

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    rejected.clear();
    available = <String>['zh-HK', 'yue-HK', 'zh-TW', 'zh-CN'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'getLanguages') return available;
          if (call.method == 'setLanguage' &&
              rejected.contains(call.arguments)) {
            return 0;
          }
          return 1;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  test(
    'iOS selects zh-HK first and configures the shared audio session',
    () async {
      final tts = _AudioSessionTts();
      final speaker = FlutterTtsSpeaker(tts: tts);
      expect(await speaker.initialize(), 'zh-HK');
      expect(calls.where((c) => c.method == 'setSharedInstance'), isNotEmpty);
      expect(tts.category, IosTextToSpeechAudioCategory.playback);
      await speaker.speak('垃圾桶');
      expect(calls.where((c) => c.method == 'speak').single.arguments, '垃圾桶');
    },
  );

  test(
    'applies the configured speech rate before and after initialization',
    () async {
      final speaker = FlutterTtsSpeaker(speechRate: 0.35);

      await speaker.initialize();
      expect(
        calls.where((call) => call.method == 'setSpeechRate').first.arguments,
        0.35,
      );

      await speaker.setSpeechRate(0.55);
      expect(speaker.speechRate, 0.55);
      expect(
        calls.where((call) => call.method == 'setSpeechRate').last.arguments,
        0.55,
      );
    },
  );

  test(
    'rejected Cantonese voice falls back to another accepted Cantonese voice',
    () async {
      rejected.add('zh-HK');
      expect(await FlutterTtsSpeaker().initialize(), 'yue-HK');
    },
  );

  test(
    'no accepted language stays unavailable and never sends speech',
    () async {
      rejected.addAll(available);
      final speaker = FlutterTtsSpeaker();
      expect(await speaker.initialize(), isNull);
      expect(speaker.isCantonese, isFalse);
      await speaker.speak('垃圾桶');
      expect(calls.where((c) => c.method == 'speak'), isEmpty);
    },
  );

  test(
    'Android retains yue-HK preference and Android queue configuration',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await FlutterTtsSpeaker().initialize(), 'yue-HK');
      expect(calls.where((c) => c.method == 'setQueueMode'), isNotEmpty);
      expect(calls.where((c) => c.method == 'setIosAudioCategory'), isEmpty);
    },
  );
}
