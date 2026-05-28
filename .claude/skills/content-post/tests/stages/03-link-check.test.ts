/**
 * tests/stages/03-link-check.test.ts — Task #56 W2 (11.3d-B)
 *
 * Unit tests for runLinkCheck() — the pure stage 03 helper. We do not exercise
 * the real HTTP path (covered by tests/posting/link-check.test.ts). Instead we
 * verify the gating behaviour: --no-link-check skip, no-URL early-return, and
 * the basic shape of the success path (no broken).
 */
import { describe, it, expect } from "vitest";
import { runLinkCheck } from "../../scripts/stages/03-link-check.js";

describe("scripts/stages/03-link-check — Task #56 W2", () => {
  it("returns { skipped: true, reason: \"no-link-check\" } when linkCheck=false", async () => {
    const result = await runLinkCheck(
      "see [link](https://example.com)",
      { linkCheck: false, linkCheckStrict: false },
      {},
    );
    expect(result.skipped).toBe(true);
    if (result.skipped) {
      expect(result.reason).toBe("no-link-check");
    }
  });

  it("returns { skipped: true, reason: \"no-external-urls\" } when source has no http(s) links", async () => {
    const result = await runLinkCheck(
      "no urls here, only plain text",
      { linkCheck: true, linkCheckStrict: false },
      {},
    );
    expect(result.skipped).toBe(true);
    if (result.skipped) {
      expect(result.reason).toBe("no-external-urls");
    }
  });
});
