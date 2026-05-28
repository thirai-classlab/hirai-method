/**
 * scripts/post-types.ts — Task #56 W3 (11.3d-C)
 *
 * Public type surface for scripts/post.ts. Split out so post.ts can stay
 * within the ≤150-line budget while still exporting these interfaces from
 * its public API surface (tests import them via "../scripts/post.js").
 */
import type { ProcessPlantUMLOptions } from "../src/lib/plantuml-processor.js";
import type { loadTemplates } from "../src/lib/templates.js";
import type { ingestViaApi as ingestViaApiImpl } from "../src/posting/api-client.js";
import type { validateInput } from "../src/posting/validate.js";
import type { parseMarkdown } from "../src/lib/markdown.js";
import type {
  ProcessImagesOptions,
  ImageReplacement,
} from "../src/lib/image-processor.js";
import type {
  ThumbnailHearingDeps,
  ThumbnailHearingInput,
  ThumbnailHearingResult,
} from "../src/posting/thumbnail-hearing.js";

/** Captured stdout / stderr streams (injectable for tests). */
export interface Streams {
  out: string[];
  err: string[];
  write(line: string): void;
  writeErr(line: string): void;
}

export interface PostDeps {
  loadFile: (path: string) => Promise<string>;
  loadTemplates?: typeof loadTemplates;
  ingestViaApi?: typeof ingestViaApiImpl;
  validate: typeof validateInput;
  parseMarkdown: typeof parseMarkdown;
  renderToHtml: (
    source: string,
    template: unknown,
  ) => { html: string; appliedClasses: string[] };
  renderToHtmlAsync: (
    source: string,
    template: unknown,
    options?: ProcessPlantUMLOptions,
  ) => Promise<{ html: string; appliedClasses: string[]; plantumlReplacements?: unknown[] }>;
  generateSlug: (title: string, contentType: string, client: unknown) => Promise<string>;
  ensureUniqueSlug: (base: string, contentType: string, client: unknown) => Promise<string>;
  assertSlugAvailable?: (slug: string, contentType: string, client: unknown) => Promise<void>;
  generateEmbedding: (text: string) => Promise<number[]>;
  checkDuplicate: (opts: unknown) => Promise<{
    level: "ok" | "warn" | "block";
    matches: Array<{ content_id: string; similarity: number }>;
    reason: string | null;
  }>;
  suggestCategory: (input: unknown, deps: unknown) => Promise<{
    slug: string;
    name: string;
    confidence: number;
    isNew: boolean;
  }>;
  suggestTags: (input: unknown, deps: unknown) => Promise<Array<{ name: string; confidence: number }>>;
  resolveTagAgainstMasters: (candidates: unknown, client: unknown) => Promise<Array<Record<string, unknown>>>;
  confirmInteractively: (args: unknown, deps: unknown) => Promise<{
    committed: boolean;
    category: { slug: string; name: string; isNew: boolean; id?: string };
    tags: Array<{ name: string; id?: string; isNew: boolean }>;
  }>;
  getSupabaseClient: () => unknown;
  processMarkdownImages?: (
    markdown: string,
    options: ProcessImagesOptions,
  ) => Promise<{ markdown: string; replacements: ImageReplacement[] }>;
  invalidateCloudFront?: (paths: string[]) => Promise<{ id: string }>;
  uploadThumbnail?: (
    absPath: string,
    opts: { slug: string; contentType: "knowledge" | "tech_article" | "issue" },
  ) => Promise<{ cloudfrontUrl: string }>;
  searchSimilar?: (
    embedding: number[],
    opts: { limit?: number; threshold?: number },
  ) => Promise<Array<{ content_type: string; content_id: string; similarity: number }>>;
  runThumbnailHearing?: (
    input: ThumbnailHearingInput,
    deps: ThumbnailHearingDeps,
  ) => Promise<ThumbnailHearingResult>;
  thumbnailHearingDeps?: ThumbnailHearingDeps;
  publishContent?: (opts: {
    kind: "tech_article" | "issue" | "knowledge";
    slug: string;
  }) => Promise<{
    success: boolean;
    published_at: string;
    revalidated: string[];
    already_published?: boolean;
  }>;
  webSearch: { search: (q: string) => Promise<unknown[]> };
  reader: { question: (prompt: string) => Promise<string>; close: () => void };
  streams: Streams;
  env: Record<string, string | undefined>;
  expandGlob?: (pattern: string) => Promise<string[]>;
  contentsManageDir?: string;
  enrichLinkCards?: (html: string) => Promise<string>;
}

/**
 * #58 Step 1: knowledge.kind 列の 3 値 (サイト側 Task #57 で追加)。
 * `--kind` 引数の唯一の真実源 (DRY)。`weekly_issues` / `tech_articles` には無関係。
 */
// kind の SSoT は本リポ classlab-weekly-news の DB CHECK 制約 knowledge_kind_check (migration 20260527005417)。値追加時は本リポ kind-weighting.ts / route.ts ALLOWED_KNOWLEDGE_KINDS と同期
export const KNOWLEDGE_KINDS = ["concept", "operation", "domain_knowledge"] as const;
export type KnowledgeKind = (typeof KNOWLEDGE_KINDS)[number];
/** `--kind` 省略時の後方互換デフォルト (#58 Step 1)。 */
export const DEFAULT_KNOWLEDGE_KIND: KnowledgeKind = "concept";

export interface ParsedOptions {
  file?: string;
  batch?: string;
  dryRun: boolean;
  autoApprove: boolean;
  update: boolean;
  slug?: string;
  force: boolean;
  verbose: boolean;
  thumbnailHearing: boolean;
  publish: boolean;
  linkCheck: boolean;
  linkCheckStrict: boolean;
  /**
   * #58 Step 1: knowledge コンテンツの kind。`--kind` 省略時は "concept"
   * (後方互換)。`contentType === "knowledge"` のときのみ ingest payload に反映。
   */
  knowledgeKind: KnowledgeKind;
}
