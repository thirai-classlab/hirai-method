/**
 * tests/scripts/contents-list.test.ts
 *
 * TDD for scripts/contents-list.ts
 *
 * Test cases:
 *   1. コンテンツなし → "No contents found."
 *   2. テーブル形式 stdout 出力 (デフォルト)
 *   3. --json フラグで JSON 出力
 *   4. --md フラグで INDEX.md を再生成
 *   5. INDEX.md に auto-generated コメント + 正しい行数
 *   6. formatTable のカラム構造検証
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

async function mkTmpDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "contents-list-test-"));
}

/** テスト用 slug ディレクトリを作成するヘルパー */
async function seedSlug(
  contentsDir: string,
  slug: string,
  meta: Record<string, unknown>,
): Promise<void> {
  const slugDir = path.join(contentsDir, slug);
  await fs.mkdir(slugDir, { recursive: true });
  await fs.writeFile(
    path.join(slugDir, "meta.json"),
    JSON.stringify(meta, null, 2),
    "utf-8",
  );
}

const BASE_META = {
  kind: "tech_article",
  current_version: 1,
  published_version: 1,
  published_at: "2026-04-26T00:00:00Z",
  versions: [
    {
      v: 1,
      created_at: "2026-04-26T00:00:00Z",
      author: "test",
      snapshot_taken: true,
    },
  ],
};

describe("scripts/contents-list.ts", () => {
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

  it("1. コンテンツなし → 'No contents found.'", async () => {
    const { main } = await import("../../scripts/contents-list.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    const code = await main(["node", "contents-list.ts"], {
      contentsDir,
      streams,
    });

    expect(code).toBe(0);
    expect(streams.out.join("\n")).toContain("No contents found");
  });

  it("2. テーブル形式 stdout 出力 (デフォルト)", async () => {
    await seedSlug(contentsDir, "my-article-slug", {
      ...BASE_META,
      slug: "my-article-slug",
      title: "My Article Title",
    });

    const { main } = await import("../../scripts/contents-list.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    const code = await main(["node", "contents-list.ts"], {
      contentsDir,
      streams,
    });

    expect(code).toBe(0);
    const output = streams.out.join("\n");
    expect(output).toContain("my-article-slug");
    expect(output).toContain("tech_article");
  });

  it("3. --json フラグで JSON 出力", async () => {
    await seedSlug(contentsDir, "json-test-slug", {
      ...BASE_META,
      slug: "json-test-slug",
      title: "JSON Test",
      kind: "knowledge",
    });

    const { main } = await import("../../scripts/contents-list.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    const code = await main(["node", "contents-list.ts", "--json"], {
      contentsDir,
      streams,
    });

    expect(code).toBe(0);
    const parsed = JSON.parse(streams.out.join("")) as Array<{ slug: string; kind: string }>;
    expect(Array.isArray(parsed)).toBe(true);
    expect(parsed[0]!.slug).toBe("json-test-slug");
    expect(parsed[0]!.kind).toBe("knowledge");
  });

  it("4. --md フラグで INDEX.md を再生成", async () => {
    await seedSlug(contentsDir, "md-test-slug", {
      ...BASE_META,
      slug: "md-test-slug",
      title: "INDEX.md Test Article",
    });

    const { main } = await import("../../scripts/contents-list.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    const code = await main(["node", "contents-list.ts", "--md"], {
      contentsDir,
      streams,
    });

    expect(code).toBe(0);

    // INDEX.md が生成されている
    const indexPath = path.join(contentsDir, "..", "INDEX.md");
    const indexContent = await fs.readFile(indexPath, "utf-8");
    expect(indexContent).toContain("AUTO-GENERATED");
    expect(indexContent).toContain("md-test-slug");
    expect(indexContent).toContain("INDEX.md Test");
  });

  it("5. INDEX.md にヘッダー + 全スラッグが含まれる", async () => {
    await seedSlug(contentsDir, "slug-a", {
      ...BASE_META,
      slug: "slug-a",
      title: "Article A",
      kind: "tech_article",
    });
    await seedSlug(contentsDir, "slug-b", {
      ...BASE_META,
      slug: "slug-b",
      title: "Article B",
      kind: "knowledge",
      current_version: 3,
      published_version: 2,
    });

    const { main } = await import("../../scripts/contents-list.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    await main(["node", "contents-list.ts", "--md"], { contentsDir, streams });

    const indexPath = path.join(contentsDir, "..", "INDEX.md");
    const indexContent = await fs.readFile(indexPath, "utf-8");

    expect(indexContent).toContain("# Contents Index");
    expect(indexContent).toContain("Total: **2**");
    expect(indexContent).toContain("slug-a");
    expect(indexContent).toContain("slug-b");
    expect(indexContent).toContain("knowledge");
  });

  it("6. formatTable カラム構造検証", async () => {
    const { formatTable } = await import("../../scripts/contents-list.js");

    const summaries = [
      {
        slug: "test-slug",
        kind: "tech_article" as const,
        title: "Test Title",
        currentVersion: 2,
        publishedVersion: 1,
        totalVersions: 2,
        status: "published" as const,
        publishedAt: "2026-04-26T00:00:00Z",
      },
    ];

    const table = formatTable(summaries);
    expect(table).toContain("test-slug");
    expect(table).toContain("tech_article");
    expect(table).toContain("v2");
    expect(table).toContain("v1");
    expect(table).toContain("published");
  });

  it("7. 複数 slug はアルファベット順にソートされる", async () => {
    await seedSlug(contentsDir, "zzz-last", {
      ...BASE_META, slug: "zzz-last", title: "Last", kind: "knowledge",
    });
    await seedSlug(contentsDir, "aaa-first", {
      ...BASE_META, slug: "aaa-first", title: "First", kind: "tech_article",
    });

    const { main } = await import("../../scripts/contents-list.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    await main(["node", "contents-list.ts", "--json"], { contentsDir, streams });

    const parsed = JSON.parse(streams.out.join("")) as Array<{ slug: string }>;
    expect(parsed[0]!.slug).toBe("aaa-first");
    expect(parsed[1]!.slug).toBe("zzz-last");
  });
});
