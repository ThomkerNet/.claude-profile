/**
 * CLI argument parsing for AI Peer Review
 */

import { ALL_MODELS, REVIEW_TYPE_MODELS } from "./config";
import type { ReviewMode } from "./fileSystem";

export interface ParsedArgs {
  filePath?: string;
  reviewType?: string;
  mode?: ReviewMode;
  showHelp: boolean;
}

/**
 * Parse command line arguments
 */
export function parseArgs(argv: string[]): ParsedArgs {
  const args = argv.slice(2); // Remove node/bun and script path
  let filePath: string | undefined;
  let reviewType: string | undefined;
  let mode: ReviewMode | undefined;
  let showHelp = false;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === "--type" || arg === "-t") {
      if (i + 1 >= args.length) {
        console.error(`Error: ${arg} requires a value`);
        console.error(
          `Available types: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}`
        );
        process.exit(1);
      }
      const typeArg = args[++i].toLowerCase();
      if (!(typeArg in REVIEW_TYPE_MODELS)) {
        console.error(`Invalid review type: ${typeArg}`);
        console.error(
          `Available types: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}`
        );
        process.exit(1);
      }
      reviewType = typeArg;
    } else if (arg === "--mode" || arg === "-m") {
      if (i + 1 >= args.length) {
        console.error(`Error: ${arg} requires a value (git, plan)`);
        process.exit(1);
      }
      const modeArg = args[++i].toLowerCase();
      if (!["git", "plan"].includes(modeArg)) {
        console.error(`Invalid mode: ${modeArg}`);
        console.error("Available modes: git, plan");
        process.exit(1);
      }
      mode = modeArg as ReviewMode;
    } else if (arg === "--help" || arg === "-h") {
      showHelp = true;
    } else if (!arg.startsWith("-")) {
      filePath = arg;
    } else {
      console.error(`Unknown option: ${arg}`);
      console.error("Use --help for usage information");
      process.exit(1);
    }
  }

  return { filePath, reviewType, mode, showHelp };
}

/**
 * Print help message
 */
export function printHelp(): void {
  const modelsByType = Object.entries(REVIEW_TYPE_MODELS)
    .map(
      ([type, config]) =>
        `  ${type.padEnd(12)} → ${config.models.map((m) => ALL_MODELS[m]?.name || m).join(", ")}`
    )
    .join("\n");

  console.log(`
AI Peer Review - Smart multi-model code review via LiteLLM

Usage: /aipeerreview [options] [file]

Options:
  -t, --type <type>  Review type: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}
  -m, --mode <mode>  File selection: git (default), plan
  -h, --help         Show this help

File Selection:
  (default)          Auto-detect git changes, fallback to plans
  --mode git         Review git changes in current repo
  --mode plan        Review most recent file in ~/.claude/plans/
  <file>             Review specific file (overrides mode)

Review Types & Models:
${modelsByType}

Environment Variables:
  LITELLM_BASE_URL   LiteLLM proxy URL (default: http://localhost:4000/v1)
  LITELLM_API_KEY    LiteLLM API key (required)

  Or configure in ~/.claude/secrets.json:
  {
    "litellm": {
      "base_url": "http://your-proxy:4000/v1",
      "api_key": "your-api-key"
    }
  }

Examples:
  /aipeerreview                          # Review git changes (or fallback to plans)
  /aipeerreview -t security              # Security review of git changes
  /aipeerreview --mode plan              # Review most recent plan
  /aipeerreview src/auth.ts              # Review specific file
`);
}

/**
 * Print review header
 */
export function printHeader(
  displayName: string,
  reviewType: string,
  isExplicit: boolean,
  modelNames: string[]
): void {
  console.log(`\n${"═".repeat(70)}`);
  console.log(`   AI PEER REVIEW - ${reviewType.toUpperCase()} Analysis`);
  console.log(`${"═".repeat(70)}\n`);
  console.log(`📄 Document: ${displayName}`);
  console.log(
    `🎯 Review Type: ${reviewType}${isExplicit ? " (explicit)" : " (auto-detected)"}`
  );
  console.log(`🤖 Models: ${modelNames.join(" → ")}`);
  console.log(`\n⚡ Starting parallel peer review across ${modelNames.length} AI models...\n`);
}

/**
 * Print a single model's review result
 */
export function printModelResult(
  modelName: string,
  ok: boolean,
  content?: string,
  error?: string
): void {
  console.log(`\n${"─".repeat(70)}`);
  console.log(`📋 ${modelName}`);
  console.log(`${"─".repeat(70)}\n`);

  if (!ok || error) {
    console.error(`❌ ${error || "Unknown error"}`);
  } else {
    console.log(content || "(No content returned)");
  }
}

/**
 * Print review summary footer
 */
export function printFooter(
  reviewType: string,
  totalCount: number,
  failureCount: number,
  durationSec: number
): void {
  console.log(`\n${"═".repeat(70)}`);
  if (failureCount === totalCount) {
    console.log(`❌ All ${failureCount} reviews failed! (${durationSec}s)`);
  } else if (failureCount > 0) {
    console.log(
      `⚠️  ${reviewType.toUpperCase()} peer review complete with ${failureCount} failure(s)! (${durationSec}s)`
    );
  } else {
    console.log(
      `✅ ${reviewType.toUpperCase()} peer review complete! (${durationSec}s)`
    );
  }
  console.log(`${"═".repeat(70)}\n`);
}
