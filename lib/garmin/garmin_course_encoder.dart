import 'dart:math' as math;

import '../geo/geo_model.dart';
import 'garmin_course_payload.dart';

class GarminCourseEncoder {
  static const int maxVertices = 100;

  GarminCoursePayload encode(
    GeoModel model, {
    required String fileName,
    DateTime? armedUntil,
  }) {
    if (model.polygons.length != 1) {
      throw const FormatException('Garminへ送信できるのは単一Polygonのみです。');
    }
    var points = model.polygons.single.points;
    if (points.length > 1 &&
        points.first.latitude == points.last.latitude &&
        points.first.longitude == points.last.longitude) {
      points = points.sublist(0, points.length - 1);
    }
    if (points.length < 3 || points.length > maxVertices) {
      throw FormatException('頂点数は3〜$maxVertices点にしてください（現在${points.length}点）。');
    }

    final originLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final originLon =
        points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    final metersPerLon = 111320.0 * math.cos(originLat * math.pi / 180);
    final encoded = <String>[];
    for (final point in points) {
      final x = ((point.longitude - originLon) * metersPerLon).round();
      final y = ((point.latitude - originLat) * 110540.0).round();
      if (x < -32768 || x > 32767 || y < -32768 || y > 32767) {
        throw const FormatException('競技エリアがGarmin用座標の範囲を超えています。');
      }
      encoded.add('$x,$y');
    }
    final data = 'AGW1|${encoded.join(';')}';
    if (data.length > 2048) {
      throw const FormatException('Garmin用データが2KBを超えています。頂点を簡略化してください。');
    }
    final normalizedName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final courseId = '${normalizedName}_${_checksum(data)}';
    final expiry = armedUntil ?? DateTime.now().add(const Duration(hours: 12));
    return GarminCoursePayload(
      courseId: courseId.length <= 64
          ? courseId
          : courseId.substring(courseId.length - 64),
      armedUntil: expiry.millisecondsSinceEpoch ~/ 1000,
      vertexCount: points.length,
      originLatE7: (originLat * 1e7).round(),
      originLonE7: (originLon * 1e7).round(),
      data: data,
      checksum: _checksum(data),
    );
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
