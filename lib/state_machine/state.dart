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
    this.navigationFromLastReliableFix = false,
  });

  final LocationStateStatus status;
  final DateTime timestamp;
  final double? distanceToBoundaryM;
  final double? horizontalAccuracyM;
  final bool geoJsonLoaded;
  final String? notes;
  final LatLng? nearestBoundaryPoint;
  final double? bearingToBoundaryDeg;

  /// 距離・方位が「最後に信頼できた測位」由来かどうか。
  ///
  /// 使えない測位（精度不良・座標不正）でOUTERを維持しているあいだ、
  /// 案内の値は現在位置ではなく過去の値になる。判定した状態機械が事実として
  /// 持つ。表示側で精度としきい値から再計算すると、状態機械が「使えない」と
  /// 判断する条件が増えたときに食い違い、古い案内を現在位置として
  /// 表示してしまう。
  final bool navigationFromLastReliableFix;

  /// Returns whether GeoJSON is loaded.
  bool get hasGeoJson => geoJsonLoaded;

  StateSnapshot copyWith({
    LocationStateStatus? status,
    DateTime? timestamp,
    double? distanceToBoundaryM,
    double? horizontalAccuracyM,
    bool? geoJsonLoaded,
    String? notes,
    LatLng? nearestBoundaryPoint,
    double? bearingToBoundaryDeg,
    bool? navigationFromLastReliableFix,
  }) {
    return StateSnapshot(
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      distanceToBoundaryM: distanceToBoundaryM ?? this.distanceToBoundaryM,
      horizontalAccuracyM: horizontalAccuracyM ?? this.horizontalAccuracyM,
      geoJsonLoaded: geoJsonLoaded ?? this.geoJsonLoaded,
      notes: notes ?? this.notes,
      nearestBoundaryPoint: nearestBoundaryPoint ?? this.nearestBoundaryPoint,
      bearingToBoundaryDeg: bearingToBoundaryDeg ?? this.bearingToBoundaryDeg,
      navigationFromLastReliableFix:
          navigationFromLastReliableFix ?? this.navigationFromLastReliableFix,
    );
  }
}
