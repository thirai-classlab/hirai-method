/**
 * src/posting/version-manager.ts
 *
 * コンテンツバージョン管理 — contents_manage/ の read/write を担当。
 *
 * 公開 API:
 *   validateMetaSchema(meta)                     — meta.json 構造バリデーション
 *   snapshotBeforeUpdate(slug, kind, deps)        — DB 取得 → ローカル退避
 *   bumpVersion(slug, opts, deps?)               — meta.json current_version++ 更新
 *   loadCurrentMarkdown(slug, deps?)             — v{current}/post.md 読み込み
 *   saveSnapshotAfter(slug, version, html, deps?) — v{N}/snapshot.html 書き込み
 *
 * 設計方針:
 *   - 全ての外部 I/O (fs, DB fetch) は deps で注入可能にして unit-testable を保つ
 *   - snapshotBeforeUpdate が失敗した場合は throw して呼び出し元に伝播させる
 *     (post.ts は catch して DB UPDATE を実行しない = fail-safe)
 */

import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ContentKind = "tech_article" | "weekly_issue" | "knowledge";

export interface MetaVersionEntry {
  v: number;
  created_at: string;
  author: string;
  snapshot_taken: boolean;
  note?: string;
}

export interface ContentMeta {
  slug: string;
  kind: ContentKind;
  title: string;
  current_version: number;
  published_version: number;
  published_at?: string;
  versions: MetaVersionEntry[];
}

/** DB から取得したコンテンツの最小限のフィールド */
export interface FetchedContent {
  body: string;
  raw_markdown: string | null;
}

// ---------------------------------------------------------------------------
// Default paths
// ---------------------------------------------------------------------------

/** contents_manage/contents/ の絶対パスを返す (デフォルト) */
function defaultContentsDir(): string {
  // __dirname 相当: src/posting/ → 2 階層上が スキルルート
  const skillRoot = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "../..",
  );
  return path.join(skillRoot, "contents_manage", "contents");
}

// ---------------------------------------------------------------------------
// validateMetaSchema
// ---------------------------------------------------------------------------

const VALID_KINDS: ContentKind[] = ["tech_article", "weekly_issue", "knowledge"];

/**
 * meta.json の構造を検証する。問題があれば throw する。
 */
export function validateMetaSchema(meta: unknown): asserts meta is ContentMeta {
  if (typeof meta !== "object" || meta === null) {
    throw new Error("meta.json must be an object");
  }
  const m = meta as Record<string, unknown>;

  if (typeof m["slug"] !== "string" || m["slug"].length === 0) {
    throw new Error("meta.json: slug is required and must be a non-empty string");
  }

  if (!VALID_KINDS.includes(m["kind"] as ContentKind)) {
    throw new Error(
      `meta.json: kind must be one of ${VALID_KINDS.join(", ")} (got "${String(m["kind"])}") `,
    );
  }

  if (typeof m["title"] !== "string") {
    throw new Error("meta.json: title must be a string");
  }

  if (
    typeof m["current_version"] !== "number" ||
    !Number.isInteger(m["current_version"]) ||
    m["current_version"] < 1
  ) {
    throw new Error(
      `meta.json: current_version must be a positive integer (got ${String(m["current_version"])})`,
    );
  }

  if (!Array.isArray(m["versions"])) {
    throw new Error("meta.json: versions must be an array");
  }

  for (const entry of m["versions"] as unknown[]) {
    if (typeof entry !== "object" || entry === null) {
      throw new Error("meta.json: versions entries must be objects");
    }
    const e = entry as Record<string, unknown>;
    if (typeof e["v"] !== "number" || typeof e["created_at"] !== "string" || typeof e["author"] !== "string" || typeof e["snapshot_taken"] !== "boolean") {
      throw new Error(
        "meta.json: versions entries must have v (number), created_at (string), author (string), snapshot_taken (boolean)",
      );
    }
  }
}

// ---------------------------------------------------------------------------
// readMeta / writeMeta helpers
// ---------------------------------------------------------------------------

async function readMeta(slugDir: string): Promise<ContentMeta> {
  const metaPath = path.join(slugDir, "meta.json");
  let raw: string;
  try {
    raw = await fs.readFile(metaPath, "utf-8");
  } catch {
    throw new Error(`meta.json not found at ${metaPath}`);
  }
  const parsed: unknown = JSON.parse(raw);
  validateMetaSchema(parsed);
  return parsed;
}

async function writeMeta(slugDir: string, meta: ContentMeta): Promise<void> {
  const metaPath = path.join(slugDir, "meta.json");
  await fs.writeFile(metaPath, JSON.stringify(meta, null, 2) + "\n", "utf-8");
}

// ---------------------------------------------------------------------------
// snapshotBeforeUpdate
// ---------------------------------------------------------------------------

export interface SnapshotBeforeUpdateDeps {
  /** contents_manage/contents/ の絶対パス (テストで tmpDir を注入) */
  contentsDir?: string;
  /** DB から body + raw_markdown を取得する関数 */
  fetchCurrentContent: (
    slug: string,
    kind: ContentKind,
  ) => Promise<FetchedContent | null>;
}

/**
 * --update 実行前の必須前処理:
 * 1. meta.json を読んで current_version を確認
 *    (meta.json が存在しない場合は DB から遡及作成して v1 として扱う)
 * 2. DB から現在の body を取得
 * 3. v{N+1}/snapshot-before-update.html に保存
 *
 * DB 取得に失敗した場合は throw → 呼び出し元 (post.ts) で catch して中断
 */
export interface SnapshotBeforeUpdateResult {
  /** The next (new) version number that was prepared. */
  nextVersion: number;
}

export async function snapshotBeforeUpdate(
  slug: string,
  kind: ContentKind,
  deps: SnapshotBeforeUpdateDeps,
): Promise<SnapshotBeforeUpdateResult> {
  const contentsDir = deps.contentsDir ?? defaultContentsDir();
  const slugDir = path.join(contentsDir, slug);
  await fs.mkdir(slugDir, { recursive: true });

  // 1. DB から現在の body を取得 (これが失敗したら throw して中断)
  const fetched = await deps.fetchCurrentContent(slug, kind);
  if (!fetched) {
    throw new Error(
      `snapshotBeforeUpdate: ${slug} not found in DB — aborting to prevent overwrite`,
    );
  }

  // 2. meta.json を読む。存在しなければ遡及的に v1 として作成する。
  let meta: ContentMeta;
  try {
    meta = await readMeta(slugDir);
  } catch {
    // meta.json が存在しない = version management 導入前のコンテンツ
    // DB の現状を v1 として遡及保存して続行する
    const v1Dir = path.join(slugDir, "v1");
    await fs.mkdir(v1Dir, { recursive: true });
    await fs.writeFile(path.join(v1Dir, "snapshot.html"), fetched.body, "utf-8");
    if (fetched.raw_markdown) {
      await fs.writeFile(path.join(v1Dir, "post.md"), fetched.raw_markdown, "utf-8");
    }
    const now = new Date().toISOString();
    meta = {
      slug,
      kind,
      title: slug, // title は DB から取れないのでスラッグで代用
      current_version: 1,
      published_version: 1,
      versions: [
        {
          v: 1,
          created_at: now,
          author: "snapshotBeforeUpdate (auto-seed)",
          snapshot_taken: true,
          note: "auto-seeded by snapshotBeforeUpdate — version management was not initialized",
        },
      ],
    };
    validateMetaSchema(meta);
    await writeMeta(slugDir, meta);
  }

  // 3. 次のバージョンディレクトリに退避
  const nextVersion = meta.current_version + 1;
  const nextVersionDir = path.join(slugDir, `v${nextVersion}`);
  await fs.mkdir(nextVersionDir, { recursive: true });

  const snapshotPath = path.join(nextVersionDir, "snapshot-before-update.html");
  await fs.writeFile(snapshotPath, fetched.body, "utf-8");

  return { nextVersion };
}

// ---------------------------------------------------------------------------
// bumpVersion
// ---------------------------------------------------------------------------

export interface BumpVersionOpts {
  author: string;
  note?: string;
  publishedVersion?: number;
  contentsDir?: string;
  /**
   * When true, regenerate contents_manage/INDEX.md after bumping.
   * Defaults to false to avoid side-effects in unit tests.
   */
  refreshIndex?: boolean;
  // Initial creation options (when meta.json does not exist yet)
  initial?: boolean;
  slug?: string;
  kind?: ContentKind;
  title?: string;
  publishedAt?: string;
  /**
   * Raw markdown of the new version (task-54 fix 2: content-hash idempotency).
   *
   * When provided (and not `initial`):
   *   - The current version's stored `v{current}/post.md` is read and hashed.
   *   - If its sha256 matches `content`'s sha256, bumpVersion is a NO-OP
   *     (no version increment, no new entry, no INDEX refresh) and returns false.
   *   - Otherwise the version is bumped and `content` is persisted to
   *     `v{next}/post.md` so subsequent runs can compare against it.
   *
   * When omitted, behavior is unchanged (always bump) for backward compat.
   */
  content?: string;
}

function sha256(s: string): string {
  return createHash("sha256").update(s, "utf-8").digest("hex");
}

/**
 * meta.json の current_version をインクリメントして新 versions エントリを追加する。
 * initial=true の場合は meta.json を新規作成する。
 *
 * @returns true = bump した / false = content 同一で no-op skip した (task-54 fix 2)。
 *          initial 作成時は常に true。
 */
export async function bumpVersion(
  slug: string,
  opts: BumpVersionOpts,
): Promise<boolean> {
  const contentsDir = opts.contentsDir ?? defaultContentsDir();
  const slugDir = path.join(contentsDir, slug);
  await fs.mkdir(slugDir, { recursive: true });

  const now = new Date().toISOString();

  if (opts.initial) {
    // 新規 meta.json 作成
    const meta: ContentMeta = {
      slug: opts.slug ?? slug,
      kind: opts.kind ?? "knowledge",
      title: opts.title ?? slug,
      current_version: 1,
      published_version: opts.publishedVersion ?? 1,
      published_at: opts.publishedAt,
      versions: [
        {
          v: 1,
          created_at: now,
          author: opts.author,
          snapshot_taken: true,
          note: opts.note,
        },
      ],
    };
    validateMetaSchema(meta);
    await writeMeta(slugDir, meta);
    // initial 作成時も content が渡されていれば v1/post.md を保存し、
    // 次回 --update が同一内容なら冪等 skip できるようにする。
    if (opts.content !== undefined) {
      const v1Dir = path.join(slugDir, "v1");
      await fs.mkdir(v1Dir, { recursive: true });
      await fs.writeFile(path.join(v1Dir, "post.md"), opts.content, "utf-8");
    }
    return true;
  }

  // 既存 meta.json を読み込んで increment
  const meta = await readMeta(slugDir);

  // content-hash 冪等化 (task-54 fix 2):
  // content が渡され、直前 version の post.md と内容が同一なら bump せず no-op。
  if (opts.content !== undefined) {
    const currentMdPath = path.join(slugDir, `v${meta.current_version}`, "post.md");
    let currentMd: string | null = null;
    try {
      currentMd = await fs.readFile(currentMdPath, "utf-8");
    } catch {
      // 直前 version の post.md が無い場合は比較不能 → 通常通り bump する
      currentMd = null;
    }
    if (currentMd !== null && sha256(currentMd) === sha256(opts.content)) {
      // 同一内容: version を増やさない (冪等)
      return false;
    }
  }

  const nextVersion = meta.current_version + 1;

  const newEntry: MetaVersionEntry = {
    v: nextVersion,
    created_at: now,
    author: opts.author,
    snapshot_taken: true,
    ...(opts.note !== undefined ? { note: opts.note } : {}),
  };

  const updated: ContentMeta = {
    ...meta,
    current_version: nextVersion,
    published_version: opts.publishedVersion ?? nextVersion,
    versions: [...meta.versions, newEntry],
  };

  validateMetaSchema(updated);
  await writeMeta(slugDir, updated);

  // 新 version の post.md を保存して、次回の content-hash 比較の基準にする。
  if (opts.content !== undefined) {
    const nextVersionDir = path.join(slugDir, `v${nextVersion}`);
    await fs.mkdir(nextVersionDir, { recursive: true });
    await fs.writeFile(path.join(nextVersionDir, "post.md"), opts.content, "utf-8");
  }

  // Auto-refresh INDEX.md when requested
  if (opts.refreshIndex) {
    await refreshIndexMd(contentsDir);
  }

  return true;
}

/**
 * contents_manage/INDEX.md を再生成するヘルパー (bumpVersion 内部から呼ばれる)。
 */
async function refreshIndexMd(contentsDir: string): Promise<void> {
  try {
    const summaries = await listContents({ contentsDir });
    const md = generateIndexMd(summaries);
    const indexPath = path.join(contentsDir, "..", "INDEX.md");
    await fs.writeFile(indexPath, md, "utf-8");
  } catch {
    // INDEX.md 更新失敗は非致命的 — 本体処理に影響させない
  }
}

// ---------------------------------------------------------------------------
// loadCurrentMarkdown
// ---------------------------------------------------------------------------

export interface LoadCurrentMarkdownDeps {
  contentsDir?: string;
}

/**
 * meta.json の current_version に対応する post.md を読み込む。
 * 存在しない場合は null を返す (throw しない)。
 */
export async function loadCurrentMarkdown(
  slug: string,
  deps: LoadCurrentMarkdownDeps = {},
): Promise<string | null> {
  const contentsDir = deps.contentsDir ?? defaultContentsDir();
  const slugDir = path.join(contentsDir, slug);

  let meta: ContentMeta;
  try {
    meta = await readMeta(slugDir);
  } catch {
    return null;
  }

  const postMdPath = path.join(slugDir, `v${meta.current_version}`, "post.md");
  try {
    return await fs.readFile(postMdPath, "utf-8");
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// saveSnapshotAfter
// ---------------------------------------------------------------------------

export interface SaveSnapshotAfterDeps {
  contentsDir?: string;
}

/**
 * DB UPDATE / INSERT 完了後に最終 HTML を v{N}/snapshot.html として保存する。
 */
export async function saveSnapshotAfter(
  slug: string,
  version: number,
  html: string,
  deps: SaveSnapshotAfterDeps = {},
): Promise<void> {
  const contentsDir = deps.contentsDir ?? defaultContentsDir();
  const versionDir = path.join(contentsDir, slug, `v${version}`);
  await fs.mkdir(versionDir, { recursive: true });
  await fs.writeFile(path.join(versionDir, "snapshot.html"), html, "utf-8");
}

// ---------------------------------------------------------------------------
// rollbackVersion
// ---------------------------------------------------------------------------

export interface RollbackVersionDeps {
  contentsDir?: string;
  /** DB body + raw_markdown を指定 version の snapshot から直接 UPDATE する関数 */
  updateContent: (
    slug: string,
    opts: { body: string; rawMarkdown: string | null },
  ) => Promise<void>;
  /** ISR revalidate を呼び出す関数 */
  revalidate?: () => Promise<void>;
}

export interface RollbackVersionResult {
  slug: string;
  rolledBackToVersion: number;
  previousVersion: number;
}

/**
 * 指定バージョンの snapshot.html を DB に書き戻す。
 * dry-run=true のときは読み込み + diff 表示のみで DB には触らない。
 */
export async function rollbackVersion(
  slug: string,
  toVersion: number,
  opts: { dryRun?: boolean; noRevalidate?: boolean },
  deps: RollbackVersionDeps,
): Promise<RollbackVersionResult> {
  const contentsDir = deps.contentsDir ?? defaultContentsDir();
  const slugDir = path.join(contentsDir, slug);
  const versionDir = path.join(slugDir, `v${toVersion}`);

  // 1. snapshot.html を読む
  let snapshotHtml: string;
  try {
    snapshotHtml = await fs.readFile(path.join(versionDir, "snapshot.html"), "utf-8");
  } catch {
    throw Object.assign(
      new Error(`rollback: v${toVersion} snapshot.html not found for slug "${slug}"`),
      { code: "SNAPSHOT_NOT_FOUND", exitCode: 2 },
    );
  }

  if (snapshotHtml.trim().length === 0) {
    throw Object.assign(
      new Error(`rollback: v${toVersion} snapshot.html is empty for slug "${slug}"`),
      { code: "SNAPSHOT_EMPTY", exitCode: 2 },
    );
  }

  // 2. post.md を読む (raw_markdown 復元用、なければ null)
  let rawMarkdown: string | null = null;
  try {
    rawMarkdown = await fs.readFile(path.join(versionDir, "post.md"), "utf-8");
  } catch {
    // post.md が存在しなくても rollback 自体は続行できる
  }

  // 3. meta.json を読んで current_version を把握
  const meta = await readMeta(slugDir);
  const previousVersion = meta.current_version;

  if (opts.dryRun) {
    // dry-run: 読み込み確認のみ、DB は触らない
    return { slug, rolledBackToVersion: toVersion, previousVersion };
  }

  // 4. DB UPDATE
  try {
    await deps.updateContent(slug, { body: snapshotHtml, rawMarkdown });
  } catch (err) {
    throw Object.assign(
      new Error(`rollback: DB UPDATE failed — ${(err as Error).message}`),
      { exitCode: 1 },
    );
  }

  // 5. meta.json の published_version を更新 + rollback ログ追記
  const rollbackEntry: MetaVersionEntry & { rollback_from?: number; rollback_to?: number } = {
    v: previousVersion + 1,
    created_at: new Date().toISOString(),
    author: `rollback to v${toVersion}`,
    snapshot_taken: false,
    note: `rollback from v${previousVersion} to v${toVersion}`,
  };

  const updatedMeta: ContentMeta = {
    ...meta,
    current_version: previousVersion + 1,
    published_version: toVersion,
    versions: [...meta.versions, rollbackEntry],
  };
  validateMetaSchema(updatedMeta);
  await writeMeta(slugDir, updatedMeta);

  // 6. revalidate
  if (!opts.noRevalidate && deps.revalidate) {
    await deps.revalidate();
  }

  return { slug, rolledBackToVersion: toVersion, previousVersion };
}

// ---------------------------------------------------------------------------
// listContents / generateIndexMd
// ---------------------------------------------------------------------------

export interface ContentSummary {
  slug: string;
  kind: ContentKind;
  title: string;
  currentVersion: number;
  publishedVersion: number;
  totalVersions: number;
  status: "published" | "draft" | "archived";
  publishedAt?: string;
}

export interface ListContentsDeps {
  contentsDir?: string;
}

/**
 * contents_manage/contents/ 配下の全 slug の meta.json を読んで一覧を返す。
 */
export async function listContents(deps: ListContentsDeps = {}): Promise<ContentSummary[]> {
  const contentsDir = deps.contentsDir ?? defaultContentsDir();

  let slugDirs: string[];
  try {
    const entries = await fs.readdir(contentsDir, { withFileTypes: true });
    slugDirs = entries
      .filter((e) => e.isDirectory())
      .map((e) => e.name);
  } catch {
    return [];
  }

  const results: ContentSummary[] = [];
  for (const slug of slugDirs) {
    const slugDir = path.join(contentsDir, slug);
    try {
      const meta = await readMeta(slugDir);
      const status = deriveStatus(meta);
      results.push({
        slug: meta.slug,
        kind: meta.kind,
        title: meta.title,
        currentVersion: meta.current_version,
        publishedVersion: meta.published_version,
        totalVersions: meta.versions.length,
        status,
        publishedAt: meta.published_at,
      });
    } catch {
      // 読み込み失敗の slug はスキップ
    }
  }

  return results.sort((a, b) => a.slug.localeCompare(b.slug));
}

function deriveStatus(meta: ContentMeta): "published" | "draft" | "archived" {
  if (meta.published_at && meta.published_version >= 1) return "published";
  return "draft";
}

/**
 * ContentSummary[] を Markdown テーブル形式に変換する。
 */
export function generateIndexMd(summaries: ContentSummary[]): string {
  const now = new Date().toISOString();
  const header = [
    `<!-- AUTO-GENERATED by contents-list.ts at ${now} — DO NOT EDIT MANUALLY -->`,
    "",
    "# Contents Index",
    "",
    `Total: **${summaries.length}** articles`,
    "",
    "| Kind | Slug | Title | Versions | Current | Published | Status |",
    "|------|------|-------|----------|---------|-----------|--------|",
  ];

  const rows = summaries.map((s) => {
    const title = s.title.length > 40 ? s.title.slice(0, 37) + "..." : s.title;
    const statusEmoji = s.status === "published" ? "published" : s.status === "archived" ? "archived" : "draft";
    return `| ${s.kind} | ${s.slug} | ${title} | ${s.totalVersions} | v${s.currentVersion} | v${s.publishedVersion} | ${statusEmoji} |`;
  });

  return [...header, ...rows, ""].join("\n");
}
