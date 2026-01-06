#!/usr/bin/env bun
/**
 * Zero-Friction Commit - Automate commit, push, and documentation
 * Analyzes changes and creates meaningful commits with automatic documentation
 */

import { execSync } from "child_process";
import { readFileSync, writeFileSync, appendFileSync, existsSync } from "fs";
import { resolve } from "path";

interface ChangeAnalysis {
  filesChanged: string[];
  summary: string;
  isSignificant: boolean;
  commitMessage: string;
}

function getGitStatus(): string {
  try {
    return execSync("git status --porcelain", { encoding: "utf-8" });
  } catch {
    console.error("Not in a git repository");
    process.exit(1);
  }
}

function getGitDiff(): string {
  try {
    return execSync("git diff --name-only", { encoding: "utf-8" });
  } catch {
    return "";
  }
}

function getStagedDiff(): string {
  try {
    return execSync("git diff --cached --name-only", { encoding: "utf-8" });
  } catch {
    return "";
  }
}

function analyzeChanges(): ChangeAnalysis {
  const status = getGitStatus();
  const diffFiles = getGitDiff();
  const stagedFiles = getStagedDiff();

  const allChanges = new Set<string>();

  // Parse git status for changed files
  status.split("\n").forEach((line) => {
    if (line.trim()) {
      const file = line.substring(3).trim();
      if (file) allChanges.add(file);
    }
  });

  // Add diff files
  diffFiles.split("\n").forEach((line) => {
    if (line.trim()) allChanges.add(line.trim());
  });

  // Add staged files
  stagedFiles.split("\n").forEach((line) => {
    if (line.trim()) allChanges.add(line.trim());
  });

  const filesChanged = Array.from(allChanges).sort();

  if (filesChanged.length === 0) {
    console.error("❌ No changes to commit");
    process.exit(1);
  }

  // Categorize changes
  const categories: { [key: string]: string[] } = {
    features: [],
    tests: [],
    docs: [],
    scripts: [],
    config: [],
    other: [],
  };

  filesChanged.forEach((file) => {
    if (file.includes("test") || file.includes("spec")) {
      categories.tests.push(file);
    } else if (file.includes("README") || file.includes(".md")) {
      categories.docs.push(file);
    } else if (file.endsWith(".sh") || file.endsWith(".ts") || file.endsWith(".js")) {
      if (
        file.includes("src/") ||
        file.includes("skills/") ||
        file.includes("hooks/")
      ) {
        categories.features.push(file);
      } else {
        categories.scripts.push(file);
      }
    } else if (
      file.includes("json") ||
      file.includes("config") ||
      file.includes("yml")
    ) {
      categories.config.push(file);
    } else {
      categories.other.push(file);
    }
  });

  // Generate summary
  const summaryParts: string[] = [];

  if (categories.features.length > 0) {
    summaryParts.push(
      `Add/update ${categories.features.length} feature file(s)`
    );
  }
  if (categories.tests.length > 0) {
    summaryParts.push(`Add/update ${categories.tests.length} test(s)`);
  }
  if (categories.docs.length > 0) {
    summaryParts.push(`Update documentation`);
  }
  if (categories.scripts.length > 0) {
    summaryParts.push(`Update scripts/tools`);
  }
  if (categories.config.length > 0) {
    summaryParts.push(`Update configuration`);
  }

  const summary = summaryParts.join(" and ");
  const isSignificant =
    filesChanged.length > 1 || categories.features.length > 0;

  // Build file list for message
  const fileDetails: string[] = [];

  if (categories.features.length > 0) {
    fileDetails.push(`- Add/update: ${categories.features.join(", ")}`);
  }
  if (categories.tests.length > 0) {
    fileDetails.push(`- Tests: ${categories.tests.join(", ")}`);
  }
  if (categories.docs.length > 0) {
    fileDetails.push(`- Documentation: ${categories.docs.join(", ")}`);
  }
  if (categories.scripts.length > 0) {
    fileDetails.push(`- Scripts: ${categories.scripts.join(", ")}`);
  }
  if (categories.config.length > 0) {
    fileDetails.push(`- Config: ${categories.config.join(", ")}`);
  }

  const commitMessage =
    summaryParts.length > 0
      ? `${summaryParts[0].charAt(0).toUpperCase() + summaryParts[0].slice(1)}\n\n${fileDetails.join("\n")}`
      : `Update files\n\n${fileDetails.join("\n")}`;

  return {
    filesChanged,
    summary,
    isSignificant,
    commitMessage,
  };
}

function stageAndCommit(userMessage: string | undefined, analysis: ChangeAnalysis): void {
  const finalMessage = userMessage || analysis.commitMessage;

  console.log("\n📝 Staging changes...");
  try {
    execSync("git add -A", { encoding: "utf-8" });
    console.log("✅ Changes staged");
  } catch (error) {
    console.error("❌ Failed to stage changes");
    process.exit(1);
  }

  console.log("📤 Committing...");
  const commitMsg = `${finalMessage}\n\n🤖 Generated with Claude Code\n\nCo-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>`;

  try {
    execSync(`git commit -m "${commitMsg.replace(/"/g, '\\"')}"`, {
      encoding: "utf-8",
      shell: "/bin/bash",
    });
    console.log("✅ Committed");
  } catch (error) {
    console.error("❌ Failed to commit");
    process.exit(1);
  }

  console.log("🚀 Pushing...");
  try {
    execSync("git push", { encoding: "utf-8" });
    console.log("✅ Pushed to remote");
  } catch (error) {
    console.error("⚠️  Push failed (but commit succeeded)");
  }
}

function documentWork(analysis: ChangeAnalysis): void {
  const timestamp = new Date().toISOString().split("T")[0];
  const planFile = resolve(
    process.env.HOME || ".",
    ".claude/plans/work-summary.md"
  );

  const entry = `
## ${timestamp} - ${analysis.summary}

${analysis.commitMessage.split("\n").map((line) => `> ${line}`).join("\n")}

Files changed: ${analysis.filesChanged.length}
${analysis.filesChanged.map((f) => `- \`${f}\``).join("\n")}

---
`;

  try {
    if (existsSync(planFile)) {
      appendFileSync(planFile, entry);
    } else {
      writeFileSync(
        planFile,
        `# Work Summary Log\n\nAutomated documentation of commits and changes.\n${entry}`
      );
    }
    console.log("📚 Work documented in work-summary.md");
  } catch (error) {
    console.warn("⚠️  Could not document work");
  }
}

function main(): void {
  const customMessage = process.argv[2];

  console.log("\n📊 Analyzing changes...");
  const analysis = analyzeChanges();

  console.log(`✅ Changes detected: ${analysis.filesChanged.length} file(s)\n`);
  console.log("Generated commit message:");
  console.log("---");
  console.log(analysis.commitMessage);
  console.log("---\n");

  stageAndCommit(customMessage, analysis);
  documentWork(analysis);

  console.log("\n✨ Done! Changes committed, pushed, and documented.\n");
}

main();
