#!/usr/bin/env node
// Render HTML → PNG at exact specified output dimensions (deviceScaleFactor=1).
// Usage: node gen-sketchnote.mjs <html> <png> <width> <height>
import { chromium } from 'playwright';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const [, , htmlArg, outArg, wArg, hArg] = process.argv;
if (!htmlArg || !outArg || !wArg || !hArg) {
  console.error('Usage: gen-sketchnote.mjs <html> <out.png> <width> <height>');
  process.exit(1);
}
const htmlPath = resolve(htmlArg);
const outPath = resolve(outArg);
const width = Number(wArg);
const height = Number(hArg);

const html = readFileSync(htmlPath, 'utf8');
const baseDir = dirname(htmlPath);
const fileUrl = `file://${baseDir}/`;

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width, height },
  deviceScaleFactor: 1,
});
const page = await ctx.newPage();

await page.setContent(html, { waitUntil: 'networkidle', baseURL: fileUrl });
// inject base href so relative CSS resolves
await page.evaluate((base) => {
  const b = document.createElement('base');
  b.href = base;
  document.head.prepend(b);
}, fileUrl);

await page.evaluate(async () => {
  if (document.fonts && document.fonts.ready) await document.fonts.ready;
});
await page.waitForTimeout(900);

await page.screenshot({ path: outPath, fullPage: false, omitBackground: false });
await browser.close();
console.log(`generated: ${outPath} (${width}x${height})`);
