/**
 * File system and Git operations for AI Peer Review
 * Handles target discovery and file reading
 */

import { readFileSync, readdirSync, statSync, existsSync } from "fs";
import { resolve, basename, join, relative, extname } from "path";
import { execSync } from "child_process";
import type { ReviewFile, ReviewJob } from "./types";
import { ReviewError } from "./types";
import { LIMITS, REVIEWABLE_EXTENSIONS, REVIEW_TYPE_MODELS } from "./config";

/**
 * Language detection from file extension
 */
const LANGUAGE_MAP: Record<string, string> = {
  ".ts": "typescript",
  ".tsx": "tsx",
  ".js": "javascript",
  ".jsx": "jsx",
  ".py": "python",
  ".go": "go",
  ".rs": "rust",
  ".java": "java",
  ".kt": "kotlin",
  ".swift": "swift",
  ".c": "c",
  ".cpp": "cpp",
  ".cs": "csharp",
  ".rb": "ruby",
  ".php": "php",
  ".scala": "scala",
  ".yml": "yaml",
  ".yaml": "yaml",
  ".json": "json",
  ".toml": "toml",
  ".tf": "hcl",
  ".hcl": "hcl",
  ".bicep": "bicep",
  ".sh": "bash",
  ".bash": "bash",
  ".zsh": "zsh",
  ".ps1": "powershell",
  ".sql": "sql",
  ".graphql": "graphql",
  ".prisma": "prisma",
  ".md": "markdown",
  ".mdx": "mdx",
};

/**
 * Get language identifier from file extension
 */
export function getLanguageFromExt(filePath: string): string {
  const ext = extname(filePath).toLowerCase();
  return LANGUAGE_MAP[ext] || "text";
}

/**
 * Get git repository root directory
 */
export function getGitRoot(): string | null {
  try {
    return execSync("git rev-parse --show-toplevel 2>/dev/null", {
      encoding: "utf-8",
    }).trim();
  } catch {
    return null;
  }
}

/**
 * Check if a file is reviewable based on extension
 */
function isReviewableFile(filePath: string): boolean {
  const ext = extname(filePath).toLowerCase();
  const filename = basename(filePath).toLowerCase();
  return (
    REVIEWABLE_EXTENSIONS.includes(ext) ||
    filename === "dockerfile" ||
    filename === "makefile" ||
    filename === "containerfile"
  );
}

/**
 * Get list of changed files from git (staged and unstaged)
 */
export function getGitChangedFiles(): string[] {
  const gitRoot = getGitRoot();
  if (!gitRoot) return [];

  try {
    const unstaged = execSync("git diff --name-only 2>/dev/null", {
      encoding: "utf-8",
    });
    const staged = execSync("git diff --cached --name-only 2>/dev/null", {
      encoding: "utf-8",
    });

    const files = [...new Set([...unstaged.split("\n"), ...staged.split("\n")])]
      .filter((f) => f.trim())
      .filter(isReviewableFile)
      .map((f) => join(gitRoot, f))
      .filter((f) => existsSync(f))
      .filter((f) => {
        try {
          return statSync(f).size <= LIMITS.MAX_FILE_SIZE;
        } catch {
          return false;
        }
      });

    return files;
  } catch (error) {
    const msg = error instanceof Error ? error.message : "Unknown error";
    console.warn(`⚠️  Git detection failed: ${msg}`);
    return [];
  }
}

/**
 * Find the most recently modified plan file
 */
export function findMostRecentPlan(): string | null {
  const home = process.env.HOME;
  if (!home) return null;

  const plansDir = resolve(home, ".claude", "plans");

  try {
    const files = readdirSync(plansDir)
      .filter((f) => f.endsWith(".md"))
      .map((f) => {
        const fullPath = resolve(plansDir, f);
        return { path: fullPath, mtime: statSync(fullPath).mtime.getTime() };
      })
      .sort((a, b) => b.mtime - a.mtime);

    return files.length > 0 ? files[0].path : null;
  } catch {
    return null;
  }
}

/**
 * Read file content with validation
 */
export function readFileContent(filePath: string): string {
  try {
    const content = readFileSync(filePath, "utf-8");
    if (!content.trim()) {
      throw new ReviewError(
        "Validation",
        `File is empty or contains only whitespace: ${filePath}`
      );
    }
    return content;
  } catch (error) {
    if (error instanceof ReviewError) throw error;
    throw new ReviewError("IO", `Failed to read file: ${filePath}`, error);
  }
}

/**
 * Load a single file as a ReviewFile
 */
function loadReviewFile(filePath: string, gitRoot: string | null): ReviewFile {
  const content = readFileContent(filePath);
  const displayName = gitRoot ? relative(gitRoot, filePath) : basename(filePath);

  return {
    path: filePath,
    displayName,
    language: getLanguageFromExt(filePath),
    content,
  };
}

export type ReviewMode = "git" | "plan" | "file";

export interface FindTargetOptions {
  filePath?: string;
  mode?: ReviewMode;
}

/**
 * Find review target files based on mode
 */
export function findReviewTargets(options: FindTargetOptions): ReviewFile[] {
  const { filePath, mode } = options;
  const gitRoot = getGitRoot();

  // Explicit file path
  if (filePath) {
    const fullPath = resolve(filePath);

    if (!existsSync(fullPath)) {
      throw new ReviewError("IO", `File not found: ${filePath}`);
    }

    const stats = statSync(fullPath);
    if (stats.size === 0) {
      throw new ReviewError("Validation", `File is empty: ${filePath}`);
    }
    if (stats.size > LIMITS.MAX_FILE_SIZE) {
      throw new ReviewError(
        "Validation",
        `File exceeds ${LIMITS.MAX_FILE_SIZE / 1024 / 1024}MB limit: ${filePath}`
      );
    }

    return [loadReviewFile(fullPath, gitRoot)];
  }

  // Plan mode
  if (mode === "plan") {
    const plan = findMostRecentPlan();
    if (!plan) {
      throw new ReviewError("IO", "No plans found in ~/.claude/plans/");
    }
    return [loadReviewFile(plan, gitRoot)];
  }

  // Git mode (default) - find changed files
  const gitFiles = getGitChangedFiles();
  if (gitFiles.length > 0) {
    let totalSize = 0;
    const limitedFiles = gitFiles.slice(0, LIMITS.MAX_FILES).filter((f) => {
      try {
        const size = statSync(f).size;
        if (totalSize + size > LIMITS.MAX_TOTAL_SIZE) return false;
        totalSize += size;
        return true;
      } catch {
        return false;
      }
    });

    if (limitedFiles.length > 0) {
      console.log(
        `📂 Auto-detected ${limitedFiles.length} changed file(s) from git:`
      );
      limitedFiles.forEach((f) => {
        const relPath = gitRoot ? relative(gitRoot, f) : basename(f);
        console.log(`   • ${relPath}`);
      });
      if (gitFiles.length > limitedFiles.length) {
        console.log(
          `   (${gitFiles.length - limitedFiles.length} files skipped due to size limits)`
        );
      }

      return limitedFiles.map((f) => loadReviewFile(f, gitRoot));
    }
  }

  // Fallback to plans
  console.log("⚠️  No git changes detected, falling back to plans directory...");
  const plan = findMostRecentPlan();
  if (!plan) {
    throw new ReviewError(
      "IO",
      "No files to review. Make changes in a git repo or create a plan in ~/.claude/plans/"
    );
  }
  return [loadReviewFile(plan, gitRoot)];
}

/**
 * Auto-detect review type from content using keyword analysis
 */
export function detectReviewType(content: string): string {
  const contentLower = content.toLowerCase();

  const typePatterns: Array<{
    type: string;
    patterns: RegExp[];
  }> = [
    {
      type: "security",
      patterns: [
        /\bsecurity\b/gi,
        /\bauth(?:entication|orization)?\b/gi,
        /\bvulnerabilit(?:y|ies)\b/gi,
        /\binjection\b/gi,
        /\bxss\b/gi,
        /\bcsrf\b/gi,
        /\bpermissions?\b/gi,
        /\bcredentials?\b/gi,
        /\bencrypt(?:ion|ed)?\b/gi,
        /\btokens?\b/gi,
        /\boauth\b/gi,
        /\bjwt\b/gi,
      ],
    },
    {
      type: "architecture",
      patterns: [
        /\barchitecture\b/gi,
        /\bdesign\s*pattern\b/gi,
        /\bstructure\b/gi,
        /\bscalab(?:le|ility)\b/gi,
        /\bmicroservices?\b/gi,
        /\bmonolith\b/gi,
        /\bcomponents?\b/gi,
        /\bmodules?\b/gi,
        /\blayers?\b/gi,
        /\bdependenc(?:y|ies)\b/gi,
      ],
    },
    {
      type: "bug",
      patterns: [
        /\bbugs?\b/gi,
        /\bfix(?:es|ed|ing)?\b/gi,
        /\berrors?\b/gi,
        /\bexceptions?\b/gi,
        /\bcrash(?:es|ed|ing)?\b/gi,
        /\bissues?\b/gi,
        /\bbroken\b/gi,
        /\bfailing\b/gi,
        /\bnull\b/gi,
        /\bundefined\b/gi,
        /\brace\s*condition\b/gi,
      ],
    },
    {
      type: "performance",
      patterns: [
        /\bperformance\b/gi,
        /\boptimiz(?:e|ation|ed|ing)\b/gi,
        /\bslow\b/gi,
        /\bfast(?:er)?\b/gi,
        /\bmemory\b/gi,
        /\bcach(?:e|ing|ed)\b/gi,
        /\blatency\b/gi,
        /\bthroughput\b/gi,
        /\bbottleneck\b/gi,
        /\befficient\b/gi,
        /\bcomplexity\b/gi,
      ],
    },
    {
      type: "api",
      patterns: [
        /\bapi\b/gi,
        /\bendpoints?\b/gi,
        /\brest(?:ful)?\b/gi,
        /\bgraphql\b/gi,
        /\brequests?\b/gi,
        /\bresponses?\b/gi,
        /\broutes?\b/gi,
        /\bhandlers?\b/gi,
        /\bmiddleware\b/gi,
        /\bcontracts?\b/gi,
      ],
    },
    {
      type: "test",
      patterns: [
        /\btests?\b/gi,
        /\bspec\b/gi,
        /\bcoverage\b/gi,
        /\bmocks?\b/gi,
        /\bstubs?\b/gi,
        /\bassert(?:ions?)?\b/gi,
        /\bexpect\b/gi,
        /\bjest\b/gi,
        /\bvitest\b/gi,
        /\bpytest\b/gi,
        /\bunit\s*tests?\b/gi,
        /\bintegration\b/gi,
      ],
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

/**
 * Build a ReviewJob from files
 */
export function buildReviewJob(
  files: ReviewFile[],
  explicitType?: string
): ReviewJob {
  let displayName: string;
  let combinedContent: string;

  if (files.length === 1) {
    displayName = files[0].displayName;
    combinedContent = files[0].content;
  } else {
    displayName = `${files.length} files`;
    combinedContent = files
      .map(
        (f) =>
          `## File: ${f.displayName}\n\n\`\`\`${f.language}\n${f.content}\n\`\`\``
      )
      .join("\n\n---\n\n");
  }

  const reviewType = explicitType || detectReviewType(combinedContent);

  // Validate review type
  if (!REVIEW_TYPE_MODELS[reviewType]) {
    throw new ReviewError(
      "Validation",
      `Unknown review type: ${reviewType}. Valid types: ${Object.keys(REVIEW_TYPE_MODELS).join(", ")}`
    );
  }

  return {
    files,
    reviewType,
    displayName,
    combinedContent,
  };
}
