import 'package:pathguide/navigation/navigation_models.dart';
import 'package:pathguide/outdoor_routes/outdoor_track.dart';

final outdoorEpoch = DateTime.utc(2026, 11, 27);

Coordinate metres(num east, num north) =>
    Coordinate(north / 111195, east / 111195);

DateTime at(int seconds) => outdoorEpoch.add(Duration(seconds: seconds));
Duration elapsed(int seconds) => Duration(seconds: seconds);

LocationFix fix(
  int time,
  num east,
  num north, {
  double accuracy = 3,
  double? speed = 1.4,
  double? speedAccuracy = 0.2,
  double? course,
  int? received,
  double ageSeconds = 0,
}) => LocationFix(
  coordinate: metres(east, north),
  accuracy: accuracy,
  sampledAt: at(time),
  receivedAt: elapsed(received ?? time),
  speed: speed,
  speedAccuracy: speedAccuracy,
  course: course,
  ageSeconds: ageSeconds,
);

OutdoorTrack routeWith(
  List<(int, int)> coordinates, {
  double accuracy = 3,
  List<OutdoorMark> marks = const [],
}) => OutdoorTrack(
  segments: [
    [
      for (final (index, (x, y)) in coordinates.indexed)
        OutdoorPoint(metres(x, y), at(index * 5), accuracy, 1.4),
    ],
  ],
  marks: marks,
  speeds: [(time: at(1), metresPerSecond: 1.4)],
  elapsed: elapsed(coordinates.length * 5),
  hasGap: false,
  atCapacity: false,
);

OutdoorTrack cornerRoute({
  double accuracy = 3,
  List<OutdoorMark> marks = const [],
}) => routeWith(
  [(0, 0), (10, 0), (20, 0), (30, 0), (30, 10), (30, 20), (30, 30)],
  accuracy: accuracy,
  marks: marks,
);
