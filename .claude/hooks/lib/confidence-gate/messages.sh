#!/usr/bin/env bash
# messages.sh — confidence-gate の block reason text 生成
#
# 提供関数:
#   build_no_match_reason <threshold>     — confidence 未記載 block の reason text
#   build_below_threshold_reason <score> <threshold>
#                                         — confidence 閾値未満 block の reason text

build_no_match_reason() {
  local threshold="$1"
  local reason="[confidence-gate] サブエージェントの completion summary に confidence 自己評価が見つかりません。

期待 format:
  confidence: 0.X    （0.0〜1.0、現在の閾値 = ${threshold}）

confidence 算出基準:
  0.9-1.0  全条件を実測値で確認（build/test/grep の生 log 引用可）
  0.7-0.8  主要条件は確認、周辺は推定（一部 grep 未実行など）
  0.5-0.6  実装は完了したが検証が浅い、あるいは未確認の前提に依存
  0.0-0.4  方針が不明確、あるいは曖昧な仮実装

記載例:
  '実装完了。\$IMPL_FILE に 3 関数追加、5 件の unit test PASS、grep で caller 4 ファイル変更不要を確認。confidence: 0.85'

Bypass:
  /gate-bypass confidence <reason>     # 次回 1 回だけ pass
  ECC_CONFIDENCE_GATE=off              # セッション全体で OFF
  HC_CONFIDENCE_REQUIRED=false         # config レベル OFF"
  # 旧 inline 実装と同じ ${threshold} の literal `\${threshold}` 置換を維持 (互換性保持)
  reason="${reason//\$\{threshold\}/$threshold}"
  printf '%s' "$reason"
}

build_below_threshold_reason() {
  local score="$1"
  local threshold="$2"
  printf '%s' "[confidence-gate] confidence ${score} が閾値 ${threshold} 未満です。

サブエージェントの自己評価が低い状態で完了宣言を返しています。
以下のいずれかで対処してください:

1. 不足している検証を追加実行し、confidence を再評価する
   - build/test の実測 log を取得
   - grep / Read で前提（caller, schema, env 等）を確認
   - 失敗ケース / edge case を 1 つでも実測

2. confidence を上げられない事情があれば、未解決事項を箇条書きで明示し
   /finish-task ではなく user に判断を仰ぐ

3. やむを得ず通過させる場合:
   /gate-bypass confidence <理由>      # 次回 1 回だけ pass
   ECC_CONFIDENCE_GATE=off              # セッション全体で OFF"
}
