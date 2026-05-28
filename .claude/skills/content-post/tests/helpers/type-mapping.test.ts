/**
 * tests/helpers/type-mapping.test.ts — Task #56 W1 (11.3d-A)
 *
 * Pure unit tests for the helpers extracted from scripts/post.ts.
 * Verifies the behaviour preserved during extraction is byte-identical
 * to the pre-extraction implementation. Expected values are taken
 * directly from the original switch statements in scripts/post.ts
 * (pre-extraction commit history).
 */
import { describe, it, expect } from "vitest";
import {
  mapContentTypeToImagePrefix,
  contentTypeToTable,
  deriveSummary,
  toEmbeddingEnum,
} from "../../scripts/helpers/type-mapping.js";

describe("scripts/helpers/type-mapping — Task #56 W1 extraction (pure helpers)", () => {
  describe("contentTypeToTable", () => {
    it("maps each known contentType to its table name and falls back to knowledge", () => {
      expect(contentTypeToTable("knowledge")).toBe("knowledge");
      expect(contentTypeToTable("tech_articles")).toBe("tech_articles");
      expect(contentTypeToTable("weekly_issues")).toBe("weekly_issues");
      // default branch (unknown input → "knowledge")
      expect(contentTypeToTable("unknown")).toBe("knowledge");
    });
  });

  describe("mapContentTypeToImagePrefix", () => {
    it("maps post.ts contentType to S3 prefix (singular/canonical form)", () => {
      expect(mapContentTypeToImagePrefix("tech_articles")).toBe("tech_article");
      expect(mapContentTypeToImagePrefix("weekly_issues")).toBe("issue");
      expect(mapContentTypeToImagePrefix("knowledge")).toBe("knowledge");
      // default branch (unknown input → "knowledge")
      expect(mapContentTypeToImagePrefix("anything-else")).toBe("knowledge");
    });
  });

  describe("deriveSummary", () => {
    it("prefers explicit frontmatter.summary when it is a non-empty trimmed string", () => {
      expect(deriveSummary({ summary: "explicit summary" }, "body text"))
        .toBe("explicit summary");
      // trim happens before length check
      expect(deriveSummary({ summary: "   trimmed   " }, "body text"))
        .toBe("trimmed");
    });

    it("falls back to collapsed body when frontmatter.summary is missing/empty", () => {
      expect(deriveSummary({}, "hello   world\n\nlines")).toBe("hello world lines");
      // empty-string summary → fallback to body
      expect(deriveSummary({ summary: "" }, "abc")).toBe("abc");
      // non-string summary → fallback to body
      expect(deriveSummary({ summary: 123 as unknown as string }, "xyz")).toBe("xyz");
    });

    it("returns the documented placeholder when body is empty/whitespace-only", () => {
      expect(deriveSummary({}, "")).toBe("(no summary)");
      expect(deriveSummary({}, "   \n\t  ")).toBe("(no summary)");
    });

    it("truncates the collapsed body to 200 characters max", () => {
      const long = "x".repeat(500);
      const out = deriveSummary({}, long);
      expect(out.length).toBe(200);
      expect(out).toBe("x".repeat(200));
    });
  });

  describe("toEmbeddingEnum", () => {
    it("maps post.ts contentType to content_embeddings.content_type enum", () => {
      expect(toEmbeddingEnum("tech_articles")).toBe("article");
      expect(toEmbeddingEnum("weekly_issues")).toBe("issue");
      expect(toEmbeddingEnum("knowledge")).toBe("knowledge");
      // default branch (unknown input → "knowledge") — verifies the silent fallback documented in post.ts
      expect(toEmbeddingEnum("something-else")).toBe("knowledge");
    });
  });
});
