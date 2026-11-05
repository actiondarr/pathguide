import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'cross_floor_contract.dart';
import 'encrypted_route_store.dart';
import 'route_package.dart';
import 'route_observation_source.dart';
import 'route_landmark_client.dart';
import 'route_localizer.dart';

enum RecordedRouteMode { library, record, replay }

/// One screen owns camera, analysis jobs and store writes. Every asynchronous
/// operation is fenced; replay never calls save or retains new camera frames.
class RecordedRouteController extends ChangeNotifier {
  RecordedRouteController({
    required this.store,
    RouteObservationSource? source,
    RouteLandmarkClient? analyzer,
  }) : source = source ?? RouteObservationSource(),
       analyzer = analyzer ?? RouteLandmarkClient() {
    _events = this.source.events.listen(
      (status) {
        if (!_stopping &&
            _running &&
            [
              RouteCaptureStatus.paused,
              RouteCaptureStatus.stopped,
              RouteCaptureStatus.unsupported,
              RouteCaptureStatus.permission,
              RouteCaptureStatus.unavailable,
              RouteCaptureStatus.failed,
              RouteCaptureStatus.stopUnconfirmed,
            ].contains(status)) {
          unawaited(pause());
        }
      },
      onError: (Object _) {
        unawaited(pause());
      },
    );
  }
  final EncryptedRouteStore store;
  final RouteObservationSource source;
  final RouteLandmarkClient analyzer;
  StreamSubscription<RouteCaptureStatus>? _events;
  RecordedRouteMode mode = RecordedRouteMode.library;
  List<RouteLibraryEntry> entries = const [];
  List<RoutePoint> _nodes = [];
  List<RouteSegment> _edges = [];
  List<CapturedRouteView> _views = [];
  Map<String, Uint8List> _media = {};
  String? _id;
  String _name = '', _building = '';
  int _captureVersion = 1, _revision = 0, _epoch = 0;
  bool _busy = false,
      _running = false,
      _foreground = true,
      _disposed = false,
      _stopping = false,
      _dirty = false,
      _reloadRequired = false;
  bool finished = false;
  int? _index, _transition;
  String notice = 'ready';
  String? problem;
  RouteLibraryEntry? selected;
  RouteLocalizer? _localizer;
  bool get busy => _busy;
  bool get running => _running;
  bool get dirty => _dirty;
  bool get canEdit =>
      !_disposed &&
      _foreground &&
      !_busy &&
      !_stopping &&
      !_reloadRequired &&
      mode == RecordedRouteMode.record;
  bool get canCapture => canEdit && _running;
  bool get canCheck =>
      !_disposed &&
      _foreground &&
      !_busy &&
      _running &&
      mode == RecordedRouteMode.replay &&
      !finished;
  String get name => _name;
  List<RoutePoint> get nodes => List.unmodifiable(_nodes);
  String? get actualNodeId => _localizer?.actualNodeId;
  FloorRef? get actualFloor => _localizer?.actualFloor;
  FloorRef? get expectedFloor => _localizer?.expectedFloor;
  RoutePoint? get nextPoint => _index != null && _index! + 1 < _nodes.length
      ? _nodes[_index! + 1]
      : null;
  bool get atArrival =>
      actualNodeId != null && actualNodeId == _nodes.lastOrNull?.id;
  RouteDocument? get document => _id == null
      ? null
      : RouteDocument(
          id: _id!,
          name: _name,
          buildingId: _building,
          nodes: _nodes,
          edges: _edges,
          source: RouteContentSource.captured,
          views: _views,
          featureRevision: RouteLocalizer.featureRevision,
          preprocessRevision: RouteLocalizer.preprocessRevision,
        );
  bool _current(int op) => !_disposed && _foreground && op == _epoch;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  String _newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void _error(Object error) {
    problem = error is RouteStoreFailure
        ? error.problem.name
        : error is LandmarkFailure
        ? error.code
        : 'failed';
    notice = 'error';
  }

  Future<void> refresh() async {
    if (_disposed || !_foreground || _busy) return;
    final op = ++_epoch;
    _busy = true;
    _changed();
    try {
      final all = await store.list();
      final captured = <RouteLibraryEntry>[];
      for (final entry in all.routes) {
        try {
          if ((await store.read(entry.id)).document.source ==
              RouteContentSource.captured) {
            captured.add(entry);
          }
        } on RouteStoreFailure catch (error) {
          captured.add(
            RouteLibraryEntry(
              id: entry.id,
              name: entry.name,
              revision: entry.revision,
              versions: entry.versions,
              rollbackVersions: entry.rollbackVersions,
              activeVersion: entry.activeVersion,
              draftVersion: entry.draftVersion,
              problem: error.problem,
            ),
          );
        }
      }
      if (!_current(op)) return;
      entries = List.unmodifiable(captured);
      problem = null;
    } catch (e) {
      if (_current(op)) _error(e);
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
  }

  Future<void> startRecording(String name) async {
    if (_disposed ||
        !_foreground ||
        _busy ||
        name.trim().isEmpty ||
        name.length > 120) {
      return;
    }
    await pause();
    if (_disposed || !_foreground || notice == 'stopUnconfirmed') return;
    _localizer?.dispose();
    _localizer = null;
    _id = _newId();
    _building = 'b-$_id';
    _name = name.trim();
    _revision = 0;
    _captureVersion = 1;
    _nodes = [];
    _edges = [];
    _views = [];
    _media = {};
    selected = null;
    _dirty = false;
    _reloadRequired = false;
    finished = false;
    _index = _transition = null;
    mode = RecordedRouteMode.record;
    await resume();
  }

  Future<void> resume() async {
    if (_disposed ||
        !_foreground ||
        _busy ||
        _stopping ||
        _id == null ||
        _reloadRequired ||
        finished ||
        mode == RecordedRouteMode.library) {
      return;
    }
    if (mode == RecordedRouteMode.replay && _localizer == null) {
      notice = 'draft';
      _changed();
      return;
    }
    final op = ++_epoch;
    _busy = true;
    problem = null;
    _changed();
    try {
      final status = await source.start(
        routeId: _id!,
        routeVersion: _captureVersion,
      );
      if (!_current(op)) return;
      _running = status == RouteCaptureStatus.running;
      notice = _running ? 'ready' : status.name;
    } catch (e) {
      if (_current(op)) _error(e);
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
  }

  FloorRef? _floor(String label, bool confirmed) {
    if (!confirmed || label.trim().isEmpty) return null;
    if (label.trim().length > 40) {
      throw const RouteStoreFailure(RouteProblem.invalid);
    }
    String key(String value) =>
        value.trim().toUpperCase().replaceAll(RegExp(r'[\s/]'), '');
    for (final n in _nodes) {
      if (n.floor != null && key(n.floor!.label) == key(label)) return n.floor;
    }
    return FloorRef(_building, 'f-${_newId()}', label.trim());
  }

  RouteSegment _edge(int index, ConnectorMode mode, bool confirmed) {
    final a = _nodes[index - 1], b = _nodes[index];
    return RouteSegment(
      a.id,
      b.id,
      mode,
      connectorId: mode == ConnectorMode.walk ? null : 'connector-$index',
      confirmed:
          confirmed &&
          a.floor != null &&
          b.floor != null &&
          (mode != ConnectorMode.walk || a.floor == b.floor),
    );
  }

  Future<(RouteKeyframe, LandmarkAnalysis)> _capture(int op) async {
    final captured = await source.capture();
    if (!_current(op) || !_running) throw const LandmarkFailure('cancelled');
    final frame = captured.keyframe;
    if (frame == null) throw LandmarkFailure(captured.status.name);
    final value = await analyzer.analyze(frame);
    if (!_current(op) || !_running) throw const LandmarkFailure('cancelled');
    return (frame, value);
  }

  Future<void> recordLandmark(
    String name,
    String floor, {
    ConnectorMode mode = ConnectorMode.walk,
    bool confirmed = false,
    String? nodeId,
  }) async {
    if (!canCapture || name.trim().isEmpty || name.length > 120) return;
    final existing = nodeId == null
        ? null
        : _nodes.indexWhere((n) => n.id == nodeId);
    if (existing != null && existing < 0) return;
    if (_views.length >= 64 ||
        (nodeId != null &&
            _views.where((v) => v.nodeId == nodeId).length >= 4)) {
      problem = 'capacity';
      notice = 'error';
      _changed();
      return;
    }
    final op = _epoch;
    _busy = true;
    problem = null;
    _changed();
    try {
      final (frame, value) = await _capture(op);
      final id = nodeId ?? 'n-${_nodes.length + 1}';
      if (_views.any((v) => v.nodeId == id && v.imageSha == value.imageSha)) {
        notice = 'duplicate';
        return;
      }
      final featureSha = sha256.convert(value.feature).toString();
      final view = CapturedRouteView(
        nodeId: id,
        viewId: 'v-${_views.where((v) => v.nodeId == id).length + 1}',
        imageSha: value.imageSha,
        imageBytes: frame.bytes.length,
        width: frame.width,
        height: frame.height,
        featureSha: featureSha,
        featureBytes: value.feature.length,
        savedAtUtc: DateTime.now().toUtc().toIso8601String(),
        observation: frame.observation,
      );
      view.validate(_id!);
      if (nodeId == null) {
        final f = _floor(floor, confirmed);
        _nodes.add(RoutePoint(id, name.trim(), name.trim(), floor: f));
        if (_nodes.length > 1) {
          _edges.add(_edge(_nodes.length - 1, mode, confirmed));
        }
      }
      _views.add(view);
      _media[value.imageSha] = Uint8List.fromList(frame.bytes)
          .asUnmodifiableView();
      _media[featureSha] = value.feature;
      _dirty = true;
      notice = 'captured';
    } catch (e) {
      if (_current(op)) _error(e);
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
  }

  void updateNode(
    int index,
    String name,
    String floor,
    ConnectorMode mode,
    bool confirmed,
  ) {
    if (!canEdit ||
        index < 0 ||
        index >= _nodes.length ||
        name.trim().isEmpty ||
        name.length > 120) {
      return;
    }
    try {
      final previous = _nodes[index], f = _floor(floor, confirmed);
      _nodes[index] = RoutePoint(
        previous.id,
        name.trim(),
        name.trim(),
        floor: f,
      );
      if (index > 0) _edges[index - 1] = _edge(index, mode, confirmed);
      if (previous.floor != f && index < _edges.length) {
        final old = _edges[index];
        _edges[index] = RouteSegment(
          old.fromId,
          old.toId,
          old.mode,
          connectorId: old.connectorId,
          confirmed: false,
        );
      }
      _dirty = true;
      notice = 'edited';
      problem = null;
    } catch (e) {
      _error(e);
    }
    _changed();
  }

  Future<void> save({required bool activate, String? name}) async {
    if (!canEdit || _nodes.isEmpty) return;
    if (name != null) {
      if (name.trim().isEmpty || name.length > 120) return;
      _name = name.trim();
    }
    final op = ++_epoch;
    _busy = true;
    _running = false;
    _stopping = true;
    problem = null;
    _changed();
    try {
      final stopped = await source.stop();
      await analyzer.cancel();
      if (!_current(op)) return;
      if (stopped == RouteCaptureStatus.stopUnconfirmed) {
        notice = 'stopUnconfirmed';
        return;
      }
      final doc = document!;
      final saved = await store.save(
        doc,
        token: store.capture(doc.id),
        expectedRevision: _revision,
        activate: activate,
        media: _media,
      );
      if (!_current(op)) return;
      _captureVersion = saved.version;
      _revision++;
      _dirty = false;
      notice = 'saved';
    } catch (e) {
      if (_current(op)) {
        _error(e);
        if (e is RouteStoreFailure &&
            [
              RouteProblem.outcomeUnknown,
              RouteProblem.conflict,
            ].contains(e.problem)) {
          _reloadRequired = true;
        }
      }
    } finally {
      _stopping = false;
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
  }

  Future<void> open(RouteLibraryEntry entry, {bool recording = false}) async {
    await pause();
    if (_disposed || !_foreground || notice == 'stopUnconfirmed') return;
    _clearSelection();
    final op = ++_epoch;
    _busy = true;
    problem = null;
    _changed();
    try {
      final version = recording
          ? (entry.draftVersion ?? entry.activeVersion)
          : (entry.activeVersion ?? entry.draftVersion);
      final snapshot = await store.read(entry.id, version: version);
      final doc = snapshot.document;
      if (doc.source != RouteContentSource.captured) {
        throw const RouteStoreFailure(RouteProblem.incompatible);
      }
      final hashes = recording
          ? null
          : {
              for (final v in doc.views)
                if (v.featureSha != null) v.featureSha!,
            };
      final media = await store.readMediaBatch(
        entry.id,
        snapshot.version,
        hashes: hashes,
      );
      if (!_current(op)) return;
      _id = doc.id;
      _building = doc.buildingId;
      _name = doc.name;
      _nodes = List.of(doc.nodes);
      _edges = List.of(doc.edges);
      _views = List.of(doc.views);
      _media = Map.of(media);
      selected = entry;
      _revision = entry.revision;
      _captureVersion = snapshot.version;
      _dirty = false;
      _reloadRequired = false;
      finished = false;
      _index = _transition = null;
      mode = recording ? RecordedRouteMode.record : RecordedRouteMode.replay;
      _localizer?.dispose();
      _localizer = null;
      if (!recording && snapshot.published && doc.complete && doc.compatible) {
        _localizer = RouteLocalizer(
          routeId: doc.id,
          routeVersion: snapshot.version,
          landmarks: [
            for (final n in doc.nodes)
              RouteLandmarkIdentity(
                n.id,
                n.floor!,
                [
                  for (final v in doc.views.where(
                    (v) => v.nodeId == n.id && v.featureSha != null,
                  ))
                    v.viewId,
                ],
                exitForConnectors: [
                  for (final e in doc.edges.where(
                    (e) =>
                        e.toId == n.id &&
                        e.mode != ConnectorMode.walk &&
                        e.confirmed,
                  ))
                    e.connectorId!,
                ],
              ),
          ],
        );
        notice = 'replayReady';
      } else {
        notice = recording
            ? 'paused'
            : !doc.compatible
            ? 'incompatible'
            : 'draft';
      }
    } catch (e) {
      if (_current(op)) _error(e);
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
  }

  Future<void> checkPosition(
    String nodeId,
    String floor, {
    required bool directionConfirmed,
  }) async {
    if (!canCheck || _localizer == null) return;
    final candidates = _nodes.where((n) => n.id == nodeId).toList();
    if (candidates.length != 1) return;
    final node = candidates.single;
    _localizer!.pause();
    if (_transition != null) {
      final edge = _edges[_transition!];
      if (edge.toId != nodeId) {
        notice = 'wrongNode';
        _changed();
        return;
      }
      _localizer!.expectFloor(
        node.floor,
        exitNodeId: node.id,
        connectorId: edge.connectorId,
      );
    } else {
      _localizer!.expectFloor(null);
    }
    String normalized(String v) =>
        v.trim().toUpperCase().replaceAll(RegExp(r'[\s/]'), '');
    if (node.floor == null ||
        normalized(floor) != normalized(node.floor!.label) ||
        !directionConfirmed) {
      notice = !directionConfirmed ? 'wrongDirection' : 'wrongFloor';
      _changed();
      return;
    }
    final op = _epoch, watch = Stopwatch()..start();
    _busy = true;
    problem = null;
    notice = 'checking';
    _changed();
    try {
      final (frame, value) = await _capture(op);
      final featureViews = _views.where((v) => v.featureSha != null).toList();
      final distances = await analyzer.compare(value.feature, [
        for (final v in featureViews)
          _media[v.featureSha] ??
              (throw const RouteStoreFailure(RouteProblem.corrupt)),
      ]);
      if (!_current(op) || !_running) return;
      final ticket = _localizer!.beginObservation(
        frameAge:
            Duration(milliseconds: (frame.observation['ageMs'] as num).ceil()) +
            watch.elapsed,
      );
      _localizer!.accept(
        ticket,
        [
          for (var i = 0; i < featureViews.length; i++)
            RouteViewDistance(
              featureViews[i].nodeId,
              featureViews[i].viewId,
              distances[i],
            ),
        ],
        feature: RouteLocalizer.featureRevision,
        preprocess: RouteLocalizer.preprocessRevision,
        ocr: value.text,
      );
      if (_localizer!.result != RouteMatchState.candidate) {
        notice = _localizer!.result.name;
        return;
      }
      _localizer!.confirmFloor(node.floor!);
      _localizer!.confirmExit(directionConfirmed: true);
      if (_localizer!.actualNodeId != nodeId) {
        _localizer!.pause();
        notice = 'wrongNode';
        return;
      }
      _index = _nodes.indexOf(node);
      _transition = null;
      notice = atArrival ? 'arrival' : 'confirmed';
    } catch (e) {
      if (_current(op)) {
        _localizer?.pause();
        _error(e);
      }
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
  }

  bool enterConnector() {
    if (_disposed ||
        !_foreground ||
        _busy ||
        actualNodeId == null ||
        _index == null ||
        _index! >= _edges.length) {
      return false;
    }
    final edge = _edges[_index!];
    if (edge.mode == ConnectorMode.walk || !edge.confirmed) return false;
    _transition = _index;
    _localizer!.expectFloor(
      _nodes[_index! + 1].floor,
      exitNodeId: edge.toId,
      connectorId: edge.connectorId,
    );
    notice = 'transitioning';
    _changed();
    return true;
  }

  Future<void> confirmArrival() async {
    if (!atArrival || _busy) return;
    await pause();
    if (notice != 'stopUnconfirmed') {
      finished = true;
      notice = 'finished';
      _changed();
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    final op = ++_epoch;
    _busy = false;
    _running = false;
    _stopping = true;
    _localizer?.pause();
    store.cancelPending();
    notice = 'paused';
    _changed();
    await analyzer.cancel();
    final status = await source.stop();
    _stopping = false;
    if (_disposed || op != _epoch) return;
    if (status == RouteCaptureStatus.stopUnconfirmed) {
      notice = 'stopUnconfirmed';
    }
    _changed();
  }

  void setForeground(bool foreground) {
    if (_disposed) return;
    _foreground = foreground;
    if (!foreground) {
      unawaited(pause());
    } else {
      _changed();
    }
  }

  Future<void> delete(RouteLibraryEntry entry) async {
    await pause();
    if (_disposed || !_foreground || notice == 'stopUnconfirmed') return;
    final op = ++_epoch;
    _busy = true;
    _changed();
    try {
      await store.delete(entry.id, expectedRevision: entry.revision);
      if (!_current(op)) return;
      _id = null;
      _media.clear();
      _nodes = [];
      _edges = [];
      _views = [];
      _dirty = false;
      selected = null;
      mode = RecordedRouteMode.library;
      notice = 'deleted';
    } catch (e) {
      if (_current(op)) _error(e);
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
    await refresh();
  }

  Future<void> rollback(RouteLibraryEntry entry, int version) async {
    if (_busy || _disposed || !_foreground) return;
    await pause();
    if (notice == 'stopUnconfirmed') return;
    final op = ++_epoch;
    _busy = true;
    _changed();
    try {
      await store.rollback(entry.id, version, expectedRevision: entry.revision);
      if (_current(op)) {
        notice = 'rolledBack';
        mode = RecordedRouteMode.library;
        selected = null;
        _media.clear();
      }
    } catch (e) {
      if (_current(op)) _error(e);
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
    await refresh();
  }

  void _clearSelection() {
    _localizer?.dispose();
    _localizer = null;
    _id = null;
    _nodes = [];
    _edges = [];
    _views = [];
    _media.clear();
    selected = null;
    _dirty = false;
    _reloadRequired = false;
    finished = false;
    _index = _transition = null;
    mode = RecordedRouteMode.library;
  }

  bool get replayAvailable => _localizer != null;
  RoutePoint? get transitionExit =>
      _transition == null ? null : _nodes[_transition! + 1];
  ConnectorMode? get nextConnector =>
      _index == null || _index! >= _edges.length ? null : _edges[_index!].mode;
  int viewsFor(String id) => _views.where((v) => v.nodeId == id).length;
  ConnectorMode incomingMode(int index) =>
      index > 0 ? _edges[index - 1].mode : ConnectorMode.walk;
  bool incomingConfirmed(int index) =>
      _nodes[index].floor != null &&
      (index == 0 || _edges[index - 1].confirmed);

  Future<void> showLibrary() async {
    await pause();
    if (_disposed || !_foreground || notice == 'stopUnconfirmed') return;
    _clearSelection();
    await refresh();
  }

  Future<void> cleanup() async {
    if (_busy || _disposed || !_foreground) return;
    final op = ++_epoch;
    _busy = true;
    _changed();
    try {
      await store.pruneHistory();
      if (!_current(op)) return;
      await store.cleanupUnreferenced();
      if (_current(op)) notice = 'cleaned';
    } catch (e) {
      if (_current(op)) _error(e);
    } finally {
      if (_current(op)) {
        _busy = false;
        _changed();
      }
    }
    if (_current(op)) await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    store.cancelPending();
    _localizer?.dispose();
    analyzer.dispose();
    unawaited(source.stop());
    unawaited(_events?.cancel());
    _media.clear();
    super.dispose();
  }
}
