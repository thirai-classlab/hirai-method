/**
 * scripts/stages/11-category-tag.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 11: category + tag suggestion + interactive confirmation.
 *
 * Pure function:
 *   - resolveCategoryAndTags(args): fetches allowlist (Wave 11.3e), suggests
 *     category + tags, resolves against masters, runs confirmInteractively.
 *     Returns the confirmedMeta object stage 12+13 consume.
 *
 * Stage descriptor:
 *   - stage11CategoryTag.run(ctx): populates ctx.confirmedMeta. Skipped in
 *     --update mode (existing rows keep their category/tags).
 *
 * Design intent (動作保存):
 *   - 元 post.ts runOne 657-701 行と動作完全一致。
 *   - allowlist fetch 失敗時は legacy DB-match path にフォールバック。
 *   - confirmMode は dryRun > autoApprove > interactive の優先順。
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import {
  type PostDeps,
  type ParsedOptions,
  type KnowledgeKind,
  DEFAULT_KNOWLEDGE_KIND,
} from "../post.js";
import {
  fetchAllowedCategories,
  fetchAllowedCategoriesForKind,
  type CategoryAllowEntry,
} from "../../src/posting/category-allowlist.js";
import { toContentTypeEnum, type AutoTagContentType } from "../../src/posting/category-tag.js";
import {
  askTagsForKind,
  makeDefaultTagPromptUser,
  type TagHearingDeps,
} from "../../src/posting/tag-hearing.js";

export interface ConfirmedMeta {
  category: { slug: string; name: string; isNew: boolean; id?: string };
  tags: Array<{ name: string; id?: string; isNew: boolean }>;
  committed?: boolean;
}

export interface CategoryTagArgs {
  title: string;
  parsedRaw: string;
  contentType: string;
  frontmatter: Record<string, unknown>;
  opts: Pick<ParsedOptions, "dryRun" | "autoApprove">;
  /**
   * #58 Step 2: knowledge.kind。operation/domain_knowledge のとき master tag
   * (部署/業界) の hearing を行い、選択 slug を confirmedMeta.tags へマージする。
   * 省略時は master hearing を行わない (concept 後方互換)。
   */
  knowledgeKind?: KnowledgeKind;
  client: unknown;
  deps: PostDeps;
  verbose: (s: string) => void;
  /**
   * #58 Step 2: master tag hearing 注入 (テスト差し替え用)。未指定時は
   * readline ベースの実装を使う。autoApprove/dryRun では hearing を skip。
   */
  tagHearing?: {
    ask: typeof askTagsForKind;
    deps: TagHearingDeps;
  };
}

export async function resolveCategoryAndTags(
  args: CategoryTagArgs,
): Promise<ConfirmedMeta> {
  const {
    title,
    parsedRaw,
    contentType,
    frontmatter,
    opts,
    knowledgeKind,
    client,
    deps,
    verbose,
    tagHearing,
  } = args;
  const autoTagInput = { title, body: parsedRaw, type: contentType };
  let allowedCategories: CategoryAllowEntry[] = [];
  try {
    // #58 Step 3: knowledge は kind 別 allowlist (operation/domain_knowledge →
    // business-axis 2 件のみ、concept → 既存 knowledge allowlist)。
    // article / issue は kind 非対象なので従来の type 別 fetch を維持 (動作不変)。
    //
    // #58 round-2 (M10): kind 未指定 (undefined) は concept として明示解決してから
    // 渡す。fetchAllowedCategoriesForKind は非 undefined の KnowledgeKind しか
    // 受けないので、ここで default を解決することで「undefined の silent fallback」を
    // 呼び出し元の責務として明示化する (concept 経路の動作は不変)。
    allowedCategories =
      contentType === "knowledge"
        ? await fetchAllowedCategoriesForKind(
            knowledgeKind ?? DEFAULT_KNOWLEDGE_KIND,
          )
        : await fetchAllowedCategories(
            toContentTypeEnum(contentType as AutoTagContentType),
          );
  } catch (err) {
    console.warn(
      `[category] allowlist fetch failed, using legacy DB match: ${
        (err as Error).message
      }`,
    );
  }
  const confirmMode = opts.dryRun
    ? "dry-run"
    : opts.autoApprove
      ? "auto-approve"
      : "interactive";
  const suggested = await deps.suggestCategory(autoTagInput, {
    client,
    allowedCategories,
    mode: confirmMode,
    reader: deps.reader,
  });
  const fmCategory =
    typeof frontmatter.category === "string"
      ? (frontmatter.category as string).trim()
      : "";
  const category = fmCategory
    ? { slug: fmCategory, name: fmCategory, confidence: 1, isNew: false }
    : suggested;
  const tagCandidates = await deps.suggestTags(autoTagInput, { client });
  const resolved = await deps.resolveTagAgainstMasters(tagCandidates, client);
  const confirmedMeta = (await deps.confirmInteractively(
    { category, resolved, mode: confirmMode },
    { reader: deps.reader },
  )) as ConfirmedMeta;
  verbose(
    `[post] category: ${category.slug} (confidence=${(category as { confidence: number }).confidence.toFixed(2)}); tags: ${tagCandidates.length}`,
  );

  // #58 Step 2: master tag hearing (部署/業界)。knowledge かつ
  // operation/domain_knowledge のとき、interactive モードでのみ実行する。
  // 選択された master slug を confirmedMeta.tags へマージ (tag_names_new 経路)。
  const masterSlugs = await runMasterTagHearing({
    contentType,
    knowledgeKind,
    confirmMode,
    tagHearing,
    verbose,
  });
  if (masterSlugs.length > 0) {
    return {
      ...confirmedMeta,
      tags: mergeMasterTags(confirmedMeta.tags, masterSlugs),
    };
  }
  return confirmedMeta;
}

/**
 * #58 Step 2: kind 別の master tag hearing を実行し、選択 slug を返す。
 *   - knowledge 以外 / kind 未指定 / concept → []
 *   - autoApprove / dry-run → [] (対話を行わない、後続で frontmatter 由来などに委譲)
 *   - operation / domain_knowledge かつ interactive → multi-select
 */
async function runMasterTagHearing(args: {
  contentType: string;
  knowledgeKind?: KnowledgeKind;
  confirmMode: "interactive" | "auto-approve" | "dry-run";
  tagHearing?: { ask: typeof askTagsForKind; deps: TagHearingDeps };
  verbose: (s: string) => void;
}): Promise<string[]> {
  const { contentType, knowledgeKind, confirmMode, tagHearing, verbose } = args;
  if (contentType !== "knowledge") return [];
  if (!knowledgeKind || knowledgeKind === "concept") return [];
  if (confirmMode !== "interactive") return [];

  const ask = tagHearing?.ask ?? askTagsForKind;
  const hearingDeps: TagHearingDeps =
    tagHearing?.deps ?? { promptUser: makeDefaultTagPromptUser() };
  const slugs = await ask(knowledgeKind, hearingDeps);
  verbose(`[post] master tags (${knowledgeKind}): ${slugs.join(", ")}`);
  return slugs;
}

/**
 * master slug を confirmedMeta.tags にマージする (immutable)。
 * master tag はサイト側 #57 で seed 済み (slug = #57 seed taxonomy、slugify(slug)=slug の
 * 自己一致)。雑務側は tag の id を持たないため tag_names_new 経路 (isNew=true) で **slug 値**を
 * 渡し、サーバ RPC の `ON CONFLICT (slug) DO NOTHING` で既存 seed 行へ link 解決させる
 * (新規 INSERT ではなく既存行への参照解決が目的)。
 *
 * #58 round-2 (M9) — dedup 比較キーについての明示:
 *   `present` (= existing.map(t => t.name)) は **同一命名規約内** の重複追加のみを防ぐ。
 *   existing tag の name はカテゴリ提案由来で日本語表示名 (例 "システム部")、master 追加は
 *   slug 値 (例 "system") のため、両者は name 上では衝突しない。これは意図的な挙動で、
 *   真の重複解決はサーバ RPC の `ON CONFLICT (slug)` が担う (雑務側は id 不在のため
 *   日本語 name ↔ slug の対応表を持てない)。ここでの dedup は「同じ slug を 2 回 hearing で
 *   選んだ」ケースの冗長追加防止が役割で、それ以上の正規化は行わない。
 */
function mergeMasterTags(
  existing: ConfirmedMeta["tags"],
  masterSlugs: string[],
): ConfirmedMeta["tags"] {
  const present = new Set(existing.map((t) => t.name));
  const additions = masterSlugs
    .filter((slug) => !present.has(slug))
    .map((slug) => ({ name: slug, isNew: true }));
  return [...existing, ...additions];
}

export const stage11CategoryTag = {
  name: "category-tag" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (ctx.opts.update) return; // skip in update mode
    if (!ctx.frontmatter || !ctx.contentType) {
      throw new Error("stage11: frontmatter / contentType must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const title = String(ctx.frontmatter.title ?? "");
    const parsedRaw = (ctx.parsed?.raw as string | undefined) ?? "";
    const client = ctx.deps.getSupabaseClient();
    const confirmedMeta = await resolveCategoryAndTags({
      title,
      parsedRaw,
      contentType: ctx.contentType,
      frontmatter: ctx.frontmatter,
      opts: { dryRun: ctx.opts.dryRun, autoApprove: ctx.opts.autoApprove },
      knowledgeKind: ctx.opts.knowledgeKind,
      client,
      deps: ctx.deps,
      verbose,
    });
    ctx.confirmedMeta = confirmedMeta as PipelineContext["confirmedMeta"];
  },
};
