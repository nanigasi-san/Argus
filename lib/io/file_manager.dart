import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';

typedef GeoJsonFilePicker = Future<XFile?> Function({
  List<XTypeGroup>? acceptedTypeGroups,
});
typedef DocumentsDirectoryProvider = Future<Directory> Function();
typedef ConfigLoader = Future<AppConfig> Function();

/// ファイル操作を管理するクラス。
///
/// GeoJSONファイルの選択、設定ファイルの読み書き、ログファイルの取得を提供します。
class FileManager {
  FileManager({
    GeoJsonFilePicker? filePicker,
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    ConfigLoader? defaultConfigLoader,
  })  : _pickFile = filePicker ?? _defaultFilePicker,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _loadDefaultConfig = defaultConfigLoader ?? AppConfig.loadDefault;

  static Future<XFile?> _defaultFilePicker({
    List<XTypeGroup>? acceptedTypeGroups,
  }) async {
    if (acceptedTypeGroups == null) {
      return await openFile();
    }
    return await openFile(acceptedTypeGroups: acceptedTypeGroups);
  }

  final GeoJsonFilePicker _pickFile;
  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  final ConfigLoader _loadDefaultConfig;

  /// GeoJSONファイルを選択するファイルピッカーを開きます。
  Future<XFile?> pickGeoJsonFile() async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'GeoJSON files',
      extensions: ['geojson', 'json', 'bin'],
    );
    return await _pickFile(acceptedTypeGroups: [typeGroup]);
  }

  /// 設定ファイルのパスを取得します。
  ///
  /// ファイルが存在しない場合はデフォルト設定で作成します。
  Future<File> getConfigFile() async {
    final dir = await _documentsDirectoryProvider();
    final file = File('${dir.path}/config.json');
    if (!await file.exists()) {
      final defaultConfig = await _loadDefaultConfig();
      await file.writeAsString(jsonEncode(defaultConfig.toJson()));
    }
    return file;
  }

  /// 設定をファイルに保存します。
  Future<void> saveConfig(AppConfig config) async {
    final file = await getConfigFile();
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  /// 設定ファイルを読み込みます。
  ///
  /// ファイルの読み込みに失敗した場合は、デフォルト設定を返します。
  Future<AppConfig> readConfig() async {
    try {
      final file = await getConfigFile();
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AppConfig.fromJson(decoded);
    } catch (_) {
      return _loadDefaultConfig();
    }
  }

  /// ログファイルのパスを取得します。
  ///
  /// ファイルが存在しない場合は作成します。
  Future<File> openLogFile() async {
    final dir = await _documentsDirectoryProvider();
    final file = File('${dir.path}/argus.log');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }
}
