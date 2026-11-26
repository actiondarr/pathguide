import 'dart:math' as math;

import '../navigation/navigation_models.dart';
import '../route_memory/route_media.dart';
import '../route_memory/route_package.dart' show RoutePoint;

const outdoorFixAge = Duration(seconds: 5);
const outdoorRecordingLoss = Duration(seconds: 20);
const outdoorReplayLoss = Duration(seconds: 8);
const outdoorAccuracy = 15.0;

enum OutdoorMarkKind {
  steps('台階', 'Steps'),
  junction('路口', 'Junction'),
  door('門口', 'Entrance'),
  toilet('洗手間', 'Toilet'),
  subway('行人隧道', 'Pedestrian subway'),
  footbridge('行人天橋', 'Footbridge'),
  busStop('巴士站', 'Bus stop'),
  parking('停車場', 'Car park'),
  turnLeft('左轉', 'Turn left'),
  aheadLeft('左前方', 'Ahead on the left'),
  aheadRight('右前方', 'Ahead on the right'),
  turnRight('右轉', 'Turn right'),
  bypassLeft('向左繞過', 'Go around to the left'),
  bypassRight('向右繞過', 'Go around to the right'),
  audio('錄音', 'Audio'),
  text('文字', 'Text');

  const OutdoorMarkKind(this.zh, this.en);
  final String zh, en;
}

class OutdoorPoint {
  const OutdoorPoint(this.coordinate, this.time, this.accuracy, this.speed);

  final Coordinate coordinate;
  final DateTime time;
  final double accuracy;
  final double? speed;

  factory OutdoorPoint.fromFix(LocationFix fix, double? speed) =>
      OutdoorPoint(fix.coordinate, fix.sampledAt!, fix.accuracy, speed);

  factory OutdoorPoint.fromMap(List p) => OutdoorPoint(
    Coordinate((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    DateTime.fromMillisecondsSinceEpoch(p[2] as int, isUtc: true),
    (p[3] as num).toDouble(),
    (p[4] as num?)?.toDouble(),
  );

  List<Object?> toMap() => [
    coordinate.latitude,
    coordinate.longitude,
    time.millisecondsSinceEpoch,
    accuracy,
    speed,
  ];

  bool get valid =>
      coordinate.valid &&
      time.isUtc &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      accuracy <= outdoorAccuracy &&
      (speed == null || validOutdoorSpeed(speed!));
}

bool validOutdoorSpeed(double speed) =>
    speed.isFinite && speed >= 0 && speed <= 4;

bool usableOutdoorFix(LocationFix fix, Duration now, DateTime wallTime) {
  final sample = fix.sampledAt;
  if (sample == null) return false;
  final age = wallTime.difference(sample);
  return age >= const Duration(seconds: -1) &&
      age <= outdoorFixAge &&
      fix.receivedAt <= now &&
      now - fix.receivedAt <= outdoorFixAge &&
      fix.ageSeconds.isFinite &&
      fix.ageSeconds >= 0 &&
      fix.ageSeconds <= outdoorFixAge.inSeconds &&
      fix.coordinate.valid &&
      fix.accuracy.isFinite &&
      fix.accuracy >= 0 &&
      fix.accuracy <= outdoorAccuracy;
}

class OutdoorMark {
  const OutdoorMark({
    required this.kind,
    required this.point,
    required this.segment,
    required this.pointIndex,
    this.text,
    this.audio,
  });

  final OutdoorMarkKind kind;
  final OutdoorPoint point;
  final int segment, pointIndex;
  final String? text;
  final RouteAudioNote? audio;

  factory OutdoorMark.fromMap(Map mark) => OutdoorMark(
    kind: OutdoorMarkKind.values.byName(mark['kind'] as String),
    point: OutdoorPoint.fromMap(mark['position'] as List),
    segment: mark['segment'] as int,
    pointIndex: mark['point'] as int,
    text: mark['text'] as String?,
    audio: mark['audio'] == null
        ? null
        : RouteAudioNote.fromBase64(mark['audio'] as String),
  );

  Map<String, Object> toMap() => {
    'kind': kind.name,
    'position': point.toMap(),
    'segment': segment,
    'point': pointIndex,
    'text': ?text,
    if (audio != null) 'audio': audio!.encoded,
  };

  bool get valid =>
      point.valid &&
      ((kind == OutdoorMarkKind.text) == (text != null)) &&
      ((kind == OutdoorMarkKind.audio) == (audio != null)) &&
      (text == null || RoutePoint.validTextNote(text!));
}

typedef OutdoorSpeed = ({DateTime time, double metresPerSecond});

enum OutdoorDraftReason { noStart, singlePoint, gap, shortTrack, capacity }

class OutdoorTrack {
  OutdoorTrack({
    required Iterable<List<OutdoorPoint>> segments,
    required Iterable<OutdoorMark> marks,
    required Iterable<OutdoorSpeed> speeds,
    required this.elapsed,
    required this.hasGap,
    required this.atCapacity,
  }) : segments = List.unmodifiable(
         segments.map(List<OutdoorPoint>.unmodifiable),
       ),
       marks = List.unmodifiable(marks),
       speeds = List.unmodifiable(speeds) {
    validate();
  }

  static const maxPoints = 2200;
  static const maxMarks = 128;
  static const maxSpeeds = 1500;
  static const minimumDistance = 20.0;
  final List<List<OutdoorPoint>> segments;
  final List<OutdoorMark> marks;
  final List<OutdoorSpeed> speeds;
  final Duration elapsed;
  final bool hasGap, atCapacity;

  int get pointCount =>
      segments.fold(0, (count, segment) => count + segment.length);
  double get distance =>
      segments.fold(0.0, (sum, segment) => sum + outdoorDistance(segment));
  int get audioBytes =>
      marks.fold(0, (sum, m) => sum + (m.audio?.bytes.length ?? 0));
  int get encodedAudioLength =>
      marks.fold(0, (sum, m) => sum + (m.audio?.encoded.length ?? 0));

  OutdoorDraftReason? get draftReason {
    if (atCapacity) return OutdoorDraftReason.capacity;
    if (pointCount == 0) return OutdoorDraftReason.noStart;
    if (pointCount == 1) return OutdoorDraftReason.singlePoint;
    if (hasGap) return OutdoorDraftReason.gap;
    if (pointCount < 3 || distance < minimumDistance) {
      return OutdoorDraftReason.shortTrack;
    }
    return null;
  }

  factory OutdoorTrack.fromMap(Map data) {
    final track = OutdoorTrack(
      segments: (data['segments'] as List).map(
        (segment) => (segment as List)
            .map((p) => OutdoorPoint.fromMap(p as List))
            .toList(),
      ),
      marks: (data['marks'] as List).map((m) => OutdoorMark.fromMap(m as Map)),
      speeds: (data['speeds'] as List).map((value) {
        final s = value as List;
        return (
          time: DateTime.fromMillisecondsSinceEpoch(s[0] as int, isUtc: true),
          metresPerSecond: (s[1] as num).toDouble(),
        );
      }),
      elapsed: Duration(milliseconds: data['durationMs'] as int),
      hasGap: data['hasGap'] as bool,
      atCapacity: data['atCapacity'] as bool,
    );
    final savedDistance = (data['distanceMetres'] as num).toDouble();
    if (!savedDistance.isFinite ||
        (savedDistance - track.distance).abs() > 0.001) {
      throw const FormatException('Invalid outdoor distance');
    }
    return track;
  }

  Map<String, Object> toMap() => {
    'segments': [
      for (final s in segments) [for (final p in s) p.toMap()],
    ],
    'marks': [for (final m in marks) m.toMap()],
    'speeds': [
      for (final s in speeds)
        [s.time.millisecondsSinceEpoch, s.metresPerSecond],
    ],
    'durationMs': elapsed.inMilliseconds,
    'distanceMetres': distance,
    'hasGap': hasGap,
    'atCapacity': atCapacity,
  };

  void validate() {
    if (pointCount > maxPoints ||
        marks.length > maxMarks ||
        speeds.length > maxSpeeds ||
        elapsed.isNegative ||
        (segments.length > 1 && !hasGap) ||
        audioBytes > RouteMediaBounds.audioBytesPerRoute) {
      throw const FormatException('Invalid outdoor track');
    }
    OutdoorPoint? previous;
    for (final segment in segments) {
      if (segment.isEmpty) throw const FormatException('Empty outdoor segment');
      for (final point in segment) {
        if (!point.valid ||
            (previous != null && !point.time.isAfter(previous.time))) {
          throw const FormatException('Invalid outdoor point');
        }
        previous = point;
      }
    }
    for (final mark in marks) {
      if (!mark.valid ||
          mark.segment < 0 ||
          mark.segment >= segments.length ||
          mark.pointIndex < 0 ||
          mark.pointIndex >= segments[mark.segment].length ||
          mark.point.time.isBefore(
            segments[mark.segment][mark.pointIndex].time,
          )) {
        throw const FormatException('Invalid outdoor mark');
      }
    }
    DateTime? lastSpeed;
    for (final speed in speeds) {
      if (!validOutdoorSpeed(speed.metresPerSecond) ||
          !speed.time.isUtc ||
          (lastSpeed != null && !speed.time.isAfter(lastSpeed))) {
        throw const FormatException('Invalid outdoor speed');
      }
      lastSpeed = speed.time;
    }
  }
}

double outdoorDistance(List<OutdoorPoint> segment) {
  var distance = 0.0;
  for (var i = 1; i < segment.length; i++) {
    distance += segment[i - 1].coordinate.distanceTo(segment[i].coordinate);
  }
  return distance;
}

double outdoorBearing(Coordinate a, Coordinate b) {
  final north = b.latitude - a.latitude;
  final east =
      (b.longitude - a.longitude) *
      math.cos((a.latitude + b.latitude) * math.pi / 360);
  return (math.atan2(east, north) * 180 / math.pi + 360) % 360;
}

double outdoorTurn(double before, double after) =>
    (after - before + 540) % 360 - 180;
