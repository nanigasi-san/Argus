import 'package:meta/meta.dart';

/// States emitted by the Argus geofence state machine.
enum LocationStateStatus {
  waitGeoJson,
  init,
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
  });

  final LocationStateStatus status;
  final DateTime timestamp;
  final double? distanceToBoundaryM;
  final double? horizontalAccuracyM;
  final bool geoJsonLoaded;
  final String? notes;

  StateSnapshot copyWith({
    LocationStateStatus? status,
    DateTime? timestamp,
    double? distanceToBoundaryM,
    double? horizontalAccuracyM,
    bool? geoJsonLoaded,
    String? notes,
  }) {
    return StateSnapshot(
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      distanceToBoundaryM: distanceToBoundaryM ?? this.distanceToBoundaryM,
      horizontalAccuracyM:
          horizontalAccuracyM ?? this.horizontalAccuracyM,
      geoJsonLoaded: geoJsonLoaded ?? this.geoJsonLoaded,
      notes: notes ?? this.notes,
    );
  }
}
