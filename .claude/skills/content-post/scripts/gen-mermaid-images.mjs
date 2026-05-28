#!/usr/bin/env node
/**
 * gen-mermaid-images.mjs
 *
 * 本文中の ```mermaid``` ブロックを Isometric 2.5D 画像に変換し、
 * markdown 内のブロックを `![alt](path)` で完全置換するスタンドアロン CLI。
 *
 * テーマ仕様の正典は `~/cc研修/claude-image-pkg/IMAGE-PLAYBOOK.md`。
 * - サイズ: 1536x1024 生成 → 1536x864 center-crop
 * - 8 構造パターン分類 (A 直線フロー / B 階層 / C 比較 / D 分岐 /
 *   E ハブ&スポーク / F グループ / G 循環 / H 並列) を mermaid 型から推定
 * - knowledge コンテンツタイプ専用 (tech_articles / weekly_issues は実行しない)
 *
 * フロー:
 *   1. markdown から ```mermaid``` ブロックを位置情報付きで抽出
 *   2. 各ブロックの構造パターンを推定し、Haiku で英語プロンプトを生成
 *   3. ai-image-gen の gen.mjs を spawn して gpt-image-2 で画像生成
 *   4. 出力ファイルを mermaid-NN.png にリネーム
 *   5. markdown を !\[alt\](path) で完全置換 → stdout or in-place 書き出し
 *
 * 使い方:
 *   node gen-mermaid-images.mjs \
 *     --file ./drafts/foo.md \
 *     --slug my-slug \
 *     --out-dir ./drafts/images/my-slug \
 *     --content-type knowledge \
 *     [--in-place]   markdown を直接書き換える
 *     [--dry-run]    抽出のみで生成しない
 *
 * 必要 env:
 *   AI_GATEWAY_API_KEY (~/.claude/skills/ai-image-gen/.env から自動ロード)
 */

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync, spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

/**
 * デフォルト並列数。IMAGE-PLAYBOOK §5-2 によると AI Gateway は 6 並列が安定圏
 * (10-12 で速度優先、3-4 で安定性重視)。content-post パイプラインは投稿前提なので
 * 失敗による空白を避けるため 3 並列を default に取る。--concurrency で上書き可能。
 */
const DEFAULT_CONCURRENCY = 3;

const AI_GATEWAY_BASE = "https://ai-gateway.vercel.sh/v1";
const HAIKU_MODEL = "anthropic/claude-haiku-4.5";
const IMAGE_MODEL = "openai/gpt-image-2";
const AI_IMAGE_GEN_DIR = path.join(os.homedir(), ".claude/skills/ai-image-gen");
const GEN_MJS = path.join(AI_IMAGE_GEN_DIR, "scripts/gen.mjs");
const ENV_PATH = path.join(AI_IMAGE_GEN_DIR, ".env");

// .env を直読みして AI_GATEWAY_API_KEY を補完 (post.ts の dotenv 経路に乗らない場合の保険)
function loadAiGatewayEnv() {
  if (process.env.AI_GATEWAY_API_KEY || !fs.existsSync(ENV_PATH)) return;
  const text = fs.readFileSync(ENV_PATH, "utf8");
  for (const line of text.split("\n")) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!m) continue;
    const key = m[1];
    const val = m[2].replace(/^["']|["']$/g, "");
    if (!process.env[key]) process.env[key] = val;
  }
}

const MERMAID_RE = /```mermaid\n([\s\S]*?)\n```/g;

function detectMermaidType(body) {
  const first = body.trim().split("\n").find((l) => l.trim()) || "";
  const lower = first.toLowerCase().replace(/\s/g, "");
  if (lower.startsWith("flowchart") || lower.startsWith("graph")) return "flowchart";
  if (lower.startsWith("sequencediagram")) return "sequence";
  if (lower.startsWith("statediagram")) return "state";
  if (lower.startsWith("gantt")) return "gantt";
  if (lower.startsWith("quadrantchart")) return "quadrant";
  if (lower.startsWith("mindmap")) return "mindmap";
  if (lower.startsWith("classdiagram")) return "class";
  if (lower.startsWith("erdiagram")) return "er";
  if (lower.startsWith("pie")) return "pie";
  if (lower.startsWith("journey")) return "journey";
  if (lower.startsWith("timeline")) return "timeline";
  return "other";
}

/**
 * IMAGE-PLAYBOOK Section 4 の 8 構造パターン分類。
 * mermaid 型 + 内容ヒューリスティックで A〜H を推定する。
 */
function suggestStructurePattern(mermaidType, body) {
  const lower = body.toLowerCase();
  if (mermaidType === "mindmap") return { code: "F", name: "グループ・カタログ" };
  if (mermaidType === "quadrant") return { code: "F", name: "グループ・カタログ" };
  if (mermaidType === "gantt") return { code: "A", name: "直線フロー（時系列）" };
  if (mermaidType === "timeline") return { code: "A", name: "直線フロー（時系列）" };
  if (mermaidType === "state") return { code: "G", name: "循環ループ／状態遷移" };
  if (mermaidType === "sequence") return { code: "A", name: "直線フロー（順序）" };
  if (mermaidType === "er" || mermaidType === "class") return { code: "F", name: "グループ・カタログ" };

  // flowchart 系: subgraph 数 / 分岐 / 比較表現で判定
  const subgraphCount = (body.match(/^\s*subgraph/gim) || []).length;
  if (subgraphCount >= 2) return { code: "B", name: "階層／レイヤー" };

  const branchCount = (body.match(/-->\|/g) || []).length + (body.match(/\?\}/g) || []).length;
  if (branchCount >= 3) return { code: "D", name: "分岐・判断" };

  if (subgraphCount === 1) return { code: "E", name: "ハブ&スポーク" };

  if (lower.includes("vs ") || lower.includes("ng") || lower.includes("ok")) {
    return { code: "C", name: "比較 (NG vs OK)" };
  }

  return { code: "A", name: "直線フロー" };
}

async function callHaiku(userPrompt, systemPrompt) {
  const apiKey = process.env.AI_GATEWAY_API_KEY;
  if (!apiKey) throw new Error("AI_GATEWAY_API_KEY 未設定");

  const res = await fetch(`${AI_GATEWAY_BASE}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: HAIKU_MODEL,
      messages: [
        ...(systemPrompt ? [{ role: "system", content: systemPrompt }] : []),
        { role: "user", content: userPrompt },
      ],
      max_tokens: 1800,
      temperature: 0.3,
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Haiku ${res.status}: ${errText.slice(0, 300)}`);
  }
  const json = await res.json();
  return (json.choices?.[0]?.message?.content || "").trim();
}

const PROMPT_BUILDER_SYSTEM = `あなたは画像生成プロンプトを書く専門家です。
本文中の mermaid 図を Isometric 2.5D ベクター (Stripe / Vercel marketing illustration風) で視覚化するための **英語プロンプト** を作成します。

# 厳守ルール
- 出力は英語プロンプトのみ。説明文・前置き・コメント禁止
- 画像内ラベルは **日本語のみ**。製品名・API 名・略号 (CLAUDE.md, MCP, RAG, OWASP 等) のみ英字維持
- サイズ前提: 1536x1024 生成、上下 80px は crop される
- SAFE = y=80〜944、タイトル baseline は y=140〜180、上下 130px に focal text 禁止
- カラー: ivory beige (#F5F1EA) + dotted grid 背景、multi-pastel (sage green primary, peach, lavender, mustard yellow, dusty blue)
- フラットだが立体感のあるシャドウ、Noto Sans JP Bold タイポ
- mermaid の本質構造 (フロー / 階層 / 比較 / 分岐 / ハブ / カタログ / 循環 / 並列) を保持
- 中央メタファー大きめ、サイドパネル小さめ
- OS メモリ用語 (Heap / Stack / Cache / Garbage Collection) は元 mermaid が OS の話で **ない限り** 一切使わない
- 出力末尾に必ず "Japanese typography only." を含める`;

function buildPromptUserMessage({ block, contextHeading, articleTitle, pattern, mermaidType }) {
  return `# 元 mermaid 図

\`\`\`mermaid
${block.body}
\`\`\`

# コンテキスト
- 記事タイトル: ${articleTitle}
- 直前見出し: ${contextHeading || "(なし)"}
- mermaid タイプ: ${mermaidType}
- 構造パターン: ${pattern.code} - ${pattern.name}

# タスク
1. この mermaid の「中央メタファー」を 1〜2 文で決める (記事文脈に沿って)
2. 必要なラベル要素を日本語で列挙
3. 下記の雛形に沿って英語プロンプト本文を作成

# 雛形
Isometric 2.5D vector infographic in premium Stripe/Vercel marketing illustration style. 1536x1024 canvas, ivory beige background (#F5F1EA) with subtle dotted grid.

CRITICAL TITLE PLACEMENT: Bold Japanese title '[日本語タイトル]' MUST sit at TOP-LEFT with at least 140 pixels of clear margin from the top edge. Title baseline no higher than y=180. NEVER place focal text in top 130px or bottom 130px.

CENTRAL MAIN VISUAL (centered, y=200 to y=820): [中央メタファーを具体的に]

[必要なら LEFT side panel / RIGHT side panel を最大 2 個まで配置、各々 y=240〜780 内]

Multi-pastel palette: pale sage green primary, soft peach, lavender, mustard yellow, dusty blue. Soft drop shadows. Clean, premium, sophisticated. Bold Noto Sans JP typography. All in-image labels in Japanese only, except product/API names. Japanese typography only.

# 出力
プロンプト本文のみ (Markdown 不要、コードフェンス不要、前置き禁止)`;
}

async function buildImagePrompt({ block, contextHeading, articleTitle }) {
  const mermaidType = detectMermaidType(block.body);
  const pattern = suggestStructurePattern(mermaidType, block.body);
  const userPrompt = buildPromptUserMessage({
    block,
    contextHeading,
    articleTitle,
    pattern,
    mermaidType,
  });
  const result = await callHaiku(userPrompt, PROMPT_BUILDER_SYSTEM);
  return { prompt: result, mermaidType, pattern };
}

/**
 * gen.mjs を非同期で spawn して画像生成する Promise ラッパ。
 * 並列実行に対応するため spawnSync ではなく spawn を使う。
 */
function generateImageAsync(prompt, outputDir, baseFilename) {
  fs.mkdirSync(outputDir, { recursive: true });
  return new Promise((resolve, reject) => {
    /*
     * 重要: --aspect 16:9 ショートカットを必ず使う。
     * `--size 1536x1024 --final-size 1536x864` だけだと gen.mjs の default mode が
     * `letterbox` になり、generated と final のアスペクト比が違うときに
     * 横方向に縮小 (1296x864) して左右に白帯 padding が入る。
     * `--aspect 16:9` は内部で `--final-mode crop` を強制 + safety-zone instruction を
     * プロンプト先頭に自動注入する (gen.mjs L242-258 参照)。
     * IMAGE-PLAYBOOK §1-4 の center-crop ルールとも一致。
     */
    const child = spawn(
      "node",
      [
        GEN_MJS,
        "generate",
        prompt,
        "--model",
        IMAGE_MODEL,
        "--aspect",
        "16:9",
        "--out",
        outputDir,
      ],
      { stdio: ["ignore", "pipe", "pipe"] },
    );

    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d) => (stdout += d.toString()));
    child.stderr?.on("data", (d) => (stderr += d.toString()));

    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error("gen.mjs timeout (240s)"));
    }, 240000);

    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });

    child.on("close", (code) => {
      clearTimeout(timer);
      if (code !== 0) {
        const tail = (stderr || stdout).slice(-500);
        reject(new Error(`gen.mjs exit=${code}: ${tail}`));
        return;
      }
      const match = stdout.match(/"files"\s*:\s*\[\s*"([^"]+)"/);
      if (!match) {
        reject(new Error(`gen.mjs output unparseable: ${stdout.slice(-300)}`));
        return;
      }
      const generatedPath = match[1];
      const finalPath = path.join(outputDir, `${baseFilename}.png`);
      try {
        fs.renameSync(generatedPath, finalPath);
        const metaPath = generatedPath.replace(/-\d+\.png$/, ".json");
        if (fs.existsSync(metaPath)) {
          try {
            fs.unlinkSync(metaPath);
          } catch {
            /* best-effort */
          }
        }
        resolve(finalPath);
      } catch (err) {
        reject(err);
      }
    });
  });
}

/**
 * 配列を size 個のチャンクに分割するヘルパ (並列バッチ実行用)。
 */
function chunk(array, size) {
  const out = [];
  for (let i = 0; i < array.length; i += size) {
    out.push(array.slice(i, i + size));
  }
  return out;
}

function extractContextHeading(source, blockStartIdx) {
  const before = source.slice(0, blockStartIdx);
  const lines = before.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const m = lines[i].match(/^#{2,4}\s+(.+)$/);
    if (m) return m[1].trim();
  }
  return "";
}

function extractArticleTitle(source) {
  const titleMatch = source.match(/^title:\s*["']?(.+?)["']?\s*$/m);
  if (titleMatch) return titleMatch[1];
  const h1Match = source.match(/^#\s+(.+)$/m);
  return h1Match?.[1] || "";
}

function extractBlocks(source) {
  const blocks = [];
  MERMAID_RE.lastIndex = 0;
  let m;
  while ((m = MERMAID_RE.exec(source)) !== null) {
    blocks.push({
      fullMatch: m[0],
      body: m[1],
      startIdx: m.index,
      endIdx: m.index + m[0].length,
    });
  }
  return blocks;
}

/**
 * 1 ブロック分の処理 (Haiku でプロンプト生成 → gpt-image-2 で画像生成)。
 * 既存 PNG があれば skip して既存パスを返す (再投稿時に再生成しない)。
 * 失敗時は { error } を返す (throw しない) — chunk 全体の中断を避けるため。
 */
async function processOneBlock({ block, idx, total, source, articleTitle, outDir }) {
  const baseFilename = `mermaid-${String(idx).padStart(2, "0")}`;
  const targetPath = path.join(outDir, `${baseFilename}.png`);
  const contextHeading = extractContextHeading(source, block.startIdx);
  const mermaidType = detectMermaidType(block.body);
  const pattern = suggestStructurePattern(mermaidType, block.body);

  if (fs.existsSync(targetPath)) {
    console.error(
      `[mermaid-img] (${idx}/${total}) ${mermaidType} | pattern ${pattern.code} | skip (existing): ${baseFilename}.png`,
    );
    return { idx, baseFilename, contextHeading, skipped: true };
  }

  console.error(
    `[mermaid-img] (${idx}/${total}) ${mermaidType} | pattern ${pattern.code} | ctx: ${contextHeading.slice(0, 30)} … start`,
  );

  let promptInfo;
  try {
    promptInfo = await buildImagePrompt({ block, contextHeading, articleTitle });
  } catch (err) {
    console.error(`  ✗ (${idx}) prompt build failed: ${err.message}`);
    return { idx, baseFilename, contextHeading, error: err };
  }

  try {
    const imagePath = await generateImageAsync(promptInfo.prompt, outDir, baseFilename);
    console.error(`  ✓ (${idx}) ${path.basename(imagePath)}`);
    return { idx, baseFilename, contextHeading, imagePath };
  } catch (err) {
    console.error(`  ✗ (${idx}) image gen failed: ${err.message}`);
    return { idx, baseFilename, contextHeading, error: err };
  }
}

async function processFile({
  filePath,
  slug,
  outDir,
  contentType,
  publicPathPrefix,
  dryRun,
  inPlace,
  concurrency = DEFAULT_CONCURRENCY,
}) {
  if (contentType !== "knowledge") {
    console.error(`[mermaid-img] skip: content-type=${contentType} (knowledge のみ実行)`);
    return { skipped: true };
  }

  loadAiGatewayEnv();

  const source = fs.readFileSync(filePath, "utf8");
  const articleTitle = extractArticleTitle(source);
  const blocks = extractBlocks(source);

  if (blocks.length === 0) {
    console.error("[mermaid-img] mermaid ブロックなし、何もしません");
    return { count: 0 };
  }

  console.error(
    `[mermaid-img] ${blocks.length} blocks (concurrency=${concurrency}, title: ${articleTitle.slice(0, 40)})`,
  );

  if (dryRun) {
    blocks.forEach((b, i) => {
      const t = detectMermaidType(b.body);
      const p = suggestStructurePattern(t, b.body);
      const ctx = extractContextHeading(source, b.startIdx);
      console.error(
        `  [${i + 1}] ${t} (pattern ${p.code}: ${p.name}) — ctx: ${ctx.slice(0, 50)}`,
      );
    });
    return { count: blocks.length, dryRun: true };
  }

  fs.mkdirSync(outDir, { recursive: true });

  /*
   * 並列実行 — chunk 単位で Promise.all。
   * IMAGE-PLAYBOOK §5-2 に基づき default 3 並列、--concurrency で 1〜10 程度の範囲で調整可。
   * 失敗時も他のブロックは継続し、最後に集計する (best-effort)。
   */
  const total = blocks.length;
  const batches = chunk(
    blocks.map((block, i) => ({ block, idx: i + 1 })),
    Math.max(1, concurrency),
  );
  const results = [];
  for (const [batchIdx, batch] of batches.entries()) {
    console.error(
      `[mermaid-img] batch ${batchIdx + 1}/${batches.length} (size=${batch.length})`,
    );
    const batchResults = await Promise.all(
      batch.map(({ block, idx }) =>
        processOneBlock({ block, idx, total, source, articleTitle, outDir }),
      ),
    );
    results.push(...batchResults);
  }

  const replacements = [];
  let okCount = 0;
  let skipCount = 0;
  let failCount = 0;
  for (const r of results) {
    if (r.error) {
      failCount += 1;
      continue;
    }
    if (r.skipped) skipCount += 1;
    else okCount += 1;
    const refPath = publicPathPrefix
      ? `${publicPathPrefix.replace(/\/$/, "")}/${r.baseFilename}.png`
      : `./images/${slug}/${r.baseFilename}.png`;
    const alt = r.contextHeading ? `${r.contextHeading} 概念図` : `図 ${r.idx}`;
    const targetBlock = blocks[r.idx - 1];
    replacements.push({
      fullMatch: targetBlock.fullMatch,
      replacement: `![${alt}](${refPath})`,
    });
  }

  // 各 mermaid ブロックの fullMatch は内容に依存して一意なので、その場で replace。
  let newSource = source;
  for (const r of replacements) {
    newSource = newSource.replace(r.fullMatch, r.replacement);
  }

  if (inPlace) {
    fs.writeFileSync(filePath, newSource);
    console.error(
      `[mermaid-img] ${path.basename(filePath)} 書き換え完了 (ok=${okCount}, skip=${skipCount}, fail=${failCount})`,
    );
  } else {
    process.stdout.write(newSource);
  }

  return { count: total, ok: okCount, skipped: skipCount, failed: failCount };
}

function parseArgs(argv) {
  const args = { dryRun: false, inPlace: false, concurrency: DEFAULT_CONCURRENCY };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--file") args.filePath = argv[++i];
    else if (a === "--slug") args.slug = argv[++i];
    else if (a === "--out-dir") args.outDir = argv[++i];
    else if (a === "--content-type") args.contentType = argv[++i];
    else if (a === "--public-path-prefix") args.publicPathPrefix = argv[++i];
    else if (a === "--concurrency") args.concurrency = Math.max(1, parseInt(argv[++i], 10) || DEFAULT_CONCURRENCY);
    else if (a === "--dry-run") args.dryRun = true;
    else if (a === "--in-place") args.inPlace = true;
    else if (a === "--help" || a === "-h") {
      console.log(
        `Usage: gen-mermaid-images.mjs --file <md> --slug <slug> --out-dir <dir> --content-type knowledge [--in-place] [--dry-run] [--concurrency N]

  --concurrency N   並列実行数 (default ${DEFAULT_CONCURRENCY}, IMAGE-PLAYBOOK §5-2 は 6 が安定圏)
  --in-place        markdown を直接書き換える (mermaid ブロック → ![alt](path))
  --dry-run         抽出と構造パターン分類のみ実行、画像生成しない

既存の mermaid-NN.png があれば skip する (再投稿時の再生成抑止)。`,
      );
      process.exit(0);
    }
  }
  return args;
}

const isDirectRun = (() => {
  try {
    return fileURLToPath(import.meta.url) === fs.realpathSync(process.argv[1] ?? "");
  } catch {
    return false;
  }
})();
if (isDirectRun) {
  const args = parseArgs(process.argv);
  const required = ["filePath", "slug", "outDir", "contentType"];
  const missing = required.filter((k) => !args[k]);
  if (missing.length > 0) {
    console.error(`Required args missing: ${missing.join(", ")}`);
    console.error("See --help");
    process.exit(1);
  }
  processFile(args).catch((err) => {
    console.error(`[mermaid-img] fatal: ${err.message}`);
    process.exit(1);
  });
}

export {
  detectMermaidType,
  suggestStructurePattern,
  extractBlocks,
  extractContextHeading,
  extractArticleTitle,
  processFile,
};
