import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:logger/logger.dart';

import '../state_machine/state.dart';
import '../platform/location_service.dart';

class EventLogger {
  EventLogger(this._file)
      : _logger = Logger(
          printer: PrettyPrinter(
            lineLength: 80,
            printEmojis: false,
          ),
        );

  final File _file;
  final Logger _logger;
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

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
    _events.add(record);
    _logger.i(message);
    await _appendCsv(record);
    return message;
  }

  Future<void> _appendCsv(Map<String, dynamic> record) async {
    final exists = await _file.exists();
    final sink = _file.openWrite(mode: FileMode.append);
    if (!exists) {
      sink.writeln(
        'timestamp,lat,lon,status,dist_to_boundary_m,'
        'horiz_accuracy_m,battery_pct',
      );
    }
    sink.writeln(
      '${record['timestamp']},'
      '${record['lat'] ?? ''},'
      '${record['lon'] ?? ''},'
      '${record['status'] ?? ''},'
      '${record['distanceToBoundaryM'] ?? ''},'
      '${record['accuracyM'] ?? ''},'
      '${record['batteryPct'] ?? ''},',
    );
    await sink.flush();
    await sink.close();
  }

  Future<String> exportJsonl() async {
    if (!await _file.exists()) {
      return '';
    }
    final exports = await _file.readAsLines();
    final buffer = StringBuffer();
    for (final line in exports.skip(1)) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      final map = {
        'timestamp': parts.elementAtOrNull(0),
        'lat': parts.elementAtOrNull(1),
        'lon': parts.elementAtOrNull(2),
        'status': parts.elementAtOrNull(3),
        'dist_to_boundary_m': parts.elementAtOrNull(4),
        'horiz_accuracy_m': parts.elementAtOrNull(5),
        'battery_pct': parts.elementAtOrNull(6),
      };
      buffer.writeln(jsonEncode(map));
    }
    return buffer.toString();
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
    _events.add(record);
    _logger.d(message);
    await _appendCsv(record);
    return message;
  }
}
