import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../geo/geo_model.dart';
import 'config.dart';

class FileManager {
  Future<GeoModel> loadBundledGeoJson(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return GeoModel.fromGeoJson(raw);
  }

  Future<GeoModel?> pickAndLoadGeoJson() async {
    final file = await openFile();
    if (file == null) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      return GeoModel.fromGeoJson(raw);
    } on FormatException catch (e) {
      throw FormatException('GeoJSON parse error: ${e.message}');
    } catch (e) {
      throw Exception('Failed to open ${file.name}: $e');
    }
  }

  Future<XFile?> pickGeoJsonFile() async {
    return await openFile();
  }

  Future<File> getConfigFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/config.json');
    if (!await file.exists()) {
      final defaultConfig = await AppConfig.loadDefault();
      await file.writeAsString(jsonEncode(defaultConfig.toJson()));
    }
    return file;
  }

  Future<void> saveConfig(AppConfig config) async {
    final file = await getConfigFile();
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  Future<AppConfig> readConfig() async {
    try {
      final file = await getConfigFile();
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AppConfig.fromJson(decoded);
    } catch (_) {
      return AppConfig.loadDefault();
    }
  }

  Future<File> openLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/argus.log');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }
}
