import { runLLM } from "../lib/llm.js";

export interface GenerateSummaryArgs {
  title: string;
  rawMarkdown: string;
  /** frontmatter.summary が指定されていれば AI 呼び出しをスキップしてそれを使う */
  explicit?: string;
}

const MIN_SUMMARY_LEN = 80;
const MAX_SUMMARY_LEN = 220;

/**
 * 記事タイトルと本文から、HTMLタグや画像参照を含まない日本語サマリーを Haiku で生成する。
 * - 失敗時は本文先頭から空白圧縮した200文字でフォールバック（NOT NULL 制約満たすため）
 * - frontmatter.summary が指定されていればそれを優先（AI 呼び出しなし）
 */
export async function generateSummary(
  args: GenerateSummaryArgs,
): Promise<string> {
  const explicit = args.explicit?.trim();
  if (explicit && explicit.length > 0) {
    return explicit;
  }

  const cleaned = stripMarkdownNoise(args.rawMarkdown);
  const truncated = cleaned.slice(0, 4000);

  if (truncated.length === 0) {
    return "(no summary)";
  }

  const prompt = [
    "次の記事タイトルと本文から、純粋な日本語のサマリーを1段落だけ生成してください。",
    "",
    "# 出力形式の制約",
    `- 文字数は ${MIN_SUMMARY_LEN}〜${MAX_SUMMARY_LEN} 文字`,
    "- 1段落、改行なし",
    "- HTMLタグ・Markdown記法・画像参照（![]() / <img>）・URL を含めない",
    "- 「この記事は〜」「本記事は〜」のような自己言及で始めず、本文の核心から書く",
    "- 日本語のみ（プロダクト名やコード値は英字 OK：例 `Claude Code`, `MCP`, `claude --resume`）",
    "- 出力は本文だけ。前置き・後置き・引用符・コードブロック禁止",
    "",
    "# 記事タイトル",
    args.title,
    "",
    "# 記事本文（冒頭抜粋）",
    truncated,
  ].join("\n");

  try {
    const r = await runLLM({
      kind: "summarize",
      prompt,
      maxOutputTokens: 600,
      temperature: 0.3,
    });
    const sanitized = sanitizeOutput(r.text);
    if (sanitized.length === 0) {
      return fallback(cleaned);
    }
    return sanitized;
  } catch {
    return fallback(cleaned);
  }
}

function stripMarkdownNoise(md: string): string {
  return md
    .replace(/^---[\s\S]*?\n---\n/, "") // strip frontmatter
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "") // ![](url)
    .replace(/<img[^>]*>/gi, "") // <img>
    .replace(/<iframe[\s\S]*?<\/iframe>/gi, "") // <iframe>
    .replace(/```[\s\S]*?```/g, "") // fenced code
    .replace(/`[^`]+`/g, " ") // inline code
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1") // [text](url) → text
    .replace(/^>\s?/gm, "") // blockquote markers
    .replace(/^#+\s+/gm, "") // headings
    .replace(/[*_~]+/g, "") // emphasis markers
    .replace(/\s+/g, " ")
    .trim();
}

function sanitizeOutput(text: string): string {
  return text
    .replace(/<[^>]+>/g, "")
    .replace(/\r?\n+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function fallback(cleaned: string): string {
  if (cleaned.length === 0) return "(no summary)";
  return cleaned.slice(0, 200);
}
