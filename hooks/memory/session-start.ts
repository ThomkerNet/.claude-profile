#!/usr/bin/env bun
/**
 * Session Start Hook - Memory First Preferences
 *
 * Queries the Memory MCP server at session start to load:
 * - User preferences
 * - Current project patterns
 * - Recent corrections/decisions
 *
 * Outputs context as additionalContext so Claude has it immediately.
 */

import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";

interface MemoryEntity {
  name: string;
  entityType: string;
  observations: string[];
}

interface MemoryGraph {
  entities: MemoryEntity[];
  relations: { from: string; to: string; relationType: string }[];
}

const MEMORY_FILE = join(homedir(), ".claude", "memory.jsonl");

/**
 * Read memory graph from JSONL file (same format as MCP memory server)
 */
function readMemoryGraph(): MemoryGraph {
  const graph: MemoryGraph = { entities: [], relations: [] };

  if (!existsSync(MEMORY_FILE)) {
    return graph;
  }

  try {
    const content = readFileSync(MEMORY_FILE, "utf-8");
    const lines = content.split("\n").filter(line => line.trim());

    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        if (entry.type === "entity" && entry.name) {
          graph.entities.push({
            name: entry.name,
            entityType: entry.entityType || "unknown",
            observations: entry.observations || []
          });
        } else if (entry.type === "relation") {
          graph.relations.push({
            from: entry.from,
            to: entry.to,
            relationType: entry.relationType
          });
        }
      } catch {
        // Skip malformed lines
      }
    }
  } catch (error) {
    console.error("Error reading memory file:", error);
  }

  return graph;
}

/**
 * Search entities by name or type
 */
function searchEntities(graph: MemoryGraph, query: string): MemoryEntity[] {
  const lowerQuery = query.toLowerCase();
  return graph.entities.filter(e =>
    e.name.toLowerCase().includes(lowerQuery) ||
    e.entityType.toLowerCase().includes(lowerQuery) ||
    e.observations.some(o => o.toLowerCase().includes(lowerQuery))
  );
}

/**
 * Get current project name from working directory
 */
function getProjectName(cwd: string): string {
  const parts = cwd.split("/");
  return parts[parts.length - 1] || "unknown";
}

async function main() {
  // Read hook input from stdin
  const input = await Bun.stdin.text();

  if (!input) {
    process.exit(0);
  }

  try {
    const hookData = JSON.parse(input);
    const cwd = hookData.cwd || hookData.workspace?.current_dir || process.cwd();
    const projectName = getProjectName(cwd);
    const sessionType = hookData.session_start_data?.type || "startup";

    // Read memory
    const graph = readMemoryGraph();

    if (graph.entities.length === 0) {
      // No memory yet, nothing to inject
      process.exit(0);
    }

    // Find relevant entities
    const userEntities = searchEntities(graph, "user");
    const projectEntities = searchEntities(graph, projectName);
    const preferencesEntities = searchEntities(graph, "preference");

    // Build context sections
    const sections: string[] = [];

    // User preferences
    const userObs = userEntities.flatMap(e => e.observations);
    if (userObs.length > 0) {
      sections.push(`**User Preferences:**\n${userObs.map(o => `- ${o}`).join("\n")}`);
    }

    // Project context
    const projectObs = projectEntities.flatMap(e => e.observations);
    if (projectObs.length > 0) {
      sections.push(`**Project (${projectName}):**\n${projectObs.map(o => `- ${o}`).join("\n")}`);
    }

    // Additional preferences
    const prefObs = preferencesEntities
      .filter(e => !userEntities.includes(e))
      .flatMap(e => e.observations);
    if (prefObs.length > 0) {
      sections.push(`**Additional Context:**\n${prefObs.map(o => `- ${o}`).join("\n")}`);
    }

    if (sections.length === 0) {
      process.exit(0);
    }

    // Output as additionalContext
    const context = `<memory-context session="${sessionType}">
## Loaded from Memory

${sections.join("\n\n")}

---
*Use memory MCP to store new preferences/patterns discovered during this session.*
</memory-context>`;

    console.log(JSON.stringify({
      hookSpecificOutput: {
        additionalContext: context
      }
    }));

  } catch (error) {
    console.error("Session start hook error:", error);
    process.exit(0);
  }
}

main();
