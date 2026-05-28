#!/usr/bin/env tsx
/**
 * scripts/contents-list.ts — contents_manage/ コンテンツ一覧 CLI
 *
 * Usage:
 *   node scripts/contents-list.ts           # テーブル形式で stdout
 *   node scripts/contents-list.ts --md      # INDEX.md を再生成
 *   node scripts/contents-list.ts --json    # JSON 出力
 *
 * Exit codes:
 *   0 — success
 *   1 — error
 */
import { Command } from "commander";
import path from "node:path";
import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";
import {
  listContents,
  generateIndexMd,
  type ContentSummary,
} from "../src/posting/version-manager.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ContentsListDeps {
  contentsDir?: string;
  streams?: {
    write: (line: string) => void;
    writeErr: (line: string) => void;
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function defaultContentsDir(): string {
  const skillRoot = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
  );
  return path.join(skillRoot, "contents_manage", "contents");
}

function defaultIndexMdPath(contentsDir: string): string {
  return path.join(contentsDir, "..", "INDEX.md");
}

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max - 3) + "..." : s;
}

/**
 * ContentSummary[] をターミナル向けテーブル形式の文字列に変換する。
 */
export function formatTable(summaries: ContentSummary[]): string {
  if (summaries.length === 0) {
    return "No contents found.";
  }

  const header =
    "Kind          | Slug                                             | Versions | Current | Published | Status";
  const divider =
    "--------------|--------------------------------------------------|----------|---------|-----------|----------";

  const rows = summaries.map((s) => {
    const kind = s.kind.padEnd(13);
    const slug = truncate(s.slug, 49).padEnd(49);
    const versions = String(s.totalVersions).padStart(8);
    const current = `v${s.currentVersion}`.padStart(7);
    const published = `v${s.publishedVersion}`.padStart(9);
    const status = s.status.padEnd(10);
    return `${kind} | ${slug} | ${versions} | ${current} | ${published} | ${status}`;
  });

  return [header, divider, ...rows].join("\n");
}

// ---------------------------------------------------------------------------
// main (exported for tests)
// ---------------------------------------------------------------------------

export async function main(
  argv: string[],
  deps: ContentsListDeps = {},
): Promise<number> {
  const streams = deps.streams ?? {
    write: (line: string) => console.log(line),
    writeErr: (line: string) => console.error(line),
  };

  const program = new Command();
  program
    .name("contents-list")
    .description("contents_manage/ コンテンツ一覧を表示")
    .option("--md", "INDEX.md を再生成", false)
    .option("--json", "JSON 形式で出力", false)
    .exitOverride();

  try {
    program.parse(argv);
  } catch {
    streams.writeErr("[contents-list] argument parse error");
    return 1;
  }

  const opts = program.opts<{ md: boolean; json: boolean }>();
  const contentsDir = deps.contentsDir ?? defaultContentsDir();

  try {
    const summaries = await listContents({ contentsDir });

    if (opts.json) {
      streams.write(JSON.stringify(summaries, null, 2));
      return 0;
    }

    if (opts.md) {
      const md = generateIndexMd(summaries);
      const indexPath = defaultIndexMdPath(contentsDir);
      await fs.writeFile(indexPath, md, "utf-8");
      streams.write(`[contents-list] INDEX.md generated: ${indexPath}`);
      streams.write(`[contents-list] ${summaries.length} articles indexed`);
      return 0;
    }

    // デフォルト: テーブル形式
    streams.write(formatTable(summaries));
    return 0;
  } catch (err) {
    streams.writeErr(`[contents-list] ${(err as Error).message}`);
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
    return scriptPath === invokedPath || process.argv[1].endsWith("contents-list.ts");
  } catch {
    return false;
  }
}

if (isDirectInvocation()) {
  main(process.argv).then((code) => process.exit(code));
}
