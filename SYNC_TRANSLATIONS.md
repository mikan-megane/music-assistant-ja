# 翻訳同期手順 (Translation Sync Guide)

## 概要

Music Assistant の日本語翻訳ファイル (`ja.json`, `server_ja.json`) をアップストリームの英語版と同期し、新しいキーを翻訳する手順です。

同期作業は `scripts/translation_sync.py` で半自動化されています。翻訳(日本語を書く)だけが人間/エージェントの作業で、比較・マージ・検証はすべてスクリプトが担います。

## アップストリームのURL

| ファイル | URL |
|----------|-----|
| フロントエンド en.json | `https://raw.githubusercontent.com/music-assistant/frontend/main/src/translations/en.json` |
| サーバー en.json | `https://raw.githubusercontent.com/music-assistant/server/dev/music_assistant/translations/en.json` |

> **注意**: サーバー側のブランチは `dev` です (`main` ではない)。

## ファイル構造

| ファイル | 対象 | 構造 | スクリプト上の呼び名 |
|----------|------|------|----------------------|
| `ja.json` | フロントエンド | ネストされたJSON (en.json と同じ構造) | `front` |
| `server_ja.json` | サーバー | フラットなドット区切りキー | `srv` |

出力スタイルは既存ファイルに合わせること:
- `ja.json`: インデント4、末尾に改行、UTF-8 **BOMなし** (BOM があると `@intlify/unplugin-vue-i18n` が JSON.parse に失敗し、言語選択に日本語が出なくなる — Dockerfile のチェック参照)
- `server_ja.json`: インデント2、末尾に改行

## 同期ワークフロー

```bash
# 1. 差分サマリを確認 (未翻訳キー・上流で廃止されたキーの数)
python3 scripts/translation_sync.py check

# 2. 未翻訳キーを TSV で書き出す
python3 scripts/translation_sync.py export
#   -> .translation-sync/missing_front.tsv  (key<TAB>英語値)
#   -> .translation-sync/missing_srv.tsv

# 3. TSV の値列を日本語訳で埋める
#    (ファイル名に front/srv を含めた翻訳済みファイルを用意)
#    例: trans_front_1.tsv, trans_front_2.tsv, trans_srv_1.tsv ...

# 4. マージ (検証込みで ja.json / server_ja.json を再構築)
python3 scripts/translation_sync.py merge workdir/trans_front_*.tsv workdir/trans_srv_*.tsv
#    引数を省略すると .translation-sync/trans_*.tsv を自動で拾う

# 5. 差分を確認してコミット
git add ja.json server_ja.json
git commit -m "sync: update Japanese translations"
git push
```

### スクリプトがやってくれること

- `check` / `export`: 上流 en.json のダウンロードとスナップショット (`.translation-sync/en_*.json`)、フラット化キーの比較
- `merge`:
  - 既存訳を最優先で保持し、新規キーのみ翻訳TSVから採用 (en のキー順序を完全に再現)
  - 翻訳TSVの検証: カバレッジ、プレースホルダーの一致(複数形 `|` 考慮)、改行構造、vue-i18n 特殊文字の混入、半角 `?!` の検出
  - 半角 `?!` の自動正規化 (CJK文字の直後のみ全角化。URL など ASCII 文脈の `?` は保護)
  - カスタムキー `settings.language.options.ja` の保持
  - JSON 有効性・BOMなしの最終チェック

## 翻訳ルール (TSVを埋める際)

### TSV 形式

- 1行 = `key<TAB>日本語訳`。TSV 内では改行をリテラルの `\n`、タブを `\t` として書く (merge 時に実文字へ戻る)
- マークダウン記法 (`[text](url)`, `**bold**`, 箇条書き `-`) とインラインコードは en の構造をそのまま維持する

### プレースホルダー

- `{0}`, `{count}`, `{name}` などのプレースホルダーは **en と同じものを必ず残す**
- en に複数形がある場合 (`... | ...` 区切り) は、日本語は**単一形式**でよい (日本語は複数形を持たないため。既存の ja.json もこの方針)。例: `{count} play | {count} plays` → `{count}回再生`

### vue-i18n の特殊文字 (フロント側 `ja.json` のみ)

- `@` と `|` はメッセージ構文 (リンク・複数形区切り) と衝突するため**翻訳に使用しない**
- サーバー側 (`server_ja.json`) はこの制限なし

### 句読点・表記

- `?` `!` は全角 (`？` `！`) を使う。ただし URL 中の `?` は半角のまま (merge が自動判別・正規化する)
- 引用は「」、文末は既存ファイルに合わせてです・ます調 (ラベルは体言止め)
- 数値と単位の間などは半角スペースを入れる慣習 (`{0} 件` / `Music Assistant へようこそ`)

### 翻訳の温存と順序

- 既に日本語訳があるキーは**絶対に上書きしない** (merge が既存訳を優先する)
- en に存在しなくなったキーは削除する (ただし下記カスタムキーを除く)
- キー順序は en に合わせる (diff を読みやすくするため)

### カスタムキー (削除しないこと)

- `settings.language.options.ja` = `日本語` — アップストリームに存在しないキー。言語選択ドロップダウンに日本語を出すために必要

## 用語集 (訳語の統一)

| 英語 | 日本語訳 |
|------|----------|
| music source | ミュージックソース |
| player | プレーヤー |
| provider | プロバイダー |
| pairing / pair | ペアリング / ペアリングする |
| setup | セットアップ |
| scrobbling | スクロブリング |
| lossless / lossy | ロスレス / ロッシー |
| hi-res | ハイレゾ |
| stream quality | ストリーム品質 |
| playlist / track / album | プレイリスト / トラック / アルバム |
| album artist | アルバムアーティスト |
| favorites | お気に入り |
| remote access | リモートアクセス |
| storage location | ストレージロケーション |
| network share | ネットワーク共有 |
| crossfade | クロスフェード |
| announcement | アナウンス |
| transcript | 文字起こし |
| bookmark | ブックマーク |
| on air | 放送中 |
| queue | キュー |
| Music Assistant / Home Assistant / Spotify など | 固有名詞は英語のまま |

## ワークフロートリガー

以下のファイルが `main` ブランチにプッシュされるとビルドが走ります:
- `ja.json`
- `server_ja.json`
- `Dockerfile`
- `.github/workflows/build.yml`

## キー数の実績

| 時点 | フロント en | サーバー en |
|------|-------------|-------------|
| 2025-07 | 1,627 | 2,351 |
| 2026-11 | 2,678 | 3,142 |

最新の数値は `python3 scripts/translation_sync.py check` で確認できる。
