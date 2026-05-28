/**
 * Markdown image pipeline: detect local ![alt](path) references, upload to
 * S3, and rewrite the markdown so the published HTML serves images through
 * CloudFront instead of relative paths.
 *
 * Integration point: scripts/post.ts runs this after loadFile() and before
 * parseMarkdown() so the rendered HTML always points at CDN URLs.
 */
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";

import { imageSize } from "image-size";
import { uploadToS3 } from "./s3.js";

const ASPECT_16_9 = 16 / 9;
const ASPECT_1_1 = 1.0;
const ASPECT_TOLERANCE = 0.01;
const CROPPABLE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg", ".webp"]);

let _sipsWarned = false;
function sipsAvailable(): boolean {
  if (os.platform() !== "darwin") return false;
  const r = spawnSync("which", ["sips"], { encoding: "utf8" });
  return r.status === 0 && (r.stdout || "").trim().length > 0;
}

/**
 * Buffer を 16:9 に **center-crop** して返す。
 *
 * - 既に 16:9 ± 1% ならそのまま返す
 * - 正方形 (1:1 ± 1%) はベクター・ロゴ・アイコン用途として無加工
 * - SVG / GIF 等の非対応フォーマットは無加工
 * - macOS 以外ではスキップ（警告のみ）
 *
 * **方針**: 生成側で `--aspect 16:9` を使い、プロンプトに「上下 80px は
 * atmospheric only」指示を入れて生成された 1536x1024 画像を
 * 1536x864 に center-crop する。AI 画像生成パイプラインに最適化された
 * 設計で、生成→トリミングを 2 段で実現する。
 *
 * - 横長 (aspect > 16:9): 縦幅維持、左右を等量カット
 * - 縦長 (aspect < 16:9): 横幅維持、上下を等量カット（プロンプトで主要要素を
 *   中央 16:9 セーフエリアに収める前提）
 */
async function fitTo16x9CenterCrop(
  buffer: Buffer,
  filename: string,
): Promise<Buffer> {
  const ext = path.extname(filename).toLowerCase();
  if (!CROPPABLE_EXTENSIONS.has(ext)) return buffer;

  let dims: { width?: number; height?: number };
  try {
    dims = imageSize(buffer);
  } catch {
    return buffer;
  }
  const w = dims.width ?? 0;
  const h = dims.height ?? 0;
  if (w <= 0 || h <= 0) return buffer;

  const currentAspect = w / h;
  if (Math.abs(currentAspect - ASPECT_16_9) <= ASPECT_TOLERANCE) {
    return buffer;
  }
  // 正方形 (1:1) は記事内でアイコン・ロゴ・ベクター用途として保持。
  // crop すると一部欠落するので無加工で通す。
  if (Math.abs(currentAspect - ASPECT_1_1) <= ASPECT_TOLERANCE) {
    return buffer;
  }

  if (!sipsAvailable()) {
    if (!_sipsWarned) {
      console.warn(
        "[image-processor] WARN: sips unavailable (macOS-only) — 16:9 center-crop skipped.",
      );
      _sipsWarned = true;
    }
    return buffer;
  }

  // 16:9 に収まる最大寸法を決定（元画像から削るだけ、拡大はしない）
  let targetW: number;
  let targetH: number;
  if (currentAspect > ASPECT_16_9) {
    // 横長すぎ → 縦幅維持、左右をカット
    targetH = h;
    targetW = Math.round(h * ASPECT_16_9);
  } else {
    // 縦長すぎ → 横幅維持、上下をカット
    targetW = w;
    targetH = Math.round(w / ASPECT_16_9);
  }

  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "cp-img-"));
  const tmpFile = path.join(tmpDir, `crop${ext}`);
  await fs.writeFile(tmpFile, buffer);

  // sips -c H W (= cropToHeightWidth) は中央クロップ
  const r = spawnSync(
    "sips",
    ["-c", String(targetH), String(targetW), tmpFile],
    { encoding: "utf8" },
  );
  if (r.status !== 0) {
    console.warn(
      `[image-processor] WARN: sips crop failed on ${filename}: ${r.stderr?.trim() ?? "unknown"}`,
    );
    await fs.rm(tmpDir, { recursive: true, force: true });
    return buffer;
  }
  const cropped = await fs.readFile(tmpFile);
  await fs.rm(tmpDir, { recursive: true, force: true });
  return cropped;
}

// 旧名 cropTo16x9 を center-crop 実体へ繋ぐ (後方互換)
async function cropTo16x9(buffer: Buffer, filename: string): Promise<Buffer> {
  return fitTo16x9CenterCrop(buffer, filename);
}

export interface ImageReplacement {
  /** Original path written in the markdown (e.g. "./hero.png"). */
  originalPath: string;
  /** S3 object key the file was uploaded to. */
  s3Key: string;
  /** Public CloudFront URL for the uploaded object. */
  cdnUrl: string;
}

export interface ProcessImagesOptions {
  /** Slug of the content row, used as S3 key prefix. */
  slug: string;
  /** Content type used as first segment of the S3 key. */
  contentType: "knowledge" | "tech_article" | "issue";
  /** Directory that relative image paths should be resolved against. */
  baseDir: string;
}

const EXTENSION_CONTENT_TYPE: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
};

const IMAGE_MD_REGEX = /!\[([^\]]*)\]\(([^)]+)\)/g;

function isExternalUrl(src: string): boolean {
  return /^https?:\/\//i.test(src);
}

function isDataUrl(src: string): boolean {
  return src.startsWith("data:");
}

function contentTypeForFilename(filename: string): string {
  const ext = path.extname(filename).toLowerCase();
  return EXTENSION_CONTENT_TYPE[ext] ?? "application/octet-stream";
}

/**
 * Scan a markdown body for image references, upload each local file to S3,
 * and return the rewritten markdown + a replacement log.
 *
 * Skipped silently:
 *   - http(s):// external URLs (already on a CDN)
 *   - data: URLs (inline base64)
 *   - Missing files on disk (treated as a warning rather than a hard failure
 *     so a single broken draft path does not abort the whole pipeline)
 */
export async function processMarkdownImages(
  markdown: string,
  options: ProcessImagesOptions,
): Promise<{ markdown: string; replacements: ImageReplacement[] }> {
  const { slug, contentType, baseDir } = options;
  const replacements: ImageReplacement[] = [];
  let result = markdown;

  // Reset lastIndex by using matchAll on a fresh regex (regex is declared
  // with /g, but we also want to iterate deterministically before mutating
  // `result`).
  const matches = Array.from(markdown.matchAll(IMAGE_MD_REGEX));

  for (const match of matches) {
    const alt = match[1] ?? "";
    const src = match[2];
    if (!src) continue;
    if (isExternalUrl(src) || isDataUrl(src)) continue;

    const absPath = path.resolve(baseDir, src);
    let fileBuffer: Buffer;
    try {
      fileBuffer = await fs.readFile(absPath);
    } catch {
      // Missing file — leave the markdown untouched and move on.
      continue;
    }

    const filename = path.basename(absPath);

    // 16:9 へ center-crop してから S3 へ。既に 16:9 ならスキップ。
    // 生成側 (ai-image-gen-pro --aspect 16:9) でプロンプトに「上下 80px は
    // atmospheric only」指示が自動注入され、中央 864 帯セーフエリアに主要要素を
    // 配置するため、安全にクロップできる。
    // 正方形 (1:1) は recraft の SVG/ロゴ用途として無加工。
    // SVG/GIF など対応外フォーマットは無加工。非 macOS は警告して無加工。
    fileBuffer = await cropTo16x9(fileBuffer, filename);

    const hash = crypto
      .createHash("sha256")
      .update(fileBuffer)
      .digest("hex")
      .slice(0, 8);
    const s3Key = `${contentType}/${slug}/${hash}-${filename}`;
    const ct = contentTypeForFilename(filename);

    const { url } = await uploadToS3(s3Key, fileBuffer, ct);

    // Attempt to extract image dimensions for width/height attributes.
    let imgWidth: number | undefined;
    let imgHeight: number | undefined;
    try {
      const dims = imageSize(fileBuffer);
      imgWidth = dims.width;
      imgHeight = dims.height;
    } catch {
      // image-size failed (unknown format, truncated file, etc.) — skip dimensions.
    }

    // Emit an HTML img tag when dimensions are available so that the site
    // renderer does not need to add data-unknown-size.
    let replacement: string;
    if (imgWidth != null && imgHeight != null && imgWidth > 0 && imgHeight > 0) {
      const escapedAlt = alt.replace(/"/g, "&quot;");
      replacement = `<img src="${url}" alt="${escapedAlt}" width="${imgWidth}" height="${imgHeight}">`;
    } else {
      replacement = `![${alt}](${url})`;
    }
    result = result.replace(match[0], () => replacement);

    replacements.push({
      originalPath: src,
      s3Key,
      cdnUrl: url,
    });
  }

  return { markdown: result, replacements };
}

/**
 * Collect invalidation paths from already-published HTML so --update mode
 * can purge stale edge caches after re-uploading images for the same slug.
 *
 * Matches any URL that begins with `https://<cdnDomain>/` and strips the
 * host, returning `"/" + key`. Duplicates are preserved in caller order
 * (de-dupe lives at the call site if needed).
 */
export function extractCdnPathsForInvalidation(
  html: string,
  cdnDomain: string,
): string[] {
  const escaped = cdnDomain.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`https://${escaped}/([^"'\\s)]+)`, "g");
  return Array.from(html.matchAll(re)).map((m) => `/${m[1]}`);
}
