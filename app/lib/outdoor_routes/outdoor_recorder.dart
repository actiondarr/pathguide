import 'dart:math' as math;

import '../navigation/navigation_models.dart';
import '../route_memory/route_media.dart';
import '../route_memory/route_package.dart' show RoutePoint;
import 'outdoor_track.dart';

enum OutdoorRecordingState {
  waiting,
  recording,
  weak,
  permission,
  paused,
  background,
  capacity,
}

enum OutdoorMarkResult { added, noPosition, capacity, invalid }

class OutdoorRecorder {
  static const _movementCandidateAge = Duration(seconds: 8);

  final _segments = <List<OutdoorPoint>>[];
  final _marks = <OutdoorMark>[];
  final _speeds = <OutdoorSpeed>[];
  int _points = 0, _audioBytes = 0;
  double _distance = 0;
  bool _split = true, _hasGap = false;
  OutdoorRecordingState _state = OutdoorRecordingState.waiting;
  OutdoorPoint? _lastFix, _candidate;
  DateTime? _lastSample;
  Duration? _lastFixAt, _activeSince;
  Duration _elapsed = Duration.zero;
  double? _speed;
  int _stillFixes = 0;

  OutdoorRecordingState get state => _state;
  double get distance => _distance;
  double? get speed => _speed;
  double? get accuracy => _lastFix?.accuracy;
  int get pointCount => _points;
  int get markCount => _marks.length;
  bool get manuallyPaused => _state == OutdoorRecordingState.paused;
  bool get atCapacity => _state == OutdoorRecordingState.capacity;

  Duration elapsedAt(Duration now) =>
      _elapsed + (_activeSince == null ? Duration.zero : now - _activeSince!);

  void _stopClock(Duration now) {
    _elapsed = elapsedAt(now);
    _activeSince = null;
  }

  void pause(Duration now) {
    if (atCapacity) return;
    _stopClock(now);
    _interrupt(OutdoorRecordingState.paused, hasGap: false);
  }

  void resume(Duration now) {
    if (atCapacity) return;
    if (manuallyPaused && _points != 0) {
      _activeSince = now;
      _hasGap = true;
    }
    _state = OutdoorRecordingState.waiting;
  }

  void background() {
    if (!manuallyPaused && !atCapacity) {
      _interrupt(OutdoorRecordingState.background);
    }
  }

  void unavailable({required bool permission}) {
    if (!manuallyPaused && !atCapacity) {
      _interrupt(
        permission
            ? OutdoorRecordingState.permission
            : OutdoorRecordingState.weak,
      );
    }
  }

  void _interrupt(OutdoorRecordingState state, {bool hasGap = true}) {
    _hasGap |= hasGap && _points > 0;
    _state = state;
    _split = true;
    _lastFix = _candidate = null;
    _lastFixAt = null;
    _speed = null;
    _stillFixes = 0;
  }

  void tick(Duration now) {
    final last = _lastFixAt;
    if (last != null && now - last >= outdoorRecordingLoss) {
      _interrupt(OutdoorRecordingState.weak);
    }
  }

  void fix(LocationFix fix, Duration now, DateTime wallTime) {
    if (manuallyPaused ||
        atCapacity ||
        _state == OutdoorRecordingState.background) {
      return;
    }
    tick(now);
    final sample = fix.sampledAt;
    // A queued or duplicate fix cannot replace the last observation or bridge a gap.
    if (sample == null ||
        (_lastSample != null && !sample.isAfter(_lastSample!))) {
      return;
    }
    final age = wallTime.difference(sample);
    if (age > outdoorFixAge || age < const Duration(seconds: -1)) return;
    if (!usableOutdoorFix(fix, now, wallTime)) {
      _lastSample = sample;
      _interrupt(OutdoorRecordingState.weak);
      return;
    }
    _lastSample = sample;

    if (_lastFix != null &&
        sample.difference(_lastFix!.time) > outdoorReplayLoss) {
      _interrupt(OutdoorRecordingState.weak);
    }
    final previous = _lastFix;
    final displacement = previous?.coordinate.distanceTo(fix.coordinate) ?? 0;
    if (previous != null) {
      final seconds = sample.difference(previous.time).inMilliseconds / 1000;
      // Reject a jump until another credible observation or the loss timeout.
      if (displacement > seconds * 4 + fix.accuracy + previous.accuracy) return;
    }

    final speed = fix.speed, error = fix.speedAccuracy;
    final validSpeed =
        speed != null &&
        validOutdoorSpeed(speed) &&
        error != null &&
        error.isFinite &&
        error >= 0 &&
        error <= 1.2;
    final stationary =
        validSpeed &&
        speed <= 0.30 &&
        error <= 0.6 &&
        (previous == null ||
            displacement <= math.max(3, fix.accuracy + previous.accuracy));
    _stillFixes = stationary ? _stillFixes + 1 : 0;
    _speed = _stillFixes >= 2
        ? 0
        : validSpeed && speed - error >= 0.35
        ? speed
        : null;
    final point = OutdoorPoint.fromFix(fix, _speed);
    _lastFix = point;
    _lastFixAt = now - Duration(milliseconds: math.max(0, age.inMilliseconds));
    _state = OutdoorRecordingState.recording;
    if (_speed != null &&
        (_speeds.isEmpty ||
            sample.difference(_speeds.last.time) >=
                const Duration(seconds: 5))) {
      if (_speeds.length < OutdoorTrack.maxSpeeds) {
        _speeds.add((time: sample, metresPerSecond: _speed!));
      } else {
        _limit(now);
        return;
      }
    }
    if (_split) {
      _split = false;
      _activeSince ??= now;
      _segments.add([]);
      _append(point, now);
      return;
    }

    final pending = _candidate;
    if (pending != null &&
        sample.difference(pending.time) > _movementCandidateAge) {
      _candidate = null;
    }
    if (stationary) {
      final candidate = _candidate;
      if (candidate != null &&
          candidate.speed != null &&
          candidate.speed! > 0 &&
          point.coordinate.distanceTo(candidate.coordinate) <=
              math.max(2, math.min(candidate.accuracy, point.accuracy))) {
        if (_stillFixes >= 2) {
          _append(candidate, now);
          _candidate = null;
        }
      } else {
        _candidate = null;
      }
      return;
    }
    final anchor = _segments.last.last;
    final moved = anchor.coordinate.distanceTo(point.coordinate);
    final threshold = math.max(4.0, 0.65 * (point.accuracy + anchor.accuracy));
    final candidate = _candidate;
    if (candidate != null) {
      final candidateDistance = anchor.coordinate.distanceTo(
        candidate.coordinate,
      );
      final fromCandidate = candidate.coordinate.distanceTo(point.coordinate);
      final minimumProgress = math.max(1.5, point.accuracy * 0.25);
      final candidateBearing = outdoorBearing(
        anchor.coordinate,
        candidate.coordinate,
      );
      final sameDirection =
          outdoorTurn(
            candidateBearing,
            outdoorBearing(anchor.coordinate, point.coordinate),
          ).abs() <=
          60;
      if (moved >= threshold &&
          sameDirection &&
          moved >= candidateDistance + minimumProgress) {
        _append(candidate, now);
        _candidate =
            !atCapacity &&
                fromCandidate >=
                    math.max(4.0, 0.65 * (candidate.accuracy + point.accuracy))
            ? point
            : null;
        return;
      }
      // Consecutive moving fixes approaching and leaving a bend can
      // corroborate a vertex even when the total displacement barely changes.
      final bend = outdoorTurn(
        candidateBearing,
        outdoorBearing(candidate.coordinate, point.coordinate),
      ).abs();
      if (moved >= threshold &&
          (candidate.speed ?? 0) > 0 &&
          (_speed ?? 0) > 0 &&
          fromCandidate >= 1.5 &&
          bend >= 50 &&
          bend <= 115) {
        _append(candidate, now);
        _candidate = null;
        return;
      }
      // Keep the point while small, consistent GPS updates accumulate evidence
      // of progress. Replacing it each time can leave a slow walk unrecorded.
      if (moved >= threshold &&
          sameDirection &&
          moved >= candidateDistance - minimumProgress) {
        return;
      }
    }
    _candidate = moved >= threshold ? point : null;
  }

  void _append(OutdoorPoint point, Duration now) {
    final segment = _segments.last;
    if (segment.isNotEmpty) {
      _distance += segment.last.coordinate.distanceTo(point.coordinate);
    }
    segment.add(point);
    if (++_points == OutdoorTrack.maxPoints) _limit(now);
  }

  void _limit(Duration now) {
    _stopClock(now);
    _interrupt(OutdoorRecordingState.capacity);
  }

  OutdoorMark? makeMark(OutdoorMarkKind kind, Duration now) {
    tick(now);
    final point = _lastFix;
    if (_state != OutdoorRecordingState.recording || point == null) return null;
    return OutdoorMark(
      kind: kind,
      point: point,
      segment: _segments.length - 1,
      pointIndex: _segments.last.length - 1,
    );
  }

  OutdoorMarkResult addMark(
    OutdoorMark mark,
    Duration now, {
    String? text,
    RouteAudioNote? audio,
  }) {
    tick(now);
    // Notes use the position when the action was started and cannot cross an
    // interruption while the keyboard or microphone is open.
    if (_state != OutdoorRecordingState.recording ||
        mark.segment != _segments.length - 1) {
      return OutdoorMarkResult.noPosition;
    }
    final added = OutdoorMark(
      kind: mark.kind,
      point: mark.point,
      segment: mark.segment,
      pointIndex: mark.pointIndex,
      text: text,
      audio: audio,
    );
    if (text != null && !RoutePoint.validTextNote(text)) {
      return OutdoorMarkResult.invalid;
    }
    if (!added.valid) return OutdoorMarkResult.invalid;
    final bytes = audio?.bytes.length ?? 0;
    if (_marks.length == OutdoorTrack.maxMarks ||
        bytes + _audioBytes > RouteMediaBounds.audioBytesPerRoute) {
      return OutdoorMarkResult.capacity;
    }
    _audioBytes += bytes;
    _marks.add(added);
    return OutdoorMarkResult.added;
  }

  OutdoorMark? undo() {
    if (_marks.isEmpty) return null;
    final mark = _marks.removeLast();
    _audioBytes -= mark.audio?.bytes.length ?? 0;
    return mark;
  }

  OutdoorTrack finish(Duration now) {
    tick(now);
    return OutdoorTrack(
      segments: _segments,
      marks: _marks,
      speeds: _speeds,
      elapsed: elapsedAt(now),
      hasGap: _hasGap,
      atCapacity: atCapacity,
    );
  }
}
