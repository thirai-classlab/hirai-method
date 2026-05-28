/**
 * tests/scripts/restore-images-from-s3.test.ts
 *
 * TDD for scripts/restore-images-from-s3.ts
 * S3 アクセスは AWS SDK を mock 化 (実 S3 触らない)
 *
 * Test cases:
 *   1. dry-run: ファイル保存されない、件数のみカウント
 *   2. execute: 1 件 mock download + index.json 更新
 *   3. 既存 s3_key は skip
 *   4. AWS_S3_BUCKET 未設定 → exit 1
 *   5. download エラーは errors カウントに計上されるが処理は継続
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";

async function mkTmpDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "restore-s3-test-"));
}

function sha256hex(buf: Buffer): string {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

describe("scripts/restore-images-from-s3.ts", () => {
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

  it("1. dry-run: ファイル保存されない、件数のみカウント", async () => {
    const { restoreImagesFromS3 } = await import(
      "../../scripts/restore-images-from-s3.js"
    );

    const result = await restoreImagesFromS3(
      { bucket: "test-bucket", execute: false },
      {
        imagesDir,
        listS3Objects: vi.fn().mockResolvedValue([
          { key: "articles/img1.png", size: 1000 },
          { key: "articles/img2.webp", size: 2000 },
        ]),
        getS3Object: vi.fn(),
      },
    );

    expect(result.total).toBe(2);
    expect(result.downloaded).toBe(2); // dry-run では downloaded にカウント
    expect(result.skipped).toBe(0);
    expect(result.errors).toBe(0);

    // ファイルは保存されていない
    const files = await fs.readdir(imagesDir);
    expect(files).not.toContain("index.json");
  });

  it("2. execute: 1 件 mock download + index.json 更新", async () => {
    const { restoreImagesFromS3 } = await import(
      "../../scripts/restore-images-from-s3.js"
    );

    const imgContent = Buffer.from("fake-s3-image-bytes");
    const sha = sha256hex(imgContent);

    const result = await restoreImagesFromS3(
      { bucket: "test-bucket", execute: true, cloudfrontDomain: "cdn.example.com" },
      {
        imagesDir,
        listS3Objects: vi.fn().mockResolvedValue([
          { key: "articles/test.png", size: imgContent.length },
        ]),
        getS3Object: vi.fn().mockResolvedValue(imgContent),
      },
    );

    expect(result.total).toBe(1);
    expect(result.downloaded).toBe(1);
    expect(result.skipped).toBe(0);
    expect(result.errors).toBe(0);

    // ファイルが保存されている
    const savedPath = path.join(imagesDir, `${sha}.png`);
    const saved = await fs.readFile(savedPath);
    expect(saved.equals(imgContent)).toBe(true);

    // index.json が更新されている
    const indexRaw = await fs.readFile(path.join(imagesDir, "index.json"), "utf-8");
    const index = JSON.parse(indexRaw) as {
      images: Array<{ sha256: string; s3_key: string; cloudfront_url: string }>;
    };
    expect(index.images).toHaveLength(1);
    expect(index.images[0]!.sha256).toBe(sha);
    expect(index.images[0]!.s3_key).toBe("articles/test.png");
    expect(index.images[0]!.cloudfront_url).toBe(
      "https://cdn.example.com/articles/test.png",
    );
  });

  it("3. 既存 s3_key は skip", async () => {
    const { restoreImagesFromS3 } = await import(
      "../../scripts/restore-images-from-s3.js"
    );

    // 既存 index.json を事前に作成
    const existingIndex = {
      images: [
        {
          sha256: "abc123",
          ext: "png",
          size: 100,
          added_at: "2026-01-01T00:00:00Z",
          s3_key: "articles/existing.png",
        },
      ],
    };
    await fs.writeFile(
      path.join(imagesDir, "index.json"),
      JSON.stringify(existingIndex, null, 2),
      "utf-8",
    );

    const getS3Object = vi.fn();

    const result = await restoreImagesFromS3(
      { bucket: "test-bucket", execute: true },
      {
        imagesDir,
        listS3Objects: vi.fn().mockResolvedValue([
          { key: "articles/existing.png", size: 100 }, // 既存 key
        ]),
        getS3Object,
      },
    );

    expect(result.total).toBe(1);
    expect(result.skipped).toBe(1);
    expect(result.downloaded).toBe(0);
    expect(getS3Object).not.toHaveBeenCalled();
  });

  it("4. main: AWS_S3_BUCKET 未設定 → exit 1", async () => {
    const { main } = await import("../../scripts/restore-images-from-s3.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    const code = await main(["node", "restore-images-from-s3.ts", "--execute"], {
      imagesDir,
      streams,
      env: {}, // AWS_S3_BUCKET なし
    });

    expect(code).toBe(1);
    expect(
      streams.err.some((l) => /AWS_S3_BUCKET/i.test(l)),
    ).toBe(true);
  });

  it("5. download エラーは errors カウントに計上されるが他は続行", async () => {
    const { restoreImagesFromS3 } = await import(
      "../../scripts/restore-images-from-s3.js"
    );

    const goodContent = Buffer.from("good-image");

    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    const result = await restoreImagesFromS3(
      { bucket: "test-bucket", execute: true },
      {
        imagesDir,
        listS3Objects: vi.fn().mockResolvedValue([
          { key: "articles/bad.png", size: 100 },
          { key: "articles/good.png", size: goodContent.length },
        ]),
        getS3Object: vi
          .fn()
          .mockRejectedValueOnce(new Error("S3 download failed"))
          .mockResolvedValueOnce(goodContent),
        streams,
      },
    );

    expect(result.total).toBe(2);
    expect(result.downloaded).toBe(1);
    expect(result.errors).toBe(1);
    expect(streams.err.some((l) => /error/i.test(l))).toBe(true);
  });

  it("6. main dry-run: exit 0 + 件数表示", async () => {
    const { main } = await import("../../scripts/restore-images-from-s3.js");
    const streams = {
      out: [] as string[],
      err: [] as string[],
      write: (l: string) => streams.out.push(l),
      writeErr: (l: string) => streams.err.push(l),
    };

    const code = await main(
      ["node", "restore-images-from-s3.ts"], // --execute なし = dry-run
      {
        imagesDir,
        listS3Objects: vi.fn().mockResolvedValue([
          { key: "articles/a.png", size: 10 },
          { key: "articles/b.png", size: 20 },
        ]),
        getS3Object: vi.fn(),
        streams,
        env: { AWS_S3_BUCKET: "my-bucket" },
      },
    );

    expect(code).toBe(0);
    expect(streams.out.some((l) => /dry-run/i.test(l))).toBe(true);
    expect(streams.out.some((l) => /total=2/i.test(l))).toBe(true);
  });
});
