# ClipXS

Windows の **Win+V** 相当のクリップボード履歴アプリ for macOS。

## リポジトリ

```bash
git clone <repository-url> clipxs
cd clipxs
```

`project.yml` から Xcode プロジェクトを再生成する場合（[XcodeGen](https://github.com/yonaskolb/XcodeGen) が必要）:

```bash
xcodegen generate
```

- **ショートカット**: `Option + Command + V` で履歴パネルを開く
- **対応種別**: 文章・画像・ファイル
- **常駐**: メニューバー（Dock に表示されません）

## 必要環境

- macOS 13 以降
- Xcode 15 以降（ビルド時）

## ビルド

```bash
cd /path/to/clipxs
xcodebuild -scheme ClipXS -configuration Release -derivedDataPath build build
open build/Build/Products/Release/ClipXS.app
```

Debug ビルド:

```bash
xcodebuild -scheme ClipXS -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/ClipXS.app
```

## 初回セットアップ

1. `ClipXS.app` を起動する（メニューバーにクリップボードアイコンが表示されます）
2. **システム設定 → プライバシーとセキュリティ → アクセシビリティ** で **ClipXS** をオンにする  
   （履歴から選択した内容を自動で `⌘V` 貼り付けするために必要です）
3. （任意）メニューバー → **ログイン時に起動** をオンにする  
   初回は **システム設定 → 一般 → ログイン項目** で ClipXS を許可する必要がある場合があります
4. 任意のテキストをコピーし、貼り付け先で `Option + Command + V` を押す
5. 履歴から項目を選択（クリックまたは `↑` `↓` + `Return`）

## 使い方

| 操作 | 説明 |
|------|------|
| `Option + Command + V` | 履歴パネルを開く / 閉じる |
| `↑` / `↓` | 項目を移動 |
| `Return` | 選択して貼り付け |
| `Esc` | パネルを閉じる |
| メニューバーアイコン | クリックで履歴を開く |
| メニュー「ログイン時に起動」 | チェックで Mac 起動・ログイン時に自動起動 |

履歴は最大 **100 件** まで保存されます（`~/Library/Application Support/ClipXS/`）。

## 言語

UI はシステム言語に追従します（英語 / 日本語の `Localizable.strings` を同梱）。

## 今後の拡張（未実装）

- パスワードマネージャ等からのコピー除外
- iCloud 同期
- App Store 向け Notarization

## ライセンス

MIT（必要に応じて変更してください）
