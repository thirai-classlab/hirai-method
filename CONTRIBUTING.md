# Contributing to 平井メソッド (hirai-method)

ご関心ありがとうございます。本ハーネスは個人開発の運用知見を凝縮したものですが、Issue / PR は歓迎します。

## バグ報告

`.github/ISSUE_TEMPLATE/bug_report.md` を使ってください。

最低限の情報:

- 使用 OS と Claude Code のバージョン
- 再現手順（hook ログの出力含む）
- 期待した挙動と実際の挙動
- `.claude/harness-config.yml` の差分（あれば）

## 機能要望

`.github/ISSUE_TEMPLATE/feature_request.md` を使ってください。

5 層自己改善（L1〜L5）／ 3 層事実検証（F1〜F3）にどう統合できるかを書いていただけると採用判断が速くなります。

## Pull Request

1. fork → feature branch（`feat/<short-slug>` または `fix/<short-slug>`）
2. 変更は最小単位で
3. Conventional Commits 形式（`feat:` `fix:` `refactor:` 等）
4. hook を追加・変更した場合は `docs/INVENTORY.md` を更新
5. 設定 path / config key を変えた場合は `docs/PORTABILITY.md` を更新

## Style

- bash hook は `set -euo pipefail` を必須
- Python script は標準ライブラリのみ（外部依存追加は議論してから）
- ドキュメントは Markdown + Mermaid（hook で構文検証される）

## 開発ポリシー

本ハーネス自身の開発にも同じハーネスを当てています。Edit/Write を直接行わず、サブエージェント委譲・GateGuard・Confidence Gate を通すことを推奨します。

## Code of Conduct

技術的な議論は歓迎しますが、攻撃的な言動は禁止します。
