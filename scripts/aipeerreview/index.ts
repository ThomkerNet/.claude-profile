#!/usr/bin/env bun
/**
 * AI Peer Review - Multi-model code/plan review via LiteLLM proxy
 * Reviews content using the 3 most appropriate AI models based on review type
 * Uses direct HTTP calls to LiteLLM proxy for model access
 */

import { readFileSync, readdirSync, statSync, existsSync } from "fs";
import { resolve, basename, join, relative, extname } from "path";
import { execSync } from "child_process";

// LiteLLM proxy configuration
const LITELLM_BASE_URL = "http://100.74.34.7:4000/v1";
const LITELLM_API_KEY = "sk-35439ddea8690f7c89be8497e2f43e318d4890123d288cca";

// All available models via LiteLLM proxy
// Note: Claude models removed - use Claude Code directly for Claude reviews
const ALL_MODELS = {
  "gpt-5.1": {
    name: "GPT-5.1",
    description: "Visual reasoning, general purpose, adaptive",
    strengths: ["visual", "general", "api-design", "documentation", "security"],
  },
  "gpt-5": {
    name: "GPT-5",
    description: "Strong general reasoning and coding",
    strengths: ["general", "coding", "reasoning", "performance"],
  },
  "gpt-5-mini": {
    name: "GPT-5 Mini",
    description: "Fast, cost-effective GPT model",
    strengths: ["fast", "cost-effective"],
  },
  "gemini-3-pro-preview": {
    name: "Gemini 3 Pro",
    description: "Graduate-level reasoning, academic knowledge, multilingual",
    strengths: ["academic", "architecture", "security-theory", "multilingual", "complex-reasoning"],
  },
  "gemini-2.5-pro": {
    name: "Gemini 2.5 Pro",
    description: "Strong reasoning and code understanding",
    strengths: ["reasoning", "code", "analysis", "bug-detection"],
  },
  "gemini-2.5-flash": {
    name: "Gemini 2.5 Flash",
    description: "Fast Gemini model for quick tasks",
    strengths: ["fast", "general"],
  },
  "deepseek-r1": {
    name: "DeepSeek R1",
    description: "Local reasoning model, strong at logic",
    strengths: ["reasoning", "logic", "local", "bug-detection"],
  },
} as const;

type ModelId = keyof typeof ALL_MODELS;

// Review types with optimal model selection (3 models each)
// Using GPT, Gemini, and DeepSeek models (Claude accessed via Claude Code directly)
const REVIEW_TYPE_MODELS: Record<string, { models: ModelId[]; focusAreas: string[] }> = {
  security: {
    models: ["gpt-5.1", "gemini-3-pro-preview", "deepseek-r1"],
    focusAreas: [
      "Injection vulnerabilities (SQL, XSS, command injection)",
      "Authentication and authorization flaws",
      "Data exposure and sensitive information leaks",
      "Input validation and sanitization",
      "Cryptographic issues and secure storage",
      "OWASP Top 10 vulnerabilities",
    ],
  },
  architecture: {
    models: ["gemini-3-pro-preview", "gpt-5.1", "gemini-2.5-pro"],
    focusAreas: [
      "Design patterns and anti-patterns",
      "Scalability and maintainability",
      "Separation of concerns",
      "Dependency management",
      "System boundaries and interfaces",
      "Technical debt and coupling",
    ],
  },
  bug: {
    models: ["gpt-5.1", "deepseek-r1", "gemini-2.5-pro"],
    focusAreas: [
      "Logic errors and edge cases",
      "Race conditions and concurrency issues",
      "Null/undefined handling",
      "Error handling completeness",
      "Off-by-one errors and boundary conditions",
      "Resource leaks and cleanup",
    ],
  },
  performance: {
    models: ["gpt-5", "gemini-3-pro-preview", "deepseek-r1"],
    focusAreas: [
      "Algorithm complexity (time/space)",
      "Database query optimization",
      "Memory usage and allocation",
      "Network and I/O efficiency",
      "Caching opportunities",
      "Bottleneck identification",
    ],
  },
  api: {
    models: ["gpt-5.1", "gemini-3-pro-preview", "gemini-2.5-pro"],
    focusAreas: [
      "API design and RESTful principles",
      "Contract clarity and documentation",
      "Error response consistency",
      "Versioning strategy",
      "Rate limiting and pagination",
      "Backward compatibility",
    ],
  },
  test: {
    models: ["gpt-5.1", "gemini-2.5-pro", "deepseek-r1"],
    focusAreas: [
      "Test coverage gaps",
      "Edge case coverage",
      "Mock and stub quality",
      "Test isolation and independence",
      "Assertion quality",
      "Integration test completeness",
    ],
  },
  general: {
    models: ["gpt-5.1", "gemini-3-pro-preview", "gemini-2.5-pro"],
    focusAreas: [
      "Code architecture and design",
      "Security implications",
      "Feasibility and implementation concerns",
      "Best practices alignment",
      "Potential pitfalls and edge cases",
      "Suggestions for improvement",
    ],
  },
};

type ReviewType = keyof typeof REVIEW_TYPE_MODELS;

// Auto-detect review type from content using word boundaries
function detectReviewType(content: string): ReviewType {
  const contentLower = content.toLowerCase();

  const typePatterns: Array<{ type: ReviewType; patterns: RegExp[]; weight: number }> = [
    {
      type: "security",
      patterns: [
        /\bsecurity\b/gi, /\bauth(?:entication|orization)?\b/gi, /\bvulnerabilit(?:y|ies)\b/gi,
        /\binjection\b/gi, /\bxss\b/gi, /\bcsrf\b/gi, /\bpermissions?\b/gi,
        /\bcredentials?\b/gi, /\bencrypt(?:ion|ed)?\b/gi, /\btokens?\b/gi, /\boauth\b/gi, /\bjwt\b/gi
      ],
      weight: 0,
    },
    {
      type: "architecture",
      patterns: [
        /\barchitecture\b/gi, /\bdesign\s*pattern\b/gi, /\bstructure\b/gi,
        /\bscalab(?:le|ility)\b/gi, /\bmicroservices?\b/gi, /\bmonolith\b/gi,
        /\bcomponents?\b/gi, /\bmodules?\b/gi, /\blayers?\b/gi, /\bdependenc(?:y|ies)\b/gi
      ],
      weight: 0,
    },
    {
      type: "bug",
      patterns: [
        /\bbugs?\b/gi, /\bfix(?:es|ed|ing)?\b/gi, /\berrors?\b/gi, /\bexceptions?\b/gi,
        /\bcrash(?:es|ed|ing)?\b/gi, /\bissues?\b/gi, /\bbroken\b/gi, /\bfailing\b/gi,
        /\bnull\b/gi, /\bundefined\b/gi, /\brace\s*condition\b/gi
      ],
      weight: 0,
    },
    {
      type: "performance",
      patterns: [
        /\bperformance\b/gi, /\boptimiz(?:e|ation|ed|ing)\b/gi, /\bslow\b/gi, /\bfast(?:er)?\b/gi,
        /\bmemory\b/gi, /\bcach(?:e|ing|ed)\b/gi, /\blatency\b/gi, /\bthroughput\b/gi,
        /\bbottleneck\b/gi, /\befficient\b/gi, /\bcomplexity\b/gi
      ],
      weight: 0,
    },
    {
      type: "api",
      patterns: [
        /\bapi\b/gi, /\bendpoints?\b/gi, /\brest(?:ful)?\b/gi, /\bgraphql\b/gi,
        /\brequests?\b/gi, /\bresponses?\b/gi, /\broutes?\b/gi, /\bhandlers?\b/gi,
        /\bmiddleware\b/gi, /\bcontracts?\b/gi
      ],
      weight: 0,
    },
    {
      type: "test",
      patterns: [
        /\btests?\b/gi, /\bspec\b/gi, /\bcoverage\b/gi, /\bmocks?\b/gi, /\bstubs?\b/gi,
        /\bassert(?:ions?)?\b/gi, /\bexpect\b/gi, /\bjest\b/gi, /\bvitest\b/gi,
        /\bpytest\b/gi, /\bunit\s*tests?\b/gi, /\bintegration\b/gi
      ],
      weight: 0,
    },
  ];

  const scored = typePatterns.map((tp) => {
    let weight = 0;
    for (const pattern of tp.patterns) {
      const matches = contentLower.match(pattern);
      weight += matches ? matches.length : 0;
    }
    return { type: tp.type, weight };
  });

  scored.sort((a, b) => b.weight - a.weight || a.type.localeCompare(b.type));

  if (scored[0].weight > 2) {
    return scored[0].type;
  }

  return "general";
}

// File size limits
const MAX_FILE_SIZE = 5 * 1024 * 1024;
const MAX_TOTAL_SIZE = 20 * 1024 * 1024;
const MAX_FILES = 15;

// Reviewable file extensions
const REVIEWABLE_EXTENSIONS = [
  '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
  '.py', '.go', '.rs', '.java', '.kt', '.swift',
  '.c', '.cpp', '.h', '.hpp', '.cs',
  '.rb', '.php', '.scala', '.clj',
  '.yml', '.yaml', '.json', '.toml',
  '.tf', '.hcl', '.bicep',
  '.sh', '.bash', '.zsh', '.ps1',
  '.sql', '.graphql', '.prisma',
  '.md', '.mdx',
  '.dockerfile', '.containerfile',
];

type ReviewMode = 'git' | 'plan' | 'file';

function getGitRoot(): string | null {
  try {
    return execSync('git rev-parse --show-toplevel 2>/dev/null', { encoding: 'utf-8' }).trim();
  } catch {
    return null;
  }
}

function getGitChangedFiles(): string[] {
  const gitRoot = getGitRoot();
  if (!gitRoot) return [];

  try {
    const unstaged = execSync('git diff --name-only 2>/dev/null', { encoding: 'utf-8' });
    const staged = execSync('git diff --cached --name-only 2>/dev/null', { encoding: 'utf-8' });

    const files = [...new Set([...unstaged.split('\n'), ...staged.split('\n')])]
      .filter(f => f.trim())
      .filter(f => {
        const ext = extname(f).toLowerCase();
        const filename = basename(f).toLowerCase();
        return REVIEWABLE_EXTENSIONS.includes(ext) ||
               filename === 'dockerfile' ||
               filename === 'makefile' ||
               filename === 'containerfile';
      })
      .map(f => join(gitRoot, f))
      .filter(f => existsSync(f))
      .filter(f => {
        try {
          return statSync(f).size <= MAX_FILE_SIZE;
        } catch {
          return false;
        }
      });

    return files;
  } catch (error) {
    const msg = error instanceof Error ? error.message : 'Unknown error';
    console.warn(`⚠️  Git detection failed: ${msg}`);
    return [];
  }
}

function findMostRecentPlan(): string | null {
  const home = process.env.HOME;
  if (!home) return null;

  const plansDir = resolve(home, ".claude", "plans");
  let files: Array<{ path: string; mtime: number }> = [];

  try {
    const planFiles = readdirSync(plansDir)
      .filter((f) => f.endsWith(".md"))
      .map((f) => {
        const fullPath = resolve(plansDir, f);
        return { path: fullPath, mtime: statSync(fullPath).mtime.getTime() };
      });
    files = [...files, ...planFiles];
  } catch {
    // Plans directory doesn't exist
  }

  if (files.length === 0) return null;

  files.sort((a, b) => b.mtime - a.mtime);
  return files[0].path;
}

function findReviewTarget(filePath?: string, mode?: ReviewMode): string[] {
  if (filePath) {
    const fullPath = resolve(filePath);
    let stats;
    try {
      stats = statSync(fullPath);
    } catch {
      console.error(`File not found: ${filePath}`);
      process.exit(1);
    }

    if (stats.size === 0) {
      console.error(`File is empty: ${filePath}`);
      process.exit(1);
    }
    if (stats.size > MAX_FILE_SIZE) {
      console.error(`File exceeds ${MAX_FILE_SIZE / 1024 / 1024}MB limit: ${filePath}`);
      process.exit(1);
    }

    return [fullPath];
  }

  if (mode === 'plan') {
    const plan = findMostRecentPlan();
    if (!plan) {
      console.error("No plans found in ~/.claude/plans/");
      process.exit(1);
    }
    return [plan];
  }

  const gitFiles = getGitChangedFiles();
  if (gitFiles.length > 0) {
    let totalSize = 0;
    const limitedFiles = gitFiles.slice(0, MAX_FILES).filter(f => {
      try {
        const size = statSync(f).size;
        if (totalSize + size > MAX_TOTAL_SIZE) return false;
        totalSize += size;
        return true;
      } catch {
        return false;
      }
    });

    if (limitedFiles.length > 0) {
      const gitRoot = getGitRoot();
      console.log(`📂 Auto-detected ${limitedFiles.length} changed file(s) from git:`);
      limitedFiles.forEach(f => {
        const relPath = gitRoot ? relative(gitRoot, f) : basename(f);
        console.log(`   • ${relPath}`);
      });
      if (gitFiles.length > limitedFiles.length) {
        console.log(`   (${gitFiles.length - limitedFiles.length} files skipped due to size limits)`);
      }
      return limitedFiles;
    }
  }

  console.log("⚠️  No git changes detected, falling back to plans directory...");
  const plan = findMostRecentPlan();
  if (!plan) {
    console.error("No files to review. Make changes in a git repo or create a plan in ~/.claude/plans/");
    process.exit(1);
  }
  return [plan];
}

function readFileContent(filePath: string): string {
  try {
    const content = readFileSync(filePath, "utf-8");
    if (!content.trim()) {
      console.error(`File is empty or contains only whitespace: ${filePath}`);
      process.exit(1);
    }
    return content;
  } catch (error) {
    console.error(`Failed to read file: ${filePath}`);
    process.exit(1);
  }
}

// Call LiteLLM API directly
async function callLiteLLM(
  modelId: string,
  prompt: string,
  timeoutMs: number = 300000
): Promise<{ content: string; error?: string }> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${LITELLM_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${LITELLM_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: modelId,
        messages: [{ role: "user", content: prompt }],
        max_tokens: 4096,
      }),
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      return { content: "", error: `HTTP ${response.status}: ${errorText.slice(0, 500)}` };
    }

    const data = await response.json() as {
      choices?: Array<{ message?: { content?: string } }>;
      error?: { message?: string };
    };

    if (data.error) {
      return { content: "", error: data.error.message || "Unknown API error" };
    }

    const content = data.choices?.[0]?.message?.content || "";
    return { content };
  } catch (err) {
    clearTimeout(timeoutId);
    if (err instanceof Error && err.name === "AbortError") {
      return { content: "", error: `Request timed out after ${timeoutMs / 1000} seconds` };
    }
    return { content: "", error: err instanceof Error ? err.message : "Unknown error" };
  }
}

async function reviewWithModel(
  modelId: ModelId,
  content: string,
  reviewType: ReviewType
): Promise<{ model: string; result: string; error?: string }> {
  const model = ALL_MODELS[modelId];
  const config = REVIEW_TYPE_MODELS[reviewType];

  const focusAreasList = config.focusAreas.map((a) => `- ${a}`).join("\n");

  const reviewPrompt = `You are conducting a ${reviewType.toUpperCase()} peer review. Your expertise: ${model.description}

Focus on these specific areas:
${focusAreasList}

Document to review:
---
${content}
---

Provide a structured review with:
1. **Summary** - One paragraph overview
2. **Strengths** - What's done well (3-5 points)
3. **Issues Found** - Problems ranked by severity (Critical > High > Medium > Low)
4. **Recommendations** - Specific, actionable improvements
5. **Questions** - Clarifications needed from the author

Be concise but thorough. Prioritize actionable feedback over generic advice.`;

  const { content: result, error } = await callLiteLLM(modelId, reviewPrompt, 300000);

  if (error) {
    return {
      model: model.name,
      result: "",
      error,
    };
  }

  return { model: model.name, result, error: undefined };
}

function parseArgs(): { filePath?: string; reviewType?: ReviewType; mode?: ReviewMode } {
  const args = process.argv.slice(2);
  let filePath: string | undefined;
  let reviewType: ReviewType | undefined;
  let mode: ReviewMode | undefined;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === "--type" || arg === "-t") {
      if (i + 1 >= args.length) {
        console.error(`Error: ${arg} requires a value`);
        console.error(`Available types: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}`);
        process.exit(1);
      }
      const typeArg = args[++i].toLowerCase();
      if (!(typeArg in REVIEW_TYPE_MODELS)) {
        console.error(`Invalid review type: ${typeArg}`);
        console.error(`Available types: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}`);
        process.exit(1);
      }
      reviewType = typeArg as ReviewType;
    } else if (arg === "--mode" || arg === "-m") {
      if (i + 1 >= args.length) {
        console.error(`Error: ${arg} requires a value (git, plan)`);
        process.exit(1);
      }
      const modeArg = args[++i].toLowerCase();
      if (!['git', 'plan'].includes(modeArg)) {
        console.error(`Invalid mode: ${modeArg}`);
        console.error("Available modes: git, plan");
        process.exit(1);
      }
      mode = modeArg as ReviewMode;
    } else if (arg === "--help" || arg === "-h") {
      console.log(`
AI Peer Review - Smart multi-model code review via OpenCode + LiteLLM

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
${Object.entries(REVIEW_TYPE_MODELS)
  .map(([type, config]) => `  ${type.padEnd(12)} → ${config.models.map((m) => ALL_MODELS[m as ModelId].name).join(", ")}`)
  .join("\n")}

Examples:
  /aipeerreview                          # Review git changes (or fallback to plans)
  /aipeerreview -t security              # Security review of git changes
  /aipeerreview --mode plan              # Review most recent plan
  /aipeerreview src/auth.ts              # Review specific file
`);
      process.exit(0);
    } else if (!arg.startsWith("-")) {
      filePath = arg;
    } else {
      console.error(`Unknown option: ${arg}`);
      console.error("Use --help for usage information");
      process.exit(1);
    }
  }

  return { filePath, reviewType, mode };
}

function getLanguageFromExt(filePath: string): string {
  const ext = extname(filePath).toLowerCase();
  const langMap: Record<string, string> = {
    '.ts': 'typescript', '.tsx': 'tsx', '.js': 'javascript', '.jsx': 'jsx',
    '.py': 'python', '.go': 'go', '.rs': 'rust', '.java': 'java',
    '.kt': 'kotlin', '.swift': 'swift', '.c': 'c', '.cpp': 'cpp',
    '.cs': 'csharp', '.rb': 'ruby', '.php': 'php', '.scala': 'scala',
    '.yml': 'yaml', '.yaml': 'yaml', '.json': 'json', '.toml': 'toml',
    '.tf': 'hcl', '.hcl': 'hcl', '.bicep': 'bicep',
    '.sh': 'bash', '.bash': 'bash', '.zsh': 'zsh', '.ps1': 'powershell',
    '.sql': 'sql', '.graphql': 'graphql', '.prisma': 'prisma',
    '.md': 'markdown', '.mdx': 'mdx',
  };
  return langMap[ext] || 'text';
}

async function main(): Promise<void> {
  const { filePath, reviewType: explicitType, mode } = parseArgs();
  const targetFiles = findReviewTarget(filePath, mode);
  const gitRoot = getGitRoot();

  let content: string;
  let displayName: string;

  if (targetFiles.length === 1) {
    displayName = basename(targetFiles[0]);
    content = readFileContent(targetFiles[0]);
  } else {
    displayName = `${targetFiles.length} files`;
    content = targetFiles.map(f => {
      const relPath = gitRoot ? relative(gitRoot, f) : basename(f);
      const lang = getLanguageFromExt(f);
      const fileContent = readFileContent(f);
      return `## File: ${relPath}\n\n\`\`\`${lang}\n${fileContent}\n\`\`\``;
    }).join('\n\n---\n\n');
  }

  const reviewType = explicitType || detectReviewType(content);
  const config = REVIEW_TYPE_MODELS[reviewType];
  const models = config.models;

  const startTime = Date.now();

  console.log(`\n${"═".repeat(70)}`);
  console.log(`   AI PEER REVIEW - ${reviewType.toUpperCase()} Analysis`);
  console.log(`${"═".repeat(70)}\n`);
  console.log(`📄 Document: ${displayName}`);
  console.log(`🎯 Review Type: ${reviewType}${explicitType ? " (explicit)" : " (auto-detected)"}`);
  console.log(`🤖 Models: ${models.map((m) => ALL_MODELS[m].name).join(" → ")}`);
  console.log(`\n⚡ Starting parallel peer review across ${models.length} AI models...\n`);

  // Run reviews in parallel
  const results = await Promise.allSettled(
    models.map((modelId) => reviewWithModel(modelId, content, reviewType))
  );

  const reviews = results.map((result, idx) => {
    if (result.status === "fulfilled") {
      return result.value;
    } else {
      return {
        model: ALL_MODELS[models[idx]].name,
        result: "",
        error: `Promise rejected: ${result.reason}`,
      };
    }
  });

  let failureCount = 0;

  for (const review of reviews) {
    console.log(`\n${"─".repeat(70)}`);
    console.log(`📋 ${review.model}`);
    console.log(`${"─".repeat(70)}\n`);

    if (review.error) {
      console.error(`❌ ${review.error}`);
      failureCount++;
    } else {
      console.log(review.result);
    }
  }

  const duration = ((Date.now() - startTime) / 1000).toFixed(1);

  console.log(`\n${"═".repeat(70)}`);
  if (failureCount === reviews.length) {
    console.log(`❌ All ${failureCount} reviews failed! (${duration}s)`);
  } else if (failureCount > 0) {
    console.log(`⚠️  ${reviewType.toUpperCase()} peer review complete with ${failureCount} failure(s)! (${duration}s)`);
  } else {
    console.log(`✅ ${reviewType.toUpperCase()} peer review complete! (${duration}s)`);
  }
  console.log(`${"═".repeat(70)}\n`);

  if (failureCount === reviews.length) {
    process.exit(1);
  } else if (failureCount > 0) {
    process.exit(2);
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
