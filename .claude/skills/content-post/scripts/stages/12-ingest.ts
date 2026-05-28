/**
 * scripts/stages/12-ingest.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 12: INSERT path via /api/ingest (Wave 11.3a default path).
 *
 * Pure function:
 *   - ingestNew(args): build IngestPayload from confirmedMeta + rendered html,
 *     call deps.ingestViaApi, return the resulting content id.
 *
 * Stage descriptor:
 *   - stage12Ingest.run(ctx): runs only when !dryRun && !update. Populates
 *     ctx.contentId on success.
 *
 * Design intent (動作保存):
 *   - 元 post.ts runOne 703-760 行と動作完全一致.
 *   - tag_ids = existing tag IDs from confirmedMeta; tag_names_new = new ones.
 *   - apiType mapping: tech_articles→article / weekly_issues→issue / default knowledge.
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps, KnowledgeKind } from "../post.js";
import { DEFAULT_KNOWLEDGE_KIND } from "../post.js";
import {
  ingestViaApi as ingestViaApiImpl,
  type IngestPayload,
} from "../../src/posting/api-client.js";
import { deriveSummary } from "../helpers/type-mapping.js";

export interface IngestArgs {
  title: string;
  slug: string;
  contentType: string;
  /**
   * #58 Step 1: knowledge.kind。type が knowledge のときのみ payload に反映。
   * 省略時は "concept" (後方互換)。
   */
  knowledgeKind?: KnowledgeKind;
  frontmatter: Record<string, unknown>;
  parsedRaw: string;
  renderedHtml: string;
  confirmedMeta: {
    category: { slug: string };
    tags: Array<{ name: string; id?: string; isNew: boolean }>;
  } | null;
  thumbnailCdnUrl: string | null;
  relatedKnowledgeIds: string[];
  deps: PostDeps;
  log: (s: string) => void;
}

export async function ingestNew(args: IngestArgs): Promise<string> {
  const {
    title,
    slug,
    contentType,
    knowledgeKind,
    frontmatter,
    parsedRaw,
    renderedHtml,
    confirmedMeta,
    thumbnailCdnUrl,
    relatedKnowledgeIds,
    deps,
    log,
  } = args;
  const confirmedTags = confirmedMeta?.tags ?? [];
  const confirmedExistingTagIds = confirmedTags
    .filter((t) => !t.isNew && t.id)
    .map((t) => t.id as string);
  const confirmedNewTagNames = confirmedTags
    .filter((t) => t.isNew)
    .map((t) => t.name);

  const apiType = ((): IngestPayload["type"] => {
    if (contentType === "tech_articles") return "article";
    if (contentType === "weekly_issues") return "issue";
    return "knowledge";
  })();

  // #58 Step 1: kind は knowledge にのみ付与 (article/issue では undefined のまま)。
  const kind: IngestPayload["kind"] =
    apiType === "knowledge" ? (knowledgeKind ?? DEFAULT_KNOWLEDGE_KIND) : undefined;

  const ingestFn = deps.ingestViaApi ?? ingestViaApiImpl;
  const ingestResult = await ingestFn({
    type: apiType,
    kind,
    title,
    slug,
    html: renderedHtml,
    raw_markdown: parsedRaw || null,
    category_slug: confirmedMeta?.category.slug ?? "",
    summary: deriveSummary(frontmatter, parsedRaw),
    author: String(frontmatter.author ?? "") || undefined,
    tag_ids: confirmedExistingTagIds,
    tag_names_new: confirmedNewTagNames,
    related_content_ids: [],
    related_content_types: [],
    depth: 0,
    thumbnail_url: thumbnailCdnUrl,
    thumbnail_alt: (frontmatter.thumbnail_alt as string | undefined) ?? null,
    knowledge_ids: relatedKnowledgeIds.length > 0 ? relatedKnowledgeIds : undefined,
  });
  log(
    `[via-api] ingest succeeded: id=${ingestResult.id}, slug=${ingestResult.slug}, trace_id=${ingestResult.trace_id}`,
  );
  return ingestResult.id;
}

export const stage12Ingest = {
  name: "ingest" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (ctx.opts.dryRun || ctx.opts.update) return;
    if (!ctx.frontmatter || !ctx.contentType || !ctx.slug || !ctx.rendered) {
      throw new Error("stage12: frontmatter / contentType / slug / rendered must be set");
    }
    const log = (s: string) => ctx.streams.write(s);
    const title = String(ctx.frontmatter.title ?? "");
    const parsedRaw = (ctx.parsed?.raw as string | undefined) ?? "";
    const contentId = await ingestNew({
      title,
      slug: ctx.slug,
      contentType: ctx.contentType,
      knowledgeKind: ctx.opts.knowledgeKind,
      frontmatter: ctx.frontmatter,
      parsedRaw,
      renderedHtml: ctx.rendered.html,
      confirmedMeta:
        (ctx.confirmedMeta as unknown as {
          category: { slug: string };
          tags: Array<{ name: string; id?: string; isNew: boolean }>;
        } | null) ?? null,
      thumbnailCdnUrl: ctx.thumbnailCdnUrl ?? null,
      relatedKnowledgeIds: ctx.relatedKnowledgeIds ?? [],
      deps: ctx.deps,
      log,
    });
    ctx.contentId = contentId;
  },
};
