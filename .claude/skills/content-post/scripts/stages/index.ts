/**
 * scripts/stages/index.ts — Task #56 W3 (11.3d-C)
 *
 * Barrel file for the 15-stage pipeline. Re-exports pure functions and stage
 * descriptors so runner.ts can wire them into PipelineRunner without naming
 * every file individually.
 */
export {
  parseArgs,
  validateEnv,
  REQUIRED_ENV,
  stage00ParseArgs,
} from "./00-parse-args.js";
export {
  validateFrontmatter,
  stage01Validate,
  type ValidateResult,
} from "./01-validate-frontmatter.js";
export {
  parseAndRender,
  stage02ParseMarkdown,
  type ParseRenderResult,
} from "./02-parse-markdown.js";
export {
  runLinkCheck,
  stage03LinkCheck,
  CDN_DOMAIN,
  type LinkCheckResult,
} from "./03-link-check.js";
export {
  resolveSlug,
  kindForSnapshot,
  stage04SlugResolve,
  type ResolveSlugArgs,
} from "./04-slug-resolve.js";
export { stage04bMermaidImage } from "./04b-mermaid-image.js";
export {
  processImagesIfNeeded,
  stage05ImageUpload,
  type ImageUploadArgs,
  type ImageUploadOutcome,
} from "./05-image-upload.js";
export {
  runThumbnailHearingIfNeeded,
  uploadThumbnailIfNeeded,
  stage06Thumbnail,
  type HearingArgs,
  type UploadArgs,
} from "./06-thumbnail.js";
export {
  renderAsync,
  stage07RenderAsync,
  type RenderAsyncArgs,
  type RenderAsyncResult,
} from "./07-render-async.js";
export {
  enrichLinkCardsIfNeeded,
  stage08LinkCards,
} from "./08-link-cards.js";
export {
  generateEmbeddingForPipeline,
  findRelatedKnowledge,
  stage09Embedding,
} from "./09-embedding.js";
export {
  checkDuplicateForPipeline,
  stage10Duplicate,
  type DupResult,
} from "./10-duplicate.js";
export {
  resolveCategoryAndTags,
  stage11CategoryTag,
  type ConfirmedMeta,
  type CategoryTagArgs,
} from "./11-category-tag.js";
export {
  ingestNew,
  stage12Ingest,
  type IngestArgs,
} from "./12-ingest.js";
export {
  updateExisting,
  stage13Update,
  type UpdateArgs,
} from "./13-update.js";
export {
  publishIfRequested,
  stage14Publish,
  type PublishArgs,
} from "./14-publish.js";
