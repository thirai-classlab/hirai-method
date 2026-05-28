/**
 * Tests for src/lib/image-processor.ts
 *
 * Test observations:
 *   1. local image → read, upload, replace with CloudFront URL
 *   2. https:// URL → skipped (no upload, markdown unchanged)
 *   3. data: URL → skipped (no upload, markdown unchanged)
 *   4. missing local file → skipped (no throw, no replacement)
 *   5. S3 key format: <contentType>/<slug>/<sha256[0..8]>-<filename>
 *   6. multiple local images processed sequentially with distinct keys
 *   7. content-type is picked from file extension (png/jpg/svg/webp)
 *   8. extractCdnPathsForInvalidation returns "/..." paths for given CDN domain
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

const uploadMock = vi.fn<
  (
    key: string,
    body: Buffer | Uint8Array | string,
    contentType?: string,
  ) => Promise<{ key: string; url: string }>
>();

vi.mock("../../src/lib/s3.js", () => {
  return {
    uploadToS3: uploadMock,
    cloudFrontUrl: (key: string) => {
      const n = key.startsWith("/") ? key.slice(1) : key;
      return `https://d2f75plg0t6qwk.cloudfront.net/${n}`;
    },
  };
});

async function loadModule() {
  vi.resetModules();
  return await import("../../src/lib/image-processor.js");
}

async function makeTempDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "content-post-img-"));
}

describe("processMarkdownImages()", () => {
  beforeEach(() => {
    uploadMock.mockReset();
    uploadMock.mockImplementation(async (key) => ({
      key,
      url: `https://d2f75plg0t6qwk.cloudfront.net/${key}`,
    }));
  });

  afterEach(() => {
    // Nothing cleanup-critical; tmp dirs expire.
  });

  it("uploads a local image and replaces the path with a CloudFront URL", async () => {
    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    const imgPath = path.join(dir, "hero.png");
    await fs.writeFile(imgPath, Buffer.from([137, 80, 78, 71, 1, 2, 3, 4]));

    const markdown = `# Title\n\n![Hero](./hero.png)\n\nbody\n`;
    const { markdown: out, replacements } = await processMarkdownImages(
      markdown,
      {
        slug: "my-post",
        contentType: "knowledge",
        baseDir: dir,
      },
    );

    expect(uploadMock).toHaveBeenCalledTimes(1);
    const [key, body, ct] = uploadMock.mock.calls[0]!;
    expect(key).toMatch(/^knowledge\/my-post\/[0-9a-f]{8}-hero\.png$/);
    expect(Buffer.isBuffer(body)).toBe(true);
    expect(ct).toBe("image/png");

    expect(replacements).toHaveLength(1);
    expect(replacements[0]!.originalPath).toBe("./hero.png");
    expect(replacements[0]!.s3Key).toBe(key);
    expect(replacements[0]!.cdnUrl).toBe(
      `https://d2f75plg0t6qwk.cloudfront.net/${key}`,
    );

    expect(out).toContain(
      `![Hero](https://d2f75plg0t6qwk.cloudfront.net/${key})`,
    );
    expect(out).not.toContain("./hero.png");
  });

  it("skips https:// URLs", async () => {
    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    const md = "![x](https://example.com/x.png)\n";
    const { markdown, replacements } = await processMarkdownImages(md, {
      slug: "s",
      contentType: "knowledge",
      baseDir: dir,
    });
    expect(uploadMock).not.toHaveBeenCalled();
    expect(replacements).toHaveLength(0);
    expect(markdown).toBe(md);
  });

  it("skips data: URLs", async () => {
    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    const md = "![x](data:image/png;base64,AAAA)\n";
    const { markdown, replacements } = await processMarkdownImages(md, {
      slug: "s",
      contentType: "knowledge",
      baseDir: dir,
    });
    expect(uploadMock).not.toHaveBeenCalled();
    expect(replacements).toHaveLength(0);
    expect(markdown).toBe(md);
  });

  it("skips missing local files without throwing", async () => {
    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    const md = "![x](./does-not-exist.png)\n";
    const { markdown, replacements } = await processMarkdownImages(md, {
      slug: "s",
      contentType: "knowledge",
      baseDir: dir,
    });
    expect(uploadMock).not.toHaveBeenCalled();
    expect(replacements).toHaveLength(0);
    expect(markdown).toBe(md);
  });

  it("uses S3 key format <contentType>/<slug>/<sha256[0..8]>-<filename>", async () => {
    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    const imgPath = path.join(dir, "pic.jpg");
    const content = Buffer.from("fixed-bytes");
    await fs.writeFile(imgPath, content);

    await processMarkdownImages("![](./pic.jpg)", {
      slug: "tech-slug",
      contentType: "tech_article",
      baseDir: dir,
    });

    const crypto = await import("node:crypto");
    const expectedHash = crypto
      .createHash("sha256")
      .update(content)
      .digest("hex")
      .slice(0, 8);

    const [key, , ct] = uploadMock.mock.calls[0]!;
    expect(key).toBe(`tech_article/tech-slug/${expectedHash}-pic.jpg`);
    expect(ct).toBe("image/jpeg");
  });

  it("processes multiple local images sequentially and replaces all", async () => {
    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    await fs.writeFile(path.join(dir, "a.png"), Buffer.from("aaa"));
    await fs.writeFile(path.join(dir, "b.svg"), Buffer.from("<svg/>"));
    await fs.writeFile(path.join(dir, "c.webp"), Buffer.from("cccc"));

    const md = [
      "![A](./a.png)",
      "![B](./b.svg)",
      "external: ![ext](https://x.y/z.png)",
      "![C](./c.webp)",
    ].join("\n");

    const { markdown, replacements } = await processMarkdownImages(md, {
      slug: "issue-slug",
      contentType: "issue",
      baseDir: dir,
    });

    expect(uploadMock).toHaveBeenCalledTimes(3);
    expect(replacements).toHaveLength(3);
    expect(replacements.map((r) => r.originalPath)).toEqual([
      "./a.png",
      "./b.svg",
      "./c.webp",
    ]);
    const cts = uploadMock.mock.calls.map((c) => c[2]);
    expect(cts).toEqual(["image/png", "image/svg+xml", "image/webp"]);

    // All 3 local paths replaced; https:// stays.
    expect(markdown).not.toContain("./a.png");
    expect(markdown).not.toContain("./b.svg");
    expect(markdown).not.toContain("./c.webp");
    expect(markdown).toContain("https://x.y/z.png");
  });

  // ---------------------------------------------------------------------------
  // Fix 3: img tag includes width/height from image dimensions
  // ---------------------------------------------------------------------------

  it("img tag includes width/height from image dimensions when image-size succeeds", async () => {
    // Minimal valid 16x16 PNG header bytes
    const pngHeader = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG signature
      0x00, 0x00, 0x00, 0x0d,                           // IHDR chunk length
      0x49, 0x48, 0x44, 0x52,                           // IHDR type
      0x00, 0x00, 0x00, 0x10,                           // width = 16 (big-endian)
      0x00, 0x00, 0x00, 0x10,                           // height = 16 (big-endian)
      0x08, 0x02, 0x00, 0x00, 0x00,                     // bit depth, color type, ...
      0x90, 0x91, 0x68, 0x36,                           // CRC
    ]);

    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    const imgPath = path.join(dir, "img.png");
    await fs.writeFile(imgPath, pngHeader);

    const markdown = `![hero](./img.png)`;
    const { markdown: out } = await processMarkdownImages(markdown, {
      slug: "test-slug",
      contentType: "knowledge",
      baseDir: dir,
    });

    expect(out).toContain('width="16"');
    expect(out).toContain('height="16"');
    expect(out).toContain("<img");
    expect(out).not.toContain("![hero]");
  });

  it("omits width/height (keeps markdown syntax) when image-size throws (truncated file)", async () => {
    const { processMarkdownImages } = await loadModule();
    const dir = await makeTempDir();
    const imgPath = path.join(dir, "broken.png");
    // Write a tiny buffer that won't parse as a valid image
    await fs.writeFile(imgPath, Buffer.from([0x00, 0x01]));

    const markdown = `![x](./broken.png)`;
    const { markdown: out } = await processMarkdownImages(markdown, {
      slug: "test-slug",
      contentType: "knowledge",
      baseDir: dir,
    });

    // Should still be replaced with CDN URL (upload happens regardless)
    expect(uploadMock).toHaveBeenCalledTimes(1);
    // No width/height when image-size fails
    expect(out).not.toContain('width="');
    expect(out).not.toContain('height="');
  });
}); // end describe("processMarkdownImages()")

describe("extractCdnPathsForInvalidation()", () => {
  it("extracts '/<key>' paths from html body for the given CDN domain", async () => {
    const { extractCdnPathsForInvalidation } = await loadModule();
    const domain = "d2f75plg0t6qwk.cloudfront.net";
    const html = [
      `<img src="https://${domain}/knowledge/a/aa-x.png" />`,
      `<p>link: <a href='https://${domain}/tech_article/b/bb-y.jpg'>y</a></p>`,
      `<img src="https://other.cdn/z.png" />`,
    ].join("\n");

    const paths = extractCdnPathsForInvalidation(html, domain);
    expect(paths).toEqual([
      "/knowledge/a/aa-x.png",
      "/tech_article/b/bb-y.jpg",
    ]);
  });

  it("returns empty array when no matches", async () => {
    const { extractCdnPathsForInvalidation } = await loadModule();
    expect(
      extractCdnPathsForInvalidation("<p>hi</p>", "d2f75plg0t6qwk.cloudfront.net"),
    ).toEqual([]);
  });
});
