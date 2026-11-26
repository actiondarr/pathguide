import 'dart:convert';
import 'dart:math';

import '../route_memory/encrypted_route_store.dart';
import '../route_memory/route_package.dart';
import 'outdoor_track.dart';

class OutdoorRouteStore {
  OutdoorRouteStore(this.store);
  final EncryptedRouteStore store;

  static Future<OutdoorRouteStore> open() async =>
      OutdoorRouteStore(await EncryptedRouteStore.open(outdoor: true));

  static String newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<RouteLibraryListing> list() => store.list();

  Future<RouteSnapshot> read(RouteLibraryEntry entry) =>
      store.read(entry.id, version: entry.draftVersion ?? entry.activeVersion);

  Future<void> delete(RouteLibraryEntry entry) =>
      store.delete(entry.id, expectedRevision: entry.revision);

  Future<RouteSnapshot> save(String id, String name, OutdoorTrack track) async {
    final document = RouteDocument(
      id: id,
      name: name,
      buildingId: 'outdoor',
      nodes: const [],
      edges: const [],
      source: RouteContentSource.outdoor,
      outdoor: track,
    );
    try {
      return await store.save(
        document,
        token: store.capture(id),
        expectedRevision: 0,
        activate: document.complete,
      );
    } on RouteStoreFailure catch (e) {
      if (e.problem != RouteProblem.outcomeUnknown &&
          e.problem != RouteProblem.conflict) {
        rethrow;
      }
      // Recover an acknowledged-late commit, including after a UI retry.
      final persisted = await store.read(id, version: 1);
      if (jsonEncode(persisted.document.outdoor?.toMap()) ==
          jsonEncode(track.toMap())) {
        return persisted;
      }
      rethrow;
    }
  }
}
