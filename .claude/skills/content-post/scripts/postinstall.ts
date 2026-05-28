#!/usr/bin/env tsx
/**
 * postinstall / `npm run sync`
 *
 * Idempotently syncs two resources from the classlab-weekly-news repo into
 * the content-post skill:
 *
 *   1. `content-templates/*.yaml`  ← <repo>/content-templates/*.yaml
 *   2. `src/types/database.ts`     ← `supabase gen types typescript --linked`
 *
 * Behavior (per Wave D3 plan, `docs/pdca/phase-8-wave-d3/plan.md`):
 *   - If `CLASSLAB_WEEKLY_NEWS_DIR` is not set: warn + exit 0 (don't break
 *     `npm install` on machines that don't have the repo checked out).
 *   - If the dir does not exist: error log + exit 0 (same reason).
 *   - For each YAML file: compare byte-for-byte; log `create` / `update` /
 *     `skip` accordingly.
 *   - Supabase type regeneration is best-effort: if the CLI is missing or
 *     the command fails, log and continue.
 *
 * Environment variables:
 *   CLASSLAB_WEEKLY_NEWS_DIR            — path to the source repo (required)
 *   CLASSLAB_CONTENT_POST_SKILL_DIR     — override the destination skill dir
 *                                         (defaults to the script's parent dir)
 *   CONTENT_POST_DISABLE_SUPABASE_SYNC  — set to `1` in tests to skip the
 *                                         supabase step entirely
 */
import path from "node:path";
import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

type SyncTally = { created: number; updated: number; skipped: number };

function log(level: "info" | "warn" | "error", msg: string): void {
  const prefix =
    level === "info" ? "[content-post/postinstall]" : `[content-post/postinstall] ${level.toUpperCase()}:`;
  const stream = level === "error" ? process.stderr : process.stdout;
  stream.write(`${prefix} ${msg}\n`);
}

function resolveSkillDir(): string {
  const envDir = process.env.CLASSLAB_CONTENT_POST_SKILL_DIR;
  if (envDir) return path.resolve(envDir);
  const here = fileURLToPath(new URL(".", import.meta.url));
  return path.resolve(here, "..");
}

async function ensureDir(dir: string): Promise<void> {
  await fs.mkdir(dir, { recursive: true });
}

async function readIfExists(file: string): Promise<string | null> {
  try {
    return await fs.readFile(file, "utf8");
  } catch {
    return null;
  }
}

async function syncTemplates(
  sourceDir: string,
  destDir: string,
): Promise<SyncTally> {
  const tally: SyncTally = { created: 0, updated: 0, skipped: 0 };
  await ensureDir(destDir);

  const entries = await fs.readdir(sourceDir);
  const yamls = entries.filter((f) => f.endsWith(".yaml") || f.endsWith(".yml"));

  for (const name of yamls) {
    const src = path.join(sourceDir, name);
    const dst = path.join(destDir, name);
    const srcContent = await fs.readFile(src, "utf8");
    const dstContent = await readIfExists(dst);

    if (dstContent === null) {
      await fs.writeFile(dst, srcContent, "utf8");
      tally.created += 1;
      log("info", `create ${name}`);
    } else if (dstContent !== srcContent) {
      await fs.writeFile(dst, srcContent, "utf8");
      tally.updated += 1;
      log("info", `update ${name}`);
    } else {
      tally.skipped += 1;
      log("info", `skip   ${name}`);
    }
  }

  return tally;
}

function syncSupabaseTypes(sourceRepo: string, skillDir: string): void {
  if (process.env.CONTENT_POST_DISABLE_SUPABASE_SYNC === "1") {
    log("info", "supabase type sync disabled via CONTENT_POST_DISABLE_SUPABASE_SYNC");
    return;
  }
  if (!existsSync(path.join(sourceRepo, ".git"))) {
    log("info", "skip supabase types (source repo has no .git, likely not linked)");
    return;
  }
  // Probe the CLI.
  const probe = spawnSync("supabase", ["--version"], {
    stdio: "pipe",
    encoding: "utf8",
  });
  if (probe.status !== 0) {
    log("info", "skip supabase types (supabase CLI not found on PATH)");
    return;
  }

  const typesDir = path.join(skillDir, "src", "types");
  const typesFile = path.join(typesDir, "database.ts");
  const result = spawnSync(
    "supabase",
    ["gen", "types", "typescript", "--linked"],
    {
      cwd: sourceRepo,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  if (result.status !== 0) {
    log(
      "warn",
      `supabase gen types failed (status=${result.status}): ${result.stderr?.split("\n")[0] ?? ""}`,
    );
    return;
  }
  void (async () => {
    await ensureDir(typesDir);
    await fs.writeFile(typesFile, result.stdout, "utf8");
    log("info", `wrote ${path.relative(skillDir, typesFile)}`);
  })();
}

async function main(): Promise<number> {
  const skillDir = resolveSkillDir();
  const sourceRepo = process.env.CLASSLAB_WEEKLY_NEWS_DIR;

  if (!sourceRepo) {
    log(
      "warn",
      "CLASSLAB_WEEKLY_NEWS_DIR is not set; skipping template + supabase sync. Set it to the absolute path of the classlab-weekly-news repo and re-run `npm run sync`.",
    );
    return 0;
  }

  if (!existsSync(sourceRepo)) {
    log(
      "error",
      `CLASSLAB_WEEKLY_NEWS_DIR does not exist or cannot be read: ${sourceRepo}`,
    );
    // Exit 0 by design so that `npm install` is not broken on dev machines.
    return 0;
  }

  const templatesSrc = path.join(sourceRepo, "content-templates");
  if (!existsSync(templatesSrc)) {
    log("error", `Source templates directory not found: ${templatesSrc}`);
    return 0;
  }
  const templatesDst = path.join(skillDir, "content-templates");

  try {
    const tally = await syncTemplates(templatesSrc, templatesDst);
    log(
      "info",
      `templates: ${tally.created} created, ${tally.updated} updated, ${tally.skipped} skipped`,
    );
  } catch (err) {
    log("error", `template sync failed: ${(err as Error).message}`);
    // Still exit 0 — failures here shouldn't break npm install; user can re-run.
  }

  try {
    syncSupabaseTypes(sourceRepo, skillDir);
  } catch (err) {
    log("warn", `supabase type sync error: ${(err as Error).message}`);
  }

  return 0;
}

main().then(
  (code) => {
    process.exit(code);
  },
  (err: unknown) => {
    log("error", `unexpected failure: ${(err as Error).message}`);
    // Still exit 0 — npm install should not break.
    process.exit(0);
  },
);
