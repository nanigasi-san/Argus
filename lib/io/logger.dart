import 'dart:async';
import 'dart:convert';

import '../platform/location_service.dart';
import '../state_machine/state.dart';

class EventLogger {
  EventLogger();

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<String> logStateChange(StateSnapshot snapshot) async {
    final message = '${snapshot.timestamp.toIso8601String()} '
        '[STATE] ${snapshot.status.name}'
        '${snapshot.distanceToBoundaryM != null ? ' dist=${snapshot.distanceToBoundaryM!.toStringAsFixed(2)}m' : ''}'
        '${snapshot.horizontalAccuracyM != null ? ' acc=${snapshot.horizontalAccuracyM!.toStringAsFixed(1)}m' : ''}'
        '${snapshot.notes != null ? ' note=${snapshot.notes}' : ''}';
    final record = <String, dynamic>{
      'type': 'state',
      'timestamp': snapshot.timestamp.toIso8601String(),
      'status': snapshot.status.name,
      'distanceToBoundaryM': snapshot.distanceToBoundaryM,
      'accuracyM': snapshot.horizontalAccuracyM,
      'notes': snapshot.notes,
    };
    _records.add(record);
    _events.add(record);
    return message;
  }

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
      'batteryPct': fix.batteryPercent,
    };
    _records.add(record);
    _events.add(record);
    return message;
  }

  Future<String> exportJsonl() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_records);
  }
}
