import 'route_library_controller.dart';
import 'encrypted_route_store.dart';
import 'route_package.dart';
import 'cross_floor_mock_fixtures.dart';

/// P1 buttons persist an explicitly synthetic structure, never captured truth.
class DeviceRouteLibrary implements RouteLibraryBackend {
  DeviceRouteLibrary(this.store);
  final EncryptedRouteStore store;
  @override
  Future<RouteLibraryListing> list() => store.list();
  @override
  Future<void> saveSample(
    String id,
    String name,
    bool draft,
    int expectedRevision,
  ) async {
    final token = store.capture(id);
    final fixture = crossFloorFixture();
    final doc = RouteDocument(
      id: id,
      name: name,
      buildingId: mockGround.buildingId,
      nodes: [
        for (final n in fixture.nodes)
          RoutePoint(
            n.id,
            n.nameZh,
            n.nameEn,
            floor: draft && n.id == '3-exit' ? null : n.floor,
          ),
      ],
      edges: [
        for (final e in fixture.edges)
          RouteSegment(
            e.fromId,
            e.toId,
            e.mode,
            connectorId: e.connectorId,
            confirmed: !draft,
          ),
      ],
    );
    await store.save(
      doc,
      token: token,
      expectedRevision: expectedRevision,
      activate: !draft,
    );
  }

  @override
  Future<void> rollback(String id, int version, int expectedRevision) =>
      store.rollback(id, version, expectedRevision: expectedRevision);
  @override
  Future<void> delete(String id, int expectedRevision) =>
      store.delete(id, expectedRevision: expectedRevision);
  @override
  Future<void> cleanup() async {
    await store.pruneHistory();
    await store.cleanupUnreferenced();
  }

  @override
  void cancelPending() => store.cancelPending();
}
