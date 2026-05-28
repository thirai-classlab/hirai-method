/**
 * Tests for src/lib/markdown.ts
 *
 * Covers: parseMarkdown / renderToHtml with the full `.rich-*` conversion table.
 * Spec: /Users/t.hirai/work/classlab-weekly-news/docs/rich-content-classes.md §4
 */
import { describe, it, expect, beforeAll, vi } from "vitest";
import path from "node:path";
import { parseMarkdown, renderToHtml, headingAnchorId, renderToHtmlAsync, type PlantUMLReplacement } from "../../src/lib/markdown.js";
import { loadTemplates, getTemplate, type Template } from "../../src/lib/templates.js";

// ---------------------------------------------------------------------------
// Mock plantuml-processor for renderToHtmlAsync tests
// ---------------------------------------------------------------------------

const processPlantUMLBlocksMock = vi.fn<
  (html: string, options: { slug: string; contentType: "knowledge" | "tech_article" | "issue" }) => Promise<{ html: string; replacements: PlantUMLReplacement[] }>
>();

vi.mock("../../src/lib/plantuml-processor.js", () => ({
  processPlantUMLBlocks: processPlantUMLBlocksMock,
}));

const REPO_TEMPLATES = path.resolve(
  "/Users/t.hirai/work/classlab-weekly-news/content-templates",
);

let knowledgeTpl: Template;
let weeklyTpl: Template;

beforeAll(async () => {
  const registry = await loadTemplates(REPO_TEMPLATES);
  knowledgeTpl = getTemplate(registry, "knowledge");
  weeklyTpl = getTemplate(registry, "weekly_issue");
});

describe("parseMarkdown()", () => {
  it("extracts frontmatter and returns the body as `raw`", () => {
    const src = [
      "---",
      "title: テスト記事",
      "type: knowledge",
      "tags: [supabase, pgvector]",
      "---",
      "",
      "## 概要",
      "本文です。",
    ].join("\n");
    const { frontmatter, raw, sections } = parseMarkdown(src);
    expect(frontmatter.title).toBe("テスト記事");
    expect(frontmatter.type).toBe("knowledge");
    expect(frontmatter.tags).toEqual(["supabase", "pgvector"]);
    expect(raw).toContain("## 概要");
    expect(sections.some((s) => s.heading === "概要" && s.level === 2)).toBe(
      true,
    );
  });

  it("returns an empty frontmatter when none is present", () => {
    const { frontmatter, raw } = parseMarkdown("# Plain title\n\nbody");
    expect(frontmatter).toEqual({});
    expect(raw.startsWith("# Plain title")).toBe(true);
  });

  it("picks up multiple heading levels", () => {
    const { sections } = parseMarkdown("## A\n### B\n## C\n");
    expect(sections).toEqual([
      { heading: "A", level: 2 },
      { heading: "B", level: 3 },
      { heading: "C", level: 2 },
    ]);
  });
});

describe("renderToHtml() — GFM Alerts", () => {
  it.each([
    ["note", "rich-callout--note"],
    ["tip", "rich-callout--tip"],
    ["warning", "rich-callout--warn"],
    ["info", "rich-callout--info"],
  ])("> [!%s] → %s", (alert, cls) => {
    const md = `> [!${alert}]\n> hello world`;
    const { html, appliedClasses } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain(`class="rich-callout ${cls}"`);
    expect(html).toContain("hello world");
    expect(appliedClasses).toContain(cls);
  });

  it("> [!pitfall] → rich-pitfall (not rich-callout)", () => {
    const { html } = renderToHtml("> [!pitfall]\n> danger", knowledgeTpl);
    expect(html).toContain('class="rich-pitfall"');
    expect(html).toContain("danger");
  });
});

describe("renderToHtml() — custom containers", () => {
  it(":::tldr ... ::: → <div class=rich-tldr>", () => {
    const md = ":::tldr\n結論です。\n:::";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('class="rich-tldr"');
    expect(html).toContain("結論です。");
  });

  it(":::steps + numbered list → <ol class=rich-steps> with __item items", () => {
    const md = [
      ":::steps",
      "1. 最初",
      "2. 次",
      ":::",
    ].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toMatch(/<ol[^>]*class="rich-steps"/);
    expect(html).toContain('class="rich-steps__item"');
    expect(html).toContain("最初");
    expect(html).toContain("次");
  });

  it(":::compare + GFM table → <table class=\"rich-table rich-table--compare\">", () => {
    const md = [
      ":::compare",
      "| 項目 | A | B |",
      "|------|---|---|",
      "| 速度 | 高 | 中 |",
      ":::",
    ].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('class="rich-table rich-table--compare"');
    expect(html).toContain("速度");
  });

  it(":::keypoints → <ul class=rich-keypoints>", () => {
    const md = [":::keypoints", "- 重要1", "- 重要2", ":::"].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toMatch(/<ul[^>]*class="rich-keypoints"/);
  });

  it(":::classlab-usage → <aside class=rich-callout--usage> with h4 + ul + li", () => {
    const md = [
      ":::classlab-usage",
      "#### Classlabでの活用",
      "",
      "- 活用ポイント 1",
      "- 活用ポイント 2",
      ":::",
    ].join("\n");
    const { html } = renderToHtml(md, weeklyTpl);
    expect(html).toContain('class="rich-callout--usage"');
    expect(html).toContain("<aside");
    expect(html).toContain("</aside>");
    expect(html).toContain("活用ポイント 1");
    expect(html).toContain("活用ポイント 2");
  });

  it(":::classlab-usage does not produce a <table>", () => {
    const md = [
      ":::classlab-usage",
      "#### Classlabでの活用",
      "",
      "- 活用ポイント 1",
      ":::",
    ].join("\n");
    const { html } = renderToHtml(md, weeklyTpl);
    expect(html).not.toContain("<table");
  });

  it(":::classlab-usage with h5×3 sub-sections renders all three headings", () => {
    const md = [
      ":::classlab-usage",
      "#### Classlabでの活用",
      "",
      "##### 1年以内",
      "今すぐ試せる施策。",
      "",
      "##### 3年以内",
      "中期的な取り組み。",
      "",
      "##### 3年以上",
      "長期的な事業変革。",
      ":::",
    ].join("\n");
    const { html } = renderToHtml(md, weeklyTpl);
    expect(html).toContain('class="rich-callout--usage"');
    expect(html).toContain("1年以内");
    expect(html).toContain("3年以内");
    expect(html).toContain("3年以上");
    expect(html).toContain("今すぐ試せる施策。");
    expect(html).toContain("中期的な取り組み。");
    expect(html).toContain("長期的な事業変革。");
  });

  it(":::classlab-usage h5×3 — all three sub-headings render as <h5> elements", () => {
    const md = [
      ":::classlab-usage",
      "#### Classlabでの活用",
      "",
      "##### 1年以内",
      "短期施策。",
      "",
      "##### 3年以内",
      "中期施策。",
      "",
      "##### 3年以上",
      "長期施策。",
      ":::",
    ].join("\n");
    const { html } = renderToHtml(md, weeklyTpl);
    const h5Matches = [...html.matchAll(/<h5[^>]*>/g)];
    expect(h5Matches.length).toBeGreaterThanOrEqual(3);
  });

  it(":::classlab-usage with h5×3 does not produce a <table>", () => {
    const md = [
      ":::classlab-usage",
      "#### Classlabでの活用",
      "",
      "##### 1年以内",
      "短期施策。",
      "",
      "##### 3年以内",
      "中期施策。",
      "",
      "##### 3年以上",
      "長期施策。",
      ":::",
    ].join("\n");
    const { html } = renderToHtml(md, weeklyTpl);
    expect(html).not.toContain("<table");
  });
});

describe("renderToHtml() — tables and checklists", () => {
  it("plain GFM table → <table class=rich-table>", () => {
    const md = ["| a | b |", "|---|---|", "| 1 | 2 |"].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('class="rich-table"');
  });

  it("GFM checklist → <ul class=rich-checklist> without <input> elements", () => {
    const md = ["- [x] done", "- [ ] todo"].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('class="rich-checklist"');
    expect(html).not.toContain("<input");
    expect(html).toContain("todo");
  });

  it("renders unchecked task list as <li> without <input>", () => {
    const md = "- [ ] foo";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toMatch(/<li>/);
    expect(html).not.toContain("<input");
    expect(html).toContain("foo");
  });

  it("renders checked task list as <li data-checked=\"true\">", () => {
    const md = "- [x] foo";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<li data-checked="true">');
    expect(html).not.toContain("<input");
  });

  it("mixed checked/unchecked preserves order", () => {
    const md = ["- [ ] a", "- [x] b", "- [ ] c"].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    const liMatches = [...html.matchAll(/<li([^>]*)>/g)];
    expect(liMatches).toHaveLength(3);
    expect(liMatches[0][1]).not.toContain("data-checked");
    expect(liMatches[1][1]).toContain('data-checked="true"');
    expect(liMatches[2][1]).not.toContain("data-checked");
  });

  it("```diff fenced block → <pre class=rich-code-diff>", () => {
    const md = "```diff\n-old\n+new\n```";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('class="rich-code-diff"');
  });
});

// ────────────────────────────────────────────────────────────────────────────
// Task #48 Wave 48.3 — code block raw 復元用 data-raw / data-raw-encoding
//
// 仕様 (docs/task-48-code-block-enhancement-design.md §C.4 / §E.Wave 48.3):
//   - renderer.code() は <pre> に data-raw + data-raw-encoding を付与する
//   - 短いコード (<500 char): encodeURIComponent → encoding="url"
//   - 長いコード (>=500 char): base64 (UTF-8 bytes) → encoding="base64"
//   - 言語は data-lang として保持（既存挙動）。lang 未指定時は data-lang 属性なし
//   - diff ブロック (rich-code-diff) も data-raw 付与（コピー対応のため）
//   - 既存 escape(code) 挙動を壊さない（XSS 対策）
//
// 本リポ classlab-weekly-news 側 src/lib/code-block-decode.ts は data-raw を
// 同形式でデコードする責務を持つ。本テストはその出力契約を担保する。
// ────────────────────────────────────────────────────────────────────────────

describe("renderToHtml() — code block data-raw (Wave 48.3)", () => {
  function extractAttr(html: string, attr: string): string | undefined {
    const re = new RegExp(`${attr}="([^"]*)"`);
    const m = html.match(re);
    return m?.[1];
  }

  function utf8Base64(str: string): string {
    return Buffer.from(str, "utf-8").toString("base64");
  }

  it("short typescript code: data-raw is encodeURIComponent + encoding='url'", () => {
    const code = "const x: number = 1;\nconsole.log(x);";
    const md = "```typescript\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    expect(html).toContain('data-lang="typescript"');
    expect(html).toContain('data-raw-encoding="url"');
    const raw = extractAttr(html, "data-raw");
    expect(raw).toBeDefined();
    expect(decodeURIComponent(raw!)).toBe(code);
  });

  it("Japanese code: encodeURIComponent yields fully escaped bytes", () => {
    const code = "Claude codeのデザインは…";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    expect(html).toContain('data-lang="claude-code"');
    expect(html).toContain('data-raw-encoding="url"');
    const raw = extractAttr(html, "data-raw");
    expect(raw).toBe(encodeURIComponent(code));
    expect(decodeURIComponent(raw!)).toBe(code);
  });

  it("special HTML characters round-trip through data-raw (escape only inside <code>)", () => {
    // 「<」「>」「&」「"」を含むコード — XSS 対策で <code> 内は escape されるが
    // data-raw は encodeURIComponent で raw を保持
    const code = '<div class="x">a & b</div>';
    const md = "```html\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    // <code> 内は escape 済 (既存挙動を壊さない)
    expect(html).toContain("&lt;div class=&quot;x&quot;&gt;a &amp; b&lt;/div&gt;");
    // data-raw は decode で元に戻る
    const raw = extractAttr(html, "data-raw");
    expect(raw).toBeDefined();
    expect(decodeURIComponent(raw!)).toBe(code);
  });

  it("long code (>=500 chars): encoding='base64' and base64 round-trips", () => {
    // 600 文字の ASCII + 末尾に 6 文字 (Latin-1 拡張) で UTF-8 確認
    const code = "A".repeat(600) + "éééééé";
    expect(code.length).toBeGreaterThanOrEqual(500);

    const md = "```typescript\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    expect(html).toContain('data-raw-encoding="base64"');
    const raw = extractAttr(html, "data-raw");
    expect(raw).toBeDefined();
    expect(utf8Base64(code)).toBe(raw);
    expect(Buffer.from(raw!, "base64").toString("utf-8")).toBe(code);
  });

  it("boundary: exactly 500 chars uses base64", () => {
    const code = "x".repeat(500);
    const md = "```bash\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('data-raw-encoding="base64"');
  });

  it("boundary: 499 chars uses url encoding", () => {
    const code = "x".repeat(499);
    const md = "```bash\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('data-raw-encoding="url"');
  });

  it("no language specified: data-raw still added, no data-lang attr", () => {
    const code = "plain text";
    const md = "```\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    // data-lang 属性は付かない
    expect(html).not.toMatch(/<pre[^>]*data-lang="/);
    // data-raw は付く
    const raw = extractAttr(html, "data-raw");
    expect(raw).toBeDefined();
    expect(decodeURIComponent(raw!)).toBe(code);
    expect(html).toContain('data-raw-encoding="url"');
  });

  it("diff block (rich-code-diff) also has data-raw attached", () => {
    const code = "-old\n+new";
    const md = "```diff\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    // 既存挙動: rich-code-diff クラス維持
    expect(html).toContain('class="rich-code-diff"');
    // 新挙動: data-raw 付与
    const raw = extractAttr(html, "data-raw");
    expect(raw).toBeDefined();
    expect(decodeURIComponent(raw!)).toBe(code);
    expect(html).toContain('data-raw-encoding="url"');
  });

  it("data-raw encoded value never contains a literal double-quote (HTML attr safety)", () => {
    const code = 'echo "hello";';
    const md = "```bash\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);
    const raw = extractAttr(html, "data-raw");
    expect(raw).toBeDefined();
    // encodeURIComponent はダブルクォートを %22 に変換するので raw 内には現れない
    expect(raw!.includes('"')).toBe(false);
    // round-trip 確認
    expect(decodeURIComponent(raw!)).toBe(code);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 本リポ classlab-weekly-news の fixture (POSTED_*) と output 形式が一致するか
  // posting-html-fixture-sync ルール R1 / R3 準拠
  // ──────────────────────────────────────────────────────────────────────────
  describe("fixture parity with classlab-weekly-news posted-html.ts", () => {
    it("typescript fixture matches POSTED_TYPESCRIPT data-raw", () => {
      const code = "const x: number = 1;\nconsole.log(x);";
      const md = "```typescript\n" + code + "\n```";
      const { html } = renderToHtml(md, knowledgeTpl);

      // 本リポ POSTED_TYPESCRIPT の data-raw と同じ形式
      const expectedRaw = "const%20x%3A%20number%20%3D%201%3B%0Aconsole.log(x)%3B";
      expect(extractAttr(html, "data-raw")).toBe(expectedRaw);
      expect(html).toContain('data-lang="typescript"');
      expect(html).toContain('data-raw-encoding="url"');
    });

    it("claude-code fixture matches POSTED_CLAUDE_CODE data-raw (Japanese fully encoded)", () => {
      const code = "Claude codeのデザインは…";
      const md = "```claude-code\n" + code + "\n```";
      const { html } = renderToHtml(md, knowledgeTpl);

      // 本リポ POSTED_CLAUDE_CODE の data-raw — encodeURIComponent で日本語完全エンコード
      const expectedRaw =
        "Claude%20code%E3%81%AE%E3%83%87%E3%82%B6%E3%82%A4%E3%83%B3%E3%81%AF%E2%80%A6";
      expect(extractAttr(html, "data-raw")).toBe(expectedRaw);
    });

    it("terminal fixture matches POSTED_TERMINAL data-raw", () => {
      const code = 'ls -la\necho "hi"';
      const md = "```terminal\n" + code + "\n```";
      const { html } = renderToHtml(md, knowledgeTpl);
      expect(extractAttr(html, "data-raw")).toBe('ls%20-la%0Aecho%20%22hi%22');
    });

    it("ps fixture matches POSTED_PS data-raw", () => {
      const code = "Get-Process | Where-Object { $_.CPU -gt 1 }";
      const md = "```ps\n" + code + "\n```";
      const { html } = renderToHtml(md, knowledgeTpl);
      expect(extractAttr(html, "data-raw")).toBe(
        "Get-Process%20%7C%20Where-Object%20%7B%20%24_.CPU%20-gt%201%20%7D",
      );
    });
  });
});

// ────────────────────────────────────────────────────────────────────────────
// Task #48 Wave 48.7 — claude-code blocks structured with <prompt>/<output> tags
//
// 仕様 (Wave 48.7 design):
//   - claude-code 言語ブロックを <prompt>...</prompt> / <output>...</output> で構造化
//   - renderer.code() が claude-code (alias: claude / claude-prompt / cc) を検出した時、
//     <prompt> / <output> セグメントを <div class="claude-line claude-line--prompt">
//     / <div class="claude-line claude-line--output"> 構造化 HTML に変換
//   - <prompt> 行は <span class="claude-prompt-mark">❯</span> + <span class="claude-prompt-text">…</span>
//   - <output> 行は plain text (HTML escape のみ)
//   - タグなしの旧記法は <output> 扱い + console.warn (後方互換、新規記事では非推奨)
//   - HTML escape: <prompt> や <output> 内の生 < > & を escape
//   - data-raw は markdown 原文 (タグ込み) を保持 (既存挙動)
//   - claude-code 以外の言語は影響を受けない
//   - エイリアス (claude / claude-prompt / cc) は claude-code と同等の構造化
// ────────────────────────────────────────────────────────────────────────────

describe("renderToHtml() — claude-code structured <prompt>/<output> (Wave 48.7)", () => {
  function extractAttr(html: string, attr: string): string | undefined {
    const re = new RegExp(`${attr}="([^"]*)"`);
    const m = html.match(re);
    return m?.[1];
  }

  function extractCodeBody(html: string): string {
    const m = html.match(/<code>([\s\S]*?)<\/code>/);
    return m?.[1] ?? "";
  }

  it("emits <div class=\"claude-line--prompt\"> for <prompt> segment", () => {
    const code = "<prompt>レビューしてください</prompt>";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    expect(body).toContain('<div class="claude-line claude-line--prompt">');
    expect(body).toContain('<span class="claude-prompt-mark">❯</span>');
    expect(body).toContain('<span class="claude-prompt-text">レビューしてください</span>');
  });

  it("emits <div class=\"claude-line--output\"> for <output> segment", () => {
    const code = "<output>レビュー完了しました</output>";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    expect(body).toContain('<div class="claude-line claude-line--output">レビュー完了しました</div>');
    // prompt 系のマークアップは含まれない
    expect(body).not.toContain('claude-line--prompt');
  });

  it("splits multiple alternating <prompt>/<output> segments in order", () => {
    const code = [
      "<prompt>このプロジェクトをレビューしてください</prompt>",
      "<output>レビュー開始...</output>",
      "<prompt>セキュリティの観点も追加で</prompt>",
      "<output>セキュリティ観点も追加で確認しました</output>",
    ].join("\n");
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    // 4 セグメント存在
    const promptCount = (body.match(/<div class="claude-line claude-line--prompt">/g) ?? []).length;
    const outputCount = (body.match(/<div class="claude-line claude-line--output">/g) ?? []).length;
    expect(promptCount).toBe(2);
    expect(outputCount).toBe(2);

    // 順序: prompt → output → prompt → output
    const promptIdx1 = body.indexOf("このプロジェクトをレビューしてください");
    const outputIdx1 = body.indexOf("レビュー開始...");
    const promptIdx2 = body.indexOf("セキュリティの観点も追加で");
    const outputIdx2 = body.indexOf("セキュリティ観点も追加で確認しました");

    expect(promptIdx1).toBeGreaterThan(-1);
    expect(outputIdx1).toBeGreaterThan(promptIdx1);
    expect(promptIdx2).toBeGreaterThan(outputIdx1);
    expect(outputIdx2).toBeGreaterThan(promptIdx2);
  });

  it("backward-compat: claude-code without tags is treated as <output> + console.warn", () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const code = "ls -la\necho hello";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    expect(body).toContain('<div class="claude-line claude-line--output">');
    expect(body).toContain("ls -la");
    expect(body).toContain("echo hello");
    // 警告が出る
    expect(warnSpy).toHaveBeenCalled();
    const calls = warnSpy.mock.calls.map((args) => args.join(" "));
    expect(calls.some((c) => c.includes("claude-code"))).toBe(true);
    warnSpy.mockRestore();
  });

  it("HTML-escapes < > & inside <prompt> text", () => {
    const code = "<prompt>1 < 2 & 3 > 0</prompt>";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    // claude-prompt-text の内側で escape されている
    expect(body).toContain(
      '<span class="claude-prompt-text">1 &lt; 2 &amp; 3 &gt; 0</span>',
    );
    // claude-prompt-text の中身 (closing </span> の直前まで) には raw < > が含まれない
    // (& は entity prefix として残る — &lt; / &amp; / &gt; など)
    const innerMatch = body.match(/claude-prompt-text">([^<]*)<\/span>/);
    expect(innerMatch).not.toBeNull();
    const inner = innerMatch![1]!;
    expect(inner).not.toMatch(/[<>]/);
    // raw & (entity prefix でない素の &) が無いこと: & の直後が必ず entity name になる
    expect(inner).not.toMatch(/&(?!(amp|lt|gt|quot|#39|#\d+|[a-zA-Z]+);)/);
  });

  it("HTML-escapes < > & inside <output> text", () => {
    const code = "<output><script>alert(1)</script></output>";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    // raw <script> が再展開されない
    expect(body).not.toMatch(/<div class="claude-line claude-line--output"><script>/);
    expect(body).toContain("&lt;script&gt;alert(1)&lt;/script&gt;");
  });

  it("data-raw preserves the markdown body verbatim (tags included)", () => {
    const code = "<prompt>レビュー</prompt>\n<output>完了</output>";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const raw = extractAttr(html, "data-raw");
    expect(raw).toBeDefined();
    // markdown 原文 (タグ込み) が保持される
    expect(decodeURIComponent(raw!)).toBe(code);
  });

  it("data-lang remains 'claude-code'", () => {
    const code = "<prompt>x</prompt>";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    expect(html).toContain('data-lang="claude-code"');
  });

  it("alias 'claude' produces the same structured output", () => {
    const code = "<prompt>hi</prompt>";
    const md = "```claude\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    expect(body).toContain('<div class="claude-line claude-line--prompt">');
    expect(body).toContain('<span class="claude-prompt-text">hi</span>');
  });

  it("alias 'claude-prompt' produces the same structured output", () => {
    const code = "<prompt>hi</prompt>";
    const md = "```claude-prompt\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    expect(body).toContain('<div class="claude-line claude-line--prompt">');
  });

  it("alias 'cc' produces the same structured output", () => {
    const code = "<output>done</output>";
    const md = "```cc\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    expect(body).toContain('<div class="claude-line claude-line--output">done</div>');
  });

  it("non-claude-code language is unaffected (typescript still escapes raw text only)", () => {
    const code = "<prompt>not parsed</prompt>";
    const md = "```typescript\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    // <code> 内側は HTML escape のみ。claude-line 構造化は走らない
    expect(html).not.toContain('claude-line--prompt');
    expect(html).toContain("&lt;prompt&gt;not parsed&lt;/prompt&gt;");
  });

  it("preserves multiline output content with newlines escaped to plain text", () => {
    const code = "<output>line one\nline two\nline three</output>";
    const md = "```claude-code\n" + code + "\n```";
    const { html } = renderToHtml(md, knowledgeTpl);

    const body = extractCodeBody(html);
    expect(body).toContain("line one");
    expect(body).toContain("line two");
    expect(body).toContain("line three");
    // 単一の output div に格納される (newlines 含む)
    const outputCount = (body.match(/<div class="claude-line claude-line--output">/g) ?? []).length;
    expect(outputCount).toBe(1);
  });
});

describe("renderToHtml() — inline transforms", () => {
  it("[[Cmd+S]] → <kbd class=rich-kbd>Cmd+S</kbd>", () => {
    const { html } = renderToHtml("Press [[Cmd+S]] now.", knowledgeTpl);
    expect(html).toContain('<kbd class="rich-kbd">Cmd+S</kbd>');
  });

  it("inline `code` → <code class=rich-inline-code>", () => {
    const { html } = renderToHtml("use `npm test`", knowledgeTpl);
    expect(html).toContain('<code class="rich-inline-code">npm test</code>');
  });

  it("external http/https links → target=_blank without rich-source-link class (#37 hotfix)", () => {
    const md = "[Supabase](https://supabase.com/docs)";
    const { html } = renderToHtml(md, knowledgeTpl);
    // rich-source-link class は段落フローを block カード化するため付与しない
    expect(html).not.toContain('class="rich-source-link"');
    expect(html).toContain('target="_blank"');
    expect(html).toContain('rel="noopener noreferrer"');
    expect(html).toContain("https://supabase.com/docs");
  });

  it("relative links do NOT get external-badge", () => {
    const { html } = renderToHtml("[local](/about)", knowledgeTpl);
    expect(html).not.toContain("rich-external-badge");
  });
});

// ---------------------------------------------------------------------------
// renderToHtml() — link-card vs inline link
// ---------------------------------------------------------------------------

describe("renderToHtml() — link-card detection", () => {
  it("1. [text](url) inline link → <a> without .link-card class", () => {
    const md = "Refer to [Supabase](https://supabase.com/docs) for details.";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<a href="https://supabase.com/docs"');
    expect(html).not.toContain('class="link-card"');
    expect(html).not.toContain('<div class="link-card"');
  });

  it("2. URL-only paragraph → <div class=link-card> wrapping <a>", () => {
    const md = "前の段落\n\nhttps://example.com/article\n\n次の段落";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<div class="link-card">');
    // must contain an <a> inside the div
    expect(html).toMatch(/<div class="link-card"><a\s/);
    expect(html).toContain('href="https://example.com/article"');
    expect(html).toContain('data-url="https://example.com/article"');
    expect(html).toContain('target="_blank"');
    expect(html).toContain('rel="noopener noreferrer"');
    expect(html).not.toContain("<p><a");
  });

  it("3. autolink-like [https://x.com](https://x.com) as sole paragraph content → link-card with inner <a>", () => {
    const md = "\n\n[https://example.com/autolink](https://example.com/autolink)\n\n";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<div class="link-card">');
    expect(html).toMatch(/<div class="link-card"><a\s/);
    expect(html).toContain('href="https://example.com/autolink"');
    expect(html).toContain('data-url="https://example.com/autolink"');
    expect(html).toContain('target="_blank"');
    expect(html).toContain('rel="noopener noreferrer"');
  });

  it("4. paragraph with URL + other text → stays inline, no link-card", () => {
    const md = "Check out https://example.com for more info.";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).not.toContain('class="link-card"');
  });

  it("5. consecutive URL-only lines (single newline, same paragraph) → inline links, not link-card", () => {
    // Two URLs separated by a single newline are in the same paragraph block
    // and cannot both be the sole content, so they stay as inline links.
    const md = "https://example.com/a\nhttps://example.com/b";
    const { html } = renderToHtml(md, knowledgeTpl);
    // They remain in a <p> block (not link-card divs)
    // The key guarantee: both URLs appear as links but NOT as link-card divs
    expect(html).not.toContain('<div class="link-card"');
  });

  it("6. http:// (non-HTTPS) URL-only paragraph → link-card with inner <a>", () => {
    const md = "\n\nhttp://example.com/old-article\n\n";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<div class="link-card">');
    expect(html).toMatch(/<div class="link-card"><a\s/);
    expect(html).toContain('href="http://example.com/old-article"');
    expect(html).toContain('data-url="http://example.com/old-article"');
    expect(html).toContain('target="_blank"');
    expect(html).toContain('rel="noopener noreferrer"');
  });

  it("7. relative URL [foo](/articles/x) → inline link, no link-card", () => {
    const md = "[foo](/articles/x)";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<a href="/articles/x"');
    expect(html).not.toContain('class="link-card"');
  });
});

describe("renderToHtml() — heading class attachment", () => {
  it("`## 概要` in knowledge template → h2 with class=rich-summary", () => {
    const md = "## 概要\n\n本文";
    const { html, appliedClasses } = renderToHtml(md, knowledgeTpl);
    expect(html).toMatch(/<h2[^>]*class="rich-summary"/);
    expect(appliedClasses).toContain("rich-summary");
  });

  it("`## [source:anthropic]` → <section class=rich-source-section> with data-source", () => {
    const md = "## [source:anthropic]\n\nニュース本文";
    const { html } = renderToHtml(md, weeklyTpl);
    expect(html).toContain('class="rich-source-section"');
    expect(html).toContain('data-source="anthropic"');
  });
});

describe("renderToHtml() — security", () => {
  it("strips javascript: URLs from anchors", () => {
    const md = "[xss](javascript:alert(1))";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).not.toContain("javascript:");
  });

  it("strips data:text/html URLs from anchors", () => {
    const md = "[xss](data:text/html,<script>alert(1)</script>)";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).not.toMatch(/href="data:text\/html/);
  });
});

// ---------------------------------------------------------------------------
// headingAnchorId() — slug helper exported from markdown.ts
// ---------------------------------------------------------------------------

describe("headingAnchorId()", () => {
  it("lowercases and replaces spaces with hyphens", () => {
    expect(headingAnchorId("Hello World")).toBe("hello-world");
  });

  it("collapses consecutive non-alphanumeric chars to a single hyphen", () => {
    expect(headingAnchorId("foo  bar")).toBe("foo-bar");
    expect(headingAnchorId("foo---bar")).toBe("foo-bar");
  });

  it("trims leading and trailing hyphens", () => {
    expect(headingAnchorId("  Hello  ")).toBe("hello");
  });

  it("preserves ASCII digits", () => {
    expect(headingAnchorId("Step 1: Start")).toBe("step-1-start");
  });

  it("preserves Japanese-only text as a slug (Unicode-aware)", () => {
    // Unicode \p{L} keeps CJK characters; result is the Japanese text lowercased.
    const result = headingAnchorId("技術トピック");
    expect(result).toBe("技術トピック");
  });

  it("handles mixed Japanese + ASCII: number prefix + Japanese body", () => {
    // e.g. "1. 西側はモノづくりを忘れ" → "1-西側はモノづくりを忘れ"
    // The period and space become a single hyphen; Japanese chars are preserved.
    const result = headingAnchorId("1. 西側はモノづくりを忘れ");
    expect(result).toBe("1-西側はモノづくりを忘れ");
  });

  it("handles mixed Japanese + ASCII: ASCII words separated by Japanese", () => {
    // e.g. "Hacker News の話題" → "hacker-news-の話題"
    const result = headingAnchorId("Hacker News の話題");
    expect(result).toBe("hacker-news-の話題");
  });
});

// ---------------------------------------------------------------------------
// renderToHtml() — empty / partial / null template defensive handling
// ---------------------------------------------------------------------------

describe("renderToHtml() — empty/partial/null template fallback", () => {
  it("empty template object ({}) should not throw", () => {
    const md = "# Heading\n\n本文";
    expect(() => renderToHtml(md, {} as Template)).not.toThrow();
    const { html } = renderToHtml(md, {} as Template);
    expect(html).toMatch(/<h1/);
  });

  it("template with only required_sections should work", () => {
    const tpl = { required_sections: [{ heading: "概要", class: "rich-summary" }] } as unknown as Template;
    const md = "## 概要\n\n本文";
    expect(() => renderToHtml(md, tpl)).not.toThrow();
    const { html } = renderToHtml(md, tpl);
    expect(html).toMatch(/<h2/);
  });

  it("template with only optional_sections should work", () => {
    const tpl = { optional_sections: [{ heading: "参考", class: "rich-references" }] } as unknown as Template;
    const md = "## 参考\n\n本文";
    expect(() => renderToHtml(md, tpl)).not.toThrow();
    const { html } = renderToHtml(md, tpl);
    expect(html).toMatch(/<h2/);
  });

  it("template with null sections should not throw", () => {
    const tpl = { required_sections: null, optional_sections: null } as unknown as Template;
    const md = "## Heading\n\n本文";
    expect(() => renderToHtml(md, tpl)).not.toThrow();
    const { html } = renderToHtml(md, tpl);
    expect(html).toMatch(/<h2/);
  });
});

// ---------------------------------------------------------------------------
// renderToHtml() — heading id attributes
// ---------------------------------------------------------------------------

describe("renderToHtml() — heading id attributes", () => {
  it("adds id to h2 tags", () => {
    const md = "## Hello World\n\nsome text";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<h2 id="hello-world"');
  });

  it("adds id to h3 tags", () => {
    const md = "### My Section\n\nsome text";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<h3 id="my-section"');
  });

  it("adds a Unicode slug id to h2 when heading text is Japanese-only", () => {
    // Unicode-aware headingAnchorId now preserves Japanese chars directly.
    // "## 技術トピック" → id="技術トピック"
    const md = "## 技術トピック\n\nsome text";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<h2 id="技術トピック"');
  });

  it("heading id matches TOC list anchor for ASCII text", () => {
    // The LLM generates a TOC like [Hello World](#hello-world)
    // The renderer must produce <h2 id="hello-world">
    const md = [
      "## 目次",
      "",
      "- [Hello World](#hello-world)",
      "",
      "## Hello World",
      "",
      "content here",
    ].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    // The anchor href must match the heading id
    expect(html).toContain('href="#hello-world"');
    expect(html).toContain('<h2 id="hello-world"');
  });

  it("duplicate heading text gets unique ids (suffix -2, -3, ...)", () => {
    const md = "## foo\n\n## foo\n\n## foo\n\n";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<h2 id="foo"');
    expect(html).toContain('<h2 id="foo-2"');
    expect(html).toContain('<h2 id="foo-3"');
  });

  it("heading with a special class still gets an id attribute", () => {
    // '## 概要' gets class='rich-summary' from template — it must also get id
    const md = "## 概要\n\nsome text";
    const { html } = renderToHtml(md, knowledgeTpl);
    // Should have both id and class attributes
    expect(html).toMatch(/<h2[^>]*id="[^"]+"/);
    expect(html).toMatch(/<h2[^>]*class="rich-summary"/);
  });

  it("source-section heading still gets an id on the inner h-tag", () => {
    const md = "## [source:anthropic]\n\ntext";
    const { html } = renderToHtml(md, weeklyTpl);
    // The inner h2 inside the section wrapper must have an id
    expect(html).toMatch(/<h2 id="[^"]+"/);
  });

  it("adds id to h4 tags", () => {
    const md = "#### Deep Section\n\nsome text";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<h4 id="deep-section"');
  });

  it("adds id to h5 tags", () => {
    const md = "##### Even Deeper\n\nsome text";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<h5 id="even-deeper"');
  });

  it("adds id to h6 tags", () => {
    const md = "###### Leaf Section\n\nsome text";
    const { html } = renderToHtml(md, knowledgeTpl);
    expect(html).toContain('<h6 id="leaf-section"');
  });

  it("all heading levels h1-h6 get id attributes in a single document", () => {
    const md = [
      "# H1 Title",
      "",
      "## H2 Section",
      "",
      "### H3 Sub",
      "",
      "#### H4 Deep",
      "",
      "##### H5 Deeper",
      "",
      "###### H6 Leaf",
    ].join("\n");
    const { html } = renderToHtml(md, knowledgeTpl);
    // Every heading level must have an id attribute
    for (let level = 1; level <= 6; level++) {
      expect(html).toMatch(new RegExp(`<h${level}[^>]* id="[^"]+"`));
    }
  });
});

// ---------------------------------------------------------------------------
// renderToHtmlAsync() — PlantUML pipeline integration
// ---------------------------------------------------------------------------

describe("renderToHtmlAsync()", () => {
  beforeAll(async () => {
    // Templates already loaded in outer beforeAll — knowledgeTpl is available
  });

  it("1. options 未指定 → sync renderToHtml と同じ html / appliedClasses、plantumlReplacements は undefined", async () => {
    processPlantUMLBlocksMock.mockClear();

    const md = "## Hello\n\nsome text";
    const syncResult = renderToHtml(md, knowledgeTpl);
    const asyncResult = await renderToHtmlAsync(md, knowledgeTpl);

    expect(asyncResult.html).toBe(syncResult.html);
    expect(asyncResult.appliedClasses).toEqual(syncResult.appliedClasses);
    expect(asyncResult.plantumlReplacements).toBeUndefined();
    // processPlantUMLBlocks must NOT be called when options are omitted
    expect(processPlantUMLBlocksMock).not.toHaveBeenCalled();
  });

  it("2. options 指定 + plantuml ブロック含む source → img タグに置換、replacements.length === 1、cacheKey 8 文字 hex", async () => {
    const fakeImgHtml = '<img src="https://d2f75plg0t6qwk.cloudfront.net/plantuml/knowledge/my-slug/a1b2c3d4.svg" data-plantuml-source="QGFydWw=" alt="PlantUML diagram">';
    const fakeReplacement: PlantUMLReplacement = {
      cacheKey: "a1b2c3d4",
      s3Key: "plantuml/knowledge/my-slug/a1b2c3d4.svg",
      cdnUrl: "https://d2f75plg0t6qwk.cloudfront.net/plantuml/knowledge/my-slug/a1b2c3d4.svg",
      sourceBytes: 42,
      skipped: false,
    };

    processPlantUMLBlocksMock.mockResolvedValueOnce({
      html: `<h2 id="diagram">Diagram</h2>\n${fakeImgHtml}`,
      replacements: [fakeReplacement],
    });

    const md = [
      "## Diagram",
      "",
      "```plantuml",
      "@startuml",
      "Foo --> Bar",
      "@enduml",
      "```",
    ].join("\n");

    const result = await renderToHtmlAsync(md, knowledgeTpl, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result.html).toContain("https://d2f75plg0t6qwk.cloudfront.net/plantuml/");
    expect(result.html).not.toContain('data-lang="plantuml"');
    expect(result.plantumlReplacements).toHaveLength(1);
    const rep0 = result.plantumlReplacements?.[0];
    expect(rep0).toBeDefined();
    expect(rep0!.cacheKey).toMatch(/^[0-9a-f]{8}$/);
    expect(rep0!.skipped).toBe(false);
  });

  it("3. options 指定 + plantuml ブロックなし source → plantumlReplacements は [] (空配列)", async () => {
    const md = "## Hello\n\nsome text";
    const syncHtml = renderToHtml(md, knowledgeTpl).html;

    processPlantUMLBlocksMock.mockResolvedValueOnce({
      html: syncHtml,
      replacements: [],
    });

    const result = await renderToHtmlAsync(md, knowledgeTpl, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result.plantumlReplacements).toEqual([]);
    expect(result.html).toBe(syncHtml);
  });

  it("4. options 指定 + mermaid ブロックのみ → mermaid は触れられない、plantumlReplacements は []", async () => {
    const md = [
      "## Chart",
      "",
      "```mermaid",
      "graph TD; A-->B",
      "```",
    ].join("\n");

    const syncHtml = renderToHtml(md, knowledgeTpl).html;

    processPlantUMLBlocksMock.mockResolvedValueOnce({
      html: syncHtml,
      replacements: [],
    });

    const result = await renderToHtmlAsync(md, knowledgeTpl, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    // mermaid block must be untouched
    expect(result.html).toContain("mermaid");
    expect(result.html).not.toContain("plantuml");
    expect(result.plantumlReplacements).toEqual([]);
  });

  it("5. options 指定 + 構文エラー plantuml → 原文 <pre><code class=language-plantuml> 残留 + HTMLコメント、skipped === true", async () => {
    const rawInner = "@startuml\nBROKEN SYNTAX\n@enduml";
    const fallbackHtml =
      `<pre><code class="language-plantuml">${rawInner}</code></pre>` +
      `<!-- PlantUML render failed: HTTP 400 -->`;
    const fakeReplacement: PlantUMLReplacement = {
      cacheKey: "",
      s3Key: "",
      cdnUrl: "",
      sourceBytes: rawInner.length,
      skipped: true,
    };

    processPlantUMLBlocksMock.mockResolvedValueOnce({
      html: fallbackHtml,
      replacements: [fakeReplacement],
    });

    const md = [
      "```plantuml",
      rawInner,
      "```",
    ].join("\n");

    const result = await renderToHtmlAsync(md, knowledgeTpl, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result.html).toContain('class="language-plantuml"');
    expect(result.html).toContain("PlantUML render failed");
    expect(result.plantumlReplacements).toHaveLength(1);
    const errRep0 = result.plantumlReplacements?.[0];
    expect(errRep0).toBeDefined();
    expect(errRep0!.skipped).toBe(true);
  });
});
