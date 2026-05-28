/**
 * scripts/stages/03-link-check.ts — Task #56 W2 (11.3d-B)
 *
 * Stage 03: external URL reachability check (Wave 11.3e W4 functionality).
 *
 * Pure function:
 *   - runLinkCheck(source, opts, env): returns
 *     { skipped: true } | { skipped: false; summary; broken; strictFail }
 *
 * Stage descriptor:
 *   - stage03LinkCheck.run(ctx): emits warnings via ctx.streams.writeErr,
 *     sets ctx.outcome with exitCode 5 when --link-check-strict and broken found.
 *
 * Design intent (動作保存):
 *   - Default ON; --no-link-check skips entirely. --link-check-strict makes
 *     broken-link detection fatal (exit 5).
 *   - Skip self-origin (SITE_URL) and CDN host so internal references do not
 *     mask real outages. Same excludeOrigins list as post.ts inline.
 *   - Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W2.
 */
import {
  extractExternalUrls,
  checkUrls,
  summarize as summarizeLinkCheck,
  formatBrokenLine,
} from "../../src/posting/link-check.js";
import type { PipelineContext } from "../types/pipeline-context.js";
import type { ParsedOptions } from "../post.js";

/** CDN host that hosts uploaded images — excluded from external URL check. */
export const CDN_DOMAIN = "d2f75plg0t6qwk.cloudfront.net";

export type LinkCheckResult =
  | { skipped: true; reason: "no-link-check" | "no-external-urls" }
  | {
      skipped: false;
      summaryLine: string;
      brokenLines: string[];
      strictFail: boolean;
    };

/**
 * Run the external URL reachability check honouring --no-link-check and
 * --link-check-strict. Returns enough structured info that the caller can
 * write to streams in the same format post.ts used inline.
 */
export async function runLinkCheck(
  source: string,
  opts: Pick<ParsedOptions, "linkCheck" | "linkCheckStrict">,
  env: Record<string, string | undefined>,
): Promise<LinkCheckResult> {
  if (!opts.linkCheck) {
    return { skipped: true, reason: "no-link-check" };
  }
  const siteUrl = env.SITE_URL?.replace(/\/+$/, "") ?? "";
  const excludeOrigins = [
    ...(siteUrl ? [siteUrl] : []),
    `https://${CDN_DOMAIN}`,
  ];
  const urls = extractExternalUrls(source, { excludeOrigins });
  if (urls.length === 0) {
    return { skipped: true, reason: "no-external-urls" };
  }
  const results = await checkUrls(urls, { timeoutMs: 10_000, concurrency: 8 });
  const summary = summarizeLinkCheck(results);
  const summaryLine = `[post] link-check: ${summary.ok} ok / ${summary.redirect} redirect / ${summary.broken + summary.timeout} broken / ${summary.total} total`;
  const brokenLines = summary.brokenItems.map((item) => formatBrokenLine(item));
  const strictFail = brokenLines.length > 0 && !!opts.linkCheckStrict;
  return { skipped: false, summaryLine, brokenLines, strictFail };
}

export const stage03LinkCheck = {
  name: "link-check" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (typeof ctx.source !== "string") {
      throw new Error("stage03: ctx.source must be set before link-check stage");
    }
    const result = await runLinkCheck(ctx.source, ctx.opts, ctx.env);
    if (result.skipped) {
      // Nothing to write; verbose hint handled by descriptors in W3.
      return;
    }
    if (result.brokenLines.length > 0) {
      ctx.streams.writeErr(result.summaryLine);
      for (const line of result.brokenLines) ctx.streams.writeErr(line);
      if (result.strictFail) {
        ctx.streams.writeErr(
          `[post] link-check failed in --link-check-strict mode (exit 5)`,
        );
        ctx.outcome = {
          kind: "error",
          exitCode: 5,
          message: "link-check-strict-broken",
        };
        throw new Error("link-check-strict-broken");
      }
    }
  },
};
