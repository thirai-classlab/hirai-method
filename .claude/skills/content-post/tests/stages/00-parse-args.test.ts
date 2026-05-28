/**
 * tests/stages/00-parse-args.test.ts — Task #56 W2 (11.3d-B)
 *
 * Unit tests for the pure parseArgs / validateEnv functions extracted from
 * scripts/post.ts during the 14-stage pipeline refactor. Existing post.test.ts
 * suite covers the integration path; these tests pin the boundary behaviour.
 */
import { describe, it, expect } from "vitest";
import {
  parseArgs,
  validateEnv,
  REQUIRED_ENV,
} from "../../scripts/stages/00-parse-args.js";

describe("scripts/stages/00-parse-args — Task #56 W2", () => {
  describe("parseArgs", () => {
    it("returns boolean defaults and undefined for unset string options", () => {
      const opts = parseArgs(["node", "post.ts"]);
      expect(opts.file).toBeUndefined();
      expect(opts.batch).toBeUndefined();
      expect(opts.dryRun).toBe(false);
      expect(opts.autoApprove).toBe(false);
      expect(opts.update).toBe(false);
      expect(opts.force).toBe(false);
      expect(opts.verbose).toBe(false);
      // hearing / link-check default to ON (commander --no-* pattern)
      expect(opts.thumbnailHearing).toBe(true);
      expect(opts.linkCheck).toBe(true);
      expect(opts.linkCheckStrict).toBe(false);
    });

    it("parses --file / --slug / --update flags", () => {
      const opts = parseArgs([
        "node",
        "post.ts",
        "--file",
        "/tmp/a.md",
        "--update",
        "--slug",
        "my-slug",
        "--no-link-check",
        "--no-thumbnail-hearing",
        "--dry-run",
      ]);
      expect(opts.file).toBe("/tmp/a.md");
      expect(opts.update).toBe(true);
      expect(opts.slug).toBe("my-slug");
      expect(opts.linkCheck).toBe(false);
      expect(opts.thumbnailHearing).toBe(false);
      expect(opts.dryRun).toBe(true);
    });

    // --- #58 Step 1: --kind operation|domain_knowledge ---
    it("defaults knowledgeKind to 'concept' when --kind is omitted (backward compat)", () => {
      const opts = parseArgs(["node", "post.ts"]);
      expect(opts.knowledgeKind).toBe("concept");
    });

    it("parses --kind operation", () => {
      const opts = parseArgs(["node", "post.ts", "--kind", "operation"]);
      expect(opts.knowledgeKind).toBe("operation");
    });

    it("parses --kind domain_knowledge", () => {
      const opts = parseArgs(["node", "post.ts", "--kind", "domain_knowledge"]);
      expect(opts.knowledgeKind).toBe("domain_knowledge");
    });

    it("parses --kind concept (explicit)", () => {
      const opts = parseArgs(["node", "post.ts", "--kind", "concept"]);
      expect(opts.knowledgeKind).toBe("concept");
    });

    it("throws (fail-fast) on an invalid --kind value", () => {
      expect(() => parseArgs(["node", "post.ts", "--kind", "foo"])).toThrow();
    });
  });

  describe("validateEnv", () => {
    it("returns ok when every REQUIRED_ENV key is present and non-empty", () => {
      const env: Record<string, string> = {};
      for (const k of REQUIRED_ENV) env[k] = `value-for-${k}`;
      expect(validateEnv(env)).toEqual({ ok: true });
    });

    it("returns the missing keys when any required env is missing or empty", () => {
      const env: Record<string, string | undefined> = {
        SUPABASE_URL: "https://example.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY: "key",
        AI_GATEWAY_API_KEY: "   ", // whitespace-only counts as missing
        SITE_URL: "",
        // REVALIDATE_SECRET intentionally missing
      };
      const result = validateEnv(env);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.missing).toEqual([
          "AI_GATEWAY_API_KEY",
          "SITE_URL",
          "REVALIDATE_SECRET",
        ]);
      }
    });
  });
});
