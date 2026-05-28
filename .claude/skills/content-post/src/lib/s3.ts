/**
 * AWS S3 upload helpers for the content-post skill.
 *
 * Mirrors the interface of classlab-weekly-news/src/lib/s3.ts so markdown
 * images uploaded here render through the same CloudFront distribution the
 * site reads from.
 *
 * Environment:
 *   AWS_REGION                (default: ap-northeast-1)
 *   AWS_S3_BUCKET             (default: classlab-weekly-news-content)
 *   AWS_ACCESS_KEY_ID         (required for real uploads)
 *   AWS_SECRET_ACCESS_KEY     (required for real uploads)
 *   CLOUDFRONT_DOMAIN         (default: d2f75plg0t6qwk.cloudfront.net)
 */
import {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
  HeadObjectCommand,
} from "@aws-sdk/client-s3";

const DEFAULT_REGION = "ap-northeast-1";
const DEFAULT_BUCKET = "classlab-weekly-news-content";
const DEFAULT_CLOUDFRONT_DOMAIN = "d2f75plg0t6qwk.cloudfront.net";

let s3Client: S3Client | null = null;

function getRegion(): string {
  return process.env.AWS_REGION ?? DEFAULT_REGION;
}

function getBucket(): string {
  return process.env.AWS_S3_BUCKET ?? DEFAULT_BUCKET;
}

function getCloudFrontDomain(): string {
  return process.env.CLOUDFRONT_DOMAIN ?? DEFAULT_CLOUDFRONT_DOMAIN;
}

function getS3Client(): S3Client {
  if (!s3Client) {
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;
    s3Client = new S3Client({
      region: getRegion(),
      credentials:
        accessKeyId && secretAccessKey
          ? { accessKeyId, secretAccessKey }
          : undefined, // fall back to default provider chain
    });
  }
  return s3Client;
}

export async function uploadToS3(
  key: string,
  body: Buffer | Uint8Array | string,
  contentType?: string,
): Promise<{ key: string; url: string }> {
  const client = getS3Client();
  await client.send(
    new PutObjectCommand({
      Bucket: getBucket(),
      Key: key,
      Body: body,
      ContentType: contentType,
    }),
  );
  return { key, url: cloudFrontUrl(key) };
}

export async function deleteFromS3(key: string): Promise<void> {
  const client = getS3Client();
  await client.send(
    new DeleteObjectCommand({ Bucket: getBucket(), Key: key }),
  );
}

export function cloudFrontUrl(key: string): string {
  const normalized = key.startsWith("/") ? key.slice(1) : key;
  return `https://${getCloudFrontDomain()}/${normalized}`;
}

export async function objectExists(key: string): Promise<boolean> {
  if (!isS3Configured()) {
    return false;
  }
  const client = getS3Client();
  try {
    await client.send(
      new HeadObjectCommand({ Bucket: getBucket(), Key: key }),
    );
    return true;
  } catch (err) {
    // NotFound / 404 → object does not exist
    const e = err as { name?: string; $metadata?: { httpStatusCode?: number } };
    if (
      e.name === "NotFound" ||
      e.name === "NoSuchKey" ||
      e.$metadata?.httpStatusCode === 404
    ) {
      return false;
    }
    throw err;
  }
}

export function isS3Configured(): boolean {
  return Boolean(
    process.env.AWS_ACCESS_KEY_ID &&
      process.env.AWS_SECRET_ACCESS_KEY &&
      process.env.AWS_S3_BUCKET,
  );
}
