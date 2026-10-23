import 'announcer.dart';

/// One output route for both requested results and automatic announcements.
/// The screen reader and TTS must never read the same result simultaneously.
class EnvironmentSpeaker implements Speaker {
  EnvironmentSpeaker({
    required this.tts,
    required this.screenReaderActive,
    required this.announce,
  });

  final Speaker tts;
  final bool Function() screenReaderActive;
  final Future<void> Function(String) announce;

  @override
  Future<void> speak(String text) =>
      screenReaderActive() ? announce(text) : tts.speak(text);

  @override
  Future<void> stop() => tts.stop();

  @override
  Future<List<String>> languages() => tts.languages();
}
