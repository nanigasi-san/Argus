# 作業ルール

- ユーザーから作業を指示されたら、最初に現在のブランチで `git pull --ff-only` を実行してから作業に着手する。
- PRを作成・提出する前に、E2Eを全件実行する。現在のE2Eは `integration_test/` 配下の `*_test.dart` であり、今後 `e2e/` を追加した場合はその配下も再帰的に対象とする。一部のファイルだけを実行して済ませない。
  - Windowsでは `./scripts/run_android_ui_checks.ps1 -CaptureScreenshots`、Linux/macOSでは起動済みAndroid Emulatorに対して `bash scripts/run_android_e2e.sh emulator-5554` を実行する。両スクリプトは対象ディレクトリの全E2Eファイルを自動検出する。
  - E2Eのために起動したAndroid Emulatorは、テスト完了後に必ず終了する。
  - 全件の成功を確認し、PR本文へ実行コマンド・端末/API level・実行ファイル・結果を記載する。失敗または実行できない場合はPRを提出せず、該当ファイルと理由を報告する。
  - `SIMULATOR_GPS=true` などOS固有の任意モードは、通常の全件実行と区別して実行有無を記録する。
- 指示された作業を終えたら、その作業の変更をコミットし、現在のブランチに `git push` してから完了を報告する。

既存の未コミット変更や作業対象外のファイルは保持する。PULL・PUSH に失敗した場合は、強制操作をせず原因を報告する。

## Connect IQ Simulator（macOS）

- Homebrewで入れたConnect IQ SDKでは、`/Applications/ConnectIQ.app` のシミュレーターが親ディレクトリの `/Applications/version.txt` を参照する。一方、実ファイルはSDKの `bin/version.txt` にある。この参照がないと `can't open file '/Applications/version.txt'` と表示される。アプリやテストコードのエラーと取り違えない。
- `SDK_BIN=$(dirname "$(realpath "$(command -v monkeydo)")")` で使用中のSDKを特定し、`$SDK_BIN/version.txt` と `/Applications/version.txt` の存在・リンク先を確認する。後者がない場合のみ `ln -s "$SDK_BIN/version.txt" /Applications/version.txt` で参照を作る。SDK更新後はリンク切れを確認し、新しいSDKのファイルを指すように更新する。
- 参照を直した後はシミュレーターを再起動して確認する。このリンクは各Macのローカル環境設定であり、リポジトリには含まれない。
