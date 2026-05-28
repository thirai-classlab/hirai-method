/**
 * Tests for src/lib/cloudfront.ts — CloudFront invalidation helper.
 *
 * Test observations:
 *   1. noop (empty paths) returns { id: "noop" } without calling send()
 *   2. paths are normalized with leading slash
 *   3. CreateInvalidationCommand carries DistributionId + Quantity + Items
 *   4. returns Invalidation.Id from AWS response
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const sendMock = vi.fn<(cmd: unknown) => Promise<unknown>>();

vi.mock("@aws-sdk/client-cloudfront", () => {
  class FakeCloudFrontClient {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(public config: any) {}
    send = sendMock;
  }
  class CreateInvalidationCommand {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(public input: any) {}
    readonly __cmd = "CreateInvalidation";
  }
  return {
    CloudFrontClient: FakeCloudFrontClient,
    CreateInvalidationCommand,
  };
});

async function loadModule() {
  vi.resetModules();
  return await import("../../src/lib/cloudfront.js");
}

describe("src/lib/cloudfront.ts", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    sendMock.mockReset();
    sendMock.mockResolvedValue({ Invalidation: { Id: "I123ABC" } });
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("returns noop without calling send() when paths is empty", async () => {
    const { invalidateCloudFront } = await loadModule();
    const result = await invalidateCloudFront([]);
    expect(result).toEqual({ id: "noop" });
    expect(sendMock).not.toHaveBeenCalled();
  });

  it("normalizes paths with leading slash and sends CreateInvalidation", async () => {
    process.env.CLOUDFRONT_DISTRIBUTION_ID = "E19HM38I4166EC";
    const { invalidateCloudFront } = await loadModule();
    const result = await invalidateCloudFront([
      "knowledge/foo/a.png",
      "/knowledge/foo/b.png",
    ]);

    expect(sendMock).toHaveBeenCalledTimes(1);
    const cmd = sendMock.mock.calls[0]![0] as {
      input: Record<string, unknown>;
      __cmd: string;
    };
    expect(cmd.__cmd).toBe("CreateInvalidation");
    expect(cmd.input.DistributionId).toBe("E19HM38I4166EC");
    const batch = cmd.input.InvalidationBatch as {
      CallerReference: string;
      Paths: { Quantity: number; Items: string[] };
    };
    expect(batch.Paths.Quantity).toBe(2);
    expect(batch.Paths.Items).toEqual([
      "/knowledge/foo/a.png",
      "/knowledge/foo/b.png",
    ]);
    expect(batch.CallerReference).toMatch(/^content-post-\d+$/);

    expect(result).toEqual({ id: "I123ABC" });
  });

  it("falls back to 'unknown' when AWS response omits Invalidation.Id", async () => {
    sendMock.mockResolvedValueOnce({});
    const { invalidateCloudFront } = await loadModule();
    const result = await invalidateCloudFront(["/x.png"]);
    expect(result).toEqual({ id: "unknown" });
  });
});
