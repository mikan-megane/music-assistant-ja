# 翻訳同期手順 (Translation Sync Guide)

## 概要

Music Assistant の日本語翻訳ファイル (`ja.json`, `server_ja.json`) をアップストリームの英語版と同期し、新しいキーを翻訳する手順です。

## アップストリームのURL

| ファイル | URL |
|----------|-----|
| フロントエンド en.json | `https://raw.githubusercontent.com/music-assistant/frontend/main/src/translations/en.json` |
| サーバー en.json | `https://raw.githubusercontent.com/music-assistant/server/dev/music_assistant/translations/en.json` |

> **注意**: サーバー側のブランチは `dev` です (`main` ではない)。

## ファイル構造

### ja.json (フロントエンド)
- ネストされたJSON（オブジェクトの中にオブジェクト）
- `en.json` と完全に同じ構造

### server_ja.json (サーバー)
- フラットなドット区切りキー (`common.config_categories.advanced` など)
- `en.json` と同じフラット構造

## 同期スクリプト

Pythonでキー比較と同期を行う：

```bash
python3 << 'PYEOF'
import json, urllib.request

# --- フロントエンド比較 ---
en_front_url = 'https://raw.githubusercontent.com/music-assistant/frontend/main/src/translations/en.json'
with urllib.request.urlopen(en_front_url) as f:
    en_front = json.loads(f.read().decode('utf-8'))

with open('ja.json', 'r') as f:
    ja_front = json.load(f)

def walk_keys(d, prefix=''):
    keys = []
    if isinstance(d, dict):
        for k, v in d.items():
            full = f'{prefix}.{k}' if prefix else k
            if isinstance(v, dict):
                keys.extend(walk_keys(v, full))
            else:
                keys.append(full)
    return keys

en_keys = walk_keys(en_front)
ja_keys = walk_keys(ja_front)
missing_front = sorted(set(en_keys) - set(ja_keys))

print(f'=== FRONTEND (ja.json) ===')
print(f'English keys: {len(en_keys)}')
print(f'Japanese keys: {len(ja_keys)}')
print(f'Missing keys: {len(missing_front)}')
for k in missing_front:
    print(f'  {k} = {repr(get_nested(en_front, k))}')

# --- サーバー比較 ---
en_srv_url = 'https://raw.githubusercontent.com/music-assistant/server/dev/music_assistant/translations/en.json'
with urllib.request.urlopen(en_srv_url) as f:
    en_srv = json.loads(f.read().decode('utf-8'))

with open('server_ja.json', 'r') as f:
    ja_srv = json.load(f)

missing_srv = sorted(set(en_srv.keys()) - set(ja_srv.keys()))
print(f'\n=== SERVER (server_ja.json) ===')
print(f'English keys: {len(en_srv)}')
print(f'Japanese keys: {len(ja_srv)}')
print(f'Missing keys: {len(missing_srv)}')
for k in missing_srv:
    print(f'  {k} = {repr(en_srv[k])}')
PYEOF
```

## 翻訳後のプッシュ

```bash
git add ja.json server_ja.json
git commit -m "sync: update Japanese translations"
git push
```

プッシュすると GitHub Actions (`.github/workflows/build.yml`) が自動的にDockerイメージをビルド・プッシュします。

## ワークフロートリガー

以下のファイルが `main` ブランチにプッシュされるとビルドが走ります：
- `ja.json`
- `server_ja.json`
- `Dockerfile`
- `.github/workflows/build.yml`

また、毎週月曜日 04:00 UTC に自動ビルドが実行されます。

## 注意点

- `ja.json` の `settings.language.options.ja` キーはアップストリームに存在しないカスタムキーです（日本語を言語選択に追加するためのDockerfile内での注入用）
- フロントエンドのキー数: en=1627キー (2025-07時点)
- サーバーのキー数: en=2351キー (2025-07時点)
