# ClipXS

[English](README.md) | 日本語

Windowsの `Win + V` のように使える、macOS向けの軽量クリップボード履歴アプリです。`Option + Command + V` で最近コピーした項目を開き、現在のアプリを離れずに選んで貼り付けられます。

## 主な機能

- テキスト・画像・ファイルのクリップボード履歴
- Dockに表示しないメニューバー常駐アプリ
- キーボード中心で操作できる履歴パネル
- 最大100件を端末内に保存
- ログイン時の自動起動
- macOSの言語に追従する英語・日本語UI

## 初回セットアップ

1. `ClipXS.app` を起動します。
2. **システム設定 > プライバシーとセキュリティ > アクセシビリティ**でClipXSを有効にします。選択した項目を他のアプリへ貼り付けるために必要です。
3. 必要に応じてメニューバーメニューから**ログイン時に起動**を有効にします。
4. 何かをコピーし、`Option + Command + V` を押して項目を選びます。

## 操作

| 操作 | 動作 |
|---|---|
| `Option + Command + V` | 履歴を開く・閉じる |
| `↑` / `↓` | 項目を移動 |
| `Return` | 選択した項目を貼り付け |
| `Esc` | パネルを閉じる |

履歴は `~/Library/Application Support/ClipXS/` にローカル保存されます。

## ビルド

```bash
git clone https://github.com/porarrirr/clipxs.git
cd clipxs
xcodegen generate
xcodebuild -scheme ClipXS -configuration Release -derivedDataPath build build
```

## ライセンス

[MIT License](LICENSE)
