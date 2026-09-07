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
/// 設定の読み込み結果。
///
/// 「まだ保存されていない（初回起動）」と「保存されているが読めなかった」を
/// 区別するために使う。後者は利用者が調整した安全側の閾値が黙って初期値へ
/// 戻ることを意味するので、伝える必要がある。
class ConfigLoadResult {
  const ConfigLoadResult({required this.config, this.fallbackReason});

  final AppConfig config;

  /// 保存済み設定を読めずに初期設定へ戻した理由。
  /// 正常時とファイル未作成時（初回起動）は null。
  final String? fallbackReason;
}

class FileManager {
  FileManager({
    GeoJsonFilePicker? filePicker,
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    ConfigLoader? defaultConfigLoader,
  })  : _pickFile = filePicker ?? _defaultFilePicker,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _loadDefaultConfig = defaultConfigLoader ?? AppConfig.loadDefault;

  // coverage:ignore-start
  static Future<XFile?> _defaultFilePicker({
    List<XTypeGroup>? acceptedTypeGroups,
  }) async {
    if (acceptedTypeGroups == null) {
      return await openFile();
    }
    return await openFile(acceptedTypeGroups: acceptedTypeGroups);
  }
  // coverage:ignore-end

  final GeoJsonFilePicker _pickFile;
  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  final ConfigLoader _loadDefaultConfig;

  /// GeoJSONファイルを選択するファイルピッカーを開きます。
  Future<XFile?> pickGeoJsonFile() async {
    return await _pickFile();
  }

  /// QRコード画像ファイルを選択するファイルピッカーを開きます。
  Future<XFile?> pickQrImageFile() async {
    return await _pickFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'QR code image',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
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
    await file.writeAsString(jsonEncode(config.normalized().toJson()));
  }

  /// 設定ファイルを読み込みます。
  ///
  /// 読み込めない場合はデフォルト設定を返す。ファイルが存在するのに読めな
  /// かった場合だけ [ConfigLoadResult.fallbackReason] を埋める。初回起動の
  /// ファイル未作成と、保存済み設定が壊れて初期値へ戻った状況は、利用者に
  /// とって意味がまったく違う。
  Future<ConfigLoadResult> readConfig() async {
    File? file;
    try {
      file = await getConfigFile();
    } catch (error) {
      return ConfigLoadResult(
        config: (await _loadDefaultConfig()).normalized(),
        fallbackReason: '設定ファイルの場所を特定できません: $error',
      );
    }

    if (!await file.exists()) {
      return ConfigLoadResult(
        config: (await _loadDefaultConfig()).normalized(),
      );
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return ConfigLoadResult(
        config: AppConfig.fromJson(decoded).normalized(),
      );
    } catch (error) {
      return ConfigLoadResult(
        config: (await _loadDefaultConfig()).normalized(),
        fallbackReason: '設定ファイルを読み込めません: $error',
      );
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
