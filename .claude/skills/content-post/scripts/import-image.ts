#!/usr/bin/env tsx
/**
 * scripts/import-image.ts — 画像を contents_manage/images/ に sha256 重複排除でインポート
 *
 * Usage:
 *   node scripts/import-image.ts --src <path>         # ローカルファイル
 *   node scripts/import-image.ts --url <url>          # リモート download
 *
 * Exit codes:
 *   0 — success (重複 skip も含む)
 *   1 — error (ファイルなし / download 失敗等)
 */
import "dotenv/config";
import { Command } from "commander";
import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ImageIndexEntry {
  sha256: string;
  ext: string;
  size: number;
  added_at: string;
  original_url?: string;
  s3_key?: string;
  cloudfront_url?: string;
}

export interface ImageIndex {
  images: ImageIndexEntry[];
}

export interface ImportImageDeps {
  /** contents_manage/images/ の絶対パス (テストで tmpDir を注入) */
  imagesDir?: string;
  /** ファイルを読む (テストで mock 可能) */
  readFile?: (p: string) => Promise<Buffer>;
  /** リモート URL から download (テストで mock 可能) */
  fetchUrl?: (url: string) => Promise<{ buffer: Buffer; contentType: string }>;
  streams?: {
    write: (line: string) => void;
    writeErr: (line: string) => void;
  };
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

export function sha256hex(buf: Buffer): string {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

export function extFromContentType(contentType: string): string {
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/webp": "webp",
    "image/gif": "gif",
    "image/svg+xml": "svg",
    "image/avif": "avif",
  };
  const lower = contentType.split(";")[0].trim().toLowerCase();
  return map[lower] ?? "bin";
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

// ---------------------------------------------------------------------------
// importImage (core logic, exported for tests)
// ---------------------------------------------------------------------------

export interface ImportImageResult {
  sha256: string;
  ext: string;
  localPath: string;
  skipped: boolean; // true = 重複で skip
}

export async function importImage(
  opts: {
    srcPath?: string;
    srcUrl?: string;
  },
  deps: ImportImageDeps = {},
): Promise<ImportImageResult> {
  const imagesDir = deps.imagesDir ?? defaultImagesDir();
  await fs.mkdir(imagesDir, { recursive: true });

  let buffer: Buffer;
  let ext: string;
  let originalUrl: string | undefined;

  if (opts.srcPath) {
    // ローカルファイル読み込み
    const readFileFn =
      deps.readFile ?? ((p: string) => fs.readFile(p) as Promise<Buffer>);
    buffer = await readFileFn(opts.srcPath);
    ext = path.extname(opts.srcPath).replace(/^\./, "") || "bin";
    originalUrl = undefined;
  } else if (opts.srcUrl) {
    // リモート download
    if (deps.fetchUrl) {
      const result = await deps.fetchUrl(opts.srcUrl);
      buffer = result.buffer;
      ext = extFromContentType(result.contentType);
    } else {
      const res = await fetch(opts.srcUrl);
      if (!res.ok) {
        throw new Error(
          `download failed: ${res.status} ${res.statusText} — ${opts.srcUrl}`,
        );
      }
      const arrayBuf = await res.arrayBuffer();
      buffer = Buffer.from(arrayBuf);
      const ct = res.headers.get("content-type") ?? "application/octet-stream";
      ext = extFromContentType(ct);
    }
    originalUrl = opts.srcUrl;
  } else {
    throw new Error("Either --src or --url must be provided");
  }

  const sha256 = sha256hex(buffer);
  const destFilename = `${sha256}.${ext}`;
  const destPath = path.join(imagesDir, destFilename);

  // 重複チェック
  const index = await readIndex(imagesDir);
  const existing = index.images.find((e) => e.sha256 === sha256);
  if (existing) {
    return { sha256, ext, localPath: destPath, skipped: true };
  }

  // 保存
  await fs.writeFile(destPath, buffer);

  // index.json 更新
  const entry: ImageIndexEntry = {
    sha256,
    ext,
    size: buffer.length,
    added_at: new Date().toISOString(),
    ...(originalUrl ? { original_url: originalUrl } : {}),
  };
  index.images.push(entry);
  await writeIndex(imagesDir, index);

  return { sha256, ext, localPath: destPath, skipped: false };
}

// ---------------------------------------------------------------------------
// main (exported for tests)
// ---------------------------------------------------------------------------

export async function main(
  argv: string[],
  deps: ImportImageDeps = {},
): Promise<number> {
  const streams = deps.streams ?? {
    write: (line: string) => console.log(line),
    writeErr: (line: string) => console.error(line),
  };

  const program = new Command();
  program
    .name("import-image")
    .description("画像を contents_manage/images/ に sha256 重複排除でインポート")
    .option("--src <path>", "ローカルファイルパス")
    .option("--url <url>", "リモート画像 URL")
    .exitOverride();

  try {
    program.parse(argv);
  } catch {
    streams.writeErr("[import-image] argument parse error");
    return 1;
  }

  const opts = program.opts<{ src?: string; url?: string }>();

  if (!opts.src && !opts.url) {
    streams.writeErr("[import-image] --src or --url is required");
    return 1;
  }

  try {
    const result = await importImage({ srcPath: opts.src, srcUrl: opts.url }, deps);

    if (result.skipped) {
      streams.write(
        `[import-image] skip (duplicate): ${result.sha256}.${result.ext}`,
      );
    } else {
      streams.write(`[import-image] saved: ${result.localPath}`);
    }
    return 0;
  } catch (err) {
    streams.writeErr(`[import-image] ${(err as Error).message}`);
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
    return scriptPath === invokedPath || process.argv[1].endsWith("import-image.ts");
  } catch {
    return false;
  }
}

if (isDirectInvocation()) {
  main(process.argv).then((code) => process.exit(code));
}
