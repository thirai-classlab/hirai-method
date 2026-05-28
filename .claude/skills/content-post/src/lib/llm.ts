/**
 * LLM 呼び出し共通ラッパ (Haiku / Sonnet 振り分け、AI Gateway 経由)
 *
 * 設計書: /Users/t.hirai/work/classlab-weekly-news/docs/phase-8-posting-skill-design.md L322-333
 *
 * 使い分け表:
 *   Haiku 4.5 … 小タスク（自動タグ・NER・slug 生成・カテゴリ候補）
 *   Sonnet 4.6 … 判断タスク（自動リンク判定・WebSearch 要約・セクション補完・関連判定）
 *
 * モデル ID の確認コマンド（AI Gateway はドット区切り `claude-sonnet-4.6`、Anthropic 本体はハイフン `claude-sonnet-4-6` で命名規則が異なる点に注意）:
 *   curl -s https://ai-gateway.vercel.sh/v1/models | jq '.data[].id' | grep anthropic
 *
 * AI Gateway の model-string 記法 `provider/model-id` を使う (gateway docs L25-47 参照)
 */

import { generateText } from "ai";
import { config as loadDotenv } from "dotenv";

loadDotenv();

/**
 * 投稿パイプラインで LLM を呼ぶ 8 種類のタスク種別
 * 新しい種別を追加したら下記 `MODEL_BY_TASK` にマッピングも追加すること
 */
export type TaskKind =
  | "auto-tag"
  | "ner"
  | "slug"
  | "category-suggest"
  | "link-judge"
  | "web-summary"
  | "knowledge-summarize"
  | "section-complete"
  | "relate-judge"
  | "few-shot-synthesize"
  | "summarize";

// AI Gateway モデル文字列（ドット区切り：curl https://ai-gateway.vercel.sh/v1/models で 2026-04-18 確認済み）
// Wave D1 メモの `claude-haiku-4-5` / `claude-sonnet-4-6` はハイフン形式で AI Gateway 側で 404 になるため修正。
const HAIKU = "anthropic/claude-haiku-4.5";
const SONNET = "anthropic/claude-sonnet-4.6";

const MODEL_BY_TASK: Record<TaskKind, string> = {
  "auto-tag": HAIKU,
  ner: HAIKU,
  slug: HAIKU,
  "category-suggest": HAIKU,
  "link-judge": SONNET,
  "web-summary": SONNET,
  "knowledge-summarize": SONNET,
  "section-complete": SONNET,
  "relate-judge": SONNET,
  "few-shot-synthesize": HAIKU,
  summarize: HAIKU,
};

export interface RunLLMArgs {
  kind: TaskKind;
  prompt: string;
  /** 任意。system プロンプト */
  system?: string;
  /** デフォルト 1024（タスク毎に調整可能） */
  maxOutputTokens?: number;
  /** デフォルト 0.2（抽出・分類タスク向けの低温度） */
  temperature?: number;
}

export interface RunLLMResult {
  text: string;
  model: string;
  tokens: {
    input: number;
    output: number;
    total: number;
  };
}

/**
 * タスク種別に応じたモデルで LLM を呼び出す
 * @returns テキストとトークン使用量（監査ログ `content_generation_log.tokens` に記録用）
 * @throws ネットワークエラーや認証失敗時に ai-sdk が throw する
 */
export async function runLLM(args: RunLLMArgs): Promise<RunLLMResult> {
  if (!args.prompt || args.prompt.trim().length === 0) {
    throw new Error("runLLM: prompt must be non-empty");
  }

  const model = MODEL_BY_TASK[args.kind];
  if (!model) {
    throw new Error(`runLLM: unknown TaskKind "${args.kind}"`);
  }

  const { text, usage } = await generateText({
    model,
    system: args.system,
    prompt: args.prompt,
    maxOutputTokens: args.maxOutputTokens ?? 1024,
    temperature: args.temperature ?? 0.2,
  });

  return {
    text,
    model,
    tokens: {
      input: usage.inputTokens ?? 0,
      output: usage.outputTokens ?? 0,
      total: usage.totalTokens ?? 0,
    },
  };
}

/**
 * どのモデルに振り分けられるかを問い合わせるユーティリティ
 * （監査ログやコスト試算で利用）
 */
export function modelForTask(kind: TaskKind): string {
  return MODEL_BY_TASK[kind];
}
