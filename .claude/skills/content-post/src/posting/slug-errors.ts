/**
 * src/posting/slug-errors.ts — fail-loud slug collision error
 *
 * Defined in a stand-alone module so it can be imported by callers
 * (e.g. api-client.ts) without dragging slug.ts's heavyweight transitive
 * dependencies (slugify, dotenv-loading llm.ts module top-level side effects)
 * into modules that have no business loading them.
 */

/**
 * Thrown when a slug collision is detected and the operator must explicitly
 * choose remediation (--update / different slug / row deletion).
 */
export class SlugConflictError extends Error {
  constructor(
    public readonly slug: string,
    public readonly contentType: string,
    public readonly existingId?: string,
  ) {
    super(`slug "${slug}" は既に ${contentType} に存在`);
    this.name = "SlugConflictError";
  }
}
