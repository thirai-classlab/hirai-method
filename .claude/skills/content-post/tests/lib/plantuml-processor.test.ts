/**
 * Tests for src/lib/plantuml-processor.ts
 *
 * Test observations:
 *   1. replaces <pre data-lang=plantuml> with <img src> tag
 *   2. leaves original <pre> on syntax error (PlantUMLRenderError) with HTML comment
 *   3. skips S3 upload when object already exists (idempotency)
 *   4. processes multiple PlantUML blocks independently
 *   5. embeds source as data-plantuml-source attribute (base64) when <= 4 KB
 *   6. omits data-plantuml-source when source > 4 KB
 *   7. does not touch mermaid blocks
 *   8. does not touch non-plantuml code fences
 *   9. empty source is skipped (no replacement, original <pre> kept)
 *  10. replacements array shape: cacheKey 8-char hex, s3Key prefix, cdnUrl host
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock plantuml-renderer
// ---------------------------------------------------------------------------
const renderPlantUmlMock = vi.fn<
  (source: string) => Promise<{ svg: string; cacheKey: string; warnings: string[] }>
>();

vi.mock("../../src/lib/plantuml-renderer.js", () => {
  return {
    renderPlantUml: renderPlantUmlMock,
    PlantUMLRenderError: class PlantUMLRenderError extends Error {
      httpStatus: number;
      constructor(httpStatus: number, message: string) {
        super(message);
        this.name = "PlantUMLRenderError";
        this.httpStatus = httpStatus;
      }
    },
  };
});

// ---------------------------------------------------------------------------
// Mock s3
// ---------------------------------------------------------------------------
const uploadToS3Mock = vi.fn<
  (key: string, body: Buffer | Uint8Array | string, contentType?: string) => Promise<{ key: string; url: string }>
>();
const objectExistsMock = vi.fn<(key: string) => Promise<boolean>>();
const cloudFrontUrlMock = vi.fn<(key: string) => string>();

vi.mock("../../src/lib/s3.js", () => {
  return {
    uploadToS3: uploadToS3Mock,
    objectExists: objectExistsMock,
    cloudFrontUrl: cloudFrontUrlMock,
  };
});

async function loadModule() {
  vi.resetModules();
  return await import("../../src/lib/plantuml-processor.js");
}

describe("processPlantUMLBlocks()", () => {
  beforeEach(() => {
    renderPlantUmlMock.mockReset();
    uploadToS3Mock.mockReset();
    objectExistsMock.mockReset();
    cloudFrontUrlMock.mockReset();

    // Default happy-path setup
    renderPlantUmlMock.mockResolvedValue({
      svg: "<svg>diagram</svg>",
      cacheKey: "a1b2c3d4",
      warnings: [],
    });
    objectExistsMock.mockResolvedValue(false);
    uploadToS3Mock.mockImplementation(async (key) => ({
      key,
      url: `https://d2f75plg0t6qwk.cloudfront.net/${key}`,
    }));
    cloudFrontUrlMock.mockImplementation(
      (key) => `https://d2f75plg0t6qwk.cloudfront.net/${key}`,
    );
  });

  it("replaces <pre data-lang=plantuml> with <img src> tag", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const source = "@startuml\nFoo --> Bar\n@enduml";
    const html = `<pre data-lang="plantuml"><code>${source}</code></pre>`;

    const { html: result, replacements } = await processPlantUMLBlocks(html, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result).toContain("<img");
    expect(result).toContain('src="https://d2f75plg0t6qwk.cloudfront.net/plantuml/knowledge/my-slug/a1b2c3d4.svg"');
    expect(result).toContain('alt="PlantUML diagram"');
    expect(result).not.toContain('<pre data-lang="plantuml">');
    expect(replacements).toHaveLength(1);
  });

  it("leaves original <pre> on syntax error (PlantUMLRenderError) with HTML comment", async () => {
    const { PlantUMLRenderError } = await import("../../src/lib/plantuml-renderer.js");
    renderPlantUmlMock.mockRejectedValue(
      new PlantUMLRenderError(400, "syntax error"),
    );

    const { processPlantUMLBlocks } = await loadModule();
    const source = "@startuml\nINVALID\n@enduml";
    const html = `<pre data-lang="plantuml"><code>${source}</code></pre>`;

    const { html: result, replacements } = await processPlantUMLBlocks(html, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result).toContain('class="language-plantuml"');
    expect(result).toContain("<!-- PlantUML render failed:");
    expect(result).toContain("syntax error");
    expect(result).not.toContain("<img");
    expect(replacements).toHaveLength(1);
    expect(replacements[0]!.skipped).toBe(true);
  });

  it("skips S3 upload when object already exists (idempotency)", async () => {
    objectExistsMock.mockResolvedValue(true);

    const { processPlantUMLBlocks } = await loadModule();
    const source = "@startuml\nFoo --> Bar\n@enduml";
    const html = `<pre data-lang="plantuml"><code>${source}</code></pre>`;

    const { html: result } = await processPlantUMLBlocks(html, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(uploadToS3Mock).not.toHaveBeenCalled();
    expect(result).toContain("<img");
  });

  it("processes multiple PlantUML blocks independently (one error does not block others)", async () => {
    const { PlantUMLRenderError } = await import("../../src/lib/plantuml-renderer.js");

    renderPlantUmlMock
      .mockRejectedValueOnce(new PlantUMLRenderError(400, "bad diagram"))
      .mockResolvedValueOnce({
        svg: "<svg>ok</svg>",
        cacheKey: "e5f6a7b8",
        warnings: [],
      });

    cloudFrontUrlMock.mockImplementation(
      (key) => `https://d2f75plg0t6qwk.cloudfront.net/${key}`,
    );

    const { processPlantUMLBlocks } = await loadModule();
    const html =
      `<pre data-lang="plantuml"><code>@startuml\nINVALID\n@enduml</code></pre>` +
      `<pre data-lang="plantuml"><code>@startuml\nGood --> Diagram\n@enduml</code></pre>`;

    const { html: result, replacements } = await processPlantUMLBlocks(html, {
      slug: "multi-slug",
      contentType: "tech_article",
    });

    expect(replacements).toHaveLength(2);
    expect(replacements[0]!.skipped).toBe(true);
    expect(replacements[1]!.skipped).toBe(false);
    expect(result).toContain("<!-- PlantUML render failed:");
    expect(result).toContain("<img");
    expect(uploadToS3Mock).toHaveBeenCalledTimes(1);
  });

  it("embeds source as data-plantuml-source attribute (base64) when source <= 4 KB", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const source = "@startuml\nFoo --> Bar\n@enduml"; // well under 4 KB
    const html = `<pre data-lang="plantuml"><code>${source}</code></pre>`;

    const { html: result } = await processPlantUMLBlocks(html, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    const expectedB64 = Buffer.from(source, "utf8").toString("base64");
    expect(result).toContain(`data-plantuml-source="${expectedB64}"`);
  });

  it("omits data-plantuml-source when source > 4 KB", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    // Create a source that exceeds 4096 bytes
    const largeDiagram = "@startuml\n" + "Foo --> Bar\n".repeat(400) + "@enduml";
    expect(Buffer.from(largeDiagram, "utf8").byteLength).toBeGreaterThan(4096);

    const html = `<pre data-lang="plantuml"><code>${largeDiagram}</code></pre>`;

    const { html: result } = await processPlantUMLBlocks(html, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result).toContain("<img");
    expect(result).not.toContain("data-plantuml-source");
  });

  it("does not touch mermaid blocks", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const mermaidHtml = `<pre data-lang="mermaid"><code>graph TD\n  A --> B</code></pre>`;

    const { html: result, replacements } = await processPlantUMLBlocks(
      mermaidHtml,
      { slug: "my-slug", contentType: "knowledge" },
    );

    expect(result).toBe(mermaidHtml);
    expect(replacements).toHaveLength(0);
    expect(renderPlantUmlMock).not.toHaveBeenCalled();
  });

  it("does not touch non-plantuml code fences (ts, py, etc.)", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const tsHtml = `<pre data-lang="typescript"><code>const x = 1;</code></pre>`;
    const pyHtml = `<pre><code class="language-py">print("hello")</code></pre>`;
    const combined = tsHtml + "\n" + pyHtml;

    const { html: result, replacements } = await processPlantUMLBlocks(
      combined,
      { slug: "my-slug", contentType: "knowledge" },
    );

    expect(result).toBe(combined);
    expect(replacements).toHaveLength(0);
    expect(renderPlantUmlMock).not.toHaveBeenCalled();
  });

  it("skips empty source without creating a replacement", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const emptyHtml = `<pre data-lang="plantuml"><code></code></pre>`;

    const { html: result, replacements } = await processPlantUMLBlocks(
      emptyHtml,
      { slug: "my-slug", contentType: "knowledge" },
    );

    expect(result).toBe(emptyHtml);
    expect(replacements).toHaveLength(0);
    expect(renderPlantUmlMock).not.toHaveBeenCalled();
  });

  it("replacements shape: cacheKey 8-char hex, s3Key prefix, cdnUrl host", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const source = "@startuml\nFoo --> Bar\n@enduml";
    const html = `<pre data-lang="plantuml"><code>${source}</code></pre>`;

    const { replacements } = await processPlantUMLBlocks(html, {
      slug: "shape-slug",
      contentType: "issue",
    });

    expect(replacements).toHaveLength(1);
    const r = replacements[0]!;
    expect(r.cacheKey).toMatch(/^[0-9a-f]{8}$/);
    expect(r.s3Key).toMatch(/^plantuml\/issue\/shape-slug\//);
    expect(r.cdnUrl).toContain("cloudfront.net");
    expect(typeof r.sourceBytes).toBe("number");
    expect(r.skipped).toBe(false);
  });

  // ---------------------------------------------------------------------------
  // Fix 2 (HIGH): slug validation
  // ---------------------------------------------------------------------------

  it("throws on slug containing double quotes", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const html = `<pre data-lang="plantuml"><code>@startuml\nFoo-->Bar\n@enduml</code></pre>`;

    await expect(
      processPlantUMLBlocks(html, { slug: 'bad"slug', contentType: "knowledge" }),
    ).rejects.toThrow("Invalid slug");
  });

  it("throws on slug containing forward slashes", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const html = `<pre data-lang="plantuml"><code>@startuml\nFoo-->Bar\n@enduml</code></pre>`;

    await expect(
      processPlantUMLBlocks(html, { slug: "path/traversal", contentType: "knowledge" }),
    ).rejects.toThrow("Invalid slug");
  });

  it("throws on slug containing angle brackets", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const html = `<pre data-lang="plantuml"><code>@startuml\nFoo-->Bar\n@enduml</code></pre>`;

    await expect(
      processPlantUMLBlocks(html, { slug: "<script>", contentType: "knowledge" }),
    ).rejects.toThrow("Invalid slug");
  });

  it("throws on slug containing dots", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const html = `<pre data-lang="plantuml"><code>@startuml\nFoo-->Bar\n@enduml</code></pre>`;

    await expect(
      processPlantUMLBlocks(html, { slug: "../dotdot", contentType: "knowledge" }),
    ).rejects.toThrow("Invalid slug");
  });

  it("throws on empty slug", async () => {
    const { processPlantUMLBlocks } = await loadModule();
    const html = `<pre data-lang="plantuml"><code>@startuml\nFoo-->Bar\n@enduml</code></pre>`;

    await expect(
      processPlantUMLBlocks(html, { slug: "", contentType: "knowledge" }),
    ).rejects.toThrow("Invalid slug");
  });

  // ---------------------------------------------------------------------------
  // Fix 3 (MEDIUM): console.warn on PlantUMLRenderError fallback
  // ---------------------------------------------------------------------------

  it("calls console.warn with structured message on syntax error fallback (status 400)", async () => {
    const { PlantUMLRenderError } = await import("../../src/lib/plantuml-renderer.js");
    renderPlantUmlMock.mockRejectedValue(
      new PlantUMLRenderError(400, "syntax error"),
    );

    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    const { processPlantUMLBlocks } = await loadModule();
    const html = `<pre data-lang="plantuml"><code>@startuml\nINVALID\n@enduml</code></pre>`;

    await processPlantUMLBlocks(html, { slug: "warn-slug", contentType: "knowledge" });

    expect(warnSpy).toHaveBeenCalledOnce();
    const warnArg = warnSpy.mock.calls[0]?.[0] as string;
    expect(warnArg).toContain("[plantuml]");
    expect(warnArg).toContain("render failed");
    expect(warnArg).toContain("syntax error");
    expect(warnArg).toContain("status=400");
    expect(warnArg).toContain("slug=warn-slug");

    warnSpy.mockRestore();
  });

  // ---------------------------------------------------------------------------
  // Fix 2: img tag width/height
  // ---------------------------------------------------------------------------

  it("img tag includes width/height when SVG renderer returns valid dimensions", async () => {
    renderPlantUmlMock.mockResolvedValue({
      svg: '<svg width="460px" height="377px">diagram</svg>',
      cacheKey: "a1b2c3d4",
      warnings: [],
      width: 460,
      height: 377,
    });

    const { processPlantUMLBlocks } = await loadModule();
    const source = "@startuml\nFoo --> Bar\n@enduml";
    const html = `<pre data-lang="plantuml"><code>${source}</code></pre>`;

    const { html: result } = await processPlantUMLBlocks(html, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result).toContain('width="460"');
    expect(result).toContain('height="377"');
  });

  it("img tag omits width/height when renderer returns 0/0", async () => {
    renderPlantUmlMock.mockResolvedValue({
      svg: "<svg>diagram</svg>",
      cacheKey: "a1b2c3d4",
      warnings: [],
      width: 0,
      height: 0,
    });

    const { processPlantUMLBlocks } = await loadModule();
    const source = "@startuml\nFoo --> Bar\n@enduml";
    const html = `<pre data-lang="plantuml"><code>${source}</code></pre>`;

    const { html: result } = await processPlantUMLBlocks(html, {
      slug: "my-slug",
      contentType: "knowledge",
    });

    expect(result).not.toContain('width="');
    expect(result).not.toContain('height="');
    expect(result).toContain("<img");
  });

  it("calls console.warn with status=network on double network error fallback (status 0)", async () => {
    const { PlantUMLRenderError } = await import("../../src/lib/plantuml-renderer.js");
    renderPlantUmlMock.mockRejectedValue(
      new PlantUMLRenderError(0, "network error after retry"),
    );

    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    const { processPlantUMLBlocks } = await loadModule();
    const html = `<pre data-lang="plantuml"><code>@startuml\nFoo-->Bar\n@enduml</code></pre>`;

    await processPlantUMLBlocks(html, { slug: "net-slug", contentType: "knowledge" });

    expect(warnSpy).toHaveBeenCalledOnce();
    const warnArg = warnSpy.mock.calls[0]?.[0] as string;
    expect(warnArg).toContain("[plantuml]");
    expect(warnArg).toContain("status=network");
    expect(warnArg).toContain("slug=net-slug");

    warnSpy.mockRestore();
  });
});
