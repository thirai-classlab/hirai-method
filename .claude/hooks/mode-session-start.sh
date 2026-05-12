#!/usr/bin/env bash
# mode-session-start.sh — SessionStart hook
#
# 役割:
#   - セッション開始時に現在の HIRAI メソッド動作モードを表示
#   - normal モードのときは「Loop モードに切り替えますか?」をユーザに提案させる
#   - loop モードのときは loop ルールを再宣言
#
# 失敗時の挙動: exit 0 のみ。失敗してもセッションをブロックしない。

set -euo pipefail

# stdin は SessionStart hook では使わないが、念のため消費
cat > /dev/null 2>&1 || true

# モードローダーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mode-loader.sh
if [ -f "$SCRIPT_DIR/lib/mode-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/mode-loader.sh"
  MODE=$(load_mode)
else
  MODE="normal"
fi

# --- Session resume prompt (W2 of task #7) ---
# Serena memory に session/context が存在する場合、user に /resume-state 実行を提案する。
# Serena は memory key (slash 区切り) を `.serena/memories/<key>.md` に保存する。
# 失敗時は silent (hook 全体は exit 0)。
SESSION_CONTEXT_FILE=".serena/memories/session/context.md"
if [ -f "$SESSION_CONTEXT_FILE" ]; then
  cat <<'EOF'
<system-reminder>
**前回セッション状態を検出しました**

`.serena/memories/session/context.md` に前回 session の snapshot が保存されています。

続きから作業する場合は、最初の応答で **必ず以下を 1 度だけ提案** してください:

> 「前回セッション状態が見つかりました。続きから作業しますか?
>   - はい → `/resume-state` (または `/pm-start`) を実行
>   - いいえ → 新規 prompt で作業開始 (前回状態は破棄せず保持)」

ユーザが拒否 / 無視した場合は新規 session として開始してください (再提案は不要)。
</system-reminder>
EOF
fi

if [ "$MODE" = "loop" ]; then
  cat <<'EOF'
<system-reminder>
**HIRAI メソッド: Loop モード 稼働中**

このセッションは Loop モードで動作します。以下を遵守してください:

1. **AI 推奨方法を即採用**: 各ステップで複数選択肢がある場合、ユーザに確認を求めず、Why × 5 で評価した上で推奨方法を直ちに採用して実装を継続する。
2. **中間確認の停止**: 「進めてもよいですか?」「どちらにしますか?」等の確認質問を出さない。
3. **継続実装**: タスクが分割できる場合、自律的に分解し最後まで通す。
4. **停止条件は 3 つのみ**:
   - ユーザの明示的な停止指示（"stop" / "ストップ" / "止めて" 等）
   - タスクの完了
   - 致命的エラー（権限拒否 / 復旧不能な状態 / 重大なデータ破壊リスク）
5. **Why × 5 表示は維持**: ユーザ確認は省略しても、思考過程の透明性は失わない。
6. **適切な粒度でコミット**（必須）: 自律実装中も論理単位（1 機能 / 1 修正 / 1 リファクタ）ごとに `git commit` を切る。各コミットは独立動作可能な状態（テスト通過 / build green）を保ち、Conventional Commits 形式のメッセージをつける。問題発生時に `git revert` / `git reset --hard <sha>` で戻せるようにする。巨大コミットは禁止。

Loop モードを終了するには: `/mode normal`
</system-reminder>
EOF
else
  cat <<'EOF'
<system-reminder>
**HIRAI メソッド: Normal モード（現在）**

本セッションは通常モードで動作します（重要分岐でユーザ確認を取りながら進めます）。

長い実装タスクや一気通貫の作業を予定している場合、**Loop モード**（停止指示まで AI 推奨方法で実装し続ける）への切り替えが選択肢です。

このセッションの最初の応答で、ユーザに **必ず以下を 1 度だけ提案** してください:

> 「現在 Normal モードです。停止指示まで AI 推奨方法で実装し続ける **Loop モード** に切り替えますか?  `/mode loop` で切替可能です。」

ユーザが「loop」「ループ」「切替えて」等で同意した場合、`/mode loop` を実行してモード切替を行ってください。

ユーザが拒否 / 無視した場合、Normal モードを継続してください（再提案は不要）。
</system-reminder>
EOF
fi

exit 0
