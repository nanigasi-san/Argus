import 'package:flutter/foundation.dart' show compute;
import 'package:file_selector/file_selector.dart';

import '../geo/geo_model.dart';
import '../qr/geojson_qr_codec.dart';
import 'garmin_course_encoder.dart';

/// A transfer candidate that does not change the phone's monitoring course.
class GarminCourseSelection {
  const GarminCourseSelection({required this.model, required this.fileName});

  final GeoModel model;
  final String fileName;

  static Future<GarminCourseSelection> fromFile(XFile file) async {
    final model = GeoModel.fromGeoJson(await file.readAsString());
    return _validated(model, file.name);
  }

  static Future<GarminCourseSelection> fromQrText(String qrText) async {
    final decoded = await compute(_decodeQrText, qrText);
    final model = GeoModel.fromGeoJson(decoded.geoJson);
    return _validated(model, decoded.fileName ?? 'qr.geojson');
  }

  static GarminCourseSelection _validated(GeoModel model, String fileName) {
    final name = fileName.trim().isEmpty ? 'argus.geojson' : fileName.trim();
    // Reuse the exact transfer constraints without storing an early expiry.
    GarminCourseEncoder().encode(model, fileName: name);
    return GarminCourseSelection(model: model, fileName: name);
  }

  bool hasSameGeometry(GeoModel other) {
    if (model.polygons.length != other.polygons.length) return false;
    for (var polygonIndex = 0;
        polygonIndex < model.polygons.length;
        polygonIndex++) {
      final selectedPoints = model.polygons[polygonIndex].points;
      final otherPoints = other.polygons[polygonIndex].points;
      if (selectedPoints.length != otherPoints.length) return false;
      for (var pointIndex = 0;
          pointIndex < selectedPoints.length;
          pointIndex++) {
        final selected = selectedPoints[pointIndex];
        final current = otherPoints[pointIndex];
        if (selected.latitude != current.latitude ||
            selected.longitude != current.longitude) {
          return false;
        }
      }
    }
    return true;
  }
}

Future<DecodedGeoJson> _decodeQrText(String qrText) {
  return decodeGeoJsonWithMetadata(
    GeoJsonQrDecodeInput(qrTexts: [qrText], verifyHash: true),
  );
}
