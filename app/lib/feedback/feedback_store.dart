import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../route_memory/encrypted_route_store.dart';
import '../route_memory/route_file_policy.dart';

typedef FeedbackTransport = Future<bool> Function(FeedbackDraft draft);

String feedbackId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class FeedbackDraft {
  const FeedbackDraft(
    this.id,
    this.mode,
    this.savedAt,
    this.events, {
    this.audio,
    this.photo,
    this.sent = false,
  });
  final String id, mode;
  final DateTime savedAt;
  final List<Map<String, Object?>> events;
  final String? audio, photo;
  final bool sent;
  factory FeedbackDraft.fromMap(Map<String, dynamic> map) => FeedbackDraft(
    map['id'] as String,
    map['mode'] as String,
    DateTime.parse(map['savedAt'] as String),
    (map['events'] as List)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList(),
    audio: map['audio'] as String?,
    photo: map['photo'] as String?,
    sent: map['sent'] as bool? ?? false,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'mode': mode,
    'savedAt': savedAt.toIso8601String(),
    'events': events,
    'audio': audio,
    'photo': photo,
    'sent': sent,
  };
}

class FeedbackStore {
  FeedbackStore._(this.directory, this.vault, this.files);
  final Directory directory;
  final RouteKeyVault vault;
  final RouteFilePolicy? files;
  static const maxDrafts = 12;
  static final _cipher = AesGcm.with256bits();
  static final _queues = <String, Future<void>>{};

  static Future<FeedbackStore> open({
    Directory? root,
    RouteKeyVault? vault,
  }) async {
    final policy = root == null
        ? await RouteFilePolicy.open(feedback: true)
        : null;
    return FeedbackStore._(
      root ?? policy!.directory,
      vault ?? DeviceRouteKeyVault.feedback(),
      policy,
    );
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final next = (_queues[directory.path] ?? Future<void>.value()).then(
      (_) => action(),
    );
    _queues[directory.path] = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  File get _catalog => File('${directory.path}/catalog.enc');
  Future<List<FeedbackDraft>> _read() async {
    if (!await _catalog.exists()) return [];
    final bytes = await vault.read();
    if (bytes == null || await _catalog.length() > 2 * 1024 * 1024) {
      throw const FileSystemException('Feedback vault unavailable');
    }
    final envelope = await _catalog.readAsBytes();
    final box = SecretBox.fromConcatenation(
      envelope,
      nonceLength: 12,
      macLength: 16,
    );
    final plain = await _cipher.decrypt(
      box,
      secretKey: SecretKey(bytes),
      aad: utf8.encode('pathguide-feedback-v1'),
    );
    return (jsonDecode(utf8.decode(plain)) as List)
        .map((e) => FeedbackDraft.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _write(List<FeedbackDraft> drafts) async {
    var bytes = await vault.read();
    if (bytes == null) {
      bytes = await (await _cipher.newSecretKey()).extractBytes();
      await vault.write(bytes);
    }
    final data = (await _cipher.encrypt(
      utf8.encode(jsonEncode(drafts.map((d) => d.toMap()).toList())),
      secretKey: SecretKey(bytes),
      aad: utf8.encode('pathguide-feedback-v1'),
    )).concatenation();
    if (data.length > 2 * 1024 * 1024) {
      throw const FileSystemException('Feedback storage full');
    }
    final temp = File('${directory.path}/${feedbackId()}.tmp');
    try {
      if (files case final policy?) {
        await policy.write(temp, data);
        await policy.rename(temp, _catalog.path);
      } else {
        await temp.writeAsBytes(data, flush: true);
        await temp.rename(_catalog.path);
      }
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<List<FeedbackDraft>> list() => _locked(_read);

  Future<void> save(FeedbackDraft draft) => _locked(() async {
    final drafts = await _read();
    final index = drafts.indexWhere((d) => d.id == draft.id);
    if (index < 0 && drafts.length >= maxDrafts) {
      throw const FileSystemException('Feedback storage full');
    }
    if (index < 0) {
      drafts.insert(0, draft);
    } else {
      drafts[index] = draft;
    }
    await _write(drafts);
  });

  Future<void> delete(String id) => _locked(() async {
    final drafts = await _read()
      ..removeWhere((d) => d.id == id);
    await _write(drafts);
  });

  /// Transports must use draft.id as their idempotency key. A failed send leaves the original.
  Future<bool> send(FeedbackDraft draft, FeedbackTransport? transport) =>
      _locked(() async {
        final drafts = await _read();
        final index = drafts.indexWhere((d) => d.id == draft.id);
        if (index < 0 || transport == null) return false;
        final current = drafts[index];
        if (current.sent) return true;
        if (!await transport(current)) return false;
        drafts[index] = FeedbackDraft(
          current.id,
          current.mode,
          current.savedAt,
          current.events,
          audio: current.audio,
          photo: current.photo,
          sent: true,
        );
        await _write(drafts);
        return true;
      });
}
