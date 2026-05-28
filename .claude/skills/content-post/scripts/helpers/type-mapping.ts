/**
 * scripts/helpers/type-mapping.ts — Task #56 W1 (11.3d-A)
 *
 * Pure helpers extracted from scripts/post.ts during the 14-stage
 * pipeline refactor. These functions are side-effect free and contain
 * the contentType ↔ table-name ↔ S3-prefix ↔ embedding-enum mappings
 * used throughout the posting pipeline.
 *
 * Design intent (動作保存):
 *   - Same signatures, same return values, same throw semantics as the
 *     original `post.ts` definitions. No behavioural change in W1.
 *   - See ../post.ts (pre-extraction) git history for the originals.
 *   - Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W1.
 */

/**
 * Translate a pipeline `contentType` (table-name flavour) into the S3 key
 * prefix used by image uploads. Keeps S3 object keys stable and predictable
 * even when we rename DB columns.
 */
export function mapContentTypeToImagePrefix(
  type: string,
): "knowledge" | "tech_article" | "issue" {
  switch (type) {
    case "tech_articles":
      return "tech_article";
    case "weekly_issues":
      return "issue";
    case "knowledge":
    default:
      return "knowledge";
  }
}

export function contentTypeToTable(type: string): string {
  switch (type) {
    case "knowledge":
      return "knowledge";
    case "tech_articles":
      return "tech_articles";
    case "weekly_issues":
      return "weekly_issues";
    default:
      return "knowledge";
  }
}

/**
 * Derive a NOT-NULL summary string. Prefer explicit frontmatter.summary,
 * otherwise collapse whitespace from the body and take the first 200 chars.
 * Guarantees a non-empty string so the DB NOT NULL constraint is satisfied
 * even for very short drafts.
 */
export function deriveSummary(
  frontmatter: Record<string, unknown>,
  body: string,
): string {
  const explicit = frontmatter.summary;
  if (typeof explicit === "string" && explicit.trim().length > 0) {
    return explicit.trim();
  }
  const collapsed = body.replace(/\s+/g, " ").trim();
  if (collapsed.length === 0) return "(no summary)";
  return collapsed.slice(0, 200);
}

/**
 * Convert post.ts internal contentType (knowledge / tech_articles / weekly_issues)
 * to the DB enum used in `content_embeddings.content_type` —
 * ('knowledge','article','issue').
 */
export function toEmbeddingEnum(
  contentType: string,
): "knowledge" | "article" | "issue" {
  switch (contentType) {
    case "tech_articles":
      return "article";
    case "weekly_issues":
      return "issue";
    case "knowledge":
    default:
      return "knowledge";
  }
}
