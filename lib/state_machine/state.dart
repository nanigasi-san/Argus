import 'package:meta/meta.dart';

import '../geo/geo_model.dart';

/// States emitted by the Argus geofence state machine.
enum LocationStateStatus {
  waitGeoJson,
  waitStart,
  gpsBad,
  inner,
  near,
  outerPending,
  outer,
}

/// 状態マシンの最新評価結果を保持します。
@immutable
class StateSnapshot {
  const StateSnapshot({
    required this.status,
    required this.timestamp,
    this.distanceToBoundaryM,
    this.horizontalAccuracyM,
    this.hasGeoJson = false,
    this.notes,
    this.nearestBoundaryPoint,
    this.bearingToBoundaryDeg,
  });

  final LocationStateStatus status;
  final DateTime timestamp;
  final double? distanceToBoundaryM;
  final double? horizontalAccuracyM;
  final bool hasGeoJson;
  final String? notes;
  final LatLng? nearestBoundaryPoint;
  final double? bearingToBoundaryDeg;

  StateSnapshot copyWith({
    LocationStateStatus? status,
    DateTime? timestamp,
    double? distanceToBoundaryM,
    double? horizontalAccuracyM,
    bool? hasGeoJson,
    String? notes,
    LatLng? nearestBoundaryPoint,
    double? bearingToBoundaryDeg,
  }) {
    return StateSnapshot(
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      distanceToBoundaryM: distanceToBoundaryM ?? this.distanceToBoundaryM,
      horizontalAccuracyM:
          horizontalAccuracyM ?? this.horizontalAccuracyM,
      hasGeoJson: hasGeoJson ?? this.hasGeoJson,
      notes: notes ?? this.notes,
      nearestBoundaryPoint:
          nearestBoundaryPoint ?? this.nearestBoundaryPoint,
      bearingToBoundaryDeg:
          bearingToBoundaryDeg ?? this.bearingToBoundaryDeg,
    );
  }
}
