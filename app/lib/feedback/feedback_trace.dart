import 'dart:async';

import '../settings/app_settings.dart';
import '../tts/announcer.dart';
import '../tts/flutter_tts_speaker.dart';
import 'feedback_store.dart';

/// Volatile, opt-in history. Nothing is persisted until Save is requested.
class FeedbackTrace {
  FeedbackTrace(this.settings, this.mode, {DateTime Function()? clock})
    : now = clock ?? DateTime.now {
    settings.addListener(_settingsChanged);
  }

  final AppSettings settings;
  final String mode;
  final DateTime Function() now;
  static const window = Duration(seconds: 45);
  static const maxEvents = 120;
  final _events = <({DateTime time, Map<String, Object?> data})>[];
  Map<String, Object?> context = const {};
  int? _utterance;
  int _sequence = 0;
  bool _closed = false;
  Timer? _expiry;

  void _settingsChanged() {
    if (!settings.feedbackEnabled) clear();
  }

  void clear() {
    _expiry?.cancel();
    _expiry = null;
    _events.clear();
    _utterance = null;
    _speechText = null;
    context = const {};
  }

  void _prune() {
    final cutoff = now().subtract(window);
    _events.removeWhere((e) => e.time.isBefore(cutoff));
  }

  void event(String kind, [Map<String, Object?> details = const {}]) {
    if (_closed || !settings.feedbackEnabled) return;
    _prune();
    final time = now();
    _events.add((
      time: time,
      data: {
        'at': time.toUtc().toIso8601String(),
        'kind': kind,
        ...context,
        ...details,
      },
    ));
    if (_events.length > maxEvents) _events.removeAt(0);
    _expiry ??= Timer.periodic(const Duration(seconds: 5), (timer) {
      _prune();
      if (_events.isEmpty) {
        timer.cancel();
        _expiry = null;
      }
    });
  }

  int queue(String text) {
    final ticket = ++_sequence;
    if (settings.feedbackEnabled) {
      event('queued', {'utterance': ticket, 'text': text});
    }
    return ticket;
  }

  String? _speechText;
  void submitted(String text, {required bool voiceOver, int? ticket}) {
    if (!settings.feedbackEnabled || _closed) return;
    _utterance = ticket ?? ++_sequence;
    _speechText = text;
    event(voiceOver ? 'voiceOverSubmitted' : 'submitted', {
      'utterance': _utterance,
      'text': text,
    });
    if (voiceOver) _utterance = null;
  }

  void playback(TtsPlaybackEvent eventType) {
    final id = _utterance;
    if (id == null) return;
    event(eventType.name, {'utterance': id, 'text': _speechText});
    if (eventType != TtsPlaybackEvent.started) _utterance = null;
  }

  FeedbackDraft snapshot() {
    _prune();
    return FeedbackDraft(
      feedbackId(),
      mode,
      now().toUtc(),
      List.unmodifiable(
        _events.map((e) => Map<String, Object?>.unmodifiable(e.data)),
      ),
    );
  }

  void dispose() {
    settings.removeListener(_settingsChanged);
    _closed = true;
    clear();
  }
}

/// Records submission to TTS. Only the native playback callback records onset.
class FeedbackTts implements Speaker {
  FeedbackTts(this.trace, this.delegate);
  final FeedbackTrace trace;
  final Speaker delegate;
  @override
  Future<void> speak(String text) {
    trace.submitted(text, voiceOver: false);
    return delegate.speak(text);
  }

  @override
  Future<void> stop() => delegate.stop();
  @override
  Future<List<String>> languages() => delegate.languages();
}
