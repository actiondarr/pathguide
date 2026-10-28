import 'dart:async';

import 'package:pathguide/depth/depth_session.dart';

class FakeDepthSource implements DepthSource {
  final events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  String? token;
  int starts = 0, stops = 0;
  String result = 'running';
  Completer<String>? pendingStart;
  @override
  Stream<Map<Object?, Object?>> get frames => events.stream;
  @override
  Future<String> start(String session) async {
    token = session;
    starts++;
    return pendingStart == null ? result : pendingStart!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  void sample(
    double time, {
    double range = 2,
    String state = 'sample',
    Map<Object?, Object?> extra = const {},
  }) {
    events.add({
      'session': token,
      'timestamp': time,
      'ageMs': 20,
      'status': state,
      'rangeM': range,
      'planeZM': range * 0.99,
      'accepted': 25,
      'total': 25,
      'spreadM': 0.02,
      ...extra,
    });
  }

  void stable({double time = 1, double range = 2}) {
    for (var i = 0; i < 3; i++) {
      sample(time + i * 0.15, range: range);
    }
  }
}
