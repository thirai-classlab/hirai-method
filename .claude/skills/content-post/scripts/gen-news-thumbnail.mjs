#!/usr/bin/env node
// gen-news-thumbnail.mjs
// JSON config-driven news thumbnail generator (v2.0 schema).
//
// Flow:
//   1. Load thumbnail-patterns.json (config v2.0: categories + patterns)
//   2. Resolve target patterns from --pattern (csv) or --category
//   3. For each pattern: extract scene/tags via Haiku, render via gpt-image-2,
//      gen.mjs に --aspect 16:9 を渡し、安全領域指示 + 1536x864 center-crop まで委譲
//   4. Output file naming:
//      - single pattern → preserve --out path as-is (backward compatible)
//      - multi pattern  → suffix each output with -<PATTERN> (e.g. 2026-04-26-T394.png)
//
// Usage:
//   node output/gen-news-thumbnail.mjs \
//     --pattern T394 \
//     --title "週刊テック Vol.16" \
//     --headlines "Claude Sonnet 4.6 リリース|Salesforce Summer 26 公開|GitHub Trending Top10"
//
//   Multiple patterns (A/B — pass any comma-separated existing pattern IDs):
//     --pattern T394,T363 --out /tmp/thumbs/2026-04-26.png
//       → /tmp/thumbs/2026-04-26-T394.png + /tmp/thumbs/2026-04-26-T363.png
//
//   By category (uses categories.<name>.patterns):
//     --category weekly_issues --title "..." --headlines "..."
//
//   Listing helpers (stdout JSON):
//     --list-patterns
//     --list-categories
//
//   Other flags:
//     --headlines-file path/to/headlines.txt
//     --out  ./output/news-output     output directory or file path
//     --dry  print rendered prompt and exit
//     --scene "static scene override"  skip LLM extraction
//     --tags "'AI' 'クラウド'"          skip LLM extraction (patterns with tags slot only)

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const CONFIG_PATH = path.join(__dirname, 'thumbnail-patterns.json');
// ai-image-gen はグローバル ~/.claude/skills/ に昇格済み。
// 別プロジェクトに content-post を持ち出しても動くように home-relative で解決する。
const AI_IMAGE_GEN_DIR = path.join(os.homedir(), '.claude/skills/ai-image-gen');
const ENV_PATH         = path.join(AI_IMAGE_GEN_DIR, '.env');
const GEN_PATH         = path.join(AI_IMAGE_GEN_DIR, 'scripts/gen.mjs');

// ════════════════════════════════════════════════════════════════
// Pure helpers (exported for testing)
// ════════════════════════════════════════════════════════════════

/**
 * Parse comma-separated --pattern argument.
 *   "T394"        → ["T394"]
 *   "T387,T394"   → ["T387", "T394"]
 *   " T387 , T394 " → ["T387", "T394"]
 *   ""            → []
 */
export function parsePatternArg(s) {
  if (typeof s !== 'string' || !s.trim()) return [];
  return s.split(',').map(t => t.trim()).filter(Boolean);
}

/**
 * Resolve output path with optional pattern suffix.
 *   isMulti=false → return basePath unchanged (backward compatible single-pattern)
 *   isMulti=true  → insert -<pattern> before the final extension
 *     "/x/y.png" + "T394" + true → "/x/y-T394.png"
 *     "/x/y"     + "T394" + true → "/x/y-T394"
 *     "/x/2026.04.26.png" + "T394" + true → "/x/2026.04.26-T394.png"
 */
export function resolveOutputPath(basePath, pattern, isMulti) {
  if (!isMulti) return basePath;
  const dir  = path.dirname(basePath);
  const base = path.basename(basePath);
  const ext  = path.extname(base);
  const stem = ext ? base.slice(0, -ext.length) : base;
  return path.join(dir, `${stem}-${pattern}${ext}`);
}

/**
 * Get patterns array for a named category.
 * Throws if the category does not exist.
 */
export function loadCategoryPatterns(config, name) {
  const cat = config?.categories?.[name];
  if (!cat) {
    throw new Error(`unknown category: ${name}`);
  }
  return Array.isArray(cat.patterns) ? cat.patterns.slice() : [];
}

/**
 * Validate whether a pattern is allowed in a given category.
 *   - pattern.category_lock missing → allowed in any category
 *   - pattern.category_lock === categoryName → allowed
 *   - otherwise → not allowed
 *
 * Throws if the pattern is unknown.
 */
export function validatePatternForCategory(config, pattern, categoryName) {
  const def = config?.patterns?.[pattern];
  if (!def) {
    throw new Error(`unknown pattern: ${pattern}`);
  }
  if (!def.category_lock) return true;
  return def.category_lock === categoryName;
}

/**
 * Load the JSON config file.
 */
export function loadConfig(configPath) {
  return JSON.parse(fs.readFileSync(configPath, 'utf8'));
}

/**
 * Lightweight argv parser (preserved from v1).
 */
export function parseArgs(argv) {
  const a = {};
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (!k.startsWith('--')) continue;
    const key = k.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) { a[key] = true; }
    else { a[key] = next; i++; }
  }
  return a;
}

// ════════════════════════════════════════════════════════════════
// Side-effect helpers
// ════════════════════════════════════════════════════════════════

function loadEnv() {
  try {
    const raw = fs.readFileSync(ENV_PATH, 'utf8');
    for (const line of raw.split('\n')) {
      const m = line.match(/^([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/);
      if (m && !process.env[m[1]]) {
        process.env[m[1]] = m[2].replace(/^["']|["']$/g, '').trim();
      }
    }
  } catch (e) { /* ignore */ }
}

async function callLLM({ system, user }, model, apiKey) {
  const body = {
    model,
    messages: [
      { role: 'system', content: system },
      { role: 'user',   content: user   },
    ],
    max_tokens: 600,
  };
  const res = await fetch('https://ai-gateway.vercel.sh/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`LLM call failed (${res.status}): ${err.slice(0, 400)}`);
  }
  const j = await res.json();
  const content = j.choices?.[0]?.message?.content;
  if (!content) throw new Error(`LLM call returned empty: ${JSON.stringify(j).slice(0, 400)}`);
  return content.trim();
}

/**
 * Build the final image prompt for a given pattern + content.
 * Uses callback-form String.replace to avoid $& / $1 special-pattern bugs
 * (see feedback_string_replace_callback_form.md).
 */
function buildPrompt(tpl, { scene, title, headlines, tagsStr }) {
  const headlinesFormatted = headlines.map(h => `'${h}'`).join(' ');
  const replacements = {
    '{SCENE}':              scene,
    '{TITLE}':              title,
    '{HEADLINES_FORMATTED}': headlinesFormatted,
    '{N_HEADLINES}':         String(headlines.length),
    '{TAGS}':                tagsStr || '',
  };
  let out = tpl.prompt_template;
  for (const [token, value] of Object.entries(replacements)) {
    out = out.replace(token, () => value);
  }
  return out;
}

async function generateOne({ config, pattern, title, headlines, args, outPath, isMulti }) {
  const tpl = config.patterns[pattern];
  if (!tpl) {
    throw new Error(`Unknown pattern: ${pattern}. Available: ${Object.keys(config.patterns).join(', ')}`);
  }

  const trimmedHeadlines = headlines.slice(0, tpl.headlines_max);
  if (!trimmedHeadlines.length) throw new Error('headlines empty');

  // ─── extract scene / tags ────────────────────────────────────
  let scene = args.scene;
  let tagsStr = args.tags || '';

  if (!args.dry && (!scene || (tpl.background_extractor.format === 'json' && !tagsStr))) {
    const apiKey = process.env.AI_GATEWAY_API_KEY;
    if (!apiKey) {
      throw new Error(`AI_GATEWAY_API_KEY missing in ${ENV_PATH}`);
    }
    const userPrompt = tpl.background_extractor.user
      .replace('{HEADLINES}', () => trimmedHeadlines.map((h, i) => `${i + 1}. ${h}`).join('\n'));
    console.error(`[extract:${pattern}] calling ${config.llm_model} ...`);
    const raw = await callLLM(
      { system: tpl.background_extractor.system, user: userPrompt },
      config.llm_model, apiKey,
    );
    if (tpl.background_extractor.format === 'json') {
      const cleaned = raw
        .replace(/^```(?:json)?\s*/i, () => '')
        .replace(/\s*```\s*$/, () => '')
        .replace(/^[^{]*/, () => '')
        .replace(/[^}]*$/, () => '');
      const j = JSON.parse(cleaned);
      if (!scene)   scene   = j.scene;
      if (!tagsStr) tagsStr = (j.tags || []).map(t => `'${t}'`).join(' ');
    } else {
      if (!scene) scene = raw.replace(/^["']|["']$/g, () => '');
    }
  }

  if (!scene) scene = 'a workspace with floating UI panels';

  const prompt = buildPrompt(tpl, { scene, title, headlines: trimmedHeadlines, tagsStr });

  console.error(`[scene:${pattern}] ${scene}`);
  if (tagsStr) console.error(`[tags:${pattern}]  ${tagsStr}`);
  console.error(`[prompt:${pattern}] ${prompt.slice(0, 220)}...`);

  if (args.dry) {
    console.log(`### ${pattern}\n${prompt}\n`);
    return;
  }

  // ─── call gen.mjs ────────────────────────────────────────────
  // outPath may be either a directory (legacy) or a full file path.
  // If --out looks like a file path (has an extension), we use its dirname
  // and rename the produced PNG to that path. Otherwise we treat it as a dir.
  const outIsFile = !!path.extname(outPath);
  const outDir    = outIsFile ? path.dirname(outPath) : outPath;
  fs.mkdirSync(outDir, { recursive: true });

  const ts = new Date().toISOString().replace(/[-:T]/g, () => '').slice(0, 14);
  const prefix = `news-${pattern}-${ts}`;

  // gen.mjs に --aspect 16:9 を渡して中央セーフゾーン指示 + center-crop を委譲する。
  // image_size と output_size は preset から導出されるため明示は不要だが、
  // 既存設定 (1536x1024 → 1536x864) との整合のため値が一致することを前提とする。
  console.error(`[image:${pattern}] spawning gen.mjs (--aspect 16:9) ...`);
  const r = spawnSync('node', [
    GEN_PATH, 'generate', prompt,
    '--model',  config.image_model,
    '--aspect', '16:9',
    '--n',      '1',
    '--out',    outDir + '/',
    '--prefix', prefix,
  ], { stdio: 'inherit' });
  if (r.status !== 0) throw new Error(`gen.mjs exited with ${r.status}`);

  // gen.mjs 内で center-crop 済みのため、ここでは追加処理しない。
  // 後段で --out がファイル指定の場合だけ rename する。
  const generated = fs.readdirSync(outDir)
    .filter(f => f.startsWith(prefix) && f.endsWith('.png'))
    .map(f => path.join(outDir, f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);

  // If --out is a file path, rename the most recent generated PNG to it.
  if (outIsFile && generated.length > 0) {
    const src = generated[0];
    if (src !== outPath) {
      fs.renameSync(src, outPath);
      console.error(`[move:${pattern}] ${path.basename(src)} → ${outPath}`);
    }
  }
}

// ════════════════════════════════════════════════════════════════
// CLI entry point
// ════════════════════════════════════════════════════════════════

async function main() {
  const args = parseArgs(process.argv);

  // ── listing helpers ────────────────────────────────────────
  if (args['list-patterns']) {
    const config = loadConfig(CONFIG_PATH);
    const out = Object.entries(config.patterns).map(([id, def]) => ({
      id,
      label: def.label,
      tone: def.tone,
      category_lock: def.category_lock || null,
    }));
    console.log(JSON.stringify(out, null, 2));
    return;
  }
  if (args['list-categories']) {
    const config = loadConfig(CONFIG_PATH);
    const out = Object.entries(config.categories).map(([name, def]) => ({
      name,
      patterns: def.patterns,
      default_count: def.default_count,
      description: def.description,
    }));
    console.log(JSON.stringify(out, null, 2));
    return;
  }

  // ── resolve patterns ───────────────────────────────────────
  const config = loadConfig(CONFIG_PATH);
  let patterns = [];
  if (args.category) {
    patterns = loadCategoryPatterns(config, args.category);
    if (!patterns.length) {
      console.error(`Category "${args.category}" has no registered patterns.`);
      process.exit(1);
    }
  } else if (args.pattern && typeof args.pattern === 'string') {
    patterns = parsePatternArg(args.pattern);
  }

  // ── usage check ────────────────────────────────────────────
  if (!patterns.length || !args.title || (!args.headlines && !args['headlines-file'])) {
    console.error(`Usage:
  node ${path.basename(__filename)} --pattern T394 --title "..." --headlines "h1|h2|h3"
  node ${path.basename(__filename)} --pattern T394,T363 --title "..." --headlines-file path/to/headlines.txt
  node ${path.basename(__filename)} --category weekly_issues --title "..." --headlines "..."

Listing:
  node ${path.basename(__filename)} --list-patterns
  node ${path.basename(__filename)} --list-categories

Options:
  --out PATH      output directory OR file path (file path enables exact rename)
  --scene "..."   override scene extraction (skip LLM)
  --tags "..."    override tags extraction (skip LLM, T387 only)
  --dry           print prompt and exit (no LLM, no image gen)
`);
    process.exit(1);
  }

  // ── validate category lock if --category was used ──────────
  if (args.category) {
    for (const p of patterns) {
      if (!validatePatternForCategory(config, p, args.category)) {
        console.error(`Pattern ${p} is locked to a different category (category_lock=${config.patterns[p]?.category_lock}); cannot use under category "${args.category}".`);
        process.exit(1);
      }
    }
  }

  loadEnv();

  // ── headlines ──────────────────────────────────────────────
  let headlines;
  if (args['headlines-file']) {
    headlines = fs.readFileSync(args['headlines-file'], 'utf8')
      .split('\n').map(s => s.trim()).filter(Boolean);
  } else {
    headlines = String(args.headlines).split('|').map(s => s.trim()).filter(Boolean);
  }
  if (!headlines.length) { console.error('headlines empty'); process.exit(1); }

  const isMulti = patterns.length > 1;
  const baseOut = args.out || path.join(__dirname, 'news-output');

  // Generate sequentially (parallel left for a future iteration).
  for (const pattern of patterns) {
    const outPath = resolveOutputPath(baseOut, pattern, isMulti);
    await generateOne({
      config, pattern, title: args.title, headlines, args,
      outPath, isMulti,
    });
  }
}

// ── CLI guard ───────────────────────────────────────────────
// Only invoke main() when this file is executed directly via node,
// NOT when imported as an ESM module (e.g. by vitest).
const invokedAsScript =
  process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

if (invokedAsScript) {
  main().catch(e => { console.error(e); process.exit(1); });
}
