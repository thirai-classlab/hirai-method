#!/usr/bin/env node
// Generate PNG from HTML template via Playwright (Japanese-safe text rendering)
// Usage: node gen-jp-diagram.mjs <html-template-path> <output-png-path> [width] [height]
import { chromium } from 'playwright';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const [, , htmlPathArg, outPathArg, widthArg = '1536', heightArg = '864'] = process.argv;

if (!htmlPathArg || !outPathArg) {
  console.error('Usage: node gen-jp-diagram.mjs <html-template-path> <output-png-path> [width] [height]');
  process.exit(1);
}

const htmlPath = resolve(htmlPathArg);
const outPath = resolve(outPathArg);
const width = Number(widthArg);
const height = Number(heightArg);

const html = readFileSync(htmlPath, 'utf8');

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width, height },
  deviceScaleFactor: 2,
});
const page = await ctx.newPage();

await page.setContent(html, { waitUntil: 'networkidle' });

// Wait for fonts to be fully loaded (Klee One / Yusei Magic via Google Fonts)
await page.evaluate(async () => {
  if (document.fonts && document.fonts.ready) {
    await document.fonts.ready;
  }
});
await page.waitForTimeout(800);

await page.screenshot({ path: outPath, fullPage: false, omitBackground: false });
await browser.close();

console.log(`generated: ${outPath} (${width}x${height})`);
