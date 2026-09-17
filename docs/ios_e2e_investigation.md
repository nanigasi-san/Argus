# iOS E2Eの接続待ちタイムアウト調査

調査日: 2026-09-17。対象: PR #85、コミット `0d57b2f` と直前の実行。

## 結論

最新の失敗では、アプリ内のDart VM Serviceは起動しているが、Flutter CLIがそのURLをログから取得できていない。直接の停止箇所は、テスト実行前のVM Service URL検出である。

最も有力な原因はFlutter側のSimulatorログ監視初期化とアプリ起動の競合である。公式Issue #181771に同じ症状と実装上の競合の指摘があり、使用したFlutter 3.47.4にも該当する実装が残っている。ただし、このCI実行ではログ監視が実際に読み取り可能になった時刻を記録していないため、競合そのものの発生時刻までは確定していない。

## 実行環境

| 項目 | 最新失敗時の値 |
| --- | --- |
| GitHub Actions runner | `macos-26-arm64`、イメージ `20260907.0351.1` |
| macOS | 26.6.2 |
| Flutter | 3.47.4、framework `9584c6713b` |
| Xcode | 26.6、build `17F113` |
| Simulator | iPhone 17 Pro / iOS 26.4 |
| E2Eコマンド | `bash scripts/run_ios_e2e.sh "$SIMULATOR_UDID"` |
| E2E実行上限 | 900秒。ビルド・インストール・接続・テストを含む |
| Native GPS | 無効 |

## 最新実行の証拠

[Actions実行 35192271401](https://github.com/nanigasi-san/Argus/actions/runs/35192271401) と、その `ios-e2e-diagnostics` artifactを確認した。以下の時刻はUTC。

| 時刻 | 記録 | 意味 |
| --- | --- | --- |
| 07:02:22 | `Starting integration_test/ci_all_suites.dart (timeout 900s)` | 全件用エントリーポイントの実行開始 |
| 07:08:29 | `BUILD SUCCEEDED` / `Xcode build done` | コンパイルと署名は成功 |
| 07:09:14 | `simctl launch ... --start-paused ...` | テストアプリの起動要求 |
| 07:09:15 | `simctl spawn ... log stream ...` | ログ監視プロセスの起動要求。読み取り準備完了を保証する記録ではない |
| 07:09:29.760 | `simulator.log`: `The Dart VM service is listening on http://127.0.0.1:51210/.../` | アプリ内のVM Serviceは既に起動している |
| 07:09:31 | `com.argus.orienteering: 19704` / `Waiting for VM Service port to be available...` | CLIはVM ServiceのURLを検出できていない |
| 07:17:23 | `[timeout] flutter exceeded 900s` | 実行上限でプロセス群を停止 |
| 07:17:23 | `The log reader failed unexpectedly` | タイムアウトによる停止後に表示されたエラー |

`processes.txt`には終了時点でもPID 19704の `Runner.app/Runner` が残っている。`final-screen.png`は起動ロゴを表示している。これは `--start-paused` でDartを停止して起動し、接続後にdriverが再開する構成と整合する。保存ログにVM Service URLが存在する一方、CLIには `VM Service URL on device` やdriver接続の記録がない。

したがって、最後の `The log reader failed unexpectedly` を最初の原因と読むのは適切ではない。先にURL検出が停止し、その後、実行上限に達してログ監視も終了している。

## 過去の実行との比較

| Actions実行 | コミット | 結果と停止箇所 |
| --- | --- | --- |
| [35188949946](https://github.com/nanigasi-san/Argus/actions/runs/35188949946) | `691f834` | 3ファイルすべて成功。各起動後にVM Service URLを検出し、2件・9件・8件のテストが成功 |
| [35190274562](https://github.com/nanigasi-san/Argus/actions/runs/35190274562) | `f666db7` | 最初のsuiteがURL検出待ちで600秒タイムアウト。後続の2ファイルは成功 |
| [35191688093](https://github.com/nanigasi-san/Argus/actions/runs/35191688093) | `1044ead` | Simulatorのbootstatus完了後、起動確認のスクリーンショット取得が30秒タイムアウト。E2Eは未実行 |
| [35192271401](https://github.com/nanigasi-san/Argus/actions/runs/35192271401) | `0d57b2f` | 全件用エントリーポイントがURL検出待ちで900秒タイムアウト |

実行 35190274562の保存ログにも、失敗した最初のアプリPID 11426が06:39:12.257にVM Service URLを出力した記録がある。CLIはそのURLを取得できていない。これは全件のビルド集約を導入する前にも発生しているため、集約だけを原因にはできない。

スクリーンショット取得の停止は別の失敗であり、VM Service URLを見失う競合と同じ原因だと断定しない。最新コミットは画像取得失敗時にE2Eを継続するよう変更しているが、URL検出の問題は残っている。

## 公式の類似報告と実装

- [Flutter #181771](https://github.com/flutter/flutter/issues/181771): GitHub ActionsのmacOS 26上で、ビルド・アプリ起動後に `Waiting for VM Service port to be available...` で停止する。報告者は40回中3回、別の検証者も20回中2回の失敗を報告している。調査時点でOpen。
- [bkonyiの原因候補の説明](https://github.com/flutter/flutter/issues/181771#issuecomment-3891689120): `_IOSSimulatorLogReader` が同期コールバックを期待する `StreamController.broadcast.onListen` に非同期の初期化処理を渡しており、ログ監視初期化を待たずにアプリを起動するため、VM Service URLを取り逃がす可能性を指摘している。
- [Flutter 3.47.4のsimulators.dart](https://github.com/flutter/flutter/blob/3.47.4/packages/flutter_tools/lib/src/ios/simulators.dart): `startApp` は `ProtocolDiscovery.vmService(getLogReader(...))` を作成し、アプリを起動してから `vmServiceDiscovery.uri` を待つ。ログ監視側は `onListen: _start`、`Future<void> _start() async` であり、読み取り準備完了を起動処理が待つ仕組みはない。
- [Flutter 3.47.4のprotocol_discovery.dart](https://github.com/flutter/flutter/blob/3.47.4/packages/flutter_tools/lib/src/protocol_discovery.dart): URLはログストリームの通知から取得する。既に保存されたログを読み直してURLを回収する処理はない。

なお、[Flutter #129246](https://github.com/flutter/flutter/issues/129246)には実行ファイル名と製品名の不一致による同じ待ち状態の報告もある。Argusでは起動プロセス名・監視対象とも `Runner` で、成功実行も存在するため、この原因を支持する証拠はない。

## 次の修正で検証する方針

URLを取得する経路を確実にすることを優先する。タイムアウト延長だけでは、一度取り逃がした起動通知を回収できない。

検証候補は、全件用アプリをビルド・インストールして起動し、現在の起動時刻・PIDに限定した保存ログからVM Service URLを回収して、driverを既存アプリへ接続する方式である。[Flutter 3.47.4のdrive.dart](https://github.com/flutter/flutter/blob/3.47.4/packages/flutter_tools/lib/src/commands/drive.dart)は `--use-existing-app=<VM Service URL>` をサポートする。古い起動のURLを使わないこと、URL取得・接続に上限を設けること、全suiteの実行件数を維持することが必要である。

別案はFlutter側のログ監視を初期化完了後に起動するよう修正する方法である。SDK変更を採用する場合は、CIで使用するFlutterのバージョンと変更対象の一致を検証する必要がある。

この調査では既存CIログ・artifactと公式ソースを照合した。修正実装や追加のCI再実行は行っていない。Windows環境のためiOS Simulatorでのローカル再現・対策の効果検証は未実施。

## 高速化検証中のCoreSimulator初期化の失敗

VM Serviceの通知取り逃がしとは別に、2026-09-17の検証で次の失敗を確認した。

| 実行 | 停止箇所 | 状況 |
| --- | --- | --- |
| [35218293280](https://github.com/nanigasi-san/Argus/actions/runs/35218293280) | `open -a Simulator` が30秒でタイムアウト | アプリと全nativeテストのビルドは成功。GUIを端末起動完了前に開いており、nativeテストは未実行 |
| [35219182806](https://github.com/nanigasi-san/Argus/actions/runs/35219182806) | 初回の `simctl list devices available -j` が120秒でタイムアウト | macos-26-arm64 / image 20260907.0351.1。E2Eアプリのビルド前のため、VM Service接続問題とは区別する |

各WFでは前の処理の成功後に次へ進む方針とし、ビルドと起動の並行化・進捗出力解析を削除した。端末の`bootstatus`完了後にGUIを開き、GUI初回起動は120秒まで待つ。

[Appleのコンポーネント準備手順](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)に従い、WFの最初に`xcodebuild -runFirstLaunch`を実行して`-checkFirstLaunchStatus`で成功を確認する。初回の端末取得は300秒まで待ち、失敗を成功扱いしたりアプリ・テストを再試行したりしない。

端末一覧の停止だけでは必須コンポーネント未準備やサービス内部の停止を断定できない。初期設定の明示と待ち時間の修正は対策として検証し、修正後の全件成功・複数runnerでの結果をPR本文に記録する。
