/**
 * CloudFront invalidation helper for the content-post skill.
 *
 * Used by --update mode so a re-uploaded (or removed) image is not served
 * from an edge cache after the content row is rewritten.
 *
 * Environment:
 *   AWS_REGION                  (default: ap-northeast-1)
 *   AWS_ACCESS_KEY_ID           (required for real calls)
 *   AWS_SECRET_ACCESS_KEY       (required for real calls)
 *   CLOUDFRONT_DISTRIBUTION_ID  (default: E19HM38I4166EC)
 */
import {
  CloudFrontClient,
  CreateInvalidationCommand,
} from "@aws-sdk/client-cloudfront";

const DEFAULT_REGION = "ap-northeast-1";
const DEFAULT_DISTRIBUTION_ID = "E19HM38I4166EC";

let cfClient: CloudFrontClient | null = null;

function getRegion(): string {
  return process.env.AWS_REGION ?? DEFAULT_REGION;
}

function getDistributionId(): string {
  return process.env.CLOUDFRONT_DISTRIBUTION_ID ?? DEFAULT_DISTRIBUTION_ID;
}

function getClient(): CloudFrontClient {
  if (!cfClient) {
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
    cfClient = new CloudFrontClient({
      region: getRegion(),
      credentials:
        accessKeyId && secretAccessKey
          ? { accessKeyId, secretAccessKey }
          : undefined,
    });
  }
  return cfClient;
}

export async function invalidateCloudFront(
  paths: string[],
): Promise<{ id: string }> {
  if (paths.length === 0) return { id: "noop" };
  const client = getClient();
  const items = paths.map((p) => (p.startsWith("/") ? p : `/${p}`));
  const result = await client.send(
    new CreateInvalidationCommand({
      DistributionId: getDistributionId(),
      InvalidationBatch: {
        CallerReference: `content-post-${Date.now()}`,
        Paths: {
          Quantity: items.length,
          Items: items,
        },
      },
    }),
  );
  return { id: result.Invalidation?.Id ?? "unknown" };
}
