#!/usr/bin/env bun
/**
 * AI Peer Review - Multi-model code/plan review via LiteLLM proxy
 * Reviews content using the 3 most appropriate AI models based on review type
 *
 * Configuration:
 *   Environment variables: LITELLM_BASE_URL, LITELLM_API_KEY
 *   Or ~/.claude/secrets.json: { "litellm": { "base_url": "...", "api_key": "..." } }
 */

import { getLLMClientConfig, ALL_MODELS, REVIEW_TYPE_MODELS, estimateTokens, LIMITS } from "./config";
import { LLMClient } from "./apiClient";
import { findReviewTargets, buildReviewJob } from "./fileSystem";
import {
  parseArgs,
  printHelp,
  printHeader,
  printModelResult,
  printFooter,
} from "./cli";
import { ReviewError } from "./types";

/**
 * Main entry point
 */
async function main(): Promise<number> {
  // Parse arguments
  const args = parseArgs(process.argv);

  if (args.showHelp) {
    printHelp();
    return 0;
  }

  try {
    // Load configuration
    const llmConfig = getLLMClientConfig();
    const client = new LLMClient(llmConfig);

    // Find and load review targets
    const files = findReviewTargets({
      filePath: args.filePath,
      mode: args.mode,
    });

    // Build review job
    const job = buildReviewJob(files, args.reviewType);

    // Get models for this review type
    const reviewConfig = REVIEW_TYPE_MODELS[job.reviewType];
    const modelIds = reviewConfig.models;
    const modelNames = modelIds.map((id) => ALL_MODELS[id]?.name || id);

    // Token estimation warning
    const estimatedTokens = estimateTokens(job.combinedContent);
    if (estimatedTokens > LIMITS.MAX_CONTEXT_TOKENS * 0.8) {
      console.warn(
        `⚠️  Content is ~${estimatedTokens} tokens - may approach context limits for some models`
      );
    }

    // Print header
    printHeader(
      job.displayName,
      job.reviewType,
      !!args.reviewType,
      modelNames
    );

    const startTime = Date.now();

    // Execute parallel reviews
    const results = await client.reviewWithModels(
      modelIds,
      job.combinedContent,
      job.reviewType
    );

    // Print results
    let failureCount = 0;
    for (const result of results) {
      printModelResult(result.modelName, result.ok, result.content, result.error);
      if (!result.ok) failureCount++;
    }

    // Print footer
    const durationSec = ((Date.now() - startTime) / 1000).toFixed(1);
    printFooter(job.reviewType, results.length, failureCount, parseFloat(durationSec));

    // Return appropriate exit code
    if (failureCount === results.length) {
      return 1; // All failed
    } else if (failureCount > 0) {
      return 2; // Partial failure
    }
    return 0; // Success
  } catch (error) {
    if (error instanceof ReviewError) {
      console.error(`\n❌ ${error.kind} Error: ${error.message}`);
      if (error.details) {
        console.error(`   Details: ${JSON.stringify(error.details)}`);
      }
    } else {
      console.error(`\n❌ Fatal error: ${error}`);
    }
    return 1;
  }
}

// Run and exit with appropriate code
main()
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error("Unhandled error:", error);
    process.exit(1);
  });
