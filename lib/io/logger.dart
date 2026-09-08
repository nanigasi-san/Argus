import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../platform/location_service.dart';
import '../state_machine/state.dart';

/// アプリケーションイベントのログを記録するクラス。
///
/// 状態変更や位置情報の更新をログとして記録し、JSONL形式でエクスポートできます。
class EventLogger {
  EventLogger({this.maxRecords = 20000})
      : assert(maxRecords > 0, 'maxRecords must be positive');

  final int maxRecords;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final ListQueue<Map<String, dynamic>> _records =
      ListQueue<Map<String, dynamic>>();

  Stream<Map<String, dynamic>> get events => _events.stream;

  /// 状態変更をログに記録します。
  ///
  /// ログメッセージとJSONレコードの両方を返します。
  Future<String> logStateChange(StateSnapshot snapshot) async {
    final message = '${snapshot.timestamp.toIso8601String()} '
        '[STATE] ${snapshot.status.name}'
        '${snapshot.distanceToBoundaryM != null ? ' dist=${snapshot.distanceToBoundaryM!.toStringAsFixed(2)}m' : ''}'
        '${snapshot.horizontalAccuracyM != null ? ' acc=${snapshot.horizontalAccuracyM!.toStringAsFixed(1)}m' : ''}'
        '${snapshot.bearingToBoundaryDeg != null ? ' bearing=${snapshot.bearingToBoundaryDeg!.toStringAsFixed(0)}deg' : ''}'
        '${snapshot.nearestBoundaryPoint != null ? ' target=${snapshot.nearestBoundaryPoint!.latitude.toStringAsFixed(5)},${snapshot.nearestBoundaryPoint!.longitude.toStringAsFixed(5)}' : ''}'
        '${snapshot.notes != null ? ' note=${snapshot.notes}' : ''}';
    final record = <String, dynamic>{
      'type': 'state',
      'timestamp': snapshot.timestamp.toIso8601String(),
      'status': snapshot.status.name,
      'distanceToBoundaryM': snapshot.distanceToBoundaryM,
      'accuracyM': snapshot.horizontalAccuracyM,
      'bearingDeg': snapshot.bearingToBoundaryDeg,
      'nearestLat': snapshot.nearestBoundaryPoint?.latitude,
      'nearestLon': snapshot.nearestBoundaryPoint?.longitude,
      'notes': snapshot.notes,
    };
    _addRecord(record);
    _events.add(record);
    return message;
  }

  /// 位置情報の更新をログに記録します。
  Future<String> logLocationFix(LocationFix fix) async {
    final message = '${fix.timestamp.toIso8601String()} '
        '[GPS] lat=${fix.latitude.toStringAsFixed(6)} '
        'lon=${fix.longitude.toStringAsFixed(6)} '
        'acc=${fix.accuracyMeters?.toStringAsFixed(1) ?? '-'}m';
    final record = <String, dynamic>{
      'type': 'location',
      'timestamp': fix.timestamp.toIso8601String(),
      'lat': fix.latitude,
      'lon': fix.longitude,
      'status': 'GPS_FIX',
      'accuracyM': fix.accuracyMeters,
    };
    _addRecord(record);
    _events.add(record);
    return message;
  }

  /// 記録されたすべてのログをJSONL形式でエクスポートします。
  Future<String> exportJsonl() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_records.toList(growable: false));
  }

  void _addRecord(Map<String, dynamic> record) {
    if (_records.length >= maxRecords) {
      _records.removeFirst();
    }
    _records.addLast(record);
  }
}
