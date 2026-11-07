import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../platform/app_attestation.dart';

class SceneFailure implements Exception {
  const SceneFailure(this.code);
  final String code;
}

String sceneRequestId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

// Defense in depth; a prompt alone is not an output validation boundary.
String validateSceneText(Object? value) {
  if (value is! String) throw const SceneFailure('invalid-answer');
  final text = value.trim();
  final sentences = RegExp(r'[^。！？]+[。！？]').allMatches(text).toList();
  if (text.length > 240 ||
      sentences.length < 2 ||
      sentences.length > 3 ||
      sentences.map((m) => m[0]).join() != text ||
      !RegExp(r'[\u3400-\u9fff]').hasMatch(text) ||
      RegExp(
        r'[\r\n<>0-9０-９]|米|公尺|厘米|公里|met(?:er|re)|樓(?!梯)|層|目的地|安全|暢通|通行|避開|繞過|向左|向右|左轉|右轉|可以行|可以走|往前|前進|直行|行過去|走過去|左邊行|右邊行|靠左|靠右|向前|向後|往左|往右|前行|後退|退後|行去|行入|行出|走去|走入|走出|繼續行|繼續走|可通過|可行|可走|請|建議|應該|必須|你可|呎|尺|英寸|英吋|马|车|门|栏|电|这|个|侧|见|间|楼|层',
        caseSensitive: false,
      ).hasMatch(text)) {
    throw const SceneFailure('invalid-answer');
  }
  return text;
}

class SceneReply {
  SceneReply.fromMap(Map map, String expectedId) {
    if (map['requestId'] != expectedId) {
      throw const SceneFailure('wrong-request');
    }
    metrics = SceneMetrics.fromMap(map['metrics']);
    if (map['status'] == 'complete') {
      text = validateSceneText(map['text']);
    } else if (map['status'] != 'rejected' || map.containsKey('text')) {
      throw const SceneFailure('invalid-answer');
    }
  }
  String? text;
  late final SceneMetrics metrics;
}

/// Only bounded numerical telemetry crosses into the retained measurements.
class SceneMetrics {
  SceneMetrics.fromMap(Object? value) {
    if (value is! Map) throw const SceneFailure('invalid-metrics');
    final ms = value['modelMs'];
    if (ms is! int || ms < 0 || ms > 40000) {
      throw const SceneFailure('invalid-metrics');
    }
    modelMs = ms;
    final u = value['usage'];
    if (u is Map) {
      final p = u['prompt_tokens'],
          c = u['completion_tokens'],
          t = u['total_tokens'];
      if (p is int && c is int && t is int && p >= 0 && c >= 0 && t == p + c) {
        promptTokens = p;
        completionTokens = c;
        totalTokens = t;
      }
    }
    final e = value['estimate'];
    if (totalTokens != null && e is Map && e['notBillingCap'] == true) {
      final usd = e['usd'];
      if (usd is num && usd.isFinite && usd >= 0) estimatedUsd = usd.toDouble();
    }
  }
  late final int modelMs;
  int? promptTokens, completionTokens, totalTokens;
  double? estimatedUsd;
}

/// Device verification can be slow; cancellation before it finishes must not
/// start a new paid upload afterward.
Future<void> awaitSceneAttestation(
  Future<bool> activation,
  bool Function()? isCurrent,
) async {
  final ready = await activation;
  if (!(isCurrent?.call() ?? true)) throw const SceneFailure('cancelled');
  if (!ready) throw const SceneFailure('app-check-unavailable');
}

abstract interface class SceneBackend {
  Future<SceneReply> describe(
    Uint8List jpeg,
    String requestId, {
    bool Function()? isCurrent,
  });
}

class FirebaseSceneBackend implements SceneBackend {
  // Across page/controller replacement: cancellation never starts a second call.
  static bool _inFlight = false;
  @override
  Future<SceneReply> describe(
    Uint8List jpeg,
    String requestId, {
    bool Function()? isCurrent,
  }) async {
    if (_inFlight) throw const SceneFailure('busy');
    _inFlight = true;
    try {
      if (!const bool.fromEnvironment('SCENE_DESCRIPTION_ENABLED') ||
          Firebase.apps.isEmpty ||
          FirebaseAuth.instance.currentUser == null) {
        throw const SceneFailure('not-configured');
      }
      await awaitSceneAttestation(activateAppAttestation(), isCurrent);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final response = await FirebaseFunctions.instanceFor(region: 'asia-east2')
          .httpsCallable(
            'describeScene',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
          )
          .call<dynamic>({
            'schemaVersion': 1,
            'expectedUid': uid,
            'requestId': requestId,
            'mimeType': 'image/jpeg',
            'jpegBase64': base64Encode(jpeg),
          });
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw const SceneFailure('stale-account');
      }
      if (response.data is! Map) throw const SceneFailure('invalid-answer');
      return SceneReply.fromMap(response.data as Map, requestId);
    } on FirebaseFunctionsException catch (error) {
      throw SceneFailure(error.code);
    } finally {
      _inFlight = false;
    }
  }
}
