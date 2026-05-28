#!/usr/bin/env tsx
/**
 * scripts/restore-images-from-s3.ts — S3 孤立画像を contents_manage/images/ に復旧
 *
 * Usage:
 *   node scripts/restore-images-from-s3.ts [--execute] [--dry-run] [--prefix <prefix>]
 *
 * Default: dry-run (--execute で実際に download + 保存)
 *
 * Exit codes:
 *   0 — success
 *   1 — error (S3 接続失敗等)
 *
 * 環境変数:
 *   AWS_S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
 *   CLOUDFRONT_DOMAIN (optional — index.json の cloudfront_url に使用)
 */
import "dotenv/config";
import { Command } from "commander";
import { S3Client, ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { sha256hex, extFromContentType } from "./import-image.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ImageIndexEntry {
  sha256: string;
  ext: string;
  size: number;
  added_at: string;
  s3_key?: string;
  cloudfront_url?: string;
  original_url?: string;
}

export interface ImageIndex {
  images: ImageIndexEntry[];
}

export interface S3Object {
  key: string;
  size: number;
}

export interface RestoreImagesDeps {
  imagesDir?: string;
  /** S3 オブジェクト一覧を返す関数 (テストで mock) */
  listS3Objects?: (opts: { bucket: string; prefix?: string }) => Promise<S3Object[]>;
  /** S3 オブジェクトの内容を Buffer で返す関数 (テストで mock) */
  getS3Object?: (opts: { bucket: string; key: string }) => Promise<Buffer>;
  streams?: {
    write: (line: string) => void;
    writeErr: (line: string) => void;
  };
  env?: Record<string, string | undefined>;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function defaultImagesDir(): string {
  const skillRoot = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
  );
  return path.join(skillRoot, "contents_manage", "images");
}

async function readIndex(imagesDir: string): Promise<ImageIndex> {
  const indexPath = path.join(imagesDir, "index.json");
  try {
    const raw = await fs.readFile(indexPath, "utf-8");
    return JSON.parse(raw) as ImageIndex;
  } catch {
    return { images: [] };
  }
}

async function writeIndex(imagesDir: string, index: ImageIndex): Promise<void> {
  const indexPath = path.join(imagesDir, "index.json");
  await fs.writeFile(indexPath, JSON.stringify(index, null, 2) + "\n", "utf-8");
}

function extFromKey(key: string): string {
  const ext = path.extname(key).replace(/^\./, "").toLowerCase();
  return ext || "bin";
}

function buildCloudfrontUrl(key: string, domain?: string): string | undefined {
  if (!domain) return undefined;
  const d = domain.replace(/\/$/, "");
  const k = key.startsWith("/") ? key : `/${key}`;
  return `https://${d}${k}`;
}

// ---------------------------------------------------------------------------
// restoreImagesFromS3 (core, exported for tests)
// ---------------------------------------------------------------------------

export interface RestoreResult {
  total: number;
  downloaded: number;
  skipped: number;
  errors: number;
}

export async function restoreImagesFromS3(
  opts: {
    bucket: string;
    prefix?: string;
    execute: boolean;
    cloudfrontDomain?: string;
  },
  deps: RestoreImagesDeps = {},
): Promise<RestoreResult> {
  const imagesDir = deps.imagesDir ?? defaultImagesDir();

  if (opts.execute) {
    await fs.mkdir(imagesDir, { recursive: true });
  }

  // S3 オブジェクト一覧取得
  let objects: S3Object[];
  if (deps.listS3Objects) {
    objects = await deps.listS3Objects({ bucket: opts.bucket, prefix: opts.prefix });
  } else {
    const env = deps.env ?? (process.env as Record<string, string | undefined>);
    const s3 = new S3Client({
      region: env["AWS_REGION"] ?? "ap-northeast-1",
      credentials:
        env["AWS_ACCESS_KEY_ID"] && env["AWS_SECRET_ACCESS_KEY"]
          ? {
              accessKeyId: env["AWS_ACCESS_KEY_ID"]!,
              secretAccessKey: env["AWS_SECRET_ACCESS_KEY"]!,
            }
          : undefined,
    });

    objects = [];
    let continuationToken: string | undefined;
    do {
      const res = await s3.send(
        new ListObjectsV2Command({
          Bucket: opts.bucket,
          Prefix: opts.prefix,
          ContinuationToken: continuationToken,
        }),
      );
      for (const obj of res.Contents ?? []) {
        if (obj.Key && obj.Size !== undefined) {
          objects.push({ key: obj.Key, size: obj.Size });
        }
      }
      continuationToken = res.NextContinuationToken;
    } while (continuationToken);
  }

  // 現在の index を読み込む (重複チェック用)
  const index = opts.execute ? await readIndex(imagesDir) : { images: [] as ImageIndexEntry[] };
  const existingKeys = new Set(index.images.map((e) => e.s3_key));

  const result: RestoreResult = { total: objects.length, downloaded: 0, skipped: 0, errors: 0 };

  for (const obj of objects) {
    // 既存 key は skip
    if (existingKeys.has(obj.key)) {
      result.skipped++;
      continue;
    }

    if (!opts.execute) {
      // dry-run: カウントだけ
      result.downloaded++;
      continue;
    }

    try {
      // S3 から download
      let buffer: Buffer;
      if (deps.getS3Object) {
        buffer = await deps.getS3Object({ bucket: opts.bucket, key: obj.key });
      } else {
        const env = deps.env ?? (process.env as Record<string, string | undefined>);
        const s3 = new S3Client({
          region: env["AWS_REGION"] ?? "ap-northeast-1",
          credentials:
            env["AWS_ACCESS_KEY_ID"] && env["AWS_SECRET_ACCESS_KEY"]
              ? {
                  accessKeyId: env["AWS_ACCESS_KEY_ID"]!,
                  secretAccessKey: env["AWS_SECRET_ACCESS_KEY"]!,
                }
              : undefined,
        });
        const res = await s3.send(
          new GetObjectCommand({ Bucket: opts.bucket, Key: obj.key }),
        );
        if (!res.Body) throw new Error(`empty body for key ${obj.key}`);
        const chunks: Uint8Array[] = [];
        for await (const chunk of res.Body as AsyncIterable<Uint8Array>) {
          chunks.push(chunk);
        }
        buffer = Buffer.concat(chunks);
      }

      const sha256 = sha256hex(buffer);
      const ext = extFromKey(obj.key);
      const destFilename = `${sha256}.${ext}`;
      const destPath = path.join(imagesDir, destFilename);

      // sha256 重複チェック (同 sha256 で別 key)
      const sha256Existing = index.images.find((e) => e.sha256 === sha256);
      if (sha256Existing) {
        // 同一コンテンツ — s3_key だけ追記して skip
        sha256Existing.s3_key = obj.key;
        result.skipped++;
        continue;
      }

      await fs.writeFile(destPath, buffer);

      const entry: ImageIndexEntry = {
        sha256,
        ext,
        size: buffer.length,
        added_at: new Date().toISOString(),
        s3_key: obj.key,
        cloudfront_url: buildCloudfrontUrl(obj.key, opts.cloudfrontDomain),
      };
      index.images.push(entry);
      existingKeys.add(obj.key);
      result.downloaded++;
    } catch (err) {
      deps.streams?.writeErr?.(
        `[restore-images] error on ${obj.key}: ${(err as Error).message}`,
      );
      result.errors++;
    }
  }

  if (opts.execute) {
    await writeIndex(imagesDir, index);
  }

  return result;
}

// ---------------------------------------------------------------------------
// main (exported for tests)
// ---------------------------------------------------------------------------

export async function main(
  argv: string[],
  deps: RestoreImagesDeps = {},
): Promise<number> {
  const streams = deps.streams ?? {
    write: (line: string) => console.log(line),
    writeErr: (line: string) => console.error(line),
  };

  const program = new Command();
  program
    .name("restore-images-from-s3")
    .description("S3 bucket の全画像を contents_manage/images/ に復旧")
    .option("--execute", "実際に download + 保存 (未指定時は dry-run)", false)
    .option("--dry-run", "件数カウントのみ (--execute より優先)", false)
    .option("--prefix <prefix>", "S3 key prefix フィルタ")
    .exitOverride();

  try {
    program.parse(argv);
  } catch {
    streams.writeErr("[restore-images] argument parse error");
    return 1;
  }

  const opts = program.opts<{
    execute: boolean;
    dryRun: boolean;
    prefix?: string;
  }>();

  const env = deps.env ?? (process.env as Record<string, string | undefined>);
  const bucket = env["AWS_S3_BUCKET"];
  if (!bucket) {
    streams.writeErr("[restore-images] AWS_S3_BUCKET env var is required");
    return 1;
  }

  const execute = opts.execute && !opts.dryRun;
  const cloudfrontDomain = env["CLOUDFRONT_DOMAIN"];

  streams.write(
    `[restore-images] ${execute ? "execute" : "dry-run"} — bucket=${bucket}${opts.prefix ? ` prefix=${opts.prefix}` : ""}`,
  );

  try {
    const result = await restoreImagesFromS3(
      { bucket, prefix: opts.prefix, execute, cloudfrontDomain },
      deps,
    );

    streams.write(
      `[restore-images] done: total=${result.total} downloaded=${result.downloaded} skipped=${result.skipped} errors=${result.errors}`,
    );
    return result.errors > 0 ? 1 : 0;
  } catch (err) {
    streams.writeErr(`[restore-images] ${(err as Error).message}`);
    return 1;
  }
}

// ---------------------------------------------------------------------------
// CLI entrypoint
// ---------------------------------------------------------------------------

function isDirectInvocation(): boolean {
  try {
    if (typeof process === "undefined" || !process.argv[1]) return false;
    const scriptPath = fileURLToPath(import.meta.url);
    const invokedPath = path.resolve(process.argv[1]);
    return scriptPath === invokedPath || process.argv[1].endsWith("restore-images-from-s3.ts");
  } catch {
    return false;
  }
}

if (isDirectInvocation()) {
  main(process.argv).then((code) => process.exit(code));
}
