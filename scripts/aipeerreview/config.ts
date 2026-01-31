/**
 * Configuration module for AI Peer Review
 * Loads settings from environment variables with fallback to secrets.json
 */

import { readFileSync, existsSync } from "fs";
import { resolve } from "path";
import type { ModelConfig, ReviewTypeConfig, LLMClientConfig } from "./types";
import { ReviewError } from "./types";

// Environment variable names
const ENV_LITELLM_BASE_URL = "LITELLM_BASE_URL";
const ENV_LITELLM_API_KEY = "LITELLM_API_KEY";

// Defaults
const DEFAULT_BASE_URL = "http://localhost:4000/v1";
const DEFAULT_TIMEOUT_MS = 300000; // 5 minutes
const DEFAULT_MAX_TOKENS = 4096;

/**
 * Load secrets from ~/.claude/secrets.json as fallback
 */
function loadSecretsJson(): Record<string, unknown> | null {
  const home = process.env.HOME;
  if (!home) return null;

  const secretsPath = resolve(home, ".claude", "secrets.json");
  if (!existsSync(secretsPath)) return null;

  try {
    const content = readFileSync(secretsPath, "utf-8");
    return JSON.parse(content);
  } catch {
    return null;
  }
}

/**
 * Get LLM client configuration from environment or secrets.json
 */
export function getLLMClientConfig(): LLMClientConfig {
  // Try environment variables first
  let baseUrl = process.env[ENV_LITELLM_BASE_URL];
  let apiKey = process.env[ENV_LITELLM_API_KEY];

  // Fallback to secrets.json
  if (!baseUrl || !apiKey) {
    const secrets = loadSecretsJson();
    if (secrets) {
      const litellm = secrets.litellm as Record<string, string> | undefined;
      if (litellm) {
        baseUrl = baseUrl || litellm.base_url;
        apiKey = apiKey || litellm.api_key;
      }
    }
  }

  // Validate required config
  if (!apiKey) {
    throw new ReviewError(
      "Config",
      `LiteLLM API key not configured. Set ${ENV_LITELLM_API_KEY} environment variable or add litellm.api_key to ~/.claude/secrets.json`
    );
  }

  return {
    baseUrl: baseUrl || DEFAULT_BASE_URL,
    apiKey,
    timeoutMs: DEFAULT_TIMEOUT_MS,
    maxTokens: DEFAULT_MAX_TOKENS,
  };
}

/**
 * All available models via LiteLLM proxy
 * Claude models excluded - use Claude Code directly for Claude reviews
 */
export const ALL_MODELS: Record<string, ModelConfig> = {
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
};

/**
 * Review types with optimal model selection (3 models each)
 */
export const REVIEW_TYPE_MODELS: Record<string, ReviewTypeConfig> = {
  security: {
    models: ["gpt-5.1", "gemini-3-pro-preview", "gemini-2.5-pro"],
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
    models: ["gpt-5.1", "gemini-3-pro-preview", "gemini-2.5-pro"],
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
    models: ["gpt-5", "gemini-3-pro-preview", "gemini-2.5-pro"],
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
    models: ["gpt-5.1", "gemini-2.5-pro", "gemini-2.5-flash"],
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

/**
 * File size and count limits
 */
export const LIMITS = {
  MAX_FILE_SIZE: 5 * 1024 * 1024,      // 5MB per file
  MAX_TOTAL_SIZE: 20 * 1024 * 1024,    // 20MB total
  MAX_FILES: 15,                        // Max files in multi-file review
  ESTIMATED_TOKENS_PER_CHAR: 0.25,     // Rough estimate for token counting
  MAX_CONTEXT_TOKENS: 100000,          // Warn if likely to exceed
};

/**
 * Reviewable file extensions
 */
export const REVIEWABLE_EXTENSIONS = [
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

/**
 * Estimate token count for content (rough approximation)
 */
export function estimateTokens(content: string): number {
  return Math.ceil(content.length * LIMITS.ESTIMATED_TOKENS_PER_CHAR);
}
