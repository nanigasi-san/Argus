# Tasks

## 0. 事前調査
- [x] プロジェクト構成の確認
- [x] Flutter / Dart バージョンの確認
- [x] pubspec.yaml と analysis_options.yaml の確認
- [x] Android / iOS ディレクトリの有無確認
- [x] 主要画面・状態管理・ルーティング・設定画面の確認
- [x] 多言語化・文言管理・フォント設定の確認
- [x] 使用パッケージとテスト構成の確認
- [x] ビルド・実行・lint・test コマンドの確認
- [x] 既存の不具合候補の列挙
- [x] パフォーマンス・バッテリー消費リスクの列挙

## 1. 大規模リファクタリング
- [x] Android 専用前提の実装を洗い出す
- [x] iOS 対応を見据えた platform 抽象化方針を決める
- [x] platform 判定や権限周りを整理する
- [x] Android release signing 設定の安全性を改善する
- [x] 設定値モデルに安全な範囲と補正処理を追加する
- [x] 状態管理・ビジネスロジック・UI の責務を整理する
- [x] dispose 後の非同期更新・通知を防ぐ
- [x] permission denied / service disabled 時の処理を改善する
- [x] ファイル読み書き・設定読み込み失敗時の復旧性を改善する
- [x] バグ原因になりうる箇所を優先度順に修正する
- [x] 不要な rebuild や build 内処理を減らす
- [x] const constructor 化と不要なオブジェクト生成削減を行う
- [x] 高頻度 location / vibration / alarm 処理のバッテリー影響を改善する
- [x] ライフサイクルに応じた停止・再開処理を改善する
- [ ] emulator で起動と主要導線を確認する

## 2. 軽微な修正
- [x] setting で設定できる数値の役割を整理する
- [x] setting の数値を実用的な範囲・名称・説明にする
- [x] 保存済みの不正な設定値を安全に補正する
- [x] ホーム画面下部に連絡先メールリンクを追加する
- [x] `created` 表記を `Created` に修正する
- [x] 不自然に英語が混ざっている文言を日本語化する
- [x] フォントを統一する
- [x] モダンで読みやすい日本語フォントを設定する
- [x] 小さい画面でも主要 UI が崩れないか確認する

## 3. 最終確認
- [ ] flutter pub get を実行する
- [ ] format を実行する
- [ ] analyze を実行する
- [ ] test を実行する
- [ ] Android debug build を実行する
- [ ] emulator で主要導線を確認する
- [ ] すべての tasks.md のチェックを再確認する
- [ ] FINAL_REPORT.md を作成する
