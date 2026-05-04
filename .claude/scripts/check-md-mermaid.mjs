#!/usr/bin/env node
// Validate ```mermaid``` code blocks in Markdown files using mermaid@11.13.0 parser.
//
// Usage:
//   npx --yes --package=mermaid@11.13.0 --package=jsdom node \
//     .claude/scripts/check-md-mermaid.mjs "docs/**/*.md" [...more globs]
//   # or after `npm i -D mermaid@11.13.0 jsdom`:
//   node .claude/scripts/check-md-mermaid.mjs "docs/**/*.md"
//
// jsdom is required because mermaid@11 invokes DOMPurify (and DOMPurify.addHook)
// during parse(). In a pure Node environment those globals are missing and
// every block fails with "DOMPurify.addHook is not a function".
//
// Exit codes:
//   0 = all blocks parsed
//   1 = one or more parse errors
//   2 = usage / setup error

import { readFile } from 'node:fs/promises';
import { glob } from 'node:fs/promises';
import path from 'node:path';

const args = process.argv.slice(2);
if (args.length === 0) {
  console.error('Usage: check-md-mermaid.mjs <glob> [<glob> ...]');
  process.exit(2);
}

// --- DOM shim (must run before importing mermaid) ---
try {
  const { JSDOM } = await import('jsdom');
  const dom = new JSDOM('<!doctype html><html><body></body></html>', {
    url: 'http://localhost/',
  });
  const { window } = dom;
  const assign = (key, value) => {
    try {
      Object.defineProperty(globalThis, key, {
        value,
        configurable: true,
        writable: true,
      });
    } catch {
      // ignore non-writable globals (e.g. Node 22's built-in `navigator`)
    }
  };
  assign('window', window);
  assign('document', window.document);
  assign('navigator', window.navigator);
  assign('HTMLElement', window.HTMLElement);
  assign('Element', window.Element);
  assign('Node', window.Node);
  assign('DocumentFragment', window.DocumentFragment);
  assign('getComputedStyle', window.getComputedStyle);
} catch (err) {
  console.error('[setup] jsdom is required. Install it or run via:');
  console.error('  npx --yes --package=mermaid@11.13.0 --package=jsdom node .claude/scripts/check-md-mermaid.mjs <glob>');
  console.error(err?.message ?? err);
  process.exit(2);
}

let mermaid;
try {
  ({ default: mermaid } = await import('mermaid'));
} catch (err) {
  console.error('[setup] Failed to import "mermaid". Install it or run via:');
  console.error('  npx --yes --package=mermaid@11.13.0 --package=jsdom node .claude/scripts/check-md-mermaid.mjs <glob>');
  console.error(err?.message ?? err);
  process.exit(2);
}

mermaid.initialize({ startOnLoad: false, suppressErrorRendering: true });

const FENCE = /^([ \t]*)(`{3,}|~{3,})\s*mermaid\b[^\n]*\n([\s\S]*?)\n\1\2\s*$/gm;

async function expandGlobs(patterns) {
  const files = new Set();
  for (const pattern of patterns) {
    for await (const entry of glob(pattern)) {
      if (entry.endsWith('.md') || entry.endsWith('.mdx')) {
        files.add(path.resolve(entry));
      }
    }
  }
  return [...files].sort();
}

function* extractBlocks(text) {
  FENCE.lastIndex = 0;
  let m;
  while ((m = FENCE.exec(text)) !== null) {
    const before = text.slice(0, m.index);
    const startLine = before.split('\n').length + 1; // line of first diagram line
    yield { code: m[3], startLine };
  }
}

const files = await expandGlobs(args);
if (files.length === 0) {
  console.error('No .md/.mdx files matched.');
  process.exit(2);
}

let totalBlocks = 0;
let failedBlocks = 0;
const failures = [];

for (const file of files) {
  const text = await readFile(file, 'utf8');
  let idx = 0;
  for (const { code, startLine } of extractBlocks(text)) {
    idx += 1;
    totalBlocks += 1;
    try {
      await mermaid.parse(code, { suppressErrors: false });
    } catch (err) {
      failedBlocks += 1;
      failures.push({
        file: path.relative(process.cwd(), file),
        block: idx,
        line: startLine,
        message: (err?.message ?? String(err)).split('\n').slice(0, 6).join('\n'),
      });
    }
  }
}

if (failures.length > 0) {
  console.error(`\nMermaid parse failures (${failedBlocks}/${totalBlocks} blocks across ${files.length} files):\n`);
  for (const f of failures) {
    console.error(`✗ ${f.file}:${f.line}  (block #${f.block})`);
    console.error(f.message.replace(/^/gm, '    '));
    console.error('');
  }
  process.exit(1);
}

console.log(`✓ ${totalBlocks} mermaid block(s) in ${files.length} file(s) parsed cleanly.`);
