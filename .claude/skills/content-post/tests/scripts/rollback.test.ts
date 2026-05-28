/**
 * tests/scripts/rollback.test.ts
 *
 * TDD for scripts/rollback.ts
 *
 * Test cases:
 *   1. dry-run: DB UPDATE は呼ばれない
 *   2. 存在しない version → exit 2
 *   3. snapshot.html が空 → exit 2
 *   4. 正常 path: DB UPDATE + meta.json rollback ログ追記
 *   5. --no-revalidate: revalidate 関数が呼ばれない
 *   6. revalidate あり: revalidate 関数が呼ばれる
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

async function mkTmpDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "rollback-test-"));
}

/** slugDir に meta.json + vN/snapshot.html を作成するヘルパー */
async function setupSlugDir(
  contentsDir: string,
  slug: string,
  opts: {
    currentVersion: number;
    publishedVersion: number;
    versions?: Array<{ v: number }>;
    snapshotVersions?: number[]; // snapshot.html を作る version 番号
    snapshotContent?: string;
  },
): Promise<void> {
  const slugDir = path.join(contentsDir, slug);
  await fs.mkdir(slugDir, { recursive: true });

  const meta = {
    slug,
    kind: "knowledge",
    title: `${slug} title`,
    current_version: opts.currentVersion,
    published_version: opts.publishedVersion,
    published_at: "2026-04-26T00:00:00Z",
    versions: opts.versions ?? [
      { v: 1, created_at: "2026-04-26T00:00:00Z", author: "init", snapshot_taken: true },
      ...(opts.currentVersion >= 2
        ? [{ v: 2, created_at: "2026-04-26T01:00:00Z", author: "update", snapshot_taken: true }]
        : []),
    ],
  };
  await fs.writeFile(path.join(slugDir, "meta.json"), JSON.stringify(meta, null, 2), "utf-8");

  for (const v of opts.snapshotVersions ?? []) {
    const vDir = path.join(slugDir, `v${v}`);
    await fs.mkdir(vDir, { recursive: true });
    await fs.writeFile(
      path.join(vDir, "snapshot.html"),
      opts.snapshotContent ?? `<html>version ${v}</html>`,
      "utf-8",
    );
    await fs.writeFile(path.join(vDir, "post.md"), `# version ${v}`, "utf-8");
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("scripts/rollback.ts", () => {
  let tmpDir: string;
  let contentsDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
    contentsDir = path.join(tmpDir, "contents");
    await fs.mkdir(contentsDir, { recursive: true });
    vi.resetModules();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it("1. dry-run: DB UPDATE は呼ばれない", async () => {
    await setupSlugDir(contentsDir, "my-slug", {
      currentVersion: 2,
      publishedVersion: 2,
      snapshotVersions: [1, 2],
    });

    const updateContent = vi.fn().mockResolvedValue(undefined);

    const { main } = await import("../../scripts/rollback.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "rollback.ts", "--slug", "my-slug", "--to-version", "1", "--dry-run"],
      {
        contentsDir,
        updateContent,
        streams,
        env: { SUPABASE_URL: "https://example.co", SUPABASE_SERVICE_ROLE_KEY: "key" },
      },
    );

    expect(code).toBe(0);
    expect(updateContent).not.toHaveBeenCalled();
    expect(streams.out.some((l) => /dry-run/i.test(l))).toBe(true);
  });

  it("2. 存在しない version → exit 2", async () => {
    await setupSlugDir(contentsDir, "my-slug", {
      currentVersion: 1,
      publishedVersion: 1,
      snapshotVersions: [1],
    });

    const updateContent = vi.fn().mockResolvedValue(undefined);

    const { main } = await import("../../scripts/rollback.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "rollback.ts", "--slug", "my-slug", "--to-version", "99"],
      {
        contentsDir,
        updateContent,
        streams,
        env: { SUPABASE_URL: "https://example.co", SUPABASE_SERVICE_ROLE_KEY: "key" },
      },
    );

    expect(code).toBe(2);
    expect(updateContent).not.toHaveBeenCalled();
    expect(streams.err.some((l) => /not found/i.test(l) || /snapshot/i.test(l))).toBe(true);
  });

  it("3. snapshot.html が空 → exit 2", async () => {
    await setupSlugDir(contentsDir, "my-slug", {
      currentVersion: 2,
      publishedVersion: 2,
      snapshotVersions: [],
    });

    // 空の snapshot.html を手動で作成
    const slugDir = path.join(contentsDir, "my-slug");
    const v1Dir = path.join(slugDir, "v1");
    await fs.mkdir(v1Dir, { recursive: true });
    await fs.writeFile(path.join(v1Dir, "snapshot.html"), "   ", "utf-8"); // 空白のみ

    const updateContent = vi.fn().mockResolvedValue(undefined);

    const { main } = await import("../../scripts/rollback.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "rollback.ts", "--slug", "my-slug", "--to-version", "1"],
      {
        contentsDir,
        updateContent,
        streams,
        env: { SUPABASE_URL: "https://example.co", SUPABASE_SERVICE_ROLE_KEY: "key" },
      },
    );

    expect(code).toBe(2);
    expect(updateContent).not.toHaveBeenCalled();
  });

  it("4. 正常 path: DB UPDATE + meta.json rollback ログ追記", async () => {
    await setupSlugDir(contentsDir, "my-slug", {
      currentVersion: 3,
      publishedVersion: 3,
      versions: [
        { v: 1, created_at: "2026-04-26T00:00:00Z", author: "init", snapshot_taken: true } as unknown as { v: number },
        { v: 2, created_at: "2026-04-26T01:00:00Z", author: "update-1", snapshot_taken: true } as unknown as { v: number },
        { v: 3, created_at: "2026-04-26T02:00:00Z", author: "update-2", snapshot_taken: true } as unknown as { v: number },
      ],
      snapshotVersions: [1, 2, 3],
      snapshotContent: "<html>v1 content</html>",
    });

    const updateContent = vi.fn().mockResolvedValue(undefined);
    const revalidate = vi.fn().mockResolvedValue(undefined);

    const { main } = await import("../../scripts/rollback.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "rollback.ts", "--slug", "my-slug", "--to-version", "1"],
      {
        contentsDir,
        updateContent,
        revalidate,
        streams,
        env: {},
      },
    );

    expect(code).toBe(0);

    // DB UPDATE が呼ばれた
    expect(updateContent).toHaveBeenCalledOnce();
    const [calledSlug, calledOpts] = updateContent.mock.calls[0]!;
    expect(calledSlug).toBe("my-slug");
    expect(calledOpts.body).toContain("<html>v1 content</html>");

    // meta.json に rollback ログが追記されている
    const metaRaw = await fs.readFile(
      path.join(contentsDir, "my-slug", "meta.json"),
      "utf-8",
    );
    const meta = JSON.parse(metaRaw);
    expect(meta.published_version).toBe(1);
    const rollbackEntry = meta.versions.find(
      (v: { note?: string }) => v.note && /rollback/i.test(v.note),
    );
    expect(rollbackEntry).toBeTruthy();
    expect(rollbackEntry.note).toContain("rollback from v3 to v1");

    // success メッセージ
    expect(streams.out.some((l) => /success|rolled back/i.test(l))).toBe(true);
  });

  it("5. --no-revalidate: revalidate 関数が呼ばれない", async () => {
    await setupSlugDir(contentsDir, "my-slug", {
      currentVersion: 2,
      publishedVersion: 2,
      snapshotVersions: [1, 2],
    });

    const updateContent = vi.fn().mockResolvedValue(undefined);
    const revalidate = vi.fn().mockResolvedValue(undefined);

    const { main } = await import("../../scripts/rollback.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "rollback.ts", "--slug", "my-slug", "--to-version", "1", "--no-revalidate"],
      {
        contentsDir,
        updateContent,
        revalidate,
        streams,
        env: {},
      },
    );

    expect(code).toBe(0);
    expect(revalidate).not.toHaveBeenCalled();
  });

  it("6. --slug 未指定 → exit 1", async () => {
    const { main } = await import("../../scripts/rollback.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "rollback.ts", "--to-version", "1"],
      { contentsDir, streams, env: {} },
    );

    expect(code).toBe(1);
    expect(streams.err.some((l) => /--slug/i.test(l))).toBe(true);
  });

  it("7. --to-version 未指定 → exit 1", async () => {
    const { main } = await import("../../scripts/rollback.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "rollback.ts", "--slug", "my-slug"],
      { contentsDir, streams, env: {} },
    );

    expect(code).toBe(1);
    expect(streams.err.some((l) => /--to-version/i.test(l))).toBe(true);
  });
});
