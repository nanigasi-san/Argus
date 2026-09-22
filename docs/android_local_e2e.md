# macOS の Android E2E 環境

2026-09-18 に Apple Silicon の Mac でセットアップした構成。
Android SDK は `~/Library/Android/sdk` にそろえ、Flutter の SDK 設定もこの場所へ変更した。
仮想端末は Android Studio の Device Manager からも起動できる。

| 項目 | 設定 |
| --- | --- |
| Flutter | 3.44.1 |
| Java | Homebrew OpenJDK 17（既存の Flutter 設定） |
| 仮想端末名 | `argus_pr_review_api36` |
| Device profile | Pixel 7 Pro |
| System image | Android 36 / Google APIs / arm64-v8a |
| adb serial | `emulator-5554`（port 5554 で起動した場合） |

エミュレーター本体に加え、System image と command-line tools を SDK 配下に用意した。
Flutter のビルドが要求する NDK などは Gradle が必要に応じて取得する。
GitHub Actions の Android E2E は同じ API 36 と Pixel 7 Pro を使い、
Linux runner のため CPU は x86_64。Mac は arm64-v8a を使う。

## 起動して全件実行する

ターミナルで SDK のコマンドを使えるようにする。次はそのターミナルにだけ適用する設定。

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
flutter config --android-sdk "$ANDROID_HOME"
emulator -list-avds
emulator -avd argus_pr_review_api36 -port 5554 -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none
```

別のターミナルにも上の `ANDROID_HOME` と `PATH` を設定し、起動を確認して実行する。
画面不要の場合は emulator 起動時に `-no-window` を追加する。

```bash
adb devices
adb -s emulator-5554 shell getprop sys.boot_completed
# 上の値が 1 になってから実行する。
adb -s emulator-5554 shell settings put global window_animation_scale 0
adb -s emulator-5554 shell settings put global transition_animation_scale 0
adb -s emulator-5554 shell settings put global animator_duration_scale 0
bash scripts/run_android_e2e.sh emulator-5554
```

`integration_test/` と、存在する場合は `e2e/` の `*_test.dart` を全件検出し、
一度のアプリ起動で実行する。個別ファイルだけを指定して PR 前の全件実行を代替しない。
ログ・検出一覧・API level・ファイルごとの完了件数は `build/e2e/`、
スクリーンショットは `build/integration_test/screenshots/` に保存する。
通常実行では `SIMULATOR_GPS` を設定しない。

終了する場合は `adb -s emulator-5554 emu kill`。仮想端末と SDK は残る。
他の端末が port 5554 を使用している場合は終了させず、別 port と対応する adb serial を使う。

[Android 公式: コマンドラインからのエミュレーター起動](https://developer.android.com/studio/run/emulator-commandline)
に起動引数と仮想端末の保存場所が記載されている。この手順は導入済み SDK の emulator コマンドを使用する。
