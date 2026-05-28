/**
 * tests/scripts/import-image.test.ts
 *
 * TDD for scripts/import-image.ts
 *
 * Test cases:
 *   1. --src でローカルファイルをインポートできる
 *   2. 同一 sha256 の画像は skip (重複排除)
 *   3. index.json に entry が追記される
 *   4. --url でリモート画像を download してインポートできる
 *   5. --src も --url もなし → exit 1
 *   6. 重複 skip の場合は index.json に entry が追加されない
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";

async function mkTmpDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "import-img-test-"));
}

function sha256hex(buf: Buffer): string {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

describe("scripts/import-image.ts", () => {
  let tmpDir: string;
  let imagesDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
    imagesDir = path.join(tmpDir, "images");
    await fs.mkdir(imagesDir, { recursive: true });
    vi.resetModules();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it("1. --src でローカルファイルをインポートできる", async () => {
    const { importImage } = await import("../../scripts/import-image.js");
    const content = Buffer.from("fake-image-content-png");
    const sha = sha256hex(content);

    const result = await importImage(
      { srcPath: "/fake/image.png" },
      {
        imagesDir,
        readFile: vi.fn().mockResolvedValue(content),
      },
    );

    expect(result.skipped).toBe(false);
    expect(result.sha256).toBe(sha);
    expect(result.ext).toBe("png");
    expect(result.localPath).toContain(`${sha}.png`);

    // ファイルが保存されている
    const saved = await fs.readFile(path.join(imagesDir, `${sha}.png`));
    expect(saved.equals(content)).toBe(true);
  });

  it("2. 同一 sha256 の画像は skip (重複排除)", async () => {
    const { importImage } = await import("../../scripts/import-image.js");
    const content = Buffer.from("same-content");
    const sha = sha256hex(content);

    // 1回目
    await importImage(
      { srcPath: "/fake/image.png" },
      {
        imagesDir,
        readFile: vi.fn().mockResolvedValue(content),
      },
    );

    // 2回目 (同一内容)
    const result2 = await importImage(
      { srcPath: "/fake/image2.png" },
      {
        imagesDir,
        readFile: vi.fn().mockResolvedValue(content),
      },
    );

    expect(result2.skipped).toBe(true);
    expect(result2.sha256).toBe(sha);
  });

  it("3. index.json に entry が追記される", async () => {
    const { importImage } = await import("../../scripts/import-image.js");
    const content = Buffer.from("image-for-index-test");

    await importImage(
      { srcPath: "/fake/test.jpg" },
      {
        imagesDir,
        readFile: vi.fn().mockResolvedValue(content),
      },
    );

    const indexRaw = await fs.readFile(path.join(imagesDir, "index.json"), "utf-8");
    const index = JSON.parse(indexRaw) as { images: Array<{ sha256: string; ext: string; size: number }> };
    expect(index.images).toHaveLength(1);
    expect(index.images[0]!.ext).toBe("jpg");
    expect(index.images[0]!.size).toBe(content.length);
    expect(typeof index.images[0]!.sha256).toBe("string");
  });

  it("4. --url でリモート画像を download してインポートできる", async () => {
    const { importImage } = await import("../../scripts/import-image.js");
    const content = Buffer.from("remote-webp-content");
    const sha = sha256hex(content);

    const result = await importImage(
      { srcUrl: "https://example.com/image.webp" },
      {
        imagesDir,
        fetchUrl: vi.fn().mockResolvedValue({ buffer: content, contentType: "image/webp" }),
      },
    );

    expect(result.skipped).toBe(false);
    expect(result.sha256).toBe(sha);
    expect(result.ext).toBe("webp");

    const indexRaw = await fs.readFile(path.join(imagesDir, "index.json"), "utf-8");
    const index = JSON.parse(indexRaw) as { images: Array<{ original_url?: string }> };
    expect(index.images[0]!.original_url).toBe("https://example.com/image.webp");
  });

  it("5. --src も --url もなし → exit 1", async () => {
    const { main } = await import("../../scripts/import-image.js");
    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(["node", "import-image.ts"], { imagesDir, streams });
    expect(code).toBe(1);
    expect(streams.err.some((l) => /--src|--url/i.test(l))).toBe(true);
  });

  it("6. 重複 skip の場合は index.json の entry 数が増えない", async () => {
    const { importImage } = await import("../../scripts/import-image.js");
    const content = Buffer.from("deduplicated-content");

    // 1回目: 保存
    await importImage(
      { srcPath: "/a/1.png" },
      { imagesDir, readFile: vi.fn().mockResolvedValue(content) },
    );

    // 2回目: 同一 sha256 → skip
    await importImage(
      { srcPath: "/b/2.png" },
      { imagesDir, readFile: vi.fn().mockResolvedValue(content) },
    );

    const indexRaw = await fs.readFile(path.join(imagesDir, "index.json"), "utf-8");
    const index = JSON.parse(indexRaw) as { images: unknown[] };
    // 1件のみ
    expect(index.images).toHaveLength(1);
  });

  it("7. main --src で exit 0 かつファイル保存される", async () => {
    const { main } = await import("../../scripts/import-image.js");
    const content = Buffer.from("cli-main-test-content");
    const sha = sha256hex(content);

    const streams = { out: [] as string[], err: [] as string[], write: (l: string) => streams.out.push(l), writeErr: (l: string) => streams.err.push(l) };

    const code = await main(
      ["node", "import-image.ts", "--src", "/fake/img.png"],
      {
        imagesDir,
        readFile: vi.fn().mockResolvedValue(content),
        streams,
      },
    );

    expect(code).toBe(0);
    expect(streams.out.some((l) => l.includes(sha))).toBe(true);
  });
});
