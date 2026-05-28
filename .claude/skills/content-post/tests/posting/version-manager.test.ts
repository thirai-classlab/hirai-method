/**
 * tests/posting/version-manager.test.ts
 *
 * TDD for src/posting/version-manager.ts
 *
 * Functions under test:
 *   - validateMetaSchema(meta)        — meta.json 構造バリデーション
 *   - snapshotBeforeUpdate(slug, kind, deps) — DB 取得 → ローカル退避
 *   - bumpVersion(slug, opts, deps)   — meta.json current_version++ 更新
 *   - loadCurrentMarkdown(slug, deps) — v{current}/post.md 読み込み
 *   - saveSnapshotAfter(slug, version, html, deps) — v{N}/snapshot.html 書き込み
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Temporary directory per test */
async function mkTmpDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "vm-test-"));
}

/** Write a meta.json to a tmp slug dir */
async function writeMeta(
  base: string,
  slug: string,
  meta: unknown,
): Promise<void> {
  const dir = path.join(base, slug);
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(
    path.join(dir, "meta.json"),
    JSON.stringify(meta, null, 2),
    "utf-8",
  );
}

// ---------------------------------------------------------------------------
// 1. validateMetaSchema
// ---------------------------------------------------------------------------

describe("validateMetaSchema", () => {
  it("accepts a valid meta object", async () => {
    const { validateMetaSchema } = await import(
      "../../src/posting/version-manager.js"
    );
    const meta = {
      slug: "example-slug",
      kind: "tech_article",
      title: "Test Title",
      current_version: 1,
      published_version: 1,
      published_at: "2026-04-26T15:52:40Z",
      versions: [
        {
          v: 1,
          created_at: "2026-04-26T02:55:00Z",
          author: "seed",
          snapshot_taken: true,
        },
      ],
    };
    expect(() => validateMetaSchema(meta)).not.toThrow();
  });

  it("throws when slug is missing", async () => {
    const { validateMetaSchema } = await import(
      "../../src/posting/version-manager.js"
    );
    expect(() =>
      validateMetaSchema({ kind: "knowledge", title: "t", current_version: 1 }),
    ).toThrow(/slug/);
  });

  it("throws when kind is invalid", async () => {
    const { validateMetaSchema } = await import(
      "../../src/posting/version-manager.js"
    );
    expect(() =>
      validateMetaSchema({
        slug: "s",
        kind: "unknown_kind",
        title: "t",
        current_version: 1,
        published_version: 1,
        versions: [],
      }),
    ).toThrow(/kind/);
  });

  it("throws when current_version is not a positive integer", async () => {
    const { validateMetaSchema } = await import(
      "../../src/posting/version-manager.js"
    );
    expect(() =>
      validateMetaSchema({
        slug: "s",
        kind: "knowledge",
        title: "t",
        current_version: 0,
        published_version: 1,
        versions: [],
      }),
    ).toThrow(/current_version/);
  });

  it("throws when versions entry is missing required fields", async () => {
    const { validateMetaSchema } = await import(
      "../../src/posting/version-manager.js"
    );
    expect(() =>
      validateMetaSchema({
        slug: "s",
        kind: "knowledge",
        title: "t",
        current_version: 1,
        published_version: 1,
        versions: [{ v: 1 }], // missing created_at, author, snapshot_taken
      }),
    ).toThrow(/versions/);
  });
});

// ---------------------------------------------------------------------------
// 2. snapshotBeforeUpdate
// ---------------------------------------------------------------------------

describe("snapshotBeforeUpdate", () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it("fetches DB body and writes snapshot-before-update.html in next version dir", async () => {
    const { snapshotBeforeUpdate } = await import(
      "../../src/posting/version-manager.js"
    );

    // Existing v1 meta
    await writeMeta(tmpDir, "my-slug", {
      slug: "my-slug",
      kind: "tech_article",
      title: "My Article",
      current_version: 1,
      published_version: 1,
      published_at: "2026-04-26T00:00:00Z",
      versions: [
        {
          v: 1,
          created_at: "2026-04-26T00:00:00Z",
          author: "seed",
          snapshot_taken: true,
        },
      ],
    });

    const fakeBody = "<h1>DB body v1</h1>";
    const fakeFetch = vi.fn().mockResolvedValue({ body: fakeBody, raw_markdown: "# DB body v1" });

    await snapshotBeforeUpdate("my-slug", "tech_article", {
      contentsDir: tmpDir,
      fetchCurrentContent: fakeFetch,
    });

    // Should write to v2/snapshot-before-update.html
    const snapshotPath = path.join(tmpDir, "my-slug", "v2", "snapshot-before-update.html");
    const written = await fs.readFile(snapshotPath, "utf-8");
    expect(written).toBe(fakeBody);
    expect(fakeFetch).toHaveBeenCalledWith("my-slug", "tech_article");
  });

  it("throws when fetchCurrentContent returns null (slug not found in DB)", async () => {
    const { snapshotBeforeUpdate } = await import(
      "../../src/posting/version-manager.js"
    );

    await writeMeta(tmpDir, "ghost-slug", {
      slug: "ghost-slug",
      kind: "knowledge",
      title: "Ghost",
      current_version: 1,
      published_version: 1,
      published_at: "2026-04-26T00:00:00Z",
      versions: [
        {
          v: 1,
          created_at: "2026-04-26T00:00:00Z",
          author: "seed",
          snapshot_taken: true,
        },
      ],
    });

    const fakeFetch = vi.fn().mockResolvedValue(null);

    await expect(
      snapshotBeforeUpdate("ghost-slug", "knowledge", {
        contentsDir: tmpDir,
        fetchCurrentContent: fakeFetch,
      }),
    ).rejects.toThrow(/ghost-slug/);
  });

  it("auto-seeds v1 and writes v2/snapshot-before-update.html when meta.json does not exist", async () => {
    const { snapshotBeforeUpdate } = await import(
      "../../src/posting/version-manager.js"
    );

    const fakeFetch = vi.fn().mockResolvedValue({ body: "<p>ok</p>", raw_markdown: "# ok" });

    // Should NOT throw — auto-seeds v1 from DB then writes v2 snapshot
    await snapshotBeforeUpdate("no-meta-slug", "knowledge", {
      contentsDir: tmpDir,
      fetchCurrentContent: fakeFetch,
    });

    // v1 should have been auto-created
    const v1Snapshot = path.join(tmpDir, "no-meta-slug", "v1", "snapshot.html");
    await expect(fs.access(v1Snapshot)).resolves.toBeUndefined();

    // v2/snapshot-before-update.html should exist
    const v2Snapshot = path.join(tmpDir, "no-meta-slug", "v2", "snapshot-before-update.html");
    const written = await fs.readFile(v2Snapshot, "utf-8");
    expect(written).toBe("<p>ok</p>");
  });

  it("increments to v3 when current_version is 2", async () => {
    const { snapshotBeforeUpdate } = await import(
      "../../src/posting/version-manager.js"
    );

    await writeMeta(tmpDir, "slug-v2", {
      slug: "slug-v2",
      kind: "knowledge",
      title: "Article V2",
      current_version: 2,
      published_version: 2,
      published_at: "2026-04-26T00:00:00Z",
      versions: [
        { v: 1, created_at: "2026-04-25T00:00:00Z", author: "seed", snapshot_taken: true },
        { v: 2, created_at: "2026-04-26T00:00:00Z", author: "update", snapshot_taken: true },
      ],
    });

    const fakeFetch = vi.fn().mockResolvedValue({ body: "<p>v2 body</p>", raw_markdown: "v2 body" });

    await snapshotBeforeUpdate("slug-v2", "knowledge", {
      contentsDir: tmpDir,
      fetchCurrentContent: fakeFetch,
    });

    const snapshotPath = path.join(tmpDir, "slug-v2", "v3", "snapshot-before-update.html");
    const written = await fs.readFile(snapshotPath, "utf-8");
    expect(written).toBe("<p>v2 body</p>");
  });
});

// ---------------------------------------------------------------------------
// 3. bumpVersion
// ---------------------------------------------------------------------------

describe("bumpVersion", () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it("increments current_version and adds a new version entry", async () => {
    const { bumpVersion } = await import("../../src/posting/version-manager.js");

    await writeMeta(tmpDir, "bump-slug", {
      slug: "bump-slug",
      kind: "knowledge",
      title: "Bump Test",
      current_version: 1,
      published_version: 1,
      published_at: "2026-04-26T00:00:00Z",
      versions: [
        { v: 1, created_at: "2026-04-26T00:00:00Z", author: "seed", snapshot_taken: true },
      ],
    });

    await bumpVersion("bump-slug", {
      author: "post.ts --update",
      note: "test bump",
      publishedVersion: 2,
      contentsDir: tmpDir,
    });

    const raw = await fs.readFile(path.join(tmpDir, "bump-slug", "meta.json"), "utf-8");
    const meta = JSON.parse(raw) as {
      current_version: number;
      published_version: number;
      versions: Array<{ v: number; author: string; note?: string }>;
    };

    expect(meta.current_version).toBe(2);
    expect(meta.published_version).toBe(2);
    expect(meta.versions).toHaveLength(2);
    expect(meta.versions[1]).toMatchObject({ v: 2, author: "post.ts --update", note: "test bump" });
  });

  it("works for initial creation (v1)", async () => {
    const { bumpVersion } = await import("../../src/posting/version-manager.js");

    // No meta.json yet — initial creation
    const slugDir = path.join(tmpDir, "new-slug");
    await fs.mkdir(slugDir, { recursive: true });

    await bumpVersion("new-slug", {
      author: "first post",
      note: "initial",
      publishedVersion: 1,
      contentsDir: tmpDir,
      initial: true,
      slug: "new-slug",
      kind: "tech_article",
      title: "New Article",
      publishedAt: "2026-04-27T00:00:00Z",
    });

    const raw = await fs.readFile(path.join(tmpDir, "new-slug", "meta.json"), "utf-8");
    const meta = JSON.parse(raw) as { current_version: number; versions: unknown[] };
    expect(meta.current_version).toBe(1);
    expect(meta.versions).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// 4. loadCurrentMarkdown
// ---------------------------------------------------------------------------

describe("loadCurrentMarkdown", () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it("returns the post.md content for the current version", async () => {
    const { loadCurrentMarkdown } = await import(
      "../../src/posting/version-manager.js"
    );

    await writeMeta(tmpDir, "md-slug", {
      slug: "md-slug",
      kind: "knowledge",
      title: "MD Test",
      current_version: 2,
      published_version: 2,
      published_at: "2026-04-26T00:00:00Z",
      versions: [
        { v: 1, created_at: "2026-04-25T00:00:00Z", author: "seed", snapshot_taken: true },
        { v: 2, created_at: "2026-04-26T00:00:00Z", author: "update", snapshot_taken: true },
      ],
    });

    const v2Dir = path.join(tmpDir, "md-slug", "v2");
    await fs.mkdir(v2Dir, { recursive: true });
    await fs.writeFile(path.join(v2Dir, "post.md"), "# Hello v2", "utf-8");

    const content = await loadCurrentMarkdown("md-slug", { contentsDir: tmpDir });
    expect(content).toBe("# Hello v2");
  });

  it("returns null when post.md does not exist", async () => {
    const { loadCurrentMarkdown } = await import(
      "../../src/posting/version-manager.js"
    );

    await writeMeta(tmpDir, "no-md-slug", {
      slug: "no-md-slug",
      kind: "knowledge",
      title: "No MD",
      current_version: 1,
      published_version: 1,
      published_at: "2026-04-26T00:00:00Z",
      versions: [
        { v: 1, created_at: "2026-04-26T00:00:00Z", author: "seed", snapshot_taken: true },
      ],
    });
    // v1 dir exists but post.md does not

    const content = await loadCurrentMarkdown("no-md-slug", { contentsDir: tmpDir });
    expect(content).toBeNull();
  });

  it("returns null when meta.json does not exist", async () => {
    const { loadCurrentMarkdown } = await import(
      "../../src/posting/version-manager.js"
    );

    const content = await loadCurrentMarkdown("totally-unknown", { contentsDir: tmpDir });
    expect(content).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// 5. saveSnapshotAfter
// ---------------------------------------------------------------------------

describe("saveSnapshotAfter", () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
  });

  it("writes snapshot.html to the specified version directory", async () => {
    const { saveSnapshotAfter } = await import(
      "../../src/posting/version-manager.js"
    );

    const html = "<article>Hello snapshot</article>";
    await saveSnapshotAfter("snap-slug", 3, html, { contentsDir: tmpDir });

    const writtenPath = path.join(tmpDir, "snap-slug", "v3", "snapshot.html");
    const written = await fs.readFile(writtenPath, "utf-8");
    expect(written).toBe(html);
  });

  it("creates intermediate directories if they do not exist", async () => {
    const { saveSnapshotAfter } = await import(
      "../../src/posting/version-manager.js"
    );

    await saveSnapshotAfter("new-snap", 1, "<p>new</p>", { contentsDir: tmpDir });
    const writtenPath = path.join(tmpDir, "new-snap", "v1", "snapshot.html");
    await expect(fs.access(writtenPath)).resolves.toBeUndefined();
  });
});
