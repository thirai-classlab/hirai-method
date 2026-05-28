/**
 * Tests for src/lib/s3.ts — S3 upload helpers.
 *
 * Test observations:
 *   1. cloudFrontUrl strips leading "/" from key
 *   2. cloudFrontUrl uses CLOUDFRONT_DOMAIN env or default
 *   3. isS3Configured is true only when all 3 envs present
 *   4. isS3Configured is false when any env missing
 *   5. uploadToS3 sends PutObjectCommand with Bucket/Key/Body/ContentType
 *   6. uploadToS3 returns { key, url } with CloudFront URL
 *   7. deleteFromS3 sends DeleteObjectCommand with Bucket/Key
 *
 * Mock strategy: vi.mock("@aws-sdk/client-s3") so the singleton S3Client
 * captures commands without hitting AWS.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const sendMock = vi.fn<(cmd: unknown) => Promise<unknown>>();

vi.mock("@aws-sdk/client-s3", () => {
  class FakeS3Client {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(public config: any) {}
    send = sendMock;
  }
  class PutObjectCommand {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(public input: any) {}
    readonly __cmd = "Put";
  }
  class DeleteObjectCommand {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(public input: any) {}
    readonly __cmd = "Delete";
  }
  class HeadObjectCommand {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(public input: any) {}
    readonly __cmd = "Head";
  }
  return { S3Client: FakeS3Client, PutObjectCommand, DeleteObjectCommand, HeadObjectCommand };
});

// Re-import after mocks set up. Use top-level await so the singleton module
// is re-evaluated per test via vi.resetModules().
async function loadModule() {
  vi.resetModules();
  return await import("../../src/lib/s3.js");
}

describe("src/lib/s3.ts", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    sendMock.mockReset();
    sendMock.mockResolvedValue({});
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  describe("cloudFrontUrl()", () => {
    it("strips leading slash from key", async () => {
      process.env.CLOUDFRONT_DOMAIN = "d2f75plg0t6qwk.cloudfront.net";
      const { cloudFrontUrl } = await loadModule();
      expect(cloudFrontUrl("/knowledge/foo/abc-bar.png")).toBe(
        "https://d2f75plg0t6qwk.cloudfront.net/knowledge/foo/abc-bar.png",
      );
    });

    it("leaves key untouched when no leading slash", async () => {
      process.env.CLOUDFRONT_DOMAIN = "d2f75plg0t6qwk.cloudfront.net";
      const { cloudFrontUrl } = await loadModule();
      expect(cloudFrontUrl("knowledge/foo/bar.png")).toBe(
        "https://d2f75plg0t6qwk.cloudfront.net/knowledge/foo/bar.png",
      );
    });

    it("falls back to default domain when env is unset", async () => {
      delete process.env.CLOUDFRONT_DOMAIN;
      const { cloudFrontUrl } = await loadModule();
      expect(cloudFrontUrl("x/y.png")).toBe(
        "https://d2f75plg0t6qwk.cloudfront.net/x/y.png",
      );
    });
  });

  describe("isS3Configured()", () => {
    it("returns true when all 3 envs are set", async () => {
      process.env.AWS_ACCESS_KEY_ID = "AKIA";
      process.env.AWS_SECRET_ACCESS_KEY = "sek";
      process.env.AWS_S3_BUCKET = "classlab-weekly-news-content";
      const { isS3Configured } = await loadModule();
      expect(isS3Configured()).toBe(true);
    });

    it("returns false when any env is missing", async () => {
      delete process.env.AWS_ACCESS_KEY_ID;
      process.env.AWS_SECRET_ACCESS_KEY = "sek";
      process.env.AWS_S3_BUCKET = "bucket";
      const { isS3Configured } = await loadModule();
      expect(isS3Configured()).toBe(false);
    });
  });

  describe("uploadToS3()", () => {
    it("sends PutObjectCommand with Bucket/Key/Body/ContentType", async () => {
      process.env.AWS_S3_BUCKET = "classlab-weekly-news-content";
      process.env.CLOUDFRONT_DOMAIN = "d2f75plg0t6qwk.cloudfront.net";
      const { uploadToS3 } = await loadModule();

      const body = Buffer.from("hello");
      const result = await uploadToS3(
        "knowledge/slug/abc-file.png",
        body,
        "image/png",
      );

      expect(sendMock).toHaveBeenCalledTimes(1);
      const cmd = sendMock.mock.calls[0]![0] as { input: Record<string, unknown>; __cmd: string };
      expect(cmd.__cmd).toBe("Put");
      expect(cmd.input.Bucket).toBe("classlab-weekly-news-content");
      expect(cmd.input.Key).toBe("knowledge/slug/abc-file.png");
      expect(cmd.input.Body).toBe(body);
      expect(cmd.input.ContentType).toBe("image/png");

      expect(result).toEqual({
        key: "knowledge/slug/abc-file.png",
        url: "https://d2f75plg0t6qwk.cloudfront.net/knowledge/slug/abc-file.png",
      });
    });

    it("forwards string Body without ContentType when unspecified", async () => {
      const { uploadToS3 } = await loadModule();
      await uploadToS3("a/b", "raw-text");
      const cmd = sendMock.mock.calls[0]![0] as { input: Record<string, unknown> };
      expect(cmd.input.Body).toBe("raw-text");
      expect(cmd.input.ContentType).toBeUndefined();
    });
  });

  describe("deleteFromS3()", () => {
    it("sends DeleteObjectCommand with Bucket/Key", async () => {
      process.env.AWS_S3_BUCKET = "bucket-x";
      const { deleteFromS3 } = await loadModule();
      await deleteFromS3("a/b/c.png");
      const cmd = sendMock.mock.calls[0]![0] as { input: Record<string, unknown>; __cmd: string };
      expect(cmd.__cmd).toBe("Delete");
      expect(cmd.input.Bucket).toBe("bucket-x");
      expect(cmd.input.Key).toBe("a/b/c.png");
    });
  });

  describe("objectExists()", () => {
    it("returns true when HeadObjectCommand succeeds", async () => {
      process.env.AWS_ACCESS_KEY_ID = "AKIA";
      process.env.AWS_SECRET_ACCESS_KEY = "sek";
      process.env.AWS_S3_BUCKET = "bucket-x";
      sendMock.mockResolvedValueOnce({});
      const { objectExists } = await loadModule();
      const result = await objectExists("plantuml/knowledge/slug/a1b2c3d4.svg");
      expect(result).toBe(true);
      const cmd = sendMock.mock.calls[0]![0] as { input: Record<string, unknown>; __cmd: string };
      expect(cmd.__cmd).toBe("Head");
      expect(cmd.input.Key).toBe("plantuml/knowledge/slug/a1b2c3d4.svg");
    });

    it("returns false when HeadObjectCommand throws NotFound (404)", async () => {
      process.env.AWS_ACCESS_KEY_ID = "AKIA";
      process.env.AWS_SECRET_ACCESS_KEY = "sek";
      process.env.AWS_S3_BUCKET = "bucket-x";
      const notFoundErr = Object.assign(new Error("Not Found"), {
        name: "NotFound",
        $metadata: { httpStatusCode: 404 },
      });
      sendMock.mockRejectedValueOnce(notFoundErr);
      const { objectExists } = await loadModule();
      const result = await objectExists("plantuml/knowledge/slug/missing.svg");
      expect(result).toBe(false);
    });

    it("returns false when isS3Configured() is false (dev mock env)", async () => {
      delete process.env.AWS_ACCESS_KEY_ID;
      delete process.env.AWS_SECRET_ACCESS_KEY;
      delete process.env.AWS_S3_BUCKET;
      const { objectExists } = await loadModule();
      const result = await objectExists("plantuml/knowledge/slug/any.svg");
      expect(result).toBe(false);
      // Should not call S3 at all
      expect(sendMock).not.toHaveBeenCalled();
    });
  });
});
