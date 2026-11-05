import 'package:flutter/foundation.dart';

import 'cross_floor_contract.dart';
import 'route_media.dart';
export 'route_media.dart';

enum RouteProblem {
  invalid,
  conflict,
  cancelled,
  deleted,
  notFound,
  corrupt,
  incompatible,
  keyUnavailable,
  busy,
  io,
  cleanupPending,
  capacity,
  outcomeUnknown,
}

class RouteStoreFailure implements Exception {
  const RouteStoreFailure(this.problem);
  final RouteProblem problem;
  @override
  String toString() => 'RouteStoreFailure(${problem.name})';
}

@immutable
class RoutePoint {
  const RoutePoint(this.id, this.nameZh, this.nameEn, {this.floor});
  final String id, nameZh, nameEn;
  final FloorRef? floor;
}

@immutable
class RouteSegment {
  const RouteSegment(
    this.fromId,
    this.toId,
    this.mode, {
    this.connectorId,
    this.confirmed = false,
  });
  final String fromId, toId;
  final ConnectorMode mode;
  final String? connectorId;
  final bool confirmed;
}

enum RouteContentSource { synthetic, captured }

/// Schema 1 remains synthetic; schema 2 explicitly references captured media.
/// 'Complete' means structurally checked; never human/field approved.
class RouteDocument {
  RouteDocument({
    required this.id,
    required this.name,
    required this.buildingId,
    required List<RoutePoint> nodes,
    required List<RouteSegment> edges,
    this.source = RouteContentSource.synthetic,
    List<CapturedRouteView> views = const [],
    this.featureRevision = 'p0-synthetic-v1',
    this.preprocessRevision = 'none-synthetic',
  }) : views = List.unmodifiable(views),
       nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges) {
    validate();
  }
  final String id, name, buildingId, featureRevision, preprocessRevision;
  final RouteContentSource source;
  final List<CapturedRouteView> views;
  final List<RoutePoint> nodes;
  final List<RouteSegment> edges;
  static bool validId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id);
  bool get compatible => source == RouteContentSource.synthetic
      ? featureRevision == 'p0-synthetic-v1' &&
            preprocessRevision == 'none-synthetic'
      : featureRevision == 'vision-featureprint-v1' &&
            preprocessRevision == 'upright-jpeg-v1';

  void validate() {
    if ((source == RouteContentSource.synthetic && views.isNotEmpty) ||
        (source == RouteContentSource.captured &&
            (featureRevision == 'p0-synthetic-v1' ||
                preprocessRevision == 'none-synthetic')) ||
        views.length > RouteMediaBounds.viewsPerRoute) {
      throw const RouteStoreFailure(RouteProblem.invalid);
    }
    final identities = <String>{}, images = <String>{};
    final perNode = <String, int>{};
    for (final view in views) {
      view.validate(id);
      perNode[view.nodeId] = (perNode[view.nodeId] ?? 0) + 1;
      if (!nodes.any((n) => n.id == view.nodeId) ||
          !identities.add('${view.nodeId}/${view.viewId}') ||
          !images.add('${view.nodeId}/${view.imageSha}') ||
          perNode[view.nodeId]! > RouteMediaBounds.viewsPerNode) {
        throw const RouteStoreFailure(RouteProblem.invalid);
      }
    }
    if (!validId(id) ||
        !validId(buildingId) ||
        name.trim().isEmpty ||
        name.length > 120 ||
        nodes.length > 512 ||
        edges.length > 511 ||
        featureRevision.isEmpty ||
        featureRevision.length > 80 ||
        preprocessRevision.isEmpty ||
        preprocessRevision.length > 80 ||
        nodes.map((n) => n.id).toSet().length != nodes.length) {
      throw const RouteStoreFailure(RouteProblem.invalid);
    }
    for (final n in nodes) {
      if (!validId(n.id) ||
          n.nameZh.length > 120 ||
          n.nameEn.length > 120 ||
          (n.floor != null &&
              (n.floor!.buildingId != buildingId ||
                  !validId(n.floor!.id) ||
                  n.floor!.label.isEmpty ||
                  n.floor!.label.length > 40))) {
        throw const RouteStoreFailure(RouteProblem.invalid);
      }
    }
    if (edges.length > (nodes.isEmpty ? 0 : nodes.length - 1)) {
      throw const RouteStoreFailure(RouteProblem.invalid);
    }
    for (var i = 0; i < edges.length; i++) {
      if (edges[i].fromId != nodes[i].id ||
          edges[i].toId != nodes[i + 1].id ||
          (edges[i].connectorId != null && !validId(edges[i].connectorId!))) {
        throw const RouteStoreFailure(RouteProblem.invalid);
      }
    }
  }

  bool get complete {
    if (nodes.length < 2 ||
        edges.length != nodes.length - 1 ||
        nodes.any((n) => n.floor == null)) {
      return false;
    }
    if (source == RouteContentSource.captured &&
        nodes.any(
          (node) =>
              !views.any((v) => v.nodeId == node.id && v.featureSha != null),
        )) {
      return false;
    }
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      if (!e.confirmed ||
          (e.mode == ConnectorMode.walk &&
              nodes[i].floor != nodes[i + 1].floor) ||
          (e.mode != ConnectorMode.walk && e.connectorId == null)) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> toMap() => {
    'schemaVersion': source == RouteContentSource.synthetic ? 1 : 2,
    'source': source.name,
    if (source == RouteContentSource.captured)
      'views': [for (final view in views) view.toMap()],
    'direction': 'recorded',
    'id': id,
    'name': name,
    'buildingId': buildingId,
    'featureRevision': featureRevision,
    'preprocessRevision': preprocessRevision,
    'nodes': [
      for (final n in nodes)
        {
          'id': n.id,
          'zh': n.nameZh,
          'en': n.nameEn,
          'floor': n.floor == null
              ? null
              : {
                  'building': n.floor!.buildingId,
                  'id': n.floor!.id,
                  'label': n.floor!.label,
                },
        },
    ],
    'edges': [
      for (final e in edges)
        {
          'from': e.fromId,
          'to': e.toId,
          'mode': e.mode.name,
          'connector': e.connectorId,
          'confirmed': e.confirmed,
        },
    ],
  };

  factory RouteDocument.fromMap(Map<String, dynamic> v) {
    final synthetic =
        v['schemaVersion'] == 1 &&
        v['source'] == 'synthetic' &&
        !v.containsKey('views');
    final captured = v['schemaVersion'] == 2 && v['source'] == 'captured';
    if ((!synthetic && !captured) || v['direction'] != 'recorded') {
      throw const RouteStoreFailure(RouteProblem.incompatible);
    }
    return RouteDocument(
      source: captured
          ? RouteContentSource.captured
          : RouteContentSource.synthetic,
      views: captured
          ? [
              for (final view in v['views'] as List)
                CapturedRouteView.fromMap(
                  Map<String, dynamic>.from(view as Map),
                ),
            ]
          : const [],
      id: v['id'] as String,
      name: v['name'] as String,
      buildingId: v['buildingId'] as String,
      featureRevision: v['featureRevision'] as String,
      preprocessRevision: v['preprocessRevision'] as String,
      nodes: [
        for (final n in v['nodes'] as List)
          RoutePoint(
            n['id'] as String,
            n['zh'] as String,
            n['en'] as String,
            floor: n['floor'] == null
                ? null
                : FloorRef(
                    n['floor']['building'] as String,
                    n['floor']['id'] as String,
                    n['floor']['label'] as String,
                  ),
          ),
      ],
      edges: [
        for (final e in v['edges'] as List)
          RouteSegment(
            e['from'] as String,
            e['to'] as String,
            ConnectorMode.values.byName(e['mode'] as String),
            connectorId: e['connector'] as String?,
            confirmed: e['confirmed'] as bool,
          ),
      ],
    );
  }
}

@immutable
class RouteSnapshot {
  const RouteSnapshot(
    this.document,
    this.version,
    this.published,
    this.manifestSha,
  );
  final RouteDocument document;
  final int version;
  final bool published;
  final String manifestSha;
}

@immutable
class RouteLibraryEntry {
  RouteLibraryEntry({
    required this.id,
    required this.name,
    required this.revision,
    required List<int> versions,
    required List<int> rollbackVersions,
    this.activeVersion,
    this.draftVersion,
    this.problem,
  }) : versions = List.unmodifiable(versions),
       rollbackVersions = List.unmodifiable(rollbackVersions);
  final String id, name;
  final int revision;
  final int? activeVersion, draftVersion;
  final List<int> versions, rollbackVersions;
  final RouteProblem? problem;
}

@immutable
class RouteLibraryListing {
  RouteLibraryListing(List<RouteLibraryEntry> routes, this.pendingCleanup)
    : routes = List.unmodifiable(routes);
  final List<RouteLibraryEntry> routes;
  final int pendingCleanup;
}
