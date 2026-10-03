import 'dart:convert';

import '../geo/geo_model.dart';
import '../geo/geojson_validation_messages.dart';
import '../io/file_display_name.dart';
import 'garmin_course_payload.dart';
import 'garmin_course_validator.dart';

class GarminCourseEncoder {
  static const int maxVertices = GarminCourseValidator.maxVertices;
  static const int maxDataBytes = GarminCourseValidator.maxDataBytes;
  static const int maxDisplayNameBytes = 48;

  GarminCoursePayload encode(
    GeoModel model, {
    required String fileName,
    DateTime? armedUntil,
  }) {
    final validation = const GarminCourseValidator().validateModel(model);
    if (!validation.validForGarmin) {
      throw FormatException(
          GeoJsonValidationMessages.describe(validation.issues.first));
    }
    return encodePrepared(validation.prepared!,
        fileName: fileName, armedUntil: armedUntil);
  }

  GarminCoursePayload encodePrepared(
    GarminPreparedCourse prepared, {
    required String fileName,
    DateTime? armedUntil,
  }) {
    final data =
        'AGW1|${prepared.points.map((p) => '${p.x},${p.y}').join(';')}';
    assert(data.length == prepared.dataBytes);
    final normalizedName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final checksum = _checksum(data);
    final courseId = '${normalizedName}_$checksum';
    final expiry = armedUntil ?? DateTime.now().add(const Duration(hours: 12));
    return GarminCoursePayload(
      courseId: courseId.length <= 64
          ? courseId
          : courseId.substring(courseId.length - 64),
      displayName: _displayName(fileName),
      armedUntil: expiry.millisecondsSinceEpoch ~/ 1000,
      vertexCount: prepared.vertexCount,
      originLatE7: (prepared.originLat * 1e7).round(),
      originLonE7: (prepared.originLon * 1e7).round(),
      data: data,
      checksum: checksum,
    );
  }

  String _displayName(String fileName) {
    final baseName = fileName.split(RegExp(r'[/\\]')).last.trim();
    final displayName = fileDisplayName(baseName);
    final nameCharacters = (displayName.isEmpty ? 'ARGUS' : displayName).runes;
    final displayBuffer = StringBuffer();
    for (final character in nameCharacters) {
      final next =
          '${displayBuffer.toString()}${String.fromCharCode(character)}';
      if (utf8.encode(next).length > maxDisplayNameBytes) break;
      displayBuffer.writeCharCode(character);
    }
    return displayBuffer.toString();
  }

  String _checksum(String data) {
    var a = 1;
    var b = 0;
    for (final value in data.codeUnits) {
      if (value > 127) {
        throw const FormatException('Garmin用データはASCIIである必要があります。');
      }
      a = (a + value) % 65521;
      b = (b + a) % 65521;
    }
    return (b * 65536 + a).toString();
  }
}
