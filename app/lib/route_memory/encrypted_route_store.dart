import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'route_package.dart';

abstract interface class RouteKeyVault {
  Future<List<int>?> read();
  Future<void> write(List<int> bytes);
}

class DeviceRouteKeyVault implements RouteKeyVault {
  static const keyName = 'pathguide.route_memory.library.aes.v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );
  @override
  Future<List<int>?> read() async {
    final value = await _storage.read(key: keyName);
    return value == null ? null : base64Decode(value);
  }

  @override
  Future<void> write(List<int> bytes) =>
      _storage.write(key: keyName, value: base64Encode(bytes));
}

class RouteStoreLimits {
  const RouteStoreLimits({
    this.libraryBytes = 32 * 1024 * 1024,
    this.documentBytes = 256 * 1024,
    this.versionsPerRoute = 8,
  });
  final int libraryBytes, documentBytes, versionsPerRoute;
}

class _RouteActor {
  Future<void> tail = Future.value();
  final Map<String, int> routeEpoch = {};
  Future<T> run<T>(Future<T> Function() action) {
    final next = tail.then((_) => action());
    tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

class RouteWriteToken {
  RouteWriteToken._(this._owner, this.id, this._epoch, this._routeEpoch);
  final EncryptedRouteStore _owner;
  final String id;
  final int _epoch, _routeEpoch;
}

/// One route-library owner on the main isolate. Instances on that isolate share
/// a path-scoped actor; an advisory OS lock rejects another process. Do not use
/// independent writers in other isolates (POSIX locks are process-scoped).
class EncryptedRouteStore {
  EncryptedRouteStore._(this.directory, this._vault, this.limits, this._hook)
    : _actor = _actors.putIfAbsent(directory.path, _RouteActor.new);
  static final Map<String, _RouteActor> _actors = {};
  final Directory directory;
  final RouteKeyVault _vault;
  final RouteStoreLimits limits;
  final Future<void> Function(String)? _hook;
  final _RouteActor _actor;
  int _epoch = 0;
  final _cipher = AesGcm.with256bits();
  static const _scope = 'pathguide/device-local/routes/v1';

  static Future<EncryptedRouteStore> open({
    Directory? root,
    RouteKeyVault? vault,
    RouteStoreLimits limits = const RouteStoreLimits(),
    Future<void> Function(String)? checkpoint,
  }) async {
    try {
      final base = root ?? await getApplicationSupportDirectory();
      final dir = await Directory('${base.path}/route_memory_v1')
          .create(recursive: true);
      return EncryptedRouteStore._(
        Directory(await dir.resolveSymbolicLinks()),
        vault ?? DeviceRouteKeyVault(),
        limits,
        checkpoint,
      );
    } catch (_) {
      throw const RouteStoreFailure(RouteProblem.io);
    }
  }

  RouteWriteToken capture(String id) =>
      RouteWriteToken._(this, id, _epoch, _actor.routeEpoch[id] ?? 0);
  void cancelPending() => _epoch++;
  void _guard(RouteWriteToken token) {
    if (!identical(token._owner, this) ||
        token._epoch != _epoch ||
        token._routeEpoch != (_actor.routeEpoch[token.id] ?? 0)) {
      throw const RouteStoreFailure(RouteProblem.cancelled);
    }
  }

  Future<void> _step(String name) async {
    await _hook?.call(name);
  }

  String _sha(List<int> bytes) => hashes.sha256.convert(bytes).toString();
  String _random() => List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Directory _routeDir(String id) =>
      Directory('${directory.path}/${_sha(utf8.encode(id))}');
  File get _catalogFile => File('${directory.path}/catalog.enc');

  Future<T> _locked<T>(Future<T> Function(SecretKey) action) =>
      _actor.run(() async {
        RandomAccessFile? lock;
        try {
          lock = await File('${directory.path}/.lock')
              .open(mode: FileMode.append);
          try {
            await lock.lock(FileLock.exclusive);
          } on FileSystemException {
            throw const RouteStoreFailure(RouteProblem.busy);
          }
          return await action(await _key());
        } on RouteStoreFailure {
          rethrow;
        } catch (_) {
          throw const RouteStoreFailure(RouteProblem.io);
        } finally {
          await lock?.close();
        }
      });

  Future<SecretKey> _key() async {
    try {
      var bytes = await _vault.read();
      if (bytes == null) {
        await for (final f in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (f is File && !f.path.endsWith('/.lock')) {
            throw const RouteStoreFailure(RouteProblem.keyUnavailable);
          }
        }
        bytes = [for (var i = 0; i < 32; i++) Random.secure().nextInt(256)];
        await _vault.write(bytes);
      }
      if (bytes.length != 32) {
        throw const RouteStoreFailure(RouteProblem.keyUnavailable);
      }
      return SecretKey(bytes);
    } catch (_) {
      throw const RouteStoreFailure(RouteProblem.keyUnavailable);
    }
  }

  Future<List<int>> _seal(
    Map<String, dynamic> value,
    SecretKey key,
    String aad,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: key,
      aad: utf8.encode('$_scope/$aad'),
    );
    return utf8.encode(
      jsonEncode({
        'nonce': base64Encode(box.nonce),
        'data': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }

  Future<Map<String, dynamic>> _unseal(
    File file,
    SecretKey key,
    String aad,
  ) async {
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > 2 * 1024 * 1024) {
        throw const RouteStoreFailure(RouteProblem.corrupt);
      }
      final sealed = jsonDecode(await file.readAsString()) as Map;
      final bytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(sealed['data'] as String),
          nonce: base64Decode(sealed['nonce'] as String),
          mac: Mac(base64Decode(sealed['mac'] as String)),
        ),
        secretKey: key,
        aad: utf8.encode('$_scope/$aad'),
      );
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const RouteStoreFailure(RouteProblem.corrupt);
    }
  }

  Map<String, dynamic> _empty() => {
    'schema': 1,
    'owner': 'device-local',
    'routes': <String, dynamic>{},
    'deleted': <String, dynamic>{},
  };
  Future<Map<String, dynamic>> _catalog(SecretKey key) async {
    if (!await _catalogFile.exists()) return _empty();
    final cat = await _unseal(_catalogFile, key, 'catalog');
    try {
      if (cat['schema'] != 1 || cat['owner'] != 'device-local') {
        throw const RouteStoreFailure(RouteProblem.incompatible);
      }
      for (final id in (cat['deleted'] as Map).keys) {
        if (!RouteDocument.validId(id as String) ||
            (cat['routes'] as Map).containsKey(id)) {
          throw const FormatException();
        }
      }
      for (final e in (cat['routes'] as Map).entries) {
        final v = e.value as Map;
        if (!RouteDocument.validId(e.key as String) ||
            (v['revision'] as int) < 1 ||
            (v['next'] as int) < 2 ||
            (v['versions'] as Map).isEmpty) {
          throw const FormatException();
        }
        for (final p in ['active', 'draft']) {
          if (v[p] != null && !(v['versions'] as Map).containsKey('${v[p]}')) {
            throw const FormatException();
          }
        }
        for (final info in (v['versions'] as Map).entries) {
          if (int.parse(info.key as String) <= 0 ||
              int.parse(info.key as String) >= v['next'] ||
              !RegExp(r'^[a-f0-9]{32}\.enc$')
                  .hasMatch(info.value['file'] as String) ||
              !RegExp(r'^[a-f0-9]{64}$')
                  .hasMatch(info.value['sha'] as String)) {
            throw const FormatException();
          }
        }
      }
      return cat;
    } on RouteStoreFailure {
      rethrow;
    } catch (_) {
      throw const RouteStoreFailure(RouteProblem.corrupt);
    }
  }

  Future<void> _budget(int additional) async {
    var total = additional;
    await for (final f in directory.list(recursive: true, followLinks: false)) {
      if (f is File) total += await f.length();
    }
    if (total > limits.libraryBytes) {
      throw const RouteStoreFailure(RouteProblem.capacity);
    }
  }

  Future<void> _commit(
    Map<String, dynamic> cat,
    SecretKey key, {
    RouteWriteToken? token,
    bool deletion = false,
  }) async {
    final bytes = await _seal(cat, key, 'catalog');
    if (bytes.length > 2 * 1024 * 1024) {
      throw const RouteStoreFailure(RouteProblem.capacity);
    }
    if (!deletion) await _budget(bytes.length);
    final temp = File('${directory.path}/${_random()}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await _step('beforeCatalogCommit');
    if (token != null) _guard(token);
    await temp.rename(_catalogFile.path);
    try {
      await _step('afterCatalogCommit');
    } catch (_) {
      throw const RouteStoreFailure(RouteProblem.outcomeUnknown);
    }
  }

  Future<RouteSnapshot> _read(
    String id,
    int version,
    Map entry,
    SecretKey key,
  ) async {
    final info = entry['versions']['$version'];
    if (info == null) throw const RouteStoreFailure(RouteProblem.notFound);
    final file = File('${_routeDir(id).path}/${info['file']}');
    try {
      if (await file.length() > 2 * 1024 * 1024) {
        throw const RouteStoreFailure(RouteProblem.corrupt);
      }
      if (_sha(await file.readAsBytes()) != info['sha']) {
        throw const RouteStoreFailure(RouteProblem.corrupt);
      }
      final v = await _unseal(file, key, '$id/$version');
      final document = RouteDocument.fromMap(
        v['document'] as Map<String, dynamic>,
      );
      final published = v['published'] as bool;
      if (v['version'] != version ||
          document.id != id ||
          _sha(utf8.encode(jsonEncode(v['document']))) != v['manifestSha'] ||
          (published && !document.complete)) {
        throw const FormatException();
      }
      return RouteSnapshot(
        document,
        version,
        published,
        v['manifestSha'] as String,
      );
    } on RouteStoreFailure {
      rethrow;
    } catch (_) {
      throw const RouteStoreFailure(RouteProblem.corrupt);
    }
  }

  Future<RouteLibraryListing> list() => _locked((key) async {
    final cat = await _catalog(key);
    final routes = <RouteLibraryEntry>[];
    for (final e in (cat['routes'] as Map).entries) {
      final v = e.value as Map;
      final versions =
          (v['versions'] as Map).keys
              .map((s) => int.parse(s as String))
              .toList()
            ..sort();
      final recover = <int>[];
      var name = '';
      RouteProblem? problem;
      for (final version in versions) {
        try {
          final snapshot = await _read(e.key as String, version, v, key);
          if (snapshot.published &&
              snapshot.document.compatible &&
              version != v['active']) {
            recover.add(version);
          }
          if (version == (v['draft'] ?? v['active'])) {
            name = snapshot.document.name;
          }
          if ((version == v['active'] || version == v['draft']) &&
              !snapshot.document.compatible) {
            problem = RouteProblem.incompatible;
          }
        } on RouteStoreFailure catch (error) {
          if (version == v['active'] || version == v['draft']) {
            problem = error.problem;
          }
        }
      }
      routes.add(
        RouteLibraryEntry(
          id: e.key as String,
          name: name,
          revision: v['revision'] as int,
          versions: versions,
          rollbackVersions: recover,
          activeVersion: v['active'] as int?,
          draftVersion: v['draft'] as int?,
          problem: problem,
        ),
      );
    }
    var pending = 0;
    for (final id in (cat['deleted'] as Map).keys) {
      if (await _routeDir(id as String).exists()) pending++;
    }
    return RouteLibraryListing(routes, pending);
  });

  Future<RouteSnapshot> read(String id, {int? version}) => _locked((key) async {
    final cat = await _catalog(key);
    final entry = cat['routes'][id] as Map?;
    if (entry == null) throw const RouteStoreFailure(RouteProblem.notFound);
    final selected = version ?? entry['active'] ?? entry['draft'];
    return _read(id, selected as int, entry, key);
  });

  Future<RouteSnapshot> save(
    RouteDocument document, {
    required RouteWriteToken token,
    required int expectedRevision,
    required bool activate,
  }) => _locked((key) async {
    _guard(token);
    document.validate();
    if (token.id != document.id || (activate && !document.complete)) {
      throw const RouteStoreFailure(RouteProblem.invalid);
    }
    if (activate && !document.compatible) {
      throw const RouteStoreFailure(RouteProblem.incompatible);
    }
    final cat = await _catalog(key);
    if ((cat['deleted'] as Map).containsKey(document.id)) {
      throw const RouteStoreFailure(RouteProblem.deleted);
    }
    final previous = cat['routes'][document.id] as Map?;
    if ((previous?['revision'] ?? 0) != expectedRevision) {
      throw const RouteStoreFailure(RouteProblem.conflict);
    }
    if (((previous?['versions'] as Map?)?.length ?? 0) >=
        limits.versionsPerRoute) {
      throw const RouteStoreFailure(RouteProblem.capacity);
    }
    final version = previous?['next'] as int? ?? 1;
    final doc = document.toMap();
    final hash = _sha(utf8.encode(jsonEncode(doc)));
    if (utf8.encode(jsonEncode(doc)).length > limits.documentBytes) {
      throw const RouteStoreFailure(RouteProblem.capacity);
    }
    final bytes = await _seal(
      {
        'document': doc,
        'version': version,
        'published': activate,
        'manifestSha': hash,
      },
      key,
      '${document.id}/$version',
    );
    await _budget(bytes.length);
    _guard(token);
    final folder = await _routeDir(document.id).create();
    final filename = '${_random()}.enc';
    final temp = File('${folder.path}/$filename.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await _step('afterVersionWrite');
    _guard(token);
    await temp.rename('${folder.path}/$filename');
    cat['routes'][document.id] = {
      'revision': expectedRevision + 1,
      'next': version + 1,
      'active': activate ? version : previous?['active'],
      'draft': activate ? null : version,
      'versions': {
        ...?previous?['versions'] as Map?,
        '$version': {'file': filename, 'sha': _sha(bytes)},
      },
    };
    await _commit(cat, key, token: token);
    return RouteSnapshot(document, version, activate, hash);
  });

  Future<void> rollback(
    String id,
    int version, {
    required int expectedRevision,
  }) {
    final token = capture(id);
    return _locked((key) async {
      _guard(token);
      final cat = await _catalog(key);
      final e = cat['routes'][id] as Map?;
      if (e == null) throw const RouteStoreFailure(RouteProblem.notFound);
      if (e['revision'] != expectedRevision) {
        throw const RouteStoreFailure(RouteProblem.conflict);
      }
      final snapshot = await _read(id, version, e, key);
      if (!snapshot.published || !snapshot.document.compatible) {
        throw const RouteStoreFailure(RouteProblem.incompatible);
      }
      e['active'] = version;
      e['revision'] = expectedRevision + 1;
      await _commit(cat, key, token: token);
    });
  }

  Future<void> delete(String id, {required int expectedRevision}) {
    _actor.routeEpoch[id] = (_actor.routeEpoch[id] ?? 0) + 1;
    return _locked((key) async {
      final cat = await _catalog(key);
      final e = cat['routes'][id] as Map?;
      if (e == null && !(cat['deleted'] as Map).containsKey(id)) {
        throw const RouteStoreFailure(RouteProblem.notFound);
      }
      if (e != null && e['revision'] != expectedRevision) {
        throw const RouteStoreFailure(RouteProblem.conflict);
      }
      cat['routes'].remove(id);
      cat['deleted'][id] = true;
      await _commit(cat, key, deletion: true);
      try {
        await _step('beforeDeleteCleanup');
        await _removeDir(id);
      } catch (_) {
        throw const RouteStoreFailure(RouteProblem.cleanupPending);
      }
    });
  }

  Future<void> _removeDir(String id) async {
    final dir = _routeDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> cleanupDeleted() => _locked((key) async {
    final cat = await _catalog(key);
    for (final id in (cat['deleted'] as Map).keys) {
      await _removeDir(id as String);
    }
  });

  /// User-requested history pruning: retain active, current draft and one
  /// verified compatible published fallback. Never reuses version numbers.
  Future<void> pruneHistory() => _locked((key) async {
    final cat = await _catalog(key);
    var changed = false;
    for (final e in (cat['routes'] as Map).entries) {
      final entry = e.value as Map;
      final keep = <int>{
        if (entry['active'] != null) entry['active'] as int,
        if (entry['draft'] != null) entry['draft'] as int,
      };
      final versions =
          (entry['versions'] as Map).keys
              .map((s) => int.parse(s as String))
              .toList()
            ..sort((a, b) => b.compareTo(a));
      for (final version in versions) {
        if (version == entry['active']) continue;
        try {
          final s = await _read(e.key as String, version, entry, key);
          if (s.published && s.document.compatible) {
            keep.add(version);
            break;
          }
        } on RouteStoreFailure {
          /* Preserve active separately; reject corrupt fallback. */
        }
      }
      final old = entry['versions'] as Map;
      if (old.length != keep.length) {
        entry['versions'] = {for (final v in keep) '$v': old['$v']};
        entry['revision'] = (entry['revision'] as int) + 1;
        changed = true;
      }
    }
    if (changed) await _commit(cat, key, deletion: true);
  });

  /// Explicit maintenance only. Never deletes a referenced corrupt revision.
  Future<void> cleanupUnreferenced() => _locked((key) async {
    final cat = await _catalog(key);
    final keep = <String>{_catalogFile.path, '${directory.path}/.lock'};
    for (final e in (cat['routes'] as Map).entries) {
      for (final info in (e.value['versions'] as Map).values) {
        keep.add('${_routeDir(e.key as String).path}/${info['file']}');
      }
    }
    await for (final f in directory.list(recursive: true, followLinks: false)) {
      if (f is File && !keep.contains(f.path)) await f.delete();
    }
    for (final id in (cat['deleted'] as Map).keys) {
      await _removeDir(id as String);
    }
  });
}
