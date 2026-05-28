/**
 * Tests for src/lib/plantuml-renderer.ts
 *
 * Test coverage:
 *   injectTheme:
 *     1.  @startuml present → inserts !theme blueprint after @startuml
 *     2.  User-specified !theme → skipped: true, source unchanged
 *     3.  Multiple @startuml blocks → inject only after first
 *     4.  No @startuml (malformed) → skipped: true
 *     5.  !theme with leading whitespace → treated as user-specified (skipped)
 *
 *   computeCacheKey:
 *     6.  Same input → same 8-char hex key
 *     7.  Source diff by 1 char → different key
 *     8.  themeDirective diff → different key
 *     9.  Return value matches /^[0-9a-f]{8}$/
 *
 *   renderPlantUml:
 *    10. Happy path: fetch 200 with <svg>...</svg> → { svg, cacheKey, warnings: [] }
 *    11. Happy path (skipped theme): !theme explicit → warnings includes skip message
 *    12. Source exceeds MAX_PLANTUML_CHARS → throws PlantUMLRenderError(0, ...)
 *    13. fetch HTTP 400 → 1 retry → still 400 → throws PlantUMLRenderError(400, ...)
 *    14. fetch HTTP 500 → 1 retry → 200 → succeeds
 *    15. Network error → 1 retry → success
 *    16. SVG contains <script> → throws PlantUMLRenderError(0, "SVG contains <script>")
 *    17. SVG contains <Script (capital) → throws
 *    18. fetch URL is https://www.plantuml.com/plantuml/svg/<encoded>
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SIMPLE_SOURCE = "@startuml\nFoo --> Bar\n@enduml";
const SIMPLE_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\"><text>diagram</text></svg>";

function makeOkResponse(body: string): Response {
  return {
    ok: true,
    status: 200,
    text: async () => body,
  } as unknown as Response;
}

function makeErrorResponse(status: number): Response {
  return {
    ok: false,
    status,
    text: async () => "error",
  } as unknown as Response;
}

// ---------------------------------------------------------------------------
// Module import (dynamic so we can stub globals before import)
// ---------------------------------------------------------------------------

async function loadModule() {
  vi.resetModules();
  return await import("../../src/lib/plantuml-renderer.js");
}

// ---------------------------------------------------------------------------
// injectTheme
// ---------------------------------------------------------------------------

describe("injectTheme()", () => {
  it("inserts !theme blueprint after @startuml when no existing theme", async () => {
    const { injectTheme, THEME_DIRECTIVE } = await loadModule();
    const source = "@startuml\nFoo --> Bar\n@enduml";
    const result = injectTheme(source);

    expect(result.skipped).toBe(false);
    expect(result.injected).toBe(
      `@startuml\n${THEME_DIRECTIVE}\nFoo --> Bar\n@enduml`,
    );
  });

  it("returns skipped:true and leaves source unchanged when user has explicit !theme", async () => {
    const { injectTheme } = await loadModule();
    const source = "@startuml\n!theme cerulean\nFoo --> Bar\n@enduml";
    const result = injectTheme(source);

    expect(result.skipped).toBe(true);
    expect(result.injected).toBe(source);
  });

  it("injects only after the FIRST @startuml when multiple blocks are present", async () => {
    const { injectTheme, THEME_DIRECTIVE } = await loadModule();
    const source =
      "@startuml\nA --> B\n@enduml\n\n@startuml\nC --> D\n@enduml";
    const result = injectTheme(source);

    expect(result.skipped).toBe(false);
    // Only the first block should have the theme injected
    const lines = result.injected.split("\n");
    expect(lines[0]).toBe("@startuml");
    expect(lines[1]).toBe(THEME_DIRECTIVE);
    // Second @startuml should NOT have the theme prepended
    const secondStart = result.injected.indexOf("\n@startuml\n");
    const afterSecondStart = result.injected.slice(secondStart + 1);
    expect(afterSecondStart.startsWith(`@startuml\n${THEME_DIRECTIVE}`)).toBe(false);
  });

  it("returns skipped:true for malformed source without @startuml", async () => {
    const { injectTheme } = await loadModule();
    const source = "Foo --> Bar\n@enduml";
    const result = injectTheme(source);

    expect(result.skipped).toBe(true);
    expect(result.injected).toBe(source);
  });

  it("treats !theme with leading whitespace as user-specified (skipped)", async () => {
    const { injectTheme } = await loadModule();
    const source = "@startuml\n  !theme amiga\nFoo --> Bar\n@enduml";
    const result = injectTheme(source);

    expect(result.skipped).toBe(true);
    expect(result.injected).toBe(source);
  });
});

// ---------------------------------------------------------------------------
// computeCacheKey
// ---------------------------------------------------------------------------

describe("computeCacheKey()", () => {
  it("returns the same 8-char key for the same input", async () => {
    const { computeCacheKey } = await loadModule();
    const key1 = computeCacheKey("@startuml\nFoo\n@enduml", "!theme blueprint");
    const key2 = computeCacheKey("@startuml\nFoo\n@enduml", "!theme blueprint");
    expect(key1).toBe(key2);
  });

  it("returns different key when source differs by one character", async () => {
    const { computeCacheKey } = await loadModule();
    const key1 = computeCacheKey("@startuml\nFoo\n@enduml", "!theme blueprint");
    const key2 = computeCacheKey("@startuml\nFoo!\n@enduml", "!theme blueprint");
    expect(key1).not.toBe(key2);
  });

  it("returns different key when themeDirective differs", async () => {
    const { computeCacheKey } = await loadModule();
    const key1 = computeCacheKey("@startuml\nFoo\n@enduml", "!theme blueprint");
    const key2 = computeCacheKey("@startuml\nFoo\n@enduml", "!theme cerulean");
    expect(key1).not.toBe(key2);
  });

  it("return value matches /^[0-9a-f]{8}$/", async () => {
    const { computeCacheKey } = await loadModule();
    const key = computeCacheKey("@startuml\nFoo\n@enduml", "!theme blueprint");
    expect(key).toMatch(/^[0-9a-f]{8}$/);
  });
});

// ---------------------------------------------------------------------------
// renderPlantUml
// ---------------------------------------------------------------------------

describe("renderPlantUml()", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  it("returns { svg, cacheKey, warnings:[] } on happy path fetch 200", async () => {
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(SIMPLE_SVG));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const resultPromise = renderPlantUml(SIMPLE_SOURCE);
    await vi.runAllTimersAsync();
    const result = await resultPromise;

    expect(result.svg).toBe(SIMPLE_SVG);
    expect(result.warnings).toEqual([]);
    expect(result.cacheKey).toMatch(/^[0-9a-f]{8}$/);
  });

  it("includes skip warning in warnings when source has explicit !theme", async () => {
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(SIMPLE_SVG));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const source = "@startuml\n!theme cerulean\nFoo --> Bar\n@enduml";
    const resultPromise = renderPlantUml(source);
    await vi.runAllTimersAsync();
    const result = await resultPromise;

    expect(result.warnings).toContain(
      "source has explicit !theme, skipping injection",
    );
  });

  it("throws PlantUMLRenderError(0, ...) when source exceeds MAX_PLANTUML_CHARS", async () => {
    const { renderPlantUml, PlantUMLRenderError, MAX_PLANTUML_CHARS } =
      await loadModule();
    const hugeSource = "x".repeat(MAX_PLANTUML_CHARS + 1);

    const err = await renderPlantUml(hugeSource).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(PlantUMLRenderError);
    expect(err).toMatchObject({ httpStatus: 0 });
  });

  it("retries once on HTTP 400 and throws after second failure", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(makeErrorResponse(400));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml, PlantUMLRenderError } = await loadModule();

    let err: unknown;
    const resultPromise = renderPlantUml(SIMPLE_SOURCE).catch((e: unknown) => {
      err = e;
    });
    await vi.runAllTimersAsync();
    await resultPromise;

    expect(err).toBeInstanceOf(PlantUMLRenderError);
    expect(err).toMatchObject({ httpStatus: 400 });
    // fetch called twice (1 original + 1 retry)
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("retries once on HTTP 500 and succeeds on second attempt", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(makeErrorResponse(500))
      .mockResolvedValueOnce(makeOkResponse(SIMPLE_SVG));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const resultPromise = renderPlantUml(SIMPLE_SOURCE);
    await vi.runAllTimersAsync();
    const result = await resultPromise;

    expect(result.svg).toBe(SIMPLE_SVG);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("retries once on network error and succeeds on second attempt", async () => {
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new Error("network failure"))
      .mockResolvedValueOnce(makeOkResponse(SIMPLE_SVG));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const resultPromise = renderPlantUml(SIMPLE_SOURCE);
    await vi.runAllTimersAsync();
    const result = await resultPromise;

    expect(result.svg).toBe(SIMPLE_SVG);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("throws PlantUMLRenderError when SVG contains <script>", async () => {
    const svgWithScript =
      '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>';
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(svgWithScript));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml, PlantUMLRenderError } = await loadModule();

    let err: unknown;
    const resultPromise = renderPlantUml(SIMPLE_SOURCE).catch((e: unknown) => {
      err = e;
    });
    await vi.runAllTimersAsync();
    await resultPromise;

    expect(err).toBeInstanceOf(PlantUMLRenderError);
    expect(err).toMatchObject({ httpStatus: 0 });
  });

  it("throws PlantUMLRenderError when SVG contains <Script (capital S)", async () => {
    const svgWithScript =
      '<svg xmlns="http://www.w3.org/2000/svg"><Script src="evil.js"></Script></svg>';
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(svgWithScript));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml, PlantUMLRenderError } = await loadModule();

    let err: unknown;
    const resultPromise = renderPlantUml(SIMPLE_SOURCE).catch((e: unknown) => {
      err = e;
    });
    await vi.runAllTimersAsync();
    await resultPromise;

    expect(err).toBeInstanceOf(PlantUMLRenderError);
  });

  it("calls fetch with correct plantuml.com SVG URL", async () => {
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(SIMPLE_SVG));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const resultPromise = renderPlantUml(SIMPLE_SOURCE);
    await vi.runAllTimersAsync();
    await resultPromise;

    const calledUrl = fetchMock.mock.calls[0]?.[0] as string;
    expect(calledUrl).toMatch(
      /^https:\/\/www\.plantuml\.com\/plantuml\/svg\/.+/,
    );
  });

  it("throws PlantUMLRenderError when both initial and retry fetches fail with network error", async () => {
    // Both fetch calls reject with a network error (no response at all)
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce(new Error("network failure 1"))
      .mockRejectedValueOnce(new Error("network failure 2"));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml, PlantUMLRenderError } = await loadModule();

    let err: unknown;
    const resultPromise = renderPlantUml(SIMPLE_SOURCE).catch((e: unknown) => {
      err = e;
    });
    await vi.runAllTimersAsync();
    await resultPromise;

    // Must be wrapped in PlantUMLRenderError, NOT a plain Error
    expect(err).toBeInstanceOf(PlantUMLRenderError);
    expect(err).toMatchObject({ httpStatus: 0 });
    expect((err as Error).message).toContain("network error after retry");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});

// ---------------------------------------------------------------------------
// Fix 2: width/height extraction from SVG
// ---------------------------------------------------------------------------

describe("renderPlantUml() — width/height extraction", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  it("extracts width/height from SVG root (460px × 377px with px suffix)", async () => {
    const svgWithDims = '<svg xmlns="http://www.w3.org/2000/svg" width="460px" height="377px"><text>diagram</text></svg>';
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(svgWithDims));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const resultPromise = renderPlantUml(SIMPLE_SOURCE);
    await vi.runAllTimersAsync();
    const result = await resultPromise;

    expect(result.width).toBe(460);
    expect(result.height).toBe(377);
  });

  it("returns width=0/height=0 when SVG has no width/height attrs", async () => {
    const svgNoDims = '<svg xmlns="http://www.w3.org/2000/svg"><text>diagram</text></svg>';
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(svgNoDims));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const resultPromise = renderPlantUml(SIMPLE_SOURCE);
    await vi.runAllTimersAsync();
    const result = await resultPromise;

    expect(result.width).toBe(0);
    expect(result.height).toBe(0);
  });

  it("handles unquoted width/height attrs", async () => {
    const svgUnquoted = '<svg xmlns="http://www.w3.org/2000/svg" width=320 height=240><text>diagram</text></svg>';
    const fetchMock = vi.fn().mockResolvedValue(makeOkResponse(svgUnquoted));
    vi.stubGlobal("fetch", fetchMock);

    const { renderPlantUml } = await loadModule();
    const resultPromise = renderPlantUml(SIMPLE_SOURCE);
    await vi.runAllTimersAsync();
    const result = await resultPromise;

    expect(result.width).toBe(320);
    expect(result.height).toBe(240);
  });
});
