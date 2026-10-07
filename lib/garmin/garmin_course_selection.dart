import 'package:flutter/foundation.dart' show compute;
import 'package:file_selector/file_selector.dart';

import '../geo/geo_model.dart';
import '../geo/geojson_validation_messages.dart';
import '../geo/geojson_validator.dart';
import '../qr/geojson_qr_codec.dart';
import 'garmin_course_validator.dart';

/// A transfer candidate that does not change the phone's monitoring course.
class GarminCourseSelection {
  const GarminCourseSelection(
      {required this.model, required this.fileName, this.validation});

  final GeoModel model;
  final String fileName;
  final GeoJsonValidationResult? validation;

  GarminCourseValidationResult get garminValidation => validation == null
      ? const GarminCourseValidator().validateModel(model)
      : const GarminCourseValidator().validate(validation!);

  static Future<GarminCourseSelection> fromFile(XFile file) async {
    return _validated(await file.readAsString(), file.name);
  }

  static Future<GarminCourseSelection> fromQrText(String qrText) async {
    final decoded = await compute(_decodeQrText, qrText);
    return _validated(decoded.geoJson, decoded.fileName ?? 'qr.geojson');
  }

  static GarminCourseSelection _validated(String raw, String fileName) {
    final validation = const GeoJsonValidator().validate(raw);
    if (!validation.validForPhone) {
      throw FormatException(
          GeoJsonValidationMessages.describe(validation.errors.first));
    }
    final name = fileName.trim().isEmpty ? 'argus.geojson' : fileName.trim();
    return GarminCourseSelection(
        model: validation.model!, fileName: name, validation: validation);
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
