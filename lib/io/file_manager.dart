import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';

class FileManager {
  Future<XFile?> pickGeoJsonFile() async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'GeoJSON files',
      extensions: ['geojson', 'json', 'bin'],
    );
    return await openFile(acceptedTypeGroups: [typeGroup]);
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
