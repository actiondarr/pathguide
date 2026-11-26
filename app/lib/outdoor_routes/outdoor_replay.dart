import 'dart:math' as math;

import '../navigation/navigation_models.dart';
import '../navigation/route_progress.dart';
import 'outdoor_track.dart';

enum OutdoorReplayState {
  waiting,
  wrongStart,
  checkingDirection,
  reverse,
  following,
  offRoute,
  ambiguous,
  weak,
  permission,
  paused,
  nearEnd,
  arrived,
}

class OutdoorReplay {
  OutdoorReplay(OutdoorTrack track)
    : geometry = RouteGeometry(
        track.segments.single.map((p) => p.coordinate).toList(),
      ),
      _track = track {
    if (track.draftReason != null) {
      throw ArgumentError('Outdoor route is a draft');
    }
    for (final mark in track.marks) {
      final anchor = geometry.cumulative[mark.pointIndex];
      final candidates = geometry
          .projections(mark.point.coordinate)
          .where((p) => (p.along - anchor).abs() <= outdoorAccuracy)
          .toList();
      _marks.add((mark: mark, along: candidates.firstOrNull?.along ?? anchor));
    }
    for (var i = 1; i < geometry.points.length - 1; i++) {
      final along = geometry.cumulative[i];
      if (_turns.isNotEmpty && along - _turns.last.along < 15) continue;
      var before = i - 1, after = i + 1;
      while (before > 0 && along - geometry.cumulative[before] < 8) {
        before--;
      }
      while (after + 1 < geometry.points.length &&
          geometry.cumulative[after] - along < 8) {
        after++;
      }
      final a = geometry.points[before],
          b = geometry.points[i],
          c = geometry.points[after];
      if (a.distanceTo(b) < 4 || b.distanceTo(c) < 4) continue;
      final angle = outdoorTurn(outdoorBearing(a, b), outdoorBearing(b, c));
      if (angle.abs() >= 45 && angle.abs() <= 140) {
        _turns.add((along: along, left: angle < 0));
      }
    }
  }

  final RouteGeometry geometry;
  final OutdoorTrack _track;
  final _turns = <({double along, bool left})>[];
  final _marks = <({double along, OutdoorMark mark})>[];
  final _spokenTurns = <int>{};
  final _spokenMarks = <OutdoorMark>{};
  OutdoorReplayState state = OutdoorReplayState.waiting;
  bool _started = false;
  Coordinate? _startObservation;
  double _startAccuracy = 0, along = 0;
  DateTime? _lastSample, _lastProgress;
  Duration? _lastFixAt;
  LocationFix? _motionAnchor;
  int _nearEndFixes = 0;

  double get remaining => math.max(0, geometry.length - along);
  OutdoorPoint get _start => _track.segments.single.first;
  OutdoorPoint get _end => _track.segments.single.last;

  ({int metres, bool left})? nextTurn;
  int? _currentTurn;
  List<OutdoorMark> nearbyMarks = const [];
  int cue = 0;

  void suspend(OutdoorReplayState reason) {
    if (state == OutdoorReplayState.arrived) return;
    state = reason;
    _startObservation = null;
    _motionAnchor = null;
    _lastFixAt = null;
    _nearEndFixes = 0;
    _clearCues();
  }

  void _clearCues() {
    nextTurn = null;
    if (_currentTurn case final turn?) _spokenTurns.remove(turn);
    _currentTurn = null;
    nearbyMarks = const [];
  }

  void tick(Duration now) {
    final last = _lastFixAt;
    if (last != null && now - last >= outdoorReplayLoss) {
      suspend(OutdoorReplayState.weak);
    }
  }

  void fix(LocationFix fix, Duration now, DateTime wallTime) {
    if (state == OutdoorReplayState.arrived ||
        state == OutdoorReplayState.paused) {
      return;
    }
    tick(now);
    final sample = fix.sampledAt;
    if (sample == null ||
        (_lastSample != null && !sample.isAfter(_lastSample!))) {
      return;
    }
    _lastSample = sample;
    if (!usableOutdoorFix(fix, now, wallTime)) {
      suspend(OutdoorReplayState.weak);
      return;
    }
    _lastFixAt =
        now -
        Duration(
          milliseconds: math.max(0, wallTime.difference(sample).inMilliseconds),
        );
    final candidates = geometry.projections(fix.coordinate);
    final best = candidates.first;
    final uncertainty =
        fix.accuracy + math.max(_start.accuracy, _end.accuracy) * 0.4;
    final nearTrack = math.max(8, uncertainty + 3);
    if (!_started) {
      if (_startObservation == null &&
          fix.coordinate.distanceTo(_start.coordinate) > nearTrack) {
        suspend(OutdoorReplayState.wrongStart);
        return;
      }
      if (fix.accuracy > 10) {
        suspend(OutdoorReplayState.weak);
        return;
      }
      if (_ambiguous(candidates, best, uncertainty)) {
        suspend(OutdoorReplayState.ambiguous);
        return;
      }
      _startObservation ??= fix.coordinate;
      _startAccuracy = state == OutdoorReplayState.checkingDirection
          ? _startAccuracy
          : fix.accuracy;
      state = OutdoorReplayState.checkingDirection;
      final movement = _startObservation!.distanceTo(fix.coordinate);
      final course =
          _walkingCourse(fix) ??
          (movement >= math.max(5, (_startAccuracy + fix.accuracy) * 0.75)
              ? outdoorBearing(_startObservation!, fix.coordinate)
              : null);
      final firstLeg = geometry.cumulative.indexWhere((value) => value >= 8);
      final startBearing = outdoorBearing(
        _start.coordinate,
        geometry.points[firstLeg == -1 ? 1 : firstLeg],
      );
      if (course != null && outdoorTurn(startBearing, course).abs() > 105) {
        suspend(OutdoorReplayState.reverse);
        return;
      }
      if (best.distance > nearTrack || best.along > 26) {
        suspend(OutdoorReplayState.wrongStart);
        return;
      }
      if (course == null ||
          outdoorTurn(startBearing, course).abs() > 55 ||
          movement < math.max(4, fix.accuracy * 0.7) ||
          best.along < 5 ||
          best.along > 26) {
        return;
      }
      _started = true;
    } else {
      if (best.distance > nearTrack) {
        suspend(OutdoorReplayState.offRoute);
        return;
      }
      if (_ambiguous(candidates, best, uncertainty)) {
        suspend(OutdoorReplayState.ambiguous);
        return;
      }
      final elapsed = sample.difference(_lastProgress!).inMilliseconds / 1000;
      // Reacquisition remains local to the last confirmed progress.
      final allowedAhead = (elapsed * 3 + fix.accuracy).clamp(10.0, 26.0);
      if (best.along > along + allowedAhead) {
        suspend(OutdoorReplayState.ambiguous);
        return;
      }
      final leg = geometry.cumulative.indexWhere((value) => value > best.along);
      final ahead = leg < 1 ? geometry.points.length - 1 : leg;
      final heading = outdoorBearing(
        geometry.points[ahead - 1],
        geometry.points[ahead],
      );
      final motion = _motionAnchor;
      final distance = motion?.coordinate.distanceTo(fix.coordinate) ?? 0;
      final displaced =
          motion != null &&
          distance >= math.max(5, fix.accuracy + motion.accuracy);
      final course =
          _walkingCourse(fix) ??
          (displaced
              ? outdoorBearing(motion.coordinate, fix.coordinate)
              : null);
      // A single course reading at a corner can describe the adjoining leg.
      final nearCorner =
          geometry.cumulative[ahead] - best.along < 5 ||
          best.along - geometry.cumulative[ahead - 1] < 5;
      if (best.along < along - math.max(8, fix.accuracy * 1.5) ||
          (!nearCorner &&
              course != null &&
              outdoorTurn(heading, course).abs() > 115)) {
        suspend(OutdoorReplayState.reverse);
        return;
      }
      if (motion == null || displaced) _motionAnchor = fix;
    }

    final regained =
        state != OutdoorReplayState.following &&
        state != OutdoorReplayState.nearEnd;
    _motionAnchor ??= fix;
    _lastProgress = sample;
    along = math.max(along, best.along);
    if (geometry.length - best.along <= 12 &&
        fix.coordinate.distanceTo(_end.coordinate) <= 10) {
      if (fix.accuracy <= 8 && _end.accuracy <= 10) {
        _nearEndFixes++;
      } else {
        _nearEndFixes = 0;
      }
      state = OutdoorReplayState.nearEnd;
    } else {
      _nearEndFixes = 0;
      state = OutdoorReplayState.following;
    }
    final previousTurn = _currentTurn;
    final previousMarks = nearbyMarks;
    _updateCues(best.along, fix);
    if (regained ||
        _currentTurn != previousTurn ||
        !_sameMarks(previousMarks)) {
      cue++;
    }
  }

  bool _sameMarks(List<OutdoorMark> previous) =>
      previous.length == nearbyMarks.length &&
      previous.every(nearbyMarks.contains);

  void _updateCues(double matched, LocationFix fix) {
    final active = _currentTurn;
    _currentTurn = null;
    nextTurn = null;
    if (state == OutdoorReplayState.following) {
      for (var i = 0; i < _turns.length; i++) {
        final turn = _turns[i];
        final distance = turn.along - matched;
        if (distance >= -3 &&
            distance <= 18 &&
            (active == i || !_spokenTurns.contains(i))) {
          _currentTurn = i;
          nextTurn = (metres: math.max(0, distance.round()), left: turn.left);
          _spokenTurns.add(i);
          break;
        }
        if (distance > 18) break;
      }
    }
    nearbyMarks = [
      for (final mark in _marks)
        if ((mark.along - matched).abs() <= 12 &&
            mark.mark.point.coordinate.distanceTo(fix.coordinate) <=
                math.max(12, fix.accuracy))
          mark.mark,
    ];
  }

  List<OutdoorMark> takeNewMarks() =>
      nearbyMarks.where(_spokenMarks.add).toList();

  bool _ambiguous(
    List<RouteProjection> candidates,
    RouteProjection best,
    double uncertainty,
  ) => candidates.any(
    (candidate) =>
        (candidate.along - best.along).abs() >= 22 &&
        candidate.distance <= uncertainty &&
        candidate.distance <= best.distance + uncertainty * 0.75,
  );

  double? _walkingCourse(LocationFix fix) {
    final speed = fix.speed, accuracy = fix.speedAccuracy, course = fix.course;
    return speed != null &&
            validOutdoorSpeed(speed) &&
            accuracy != null &&
            accuracy >= 0 &&
            speed >= 0.8 &&
            speed - accuracy >= 0.35 &&
            course != null &&
            course.isFinite &&
            course >= 0 &&
            course < 360
        ? course
        : null;
  }

  bool get canConfirmEnd =>
      state == OutdoorReplayState.nearEnd && _nearEndFixes >= 2;

  bool confirmEnd(Duration now) {
    tick(now);
    if (!canConfirmEnd) return false;
    state = OutdoorReplayState.arrived;
    _clearCues();
    return true;
  }
}
