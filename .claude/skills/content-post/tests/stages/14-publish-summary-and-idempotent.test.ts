/**
 * tests/stages/14-publish-summary-and-idempotent.test.ts — task-54 smoke
 *
 * Smoke for two fixes ported into hirai-method (`docs/draft/harness-health-improvements.md` §3 task-54):
 *
 *   Fix 1 (scripts/stages/14-publish.ts):
 *     `[post] ok:` final pipeline summary log must fire on ALL paths
 *     (--update / skip / dry-run), not only inside the publish gate.
 *
 *   Fix 2 (src/posting/version-manager.ts):
 *     bumpVersion(slug, { content }) must be idempotent — calling it 5x
 *     with the same `content` must NOT increment current_version after
 *     the first bump.
 *
 * Test isolation: each test uses an os.tmpdir() per-test dir and cleans up.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

import { stage14Publish } from "../../scripts/stages/14-publish.js";
import { bumpVersion } from "../../src/posting/version-manager.js";
import type { PipelineContext } from "../../scripts/types/pipeline-context.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function mkTmpDir(prefix: string): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), prefix));
}

/** Minimal PipelineContext with capturing streams. */
function makeCtx(
  over: {
    slug?: string;
    tableName?: string;
    contentType?: string;
    contentId?: string;
    dryRun?: boolean;
    publish?: boolean;
    update?: boolean;
  } = {},
): { ctx: PipelineContext; out: string[]; err: string[] } {
  const out: string[] = [];
  const err: string[] = [];
  const ctx = {
    filePath: "/tmp/fake.md",
    argv: [],
    opts: {
      dryRun: over.dryRun ?? false,
      publish: over.publish ?? false,
      update: over.update ?? false,
      verbose: false,
    },
    env: {},
    streams: {
      out,
      err,
      write: (s: string) => out.push(s),
      writeErr: (s: string) => err.push(s),
    },
    deps: {
      // publishContent is intentionally undefined so publishIfRequested no-ops
      // when the publish gate IS entered (we don't want a network call here).
    },
    slug: over.slug,
    tableName: over.tableName,
    contentType: over.contentType,
    contentId: over.contentId,
  } as unknown as PipelineContext;
  return { ctx, out, err };
}

// ---------------------------------------------------------------------------
// Fix 1: `[post] ok:` summary log fires on all paths
// ---------------------------------------------------------------------------

describe("stage14Publish — final summary log fires on all paths (task-54 fix 1)", () => {
  it("emits [post] ok on --update path (publish=false, contentId set by stage 13)", async () => {
    const { ctx, out } = makeCtx({
      slug: "my-slug",
      tableName: "knowledge",
      contentType: "knowledge",
      contentId: "abc-123", // stage 13 populated this
      update: true,
      publish: false,
      dryRun: false,
    });

    await stage14Publish.run(ctx);

    const summary = out.find((s) => s.startsWith("[post] ok:"));
    expect(summary).toBeDefined();
    expect(summary).toBe("[post] ok: knowledge.my-slug");
  });

  it("emits [post] ok on skip path (no publish, no contentId)", async () => {
    const { ctx, out } = makeCtx({
      slug: "skipped-slug",
      tableName: "tech_articles",
      contentType: "tech_articles",
      publish: false,
      dryRun: false,
    });

    await stage14Publish.run(ctx);

    expect(out.find((s) => s.startsWith("[post] ok:"))).toBe(
      "[post] ok: tech_articles.skipped-slug",
    );
  });

  it("emits [post] ok with (dry-run) prefix on dry-run path", async () => {
    const { ctx, out } = makeCtx({
      slug: "dry-slug",
      tableName: "weekly_issues",
      contentType: "weekly_issues",
      contentId: "id-1",
      publish: true, // even with publish=true, dryRun=true must short-circuit publish but still emit summary
      dryRun: true,
    });

    await stage14Publish.run(ctx);

    expect(out.find((s) => s.startsWith("[post] ok:"))).toBe(
      "[post] ok: (dry-run) weekly_issues.dry-slug",
    );
  });

  it("still emits [post] ok when tableName is unset (defaults to '?')", async () => {
    const { ctx, out } = makeCtx({
      slug: "no-table-slug",
      contentType: "knowledge",
      publish: false,
      dryRun: false,
    });

    await stage14Publish.run(ctx);

    expect(out.find((s) => s.startsWith("[post] ok:"))).toBe(
      "[post] ok: ?.no-table-slug",
    );
  });
});

// ---------------------------------------------------------------------------
// Fix 2: bumpVersion is idempotent on identical content (5x smoke)
// ---------------------------------------------------------------------------

describe("bumpVersion — content-hash idempotency (task-54 fix 2)", () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir("bump-idempotent-");
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  async function seedV1(slug: string, markdown: string): Promise<void> {
    const slugDir = path.join(tmpDir, slug);
    const v1Dir = path.join(slugDir, "v1");
    await fs.mkdir(v1Dir, { recursive: true });
    await fs.writeFile(path.join(v1Dir, "post.md"), markdown, "utf-8");
    const meta = {
      slug,
      kind: "knowledge",
      title: "Seed",
      current_version: 1,
      published_version: 1,
      published_at: "2026-05-28T00:00:00Z",
      versions: [
        {
          v: 1,
          created_at: "2026-05-28T00:00:00Z",
          author: "seed",
          snapshot_taken: true,
        },
      ],
    };
    await fs.writeFile(
      path.join(slugDir, "meta.json"),
      JSON.stringify(meta, null, 2),
      "utf-8",
    );
  }

  async function readCurrentVersion(slug: string): Promise<number> {
    const raw = await fs.readFile(path.join(tmpDir, slug, "meta.json"), "utf-8");
    const meta = JSON.parse(raw) as { current_version: number };
    return meta.current_version;
  }

  it("does NOT bump when content is identical to v{current}/post.md (5x re-run)", async () => {
    const slug = "idempotent-slug";
    const content = "# Title\n\nbody line 1\nbody line 2\n";
    await seedV1(slug, content);

    // 5 consecutive bumpVersion calls with the SAME content
    const results: boolean[] = [];
    for (let i = 0; i < 5; i++) {
      const bumped = await bumpVersion(slug, {
        author: "post.ts --update",
        contentsDir: tmpDir,
        content,
      });
      results.push(bumped);
    }

    // All 5 must return false (no-op)
    expect(results).toEqual([false, false, false, false, false]);
    // current_version must still be 1
    expect(await readCurrentVersion(slug)).toBe(1);
    // No v2 directory created
    await expect(fs.access(path.join(tmpDir, slug, "v2"))).rejects.toThrow();
  });

  it("DOES bump on first change, then is idempotent for the new content", async () => {
    const slug = "change-then-stable";
    const v1Content = "# v1 title\n";
    const v2Content = "# v2 title\n\nedited body\n";
    await seedV1(slug, v1Content);

    // Different content → bumps (v1 → v2)
    const first = await bumpVersion(slug, {
      author: "post.ts --update",
      contentsDir: tmpDir,
      content: v2Content,
    });
    expect(first).toBe(true);
    expect(await readCurrentVersion(slug)).toBe(2);
    // v2/post.md must have been written so the next compare works
    const writtenV2 = await fs.readFile(
      path.join(tmpDir, slug, "v2", "post.md"),
      "utf-8",
    );
    expect(writtenV2).toBe(v2Content);

    // Same content again → 4x no-op
    for (let i = 0; i < 4; i++) {
      const r = await bumpVersion(slug, {
        author: "post.ts --update",
        contentsDir: tmpDir,
        content: v2Content,
      });
      expect(r).toBe(false);
    }
    expect(await readCurrentVersion(slug)).toBe(2);
  });

  it("falls back to bump when current post.md is missing (cannot compare)", async () => {
    // meta.json exists but v1/post.md does NOT (legacy / seed-without-md case)
    const slug = "no-post-md";
    const slugDir = path.join(tmpDir, slug);
    await fs.mkdir(slugDir, { recursive: true });
    const meta = {
      slug,
      kind: "knowledge",
      title: "Legacy",
      current_version: 1,
      published_version: 1,
      published_at: "2026-05-28T00:00:00Z",
      versions: [
        {
          v: 1,
          created_at: "2026-05-28T00:00:00Z",
          author: "seed",
          snapshot_taken: true,
        },
      ],
    };
    await fs.writeFile(
      path.join(slugDir, "meta.json"),
      JSON.stringify(meta, null, 2),
      "utf-8",
    );

    const bumped = await bumpVersion(slug, {
      author: "post.ts --update",
      contentsDir: tmpDir,
      content: "anything",
    });
    expect(bumped).toBe(true);
    expect(await readCurrentVersion(slug)).toBe(2);
  });

  it("preserves backward-compatible behavior when content opt is omitted (always bumps)", async () => {
    const slug = "no-content-opt";
    await seedV1(slug, "some content");

    // Without content, must always bump (legacy behavior)
    const r1 = await bumpVersion(slug, {
      author: "post.ts --update",
      contentsDir: tmpDir,
    });
    const r2 = await bumpVersion(slug, {
      author: "post.ts --update",
      contentsDir: tmpDir,
    });
    expect(r1).toBe(true);
    expect(r2).toBe(true);
    expect(await readCurrentVersion(slug)).toBe(3);
  });
});

// ---------------------------------------------------------------------------
// Combined check: pipeline-style — stage14 fires summary, bumpVersion idempotent
// ---------------------------------------------------------------------------

describe("combined: pipeline-style smoke (task-54)", () => {
  it("--update re-run does NOT increase version AND emits [post] ok each run (5x)", async () => {
    const tmpDir = await mkTmpDir("combined-");
    try {
      const slug = "pipeline-smoke";
      const content = "# Title\n\nstable body across re-runs\n";
      // seed v1 with the same content the pipeline would push
      const slugDir = path.join(tmpDir, slug);
      const v1Dir = path.join(slugDir, "v1");
      await fs.mkdir(v1Dir, { recursive: true });
      await fs.writeFile(path.join(v1Dir, "post.md"), content, "utf-8");
      const meta = {
        slug,
        kind: "knowledge",
        title: "Pipeline Smoke",
        current_version: 1,
        published_version: 1,
        published_at: "2026-05-28T00:00:00Z",
        versions: [
          {
            v: 1,
            created_at: "2026-05-28T00:00:00Z",
            author: "seed",
            snapshot_taken: true,
          },
        ],
      };
      await fs.writeFile(
        path.join(slugDir, "meta.json"),
        JSON.stringify(meta, null, 2),
        "utf-8",
      );

      const summaries: string[] = [];
      const bumpResults: boolean[] = [];
      for (let i = 0; i < 5; i++) {
        // (a) idempotency: bumpVersion called same way 13-update.ts now calls it
        const bumped = await bumpVersion(slug, {
          author: "post.ts --update",
          contentsDir: tmpDir,
          content,
        });
        bumpResults.push(bumped);

        // (b) summary log: stage14Publish on --update path (no publish, no dryRun)
        const { ctx, out } = makeCtx({
          slug,
          tableName: "knowledge",
          contentType: "knowledge",
          contentId: "id-1",
          update: true,
          publish: false,
        });
        await stage14Publish.run(ctx);
        const s = out.find((line) => line.startsWith("[post] ok:"));
        expect(s).toBeDefined();
        summaries.push(s!);
      }

      // All 5 runs: no version bump
      expect(bumpResults).toEqual([false, false, false, false, false]);
      const raw = await fs.readFile(
        path.join(tmpDir, slug, "meta.json"),
        "utf-8",
      );
      const finalMeta = JSON.parse(raw) as { current_version: number };
      expect(finalMeta.current_version).toBe(1);

      // All 5 runs: summary fired
      expect(summaries).toHaveLength(5);
      for (const s of summaries) {
        expect(s).toBe("[post] ok: knowledge.pipeline-smoke");
      }
    } finally {
      await fs.rm(tmpDir, { recursive: true, force: true });
    }
  });
});
