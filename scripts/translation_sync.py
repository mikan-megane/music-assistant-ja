#!/usr/bin/env python3
"""translation_sync.py — Music Assistant 日本語翻訳の上流同期ツール。

アップストリーム en.json と日本語翻訳ファイル (ja.json / server_ja.json) の
差分確認、未翻訳キーの書き出し、翻訳済み TSV のマージを担う。標準ライブラリのみ。

使い方:
    # 1. 差分サマリを表示
    python3 scripts/translation_sync.py check

    # 2. 未翻訳キーを TSV で書き出す (翻訳者/エージェントがこのファイルを埋める)
    python3 scripts/translation_sync.py export

    # 3. 翻訳済み TSV をマージして ja.json / server_ja.json を再構築 (検証込み)
    python3 scripts/translation_sync.py merge workdir/trans_front_*.tsv workdir/trans_srv_*.tsv

詳細なワークフローと翻訳ルールは SYNC_TRANSLATIONS.md を参照。
"""

import argparse
import collections
import glob
import json
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_WORKDIR = REPO / ".translation-sync"

UPSTREAM = {
    "front": "https://raw.githubusercontent.com/music-assistant/frontend/main/src/translations/en.json",
    "srv": "https://raw.githubusercontent.com/music-assistant/server/dev/music_assistant/translations/en.json",
}
LOCAL_FILES = {"front": "ja.json", "srv": "server_ja.json"}
# 上流に存在しないが意図的に保持するカスタムキー (Dockerfile が言語選択に使用)
CUSTOM_KEEP = {"front": {"settings.language.options.ja": "日本語"}}
# 出力スタイル (既存リポジトリのファイルに合わせる)
INDENT = {"front": 4, "srv": 2}


def fetch_en(side: str, workdir: Path) -> dict:
    """上流 en.json を取得 (スナップショットがあればそれを優先)。"""
    snap = workdir / f"en_{side}.json"
    if snap.exists():
        return json.loads(snap.read_text(encoding="utf-8"))
    print(f"download: {UPSTREAM[side]}")
    with urllib.request.urlopen(UPSTREAM[side]) as f:
        data = json.loads(f.read().decode("utf-8"))
    workdir.mkdir(parents=True, exist_ok=True)
    snap.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return data


def load_local(side: str) -> dict:
    return json.loads((REPO / LOCAL_FILES[side]).read_text(encoding="utf-8"))


def flat(d, prefix=""):
    """ネストされたdictを 'a.b.c' 形式のフラットな (key, value) に展開。"""
    if isinstance(d, dict):
        for k, v in d.items():
            yield from flat(v, f"{prefix}.{k}" if prefix else k)
    else:
        yield prefix, d


def count_leaves(d) -> int:
    return sum(count_leaves(v) if isinstance(v, dict) else 1 for v in d.values())


# --- TSV 入出力 (値内の \n と \t はエスケープして保持) -----------------------


def dump_tsv(pairs: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for k in sorted(pairs):
            v = pairs[k].replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
            f.write(f"{k}\t{v}\n")


def load_tsv(paths: list[str]) -> dict:
    d = {}
    for p in paths:
        for line in Path(p).read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            k, v = line.split("\t", 1)
            v = v.replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
            if k in d:
                sys.exit(f"ERROR: TSV重複キー {k} ({p})")
            d[k] = v
    return d


# --- 検証 -------------------------------------------------------------------


def placeholders(s: str) -> set:
    import re

    return set(re.findall(r"\{[^}]*\}", s))


def normalize_punct(text: str) -> str:
    """CJK文字の直後の半角 ?! を全角にする (URLなどのASCII文脈は保護)。"""
    out = []
    for i, ch in enumerate(text):
        if ch in "?!" and i > 0 and ord(text[i - 1]) >= 128:
            out.append("？" if ch == "?" else "！")
        else:
            out.append(ch)
    return "".join(out)


def validate_translations(side: str, missing: dict, trans: dict, errors: list) -> None:
    for k, ja in trans.items():
        en = missing.get(k)
        if en is None:
            continue
        # プレースホルダー: ja 側は en 側の複数形フォーム (| 区切りのいずれか) に含まれること
        en_ph = set()
        for form in en.split("|"):
            en_ph |= placeholders(form)
        ja_ph = placeholders(ja)
        if not ja_ph.issubset(en_ph):
            errors.append(f"{side} {k}: 不明なプレースホルダー ja={sorted(ja_ph)} en候補={sorted(en_ph)}")
        # フロントは vue-i18n メッセージコンパイラを通るため @ と | は使用禁止
        if side == "front":
            if "@" in ja:
                errors.append(f"front {k}: '@' は使用不可 (リンク構文と衝突)")
            if "|" in ja:
                errors.append(f"front {k}: '|' は使用不可 (複数形区切りと衝突)")
        # en に改行があるのに ja にない場合は構造崩れの疑い
        if "\n" in en and "\n" not in ja:
            errors.append(f"{side} {k}: enに改行があるがjaにない")
        # 半角 ?! の混入 (CJK直後のみ検出; normalize_punct で自動修正もされる)


# --- サブコマンド -------------------------------------------------------------


def cmd_check(args) -> None:
    workdir = Path(args.workdir)
    for side in ("front", "srv"):
        en = fetch_en(side, workdir)
        ja = load_local(side)
        en_flat = dict(flat(en))
        ja_flat = dict(flat(ja))
        missing = sorted(set(en_flat) - set(ja_flat))
        extra = sorted(set(ja_flat) - set(en_flat) - set(CUSTOM_KEEP.get(side, {})))
        same = [k for k in en_flat if k in ja_flat and ja_flat[k] == en_flat[k]]
        label = LOCAL_FILES[side]
        print(f"=== {label} ===")
        print(f"  en={len(en_flat)}  ja={len(ja_flat)}  未翻訳(欠落)={len(missing)}  上流で廃止={len(extra)}  英語のまま={len(same)}")
        for k in missing[: args.show]:
            print(f"  - {k} = {en_flat[k]!r}")
        if len(missing) > args.show:
            print(f"  ... ほか {len(missing) - args.show} 件")
        for k in extra[: args.show]:
            print(f"  + {k} = {ja_flat[k]!r}")
        if len(extra) > args.show:
            print(f"  ... ほか {len(extra) - args.show} 件")


def cmd_export(args) -> None:
    workdir = Path(args.workdir)
    for side in ("front", "srv"):
        en = fetch_en(side, workdir)
        ja = load_local(side)
        en_flat = dict(flat(en))
        ja_flat = dict(flat(ja))
        missing = {k: v for k, v in en_flat.items() if k not in ja_flat}
        out = workdir / f"missing_{side}.tsv"
        dump_tsv(missing, out)
        print(f"{LOCAL_FILES[side]}: 未翻訳 {len(missing)} 件 -> {out}")
    print("このTSVの値列を日本語訳で埋め、`merge` サブコマンドに渡してください。")


def cmd_merge(args) -> None:
    workdir = Path(args.workdir)
    trans_paths = {side: [] for side in ("front", "srv")}
    for p in args.tsv:
        side = "front" if "front" in Path(p).name else "srv" if "srv" in Path(p).name else None
        if side is None:
            sys.exit(f"ERROR: ファイル名に front/srv が含まれていません: {p}")
        trans_paths[side].append(p)
    # 引数が無い場合は workdir の trans_*.tsv を拾う
    if not args.tsv:
        for side in ("front", "srv"):
            trans_paths[side] = sorted(glob.glob(str(workdir / f"trans_{side}*.tsv")))

    for side in ("front", "srv"):
        en = fetch_en(side, workdir)
        old = load_local(side)
        en_flat = dict(flat(en))
        old_flat = dict(flat(old))
        missing = {k: v for k, v in en_flat.items() if k not in old_flat}
        trans = load_tsv(trans_paths[side])
        trans = {k: normalize_punct(v) for k, v in trans.items()}

        errors = []
        # カバレッジ
        untranslated = set(missing) - set(trans)
        if untranslated:
            errors.append(f"{LOCAL_FILES[side]}: 未翻訳 {len(untranslated)} 件 (例: {sorted(untranslated)[:5]})")
        unknown = set(trans) - set(missing)
        if unknown:
            errors.append(f"{LOCAL_FILES[side]}: enに存在しない翻訳 {len(unknown)} 件 (例: {sorted(unknown)[:5]})")
        validate_translations(side, missing, trans, errors)

        if errors:
            print(f"=== {LOCAL_FILES[side]}: 検証エラー {len(errors)} 件 ===")
            for e in errors[:30]:
                print(f"  {e}")
            if len(errors) > 30:
                print(f"  ... ほか {len(errors) - 30} 件")
            sys.exit(1)

        # --- 再構築 ---
        if side == "front":
            def build(node, prefix=""):
                if isinstance(node, dict):
                    out = collections.OrderedDict()
                    for k, v in node.items():
                        out[k] = build(v, f"{prefix}.{k}" if prefix else k)
                    return out
                if prefix in old_flat:
                    return old_flat[prefix]
                if prefix in trans:
                    return trans[prefix]
                print(f"WARNING: 翻訳がなくenの値をフォールバック: {prefix}")
                return node

            new = build(en)
            # カスタムキー (settings.language.options.ja) を末尾に追加
            new.setdefault("settings", {}).setdefault("language", {}).setdefault("options", {})
            for k, v in CUSTOM_KEEP[side].items():
                *parents, last = k.split(".")
                node = new
                for part in parents:
                    node = node.setdefault(part, {})
                if last not in node:
                    node[last] = old_flat.get(k, v)
        else:
            new = collections.OrderedDict()
            for k, v in en.items():
                new[k] = old_flat.get(k, trans.get(k, v))

        out = REPO / LOCAL_FILES[side]
        text = json.dumps(new, ensure_ascii=False, indent=INDENT[side]) + "\n"
        assert not text.startswith("﻿"), "BOMは書き出せません"
        out.write_text(text, encoding="utf-8")
        print(f"{LOCAL_FILES[side]}: 再構築 OK ({len(text.encode('utf-8'))} bytes, indent={INDENT[side]})")

    # 最終検証: JSONとして読み返し、BOM無しを確認
    for side in ("front", "srv"):
        raw = (REPO / LOCAL_FILES[side]).read_bytes()
        assert not raw.startswith(b"\xef\xbb\xbf"), f"{LOCAL_FILES[side]} にBOMが付きました"
        json.loads(raw.decode("utf-8"))
    print("検証完了: JSON有効 / BOMなし")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workdir", default=str(DEFAULT_WORKDIR), help="スナップショット/TSVの作業ディレクトリ")
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("check", help="上流との差分サマリを表示")
    c.add_argument("--show", type=int, default=20, help="キーの表示件数上限")
    c.set_defaults(fn=cmd_check)

    e = sub.add_parser("export", help="未翻訳キーをTSVで書き出す")
    e.set_defaults(fn=cmd_export)

    m = sub.add_parser("merge", help="翻訳済みTSVをマージして再構築 (nargs複数可、省略時はworkdirのtrans_*.tsv)")
    m.add_argument("tsv", nargs="*", help="翻訳済みTSV (front/srvをファイル名で判別)")
    m.set_defaults(fn=cmd_merge)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
