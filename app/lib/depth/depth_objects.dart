import 'dart:ui' show Rect;

class DepthObject {
  const DepthObject({
    required this.trackId,
    required this.classId,
    required this.score,
    required this.box,
    required this.reason,
    this.rangeM,
  });
  final int trackId, classId;
  final double score;
  final Rect box;
  final double? rangeM;
  final String reason;
}

double _iou(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.isEmpty) return 0;
  final area = intersection.width * intersection.height;
  return area / (a.width * a.height + b.width * b.height - area);
}

double? _number(Object? value) =>
    value is num && value.toDouble().isFinite ? value.toDouble() : null;

class _Observation {
  _Observation(this.id, this.score, this.box, this.range, this.reason);
  final int id;
  final double score;
  final Rect box;
  final double? range;
  final String reason;
  static _Observation? parse(Object? raw, Set<int> acceptedIds) {
    if (raw is! Map || raw['id'] is! int || !acceptedIds.contains(raw['id'])) {
      return null;
    }
    final score = _number(raw['score']);
    final coordinates = raw['box'];
    if (score == null ||
        score < 0.05 ||
        score > 1 ||
        coordinates is! List ||
        coordinates.length != 4) {
      return null;
    }
    final values = coordinates.map(_number).toList();
    if (values.any((v) => v == null)) return null;
    final box = Rect.fromLTWH(values[0]!, values[1]!, values[2]!, values[3]!);
    if (box.left < 0 ||
        box.top < 0 ||
        box.right > 1.000001 ||
        box.bottom > 1.000001 ||
        box.isEmpty) {
      return null;
    }
    final range = _number(raw['rangeM']), z = _number(raw['planeZM']);
    final count = _number(raw['accepted']),
        total = _number(raw['total']),
        spread = _number(raw['spreadM']);
    final valid =
        raw['reason'] == 'sample' &&
        range != null &&
        z != null &&
        range >= 0.2 &&
        range <= 4 &&
        z >= 0.2 &&
        z <= range &&
        count != null &&
        count == count.roundToDouble() &&
        count >= 15 &&
        count <= 25 &&
        total == 25 &&
        spread != null &&
        spread >= 0 &&
        spread <= (z * 0.08).clamp(0.1, double.infinity);
    return _Observation(
      raw['id'] as int,
      score,
      box,
      valid ? range : null,
      valid
          ? 'sample'
          : raw['reason'] == 'overlap'
          ? 'overlap'
          : 'unreliable',
    );
  }
}

class _Track {
  _Track(this.id, this.observation, this.time, this.history);
  final int id;
  final _Observation observation;
  final double time;
  final List<({double time, double range})> history;
}

/// Short image-space association, not persistent 3D identity tracking.
/// Disappearing, ambiguous or invalid observations cannot retain old ranges.
class DepthObjects {
  int _nextId = 0;
  List<_Track> _tracks = [];
  List<DepthObject> _snapshot = const [];
  List<DepthObject> get snapshot => _snapshot;
  void clear() {
    _tracks = [];
    _snapshot = const [];
  }

  bool update(Object? raw, double time, {required Set<int> acceptedIds}) {
    if (raw is! List || raw.length > 5) {
      clear();
      return false;
    }
    final parsed = raw
        .map((value) => _Observation.parse(value, acceptedIds))
        .toList();
    if (parsed.any((e) => e == null)) {
      clear();
      return false;
    }
    final observations = parsed.cast<_Observation>();
    bool matches(_Track previous, _Observation current) =>
        current.id == previous.observation.id &&
        time - previous.time <= 0.7 &&
        _iou(current.box, previous.observation.box) >= 0.45;
    final next = <_Track>[], outputs = <DepthObject>[];
    for (final observation in observations) {
      final candidates = _tracks
          .where((old) => matches(old, observation))
          .toList();
      final previous =
          candidates.length == 1 &&
              observations
                      .where((current) => matches(candidates.single, current))
                      .length ==
                  1
          ? candidates.single
          : null;
      final history =
          previous?.history.where((item) => time - item.time <= 0.7).toList() ??
          <({double time, double range})>[];
      double? range;
      if (observation.range == null) {
        history.clear();
      } else {
        final value = observation.range!;
        if (history.any(
          (item) =>
              (item.range - value).abs() >
              (value * 0.05).clamp(0.08, double.infinity),
        )) {
          history.clear();
        }
        history.add((time: time, range: value));
        if (history.length > 3) history.removeAt(0);
        if (history.length == 3 && time - history.first.time >= 0.2) {
          final values = history.map((item) => item.range).toList()..sort();
          range = values[1];
        }
      }
      final id = previous?.id ?? ++_nextId;
      next.add(_Track(id, observation, time, history));
      outputs.add(
        DepthObject(
          trackId: id,
          classId: observation.id,
          score: observation.score,
          box: observation.box,
          rangeM: range,
          reason: range != null
              ? 'ready'
              : observation.range == null
              ? observation.reason
              : 'stabilizing',
        ),
      );
    }
    _tracks = next;
    _snapshot = List.unmodifiable(outputs);
    return true;
  }
}
