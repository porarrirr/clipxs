# 履歴操作の性能計測

2026-10-17 に実際の `HistoryViewModel` を Release ビルドで比較した結果。
Apple M2 / メモリ24 GB / macOS 27.0.1 / Xcode 27.0（Swift 6.4、Swift言語モード5.9）、arm64。
改善前はコミット `5810dfc` の処理に、計測用の取得クロージャ注入だけを追加したもの。
改善前のソースは `build/PerformanceBaselineSource` に分離してビルドした。

- 日本語検索中の上下移動40往復: **3,096.476 → 0.223 ms（99.9928%短縮）**。
- 6段階の検索入力と一覧・選択項目の取得: **341.167 → 67.376 ms（80.2512%短縮）**。
- 画像フィルタ中の上下移動40往復: **2,379.631 → 0.111 ms（99.9953%短縮）**。

各操作はウォームアップ1回の後に7回計測し、中央値を使用した。
fixtureは1,000件（URL、2画像のファイル一覧、PDFファイル一覧、OCR付き画像、日本語文章を各200件）。
検索中の移動は検索語「検索」を使用し、検索入力は「検」「検索」「検索対」「検索対象」「検索」「空文字」の順。
各検索入力では一覧を2回、選択項目を1回取得する。上下移動では選択更新に加えて一覧とプレビューの取得を再現する。
fixtureの生成・読込は計測対象外。改善前後の処理結果のチェックサムは共に `560688`。
正確な数値は [history-results.json](history-results.json) に保存している。

対象は履歴モデルの処理時間。SwiftUIの描画、ディスク読込、起動時間、クリップボード監視、OCR認識自体の速度を示す数値ではない。
他のアプリによる負荷もある実機での計測なので、絶対時間は環境によって変わる。

検索・種別フィルタ・履歴の変更時だけ結果を再計算し、選択移動や再描画では配列を共有する。
検索語の空白除去は検索ごとに1回行い、種別分類は検索語を変えても再利用する。
パネル非表示中は全件再取得を止め、再表示時に最新履歴を取得する。
取得中の変更通知は1回の追加取得にまとめ、非表示前の古い応答は無視する。

Releaseビルドおよび全50テスト成功。追加の8件では、日本語・大文字小文字・OCR検索、
フィルタ、編集後の更新、選択の保持、非表示中の読込停止、通知の集約、古い応答の破棄を確認した。

再計測:

```sh
xcodebuild -scheme ClipXS -configuration Release \
  -derivedDataPath build/Performance -destination 'platform=macOS,arch=arm64' \
  -jobs 2 -only-testing:ClipXSTests/HistoryPerformanceTests \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test > build/performance-after.log 2>&1

python3 Benchmarks/compare.py build/performance-baseline.log build/performance-after.log
```

比較には、同じテストコード・fixture・ビルド設定で改善前のソースを測ったログが必要。
`compare.py` は件数・試行数・チェックサムの一致を検査し、いずれかの計測項目が80%短縮に届かなければ失敗する。
初回の比較ログと `.xcresult` は `build/` 配下にあり、Git管理対象外。
