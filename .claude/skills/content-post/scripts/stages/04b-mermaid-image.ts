/**
 * scripts/stages/04b-mermaid-image.ts
 *
 * Stage 04b: knowledge コンテンツの ```mermaid``` ブロックを
 * Isometric 2.5D ベクター画像 (claude-image-pkg テーマ) に変換し、
 * markdown 内の mermaid ブロックを `![alt](path)` で完全置換する。
 *
 * 動作条件:
 *   - content-type === "knowledge" のみ実行 (テーマ固定運用)
 *   - --dry-run では skip (gpt-image-2 呼び出しを抑止)
 *   - mermaid ブロックが 1 件も含まれない場合は早期 skip
 *
 * 実装:
 *   gen-mermaid-images.mjs (スタンドアロン CLI) を spawn して in-place 書き換え。
 *   失敗時は logErr で警告するだけで pipeline 全体は継続する (best-effort)。
 *
 * テーマ仕様:
 *   ~/cc研修/claude-image-pkg/IMAGE-PLAYBOOK.md 準拠
 *   - 1536x1024 → 1536x864 center-crop
 *   - ivory beige + dotted grid + multi-pastel
 *   - mermaid 型 → 8 構造パターン (A-H) ヒューリスティック分類
 *
 * 注意:
 *   既存 stage 05 (image-upload) より前に挿入する必要がある。
 *   stage 05 が CloudFront へアップロードする対象に mermaid 生成画像も含めるため。
 */
import path from "node:path";
import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import type { PipelineContext } from "../types/pipeline-context.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const GEN_SCRIPT = path.resolve(__dirname, "..", "gen-mermaid-images.mjs");

export const stage04bMermaidImage = {
  name: "mermaid-image" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (ctx.contentType !== "knowledge") return;
    if (ctx.opts.dryRun) return;
    if (!ctx.source || !ctx.slug || !ctx.filePath) return;

    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const logErr = (s: string) => ctx.streams.writeErr(s);

    if (!/```mermaid/.test(ctx.source)) {
      verbose("[stage04b] mermaid ブロックなし、skip\n");
      return;
    }

    const baseDir = path.dirname(ctx.filePath);
    const outDir = path.join(baseDir, "images", ctx.slug);

    verbose(
      `[stage04b] mermaid → image 変換開始 (slug=${ctx.slug}, out=${outDir})\n`,
    );

    const result = spawnSync(
      "node",
      [
        GEN_SCRIPT,
        "--file",
        ctx.filePath,
        "--slug",
        ctx.slug,
        "--out-dir",
        outDir,
        "--content-type",
        ctx.contentType,
        "--in-place",
      ],
      { stdio: ["ignore", "inherit", "inherit"], encoding: "utf8" },
    );

    if (result.status !== 0) {
      logErr(
        `[stage04b] mermaid image gen failed (continuing): exit=${result.status}\n`,
      );
      return;
    }

    try {
      const updated = await fs.readFile(ctx.filePath, "utf8");
      ctx.source = updated;
      if (typeof ctx.deps.parseMarkdown === "function") {
        ctx.parsed = ctx.deps.parseMarkdown(updated);
      }
      verbose("[stage04b] mermaid 画像化完了、source を再読込\n");
    } catch (err) {
      logErr(
        `[stage04b] source reload failed (continuing): ${(err as Error).message}\n`,
      );
    }
  },
};
