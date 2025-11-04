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

/// Holds the outcome of the latest state machine evaluation.
@immutable
class StateSnapshot {
  const StateSnapshot({
    required this.status,
    required this.timestamp,
    this.distanceToBoundaryM,
    this.horizontalAccuracyM,
    this.geoJsonLoaded = false,
    this.notes,
    this.nearestBoundaryPoint,
    this.bearingToBoundaryDeg,
  });

  final LocationStateStatus status;
  final DateTime timestamp;
  final double? distanceToBoundaryM;
  final double? horizontalAccuracyM;
  final bool geoJsonLoaded;
  final String? notes;
  final LatLng? nearestBoundaryPoint;
  final double? bearingToBoundaryDeg;

  StateSnapshot copyWith({
    LocationStateStatus? status,
    DateTime? timestamp,
    double? distanceToBoundaryM,
    double? horizontalAccuracyM,
    bool? geoJsonLoaded,
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
      geoJsonLoaded: geoJsonLoaded ?? this.geoJsonLoaded,
      notes: notes ?? this.notes,
      nearestBoundaryPoint:
          nearestBoundaryPoint ?? this.nearestBoundaryPoint,
      bearingToBoundaryDeg:
          bearingToBoundaryDeg ?? this.bearingToBoundaryDeg,
    );
  }
}
