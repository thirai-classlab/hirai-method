/**
 * src/posting/thumbnail-hearing.ts — Task #32 セッション 2
 *
 * frontmatter.thumbnail が未指定の投稿に対して、対話ヒアリングを介した
 * サムネイル自動生成パスを提供する。本リポ classlab-weekly-news 側の
 * `output/gen-news-thumbnail.mjs` を child_process 経由で呼び出す。
 *
 * 設計書: classlab-weekly-news/docs/thumbnail-hearing-flow.md
 *
 * 構成:
 *   - 純粋関数: extractHeadlineCandidates / filterPatternsByCategory / buildGeneratorArgs
 *   - 統合関数: runThumbnailHearing (DI 経由で promptUser / spawnGenerator / readPatternsConfig を注入)
 *
 * 全外部境界 (fs / readline / child_process) は ThumbnailHearingDeps を介して
 * 抽象化されているため、テストでは pure な mock を差し込む。
 */

import type { KnowledgeKind } from "../../scripts/post-types.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ThumbnailPatternDef {
  label?: string;
  tone?: string;
  category_lock?: string;
  /**
   * #58 Step 4: knowledge カテゴリ内の kind 限定 (operation / domain_knowledge)。
   * 未指定 = kind 非依存 (concept / 旧 K-* と同様、どの kind でも候補になりうる)。
   */
  kind_lock?: string;
  description?: string;
}

export interface ThumbnailCategoryDef {
  patterns: string[];
  default_count?: number;
  description?: string;
}

/**
 * #58 Step 4: knowledge カテゴリ内の kind (concept / operation / domain_knowledge)
 * 別 pattern マッピング。operation/domain_knowledge は master tag (部署/業界) 別に
 * 色味・モチーフの異なるパターンを引く。
 */
export interface ThumbnailKindDef {
  /** "department" | "industry" 等 (説明用、ロジックには未使用) */
  axis?: string;
  /** tag 未選択 / 未登録時のフォールバック pattern 群 */
  default_patterns?: string[];
  /** master tag slug → pattern 群 (例: "system-tech-lead" → ["T403","T404"]) */
  tag_patterns?: Record<string, string[]>;
  description?: string;
}

export interface ThumbnailPatternsConfig {
  version: string;
  categories: Record<string, ThumbnailCategoryDef>;
  /** #58 Step 4: kind 別マッピング。未定義の旧 config では categories fallback。 */
  knowledge_kinds?: Record<string, ThumbnailKindDef>;
  patterns: Record<string, ThumbnailPatternDef>;
  llm_model?: string;
}

/**
 * AI による用途別パターン自動選択。同一カテゴリに複数パターンが登録されている場合
 * (例: knowledge = K-HERO / K-INLINE / K-OUTRO)、記事メタデータから AI が
 * 最適な 1 つを選択する。
 *
 * - 戻り値が `null` または `allowed` に含まれない ID の場合、呼び出し側は
 *   先頭デフォルトにフォールバックする責務を持つ。
 * - API キー欠落 / ネットワーク失敗時も `null` を返す (throw しない)。
 */
export interface PatternSelectorInput {
  contentType: ThumbnailContentType;
  title: string;
  body: string;
  headlines: string[];
  allowed: string[];
  /** id → "label — description" 形式の候補一覧 (AI への提示用) */
  patternDescriptions: Record<string, string>;
  /** AI Gateway 経由で呼ぶモデル ID (省略時はデフォルト Haiku) */
  llmModel?: string;
}

export type PatternSelector = (
  input: PatternSelectorInput,
) => Promise<string | null>;

export interface ThumbnailHearingDeps {
  /**
   * 本リポ output/thumbnail-patterns.json を読み込む。
   * 環境変数 CLASSLAB_WEEKLY_NEWS_DIR を解決する責務もこの実装に持たせる。
   */
  readPatternsConfig: () => Promise<ThumbnailPatternsConfig>;

  /** readline ベースの 1 行プロンプト。改行除去後の文字列を返す。 */
  promptUser: (question: string) => Promise<string>;

  /**
   * child_process.spawn 経由で gen-news-thumbnail.mjs を呼び出す。
   * `--out` の値と `--pattern` のカンマ区切り個数から最終出力ファイル群を
   * 計算して `files` に返す。生成失敗時は ok=false。
   */
  spawnGenerator: (args: string[]) => Promise<{ files: string[]; ok: boolean }>;

  /**
   * 用途別パターンの AI 自動選択。注入されない場合は selector を呼ばず、
   * 先頭の `default_count` 件をデフォルト採用する従来挙動になる。
   */
  selectPattern?: PatternSelector;

  /** 進捗ログ (省略可、未指定時は console.log) */
  logger?: (msg: string) => void;
}

export type ThumbnailContentType =
  | "weekly_issues"
  | "tech_articles"
  | "knowledge";

export interface ThumbnailHearingInput {
  contentType: ThumbnailContentType;
  title: string;
  body: string;
  tags?: string[];
  /**
   * #58 Step 4: knowledge コンテンツの kind (concept | operation | domain_knowledge)。
   * `contentType === "knowledge"` のときのみ意味を持つ。operation/domain_knowledge は
   * tags (部署/業界 master slug) と合わせて kind 別パターン (T395-T422) を選択する。
   * 省略時は concept 扱い = 既存 K-* 経路 (後方互換)。
   * #58 round-2 (M7): `string` → post-types.ts の KnowledgeKind に型安全化。
   */
  knowledgeKind?: KnowledgeKind;
  frontmatterThumbnail?: string;
  /** ヒアリングを完全 skip し、デフォルトパターンで自動生成のみ行う */
  autoApprove?: boolean;
  /** 生成は呼ばずに skip フラグだけ立てる (S3/DB 反映なし) */
  dryRun?: boolean;
  /** 生成画像の出力先 (絶対パス推奨)。省略時は /tmp/<slug or hash>.png */
  outputPath?: string;
}

export interface ThumbnailHearingResult {
  /** 実際に画像生成 spawn が走り files が得られたら true */
  generated: boolean;
  /** 採択された 1 枚 (複数生成時は先頭) */
  thumbnailPath: string | null;
  /** 生成されたすべての候補 (A/B など) */
  candidates: string[];
  /** 採択されたパターン (CSV 形式: 単一 "T394" / 複数 "T394,T363") */
  pattern: string | null;
  /** ヒアリング省略 (frontmatter 指定 / autoApprove / weekly_issues) */
  hearingSkipped: boolean;
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

const HEADLINE_REGEX = /^(#{1,2})\s+(.+?)\s*$/gm;

/**
 * Markdown 本文から h1 / h2 見出しテキストを抽出する。
 *   - h3 以降は無視
 *   - 重複は順序を保ったまま除外
 *   - max 件数で切り詰め
 *   - 空本文 → []
 */
export function extractHeadlineCandidates(body: string, max = 6): string[] {
  if (typeof body !== "string" || !body.trim()) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  // exec ループ (callback コールではない、replace の特殊置換は無関係)
  const src = body;
  let match: RegExpExecArray | null;
  // Reset lastIndex on the shared RegExp by re-creating per call.
  const re = new RegExp(HEADLINE_REGEX.source, HEADLINE_REGEX.flags);
  while ((match = re.exec(src)) !== null) {
    const text = (match[2] ?? "").trim();
    if (!text) continue;
    if (seen.has(text)) continue;
    seen.add(text);
    out.push(text);
    if (out.length >= max) break;
  }
  return out;
}

/**
 * カテゴリに登録された pattern 一覧から、category_lock 違反を除外して返す。
 *   - lock なし pattern → 任意のカテゴリで OK
 *   - lock === category → OK
 *   - lock !== category → 除外
 */
export function filterPatternsByCategory(
  config: ThumbnailPatternsConfig,
  category: string,
): string[] {
  const cat = config.categories?.[category];
  if (!cat || !Array.isArray(cat.patterns)) return [];
  const out: string[] = [];
  for (const id of cat.patterns) {
    const def = config.patterns?.[id];
    if (!def) continue;
    if (def.category_lock && def.category_lock !== category) continue;
    out.push(id);
  }
  return out;
}

/**
 * #58 Step 4: knowledge カテゴリ内で kind (concept / operation / domain_knowledge) と
 * master tag (部署 / 業界 slug) に応じた pattern 群を選択する純粋関数。
 *
 *   - concept または knowledge_kinds 未定義 → categories.knowledge.patterns を
 *     filterPatternsByCategory 経由で返す (後方互換、K-* 経路)。
 *   - operation / domain_knowledge:
 *       1. tags を先頭から走査し、tag_patterns に登録された最初の tag を採用
 *       2. 該当 tag があれば tag_patterns[tag]
 *       3. なければ kind の default_patterns
 *   - いずれの分岐でも、patterns に実在し category_lock=knowledge と
 *     (kind_lock が付く場合) kind 一致を満たす ID のみ返す (lock 整合)。
 *
 * 戻り値が空の場合、呼び出し側は filterPatternsByCategory(knowledge) へ
 * フォールバックする責務を持つ。
 */
export function selectKindTagPatterns(
  config: ThumbnailPatternsConfig,
  kind: KnowledgeKind,
  tags: string[],
): string[] {
  const kinds = config.knowledge_kinds;
  // 旧 config / concept は既存 knowledge 経路へ委譲 (後方互換)。
  if (!kinds || kind === "concept" || !kinds[kind]) {
    return filterPatternsByCategory(config, "knowledge");
  }
  const def = kinds[kind]!;
  const tagMap = def.tag_patterns ?? {};
  let chosen: string[] | undefined;
  for (const t of tags) {
    if (Array.isArray(tagMap[t])) {
      chosen = tagMap[t];
      break;
    }
  }
  if (!chosen) chosen = def.default_patterns;
  const candidates = Array.isArray(chosen) ? chosen : [];
  return candidates.filter((id) => isPatternUsableForKind(config, id, kind));
}

/**
 * pattern が指定 kind の knowledge サムネとして使えるか。
 *   - patterns に実在すること
 *   - category_lock 不在 または category_lock === "knowledge"
 *   - kind_lock 不在 (kind 非依存) または kind_lock === kind
 */
function isPatternUsableForKind(
  config: ThumbnailPatternsConfig,
  id: string,
  kind: KnowledgeKind,
): boolean {
  const def = config.patterns?.[id];
  if (!def) return false;
  if (def.category_lock && def.category_lock !== "knowledge") return false;
  if (def.kind_lock && def.kind_lock !== kind) return false;
  return true;
}

export interface BuildGeneratorArgsInput {
  patterns: string[];
  title: string;
  headlines: string[];
  outputPath: string;
  styleHint?: string;
}

/**
 * gen-news-thumbnail.mjs に渡す引数配列を組み立てる。
 *   --pattern T394
 *   --title  "..."
 *   --headlines "h1|h2|h3"
 *   --out    /abs/path.png
 *   --scene  "..."   (styleHint がある時のみ)
 */
export function buildGeneratorArgs(input: BuildGeneratorArgsInput): string[] {
  const args: string[] = [];
  args.push("--pattern", input.patterns.join(","));
  args.push("--title", input.title);
  if (input.headlines.length > 0) {
    args.push("--headlines", input.headlines.join("|"));
  } else {
    args.push("--headlines", "");
  }
  args.push("--out", input.outputPath);
  if (typeof input.styleHint === "string" && input.styleHint.trim()) {
    args.push("--scene", input.styleHint.trim());
  }
  return args;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function noopLogger(): (m: string) => void {
  return () => {};
}

function defaultOutputPath(input: ThumbnailHearingInput): string {
  // タイトルからスラッグっぽい文字列を作って /tmp 配下に置く。
  // 既存実装の slugify を呼ぶと依存が増えるので、安全な簡易版を使う。
  const safeTitle =
    (input.title || "thumb")
      .toLowerCase()
      .replace(/[^a-z0-9-]+/g, () => "-")
      .replace(/^-+|-+$/g, () => "")
      .slice(0, 40) || "thumb";
  const ts = Date.now();
  return `/tmp/${safeTitle}-${ts}.png`;
}

interface HearingAnswers {
  patterns: string[];
  title: string;
  headlines: string[];
  styleHint: string;
}

/**
 * カテゴリ別 pattern 候補から「自動採用すべき pattern」を返す。
 *
 *   weekly_issues:
 *     cat.patterns をそのまま (T394 のように lock 付きが正解)。
 *
 *   それ以外 (knowledge / tech_articles):
 *     - 候補が 2 つ以上かつ AI selector + 記事メタデータが与えられた場合は AI 選択
 *     - AI が無効・失敗・知らないパターンを返した場合は先頭 default_count 件
 */
async function pickDefaultPatterns(
  config: ThumbnailPatternsConfig,
  contentType: ThumbnailContentType,
  content: { title: string; body: string; headlines: string[] } | null,
  selector: PatternSelector | undefined,
  log: (msg: string) => void,
  kindSelection?: string[],
): Promise<string[]> {
  const cat = config.categories?.[contentType];
  if (!cat) return [];
  if (contentType === "weekly_issues") {
    return cat.patterns.slice();
  }
  // #58 Step 4: knowledge かつ kind 別候補が与えられたら category 候補を置換。
  const allowed =
    kindSelection && kindSelection.length > 0
      ? kindSelection
      : filterPatternsByCategory(config, contentType);
  const fallbackCount = cat.default_count ?? 1;
  const fallback = allowed.slice(0, fallbackCount);

  if (allowed.length <= 1 || !selector || !content) return fallback;

  const patternDescriptions: Record<string, string> = {};
  for (const id of allowed) {
    const def = config.patterns[id];
    const label = def?.label ?? id;
    const desc = def?.description ?? "";
    patternDescriptions[id] = desc ? `${label} — ${desc}` : label;
  }

  try {
    const picked = await selector({
      contentType,
      title: content.title,
      body: content.body,
      headlines: content.headlines,
      allowed,
      patternDescriptions,
      llmModel: config.llm_model,
    });
    if (picked && allowed.includes(picked)) {
      log(
        `[thumbnail] AI 自動選択: pattern=${picked} (候補 ${allowed.join(",")})`,
      );
      return [picked];
    }
    log(
      `[thumbnail] AI 選択無効 (戻り値=${String(picked)}) → 先頭デフォルト ${fallback.join(",")} を採用`,
    );
  } catch (e) {
    log(
      `[thumbnail] AI 選択失敗 (${String((e as Error)?.message ?? e)}) → 先頭デフォルト ${fallback.join(",")} を採用`,
    );
  }
  return fallback;
}

/**
 * パターン選択プロンプト。番号入力 / パターン ID 入力の両方を受け付け、
 * lock 違反 / 未登録を弾いて再質問する。
 * Enter (空入力) のフォールバックでは AI selector が利用可能な場合に呼ばれる。
 */
async function askPatternSelection(
  deps: ThumbnailHearingDeps,
  config: ThumbnailPatternsConfig,
  contentType: ThumbnailContentType,
  content: { title: string; body: string; headlines: string[] } | null,
  kindSelection?: string[],
): Promise<string[]> {
  // #58 Step 4: knowledge かつ kind 別候補が与えられたら category 候補を置換。
  const allowed =
    kindSelection && kindSelection.length > 0
      ? kindSelection
      : filterPatternsByCategory(config, contentType);
  if (allowed.length === 0) {
    throw new Error(
      `[thumbnail-hearing] no patterns available for category "${contentType}"`,
    );
  }
  const log = deps.logger ?? noopLogger();
  const lines = allowed.map((id, i) => {
    const def = config.patterns[id];
    const label = def?.label ?? "(no label)";
    return `  ${i + 1}. ${id}  ${label}`;
  });
  const message = [
    "",
    `[thumbnail] パターンを選択してください (${contentType}):`,
    ...lines,
    "  番号 (例: 1) または ID (例: T363) を入力。複数指定はカンマ区切り (例: 1,2)。",
    "  Enter で AI 自動選択 (フォールバックはデフォルト)。",
    "> ",
  ].join("\n");

  // リトライループ (最大 5 回)
  for (let attempt = 0; attempt < 5; attempt++) {
    const raw = (await deps.promptUser(message)).trim();
    if (raw === "") {
      const def = await pickDefaultPatterns(
        config,
        contentType,
        content,
        deps.selectPattern,
        log,
        kindSelection,
      );
      log(`[thumbnail] パターン未入力 → 採用: ${def.join(",")}`);
      return def;
    }
    const tokens = raw.split(",").map((t) => t.trim()).filter(Boolean);
    const resolved: string[] = [];
    let invalid = false;
    for (const t of tokens) {
      const asIndex = Number.parseInt(t, 10);
      let id: string | undefined;
      if (Number.isFinite(asIndex) && asIndex >= 1 && asIndex <= allowed.length) {
        id = allowed[asIndex - 1];
      } else if (allowed.includes(t)) {
        id = t;
      }
      if (!id) {
        log(`[thumbnail] "${t}" は許可された候補にありません。`);
        invalid = true;
        break;
      }
      resolved.push(id);
    }
    if (invalid || resolved.length === 0) continue;
    return resolved;
  }
  throw new Error(
    "[thumbnail-hearing] pattern selection: too many invalid attempts",
  );
}

/** ヒアリング c (タイトル / サブ / 見出し語) と d (style hint) */
async function askContentDetails(
  deps: ThumbnailHearingDeps,
  initialTitle: string,
  initialHeadlines: string[],
): Promise<HearingAnswers> {
  const titleAns = (
    await deps.promptUser(
      [
        "",
        `[thumbnail] タイトル (現在: "${initialTitle}")`,
        "  Enter で現在値を維持、書き換える場合は新しい文字列を入力。",
        "> ",
      ].join("\n"),
    )
  ).trim();
  const subtitleAns = (
    await deps.promptUser(
      [
        "[thumbnail] サブタイトル (任意、Enter で空欄)",
        "> ",
      ].join("\n"),
    )
  ).trim();
  const headlineDefault = initialHeadlines.join(" / ");
  const headlinesAns = (
    await deps.promptUser(
      [
        `[thumbnail] 見出し語 (候補: ${headlineDefault || "(なし)"})`,
        "  Enter で候補そのまま、書き換える場合は ' / ' 区切りで入力。",
        "> ",
      ].join("\n"),
    )
  ).trim();
  const styleAns = (
    await deps.promptUser(
      [
        "[thumbnail] スタイル指示 (自由記述、Enter で省略)",
        "  例: 落ち着いたパステル / モノトーン中心 / 機械的な質感 など",
        "> ",
      ].join("\n"),
    )
  ).trim();

  const finalTitle = titleAns || initialTitle;
  // タイトル + サブタイトルがある場合は合成
  const combinedTitle = subtitleAns
    ? `${finalTitle} 〜${subtitleAns}〜`
    : finalTitle;

  const headlines = headlinesAns
    ? headlinesAns
        .split("/")
        .map((h) => h.trim())
        .filter(Boolean)
    : initialHeadlines;

  return {
    patterns: [], // 親で埋める
    title: combinedTitle,
    headlines,
    styleHint: styleAns,
  };
}

/**
 * 生成 + 承認ループ。
 *   - "y" / Enter → 採用
 *   - "r"          → 同じヒアリングで再生成
 *   - "p"          → パターン選択からやり直し
 *   - "n"          → スキップ (採用しない、generated=false で抜ける)
 */
async function approvalLoop(
  deps: ThumbnailHearingDeps,
  generated: { files: string[]; pattern: string },
): Promise<"accept" | "regenerate" | "change-pattern" | "skip"> {
  const list = generated.files.map((f, i) => `  ${i + 1}. ${f}`).join("\n");
  const ans = (
    await deps.promptUser(
      [
        "",
        `[thumbnail] 生成完了 (pattern=${generated.pattern})`,
        list,
        "  y=採用 / r=再生成 / p=パターン変更 / n=スキップ",
        "> ",
      ].join("\n"),
    )
  ).trim().toLowerCase();
  if (ans === "" || ans === "y" || ans === "yes") return "accept";
  if (ans === "r") return "regenerate";
  if (ans === "p") return "change-pattern";
  if (ans === "n") return "skip";
  return "accept";
}

// ---------------------------------------------------------------------------
// Default deps (for CLI entry)
// ---------------------------------------------------------------------------

/**
 * Skill-internal resolution helpers. このファイルは
 *   <skill>/src/posting/thumbnail-hearing.ts
 * に置かれ、相対で <skill>/scripts/ を解決する。
 */
async function resolveSkillScriptPath(name: string): Promise<string> {
  const path = await import("node:path");
  const { fileURLToPath } = await import("node:url");
  const here = path.dirname(fileURLToPath(import.meta.url)); // <skill>/src/posting
  const skillRoot = path.resolve(here, "..", ".."); // <skill>
  return path.join(skillRoot, "scripts", name);
}

/**
 * Default readPatternsConfig: skill-internal の
 * scripts/thumbnail-patterns.json を読む。
 *
 * テスト時は DI で差し替えるため、この関数を直接呼ぶのは CLI 経路のみ。
 */
export async function defaultReadPatternsConfig(): Promise<ThumbnailPatternsConfig> {
  const fs = await import("node:fs/promises");
  const file = await resolveSkillScriptPath("thumbnail-patterns.json");
  const raw = await fs.readFile(file, "utf-8");
  const parsed = JSON.parse(raw) as ThumbnailPatternsConfig;
  if (!parsed.categories || !parsed.patterns) {
    throw new Error(
      `[thumbnail-hearing] invalid config at ${file}: missing categories/patterns`,
    );
  }
  return parsed;
}

/**
 * Default spawnGenerator: child_process.spawn で gen-news-thumbnail.mjs を起動する。
 * stdout/stderr は inherit して進捗を可視化、生成ファイル名は引数から計算する
 * (mjs は最終 JSON を吐かないため、--out + --pattern からこちらで決定)。
 */
export function makeDefaultSpawnGenerator(): (
  args: string[],
) => Promise<{ files: string[]; ok: boolean }> {
  return async (args: string[]) => {
    const path = await import("node:path");
    const { spawn } = await import("node:child_process");
    const script = await resolveSkillScriptPath("gen-news-thumbnail.mjs");
    return await new Promise<{ files: string[]; ok: boolean }>((resolve) => {
      const child = spawn("node", [script, ...args], {
        stdio: ["inherit", "inherit", "inherit"],
      });
      child.on("error", () => {
        resolve({ files: [], ok: false });
      });
      child.on("exit", (code) => {
        if (code !== 0) {
          resolve({ files: [], ok: false });
          return;
        }
        // resolve final paths from --out + --pattern
        const outIdx = args.indexOf("--out");
        const patIdx = args.indexOf("--pattern");
        const outPath = outIdx >= 0 ? args[outIdx + 1]! : "";
        const patList =
          patIdx >= 0 ? args[patIdx + 1]!.split(",").filter(Boolean) : [];
        const files =
          patList.length > 1
            ? patList.map((p) => outPath.replace(/(\.[^.]+)$/, () => `-${p}$1`))
            : [outPath];
        // NOTE: replace() callback returns a literal "$1" because we want the
        // captured extension. Use a real captured-value form instead:
        const fixed = files.map((f, i) => {
          if (patList.length <= 1) return f;
          const ext = path.extname(outPath);
          const stem = ext ? outPath.slice(0, -ext.length) : outPath;
          return `${stem}-${patList[i]}${ext}`;
        });
        resolve({ files: fixed, ok: true });
      });
    });
  };
}

/**
 * Default PatternSelector: Vercel AI Gateway 経由で Haiku を呼んで
 * 用途別パターンを 1 つ選ばせる。
 *
 * - `AI_GATEWAY_API_KEY` が未設定なら `null` を返してフォールバックさせる
 * - HTTP / 解析失敗時も `null` を返す (throw しない)
 * - `allowed` 配列に含まれない応答は無視
 *
 * モデルは `input.llmModel` (= thumbnail-patterns.json の `llm_model`) を
 * 優先し、欠落時は `anthropic/claude-haiku-4.5`。
 */
export function makeDefaultPatternSelector(): PatternSelector {
  return async (input) => {
    if (input.allowed.length === 0) return null;
    if (input.allowed.length === 1) return input.allowed[0] ?? null;
    const apiKey = process.env.AI_GATEWAY_API_KEY;
    if (!apiKey) return null;

    const choicesList = input.allowed
      .map((id) => `- ${id}: ${input.patternDescriptions[id] ?? id}`)
      .join("\n");
    const headlinesBlock =
      input.headlines.length > 0
        ? input.headlines.map((h) => `- ${h}`).join("\n")
        : "(見出しなし)";
    const bodyExcerpt = input.body.slice(0, 1200);

    const system = [
      "あなたは記事のタイトル・見出し・本文先頭を読み、最も適切なサムネイル用途パターンを 1 つだけ選ぶアシスタントです。",
      "出力は候補の ID 文字列のみ (例: K-HERO)。説明や前置きは含めない。",
      "候補にない ID は絶対に返さない。",
    ].join("\n");

    const user = [
      `カテゴリ: ${input.contentType}`,
      "",
      "候補パターン:",
      choicesList,
      "",
      `タイトル: ${input.title}`,
      "",
      "見出し一覧:",
      headlinesBlock,
      "",
      "本文先頭 (抜粋):",
      bodyExcerpt,
      "",
      "最も適切なパターン ID を 1 つだけ返してください。",
    ].join("\n");

    const model = input.llmModel ?? "anthropic/claude-haiku-4.5";

    try {
      const res = await fetch(
        "https://ai-gateway.vercel.sh/v1/chat/completions",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model,
            messages: [
              { role: "system", content: system },
              { role: "user", content: user },
            ],
            max_tokens: 30,
          }),
        },
      );
      if (!res.ok) return null;
      const j = (await res.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const raw = (j.choices?.[0]?.message?.content ?? "").trim();
      if (!raw) return null;
      // raw からまず完全一致、なければ部分一致で許可リスト内 ID を抽出
      if (input.allowed.includes(raw)) return raw;
      for (const id of input.allowed) {
        if (raw.includes(id)) return id;
      }
      return null;
    } catch {
      return null;
    }
  };
}

export function makeDefaultPromptUser(): (q: string) => Promise<string> {
  // readline-based one-liner reader. Created lazily per question to avoid
  // holding the interface open across the entire pipeline.
  return async (question: string) => {
    const readline = await import("node:readline/promises");
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    try {
      const ans = await rl.question(question);
      return ans;
    } finally {
      rl.close();
    }
  };
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------

export async function runThumbnailHearing(
  input: ThumbnailHearingInput,
  deps: ThumbnailHearingDeps,
): Promise<ThumbnailHearingResult> {
  const log = deps.logger ?? noopLogger();

  // 3a. frontmatter.thumbnail 指定時は完全 skip
  if (input.frontmatterThumbnail && input.frontmatterThumbnail.trim()) {
    log(
      `[thumbnail] frontmatter.thumbnail 指定済み → ヒアリング skip (${input.frontmatterThumbnail})`,
    );
    return {
      generated: false,
      thumbnailPath: null,
      candidates: [],
      pattern: null,
      hearingSkipped: true,
    };
  }

  const config = await deps.readPatternsConfig();
  const outputPath = input.outputPath ?? defaultOutputPath(input);

  // weekly_issues: ヒアリングを完全省略し categories.weekly_issues.patterns を自動採用 (現状は T394 のみ)
  // tech_articles / knowledge: autoApprove 時はヒアリング skip + default 採用
  const skipHearing =
    input.contentType === "weekly_issues" || !!input.autoApprove;

  const headlinesForSelection = extractHeadlineCandidates(input.body);
  const contentForSelection = {
    title: input.title,
    body: input.body,
    headlines: headlinesForSelection,
  };

  // #58 Step 4: knowledge かつ operation/domain_knowledge のとき、kind + tags から
  // 候補パターンを限定する。concept / 旧 config / 非 knowledge は undefined のまま
  // (= 既存 category 経路、後方互換)。
  // #58 round-2 (M8): concept は selectKindTagPatterns が K-* を返すため kindSelection が
  // 非 undefined になりコメント乖離 + 余計な log を生む。concept を明示除外して undefined に
  // 揃え、後段の filterPatternsByCategory(knowledge) 経路へ委譲する。
  const kindSelection =
    input.contentType === "knowledge" &&
    input.knowledgeKind &&
    input.knowledgeKind !== "concept"
      ? selectKindTagPatterns(config, input.knowledgeKind, input.tags ?? [])
      : undefined;
  if (kindSelection && kindSelection.length > 0) {
    log(
      `[thumbnail] kind=${input.knowledgeKind} tags=${(input.tags ?? []).join(",") || "(none)"} → 候補 ${kindSelection.join(",")}`,
    );
  }

  // ヒアリング skip 経路
  if (skipHearing) {
    const patterns = await pickDefaultPatterns(
      config,
      input.contentType,
      contentForSelection,
      deps.selectPattern,
      log,
      kindSelection,
    );
    if (patterns.length === 0) {
      throw new Error(
        `[thumbnail-hearing] no default patterns for ${input.contentType}`,
      );
    }
    if (input.dryRun) {
      log(
        `[thumbnail] dryRun: skip 生成 (would generate pattern=${patterns.join(",")})`,
      );
      return {
        generated: false,
        thumbnailPath: null,
        candidates: [],
        pattern: patterns.join(","),
        hearingSkipped: true,
      };
    }
    const args = buildGeneratorArgs({
      patterns,
      title: input.title,
      headlines: headlinesForSelection,
      outputPath,
    });
    log(`[thumbnail] generating (auto): pattern=${patterns.join(",")}`);
    const res = await deps.spawnGenerator(args);
    if (!res.ok) {
      throw new Error(
        `[thumbnail-hearing] thumbnail generator exited non-zero (pattern=${patterns.join(",")})`,
      );
    }
    return {
      generated: true,
      thumbnailPath: res.files[0] ?? null,
      candidates: res.files,
      pattern: patterns.join(","),
      hearingSkipped: true,
    };
  }

  // 対話ヒアリング経路 (tech_articles / knowledge)
  const initialHeadlines = headlinesForSelection;
  let patterns: string[] = await askPatternSelection(
    deps,
    config,
    input.contentType,
    contentForSelection,
    kindSelection,
  );
  let answers: HearingAnswers = await askContentDetails(
    deps,
    input.title,
    initialHeadlines,
  );

  // dryRun: ヒアリングは行ったが生成 spawn しない
  if (input.dryRun) {
    log(
      `[thumbnail] dryRun: ヒアリング完了、生成 skip (pattern=${patterns.join(",")})`,
    );
    return {
      generated: false,
      thumbnailPath: null,
      candidates: [],
      pattern: patterns.join(","),
      hearingSkipped: false,
    };
  }

  // 生成 + 承認ループ
  // 最大 5 回まで再試行を許容 (無限ループ防止)
  for (let iter = 0; iter < 5; iter++) {
    const args = buildGeneratorArgs({
      patterns,
      title: answers.title,
      headlines: answers.headlines,
      outputPath,
      styleHint: answers.styleHint,
    });
    log(`[thumbnail] generating: pattern=${patterns.join(",")}`);
    const res = await deps.spawnGenerator(args);
    if (!res.ok) {
      throw new Error(
        `[thumbnail-hearing] thumbnail generator exited non-zero (pattern=${patterns.join(",")})`,
      );
    }
    const decision = await approvalLoop(deps, {
      files: res.files,
      pattern: patterns.join(","),
    });
    if (decision === "accept") {
      return {
        generated: true,
        thumbnailPath: res.files[0] ?? null,
        candidates: res.files,
        pattern: patterns.join(","),
        hearingSkipped: false,
      };
    }
    if (decision === "skip") {
      return {
        generated: false,
        thumbnailPath: null,
        candidates: res.files,
        pattern: patterns.join(","),
        hearingSkipped: false,
      };
    }
    if (decision === "change-pattern") {
      patterns = await askPatternSelection(
        deps,
        config,
        input.contentType,
        contentForSelection,
        kindSelection,
      );
      answers = await askContentDetails(
        deps,
        input.title,
        initialHeadlines,
      );
      continue;
    }
    // regenerate: same hearing, new spawn
  }
  throw new Error(
    "[thumbnail-hearing] approval loop exceeded maximum iterations",
  );
}
