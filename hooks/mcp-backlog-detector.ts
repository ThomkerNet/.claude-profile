#!/usr/bin/env bun
/**
 * MCP Backlog Detector Hook (PostToolUse → Bash)
 *
 * Detects direct API calls, SSH, CLI tool usage, and credential exposure
 * in Bash commands. When found, injects context instructing Claude to
 * dispatch a background sonnet subagent to evaluate and optionally create
 * a GitHub issue in ThomkerNet/TKNet-MCPServer.
 */

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  tool_name: string;
  tool_input: {
    command: string;
    description?: string;
  };
  tool_response: string;
}

interface DetectedPattern {
  category: "api_call" | "remote_access" | "cloud_cli" | "database" | "auth_exposure";
  priority: "HIGH" | "MEDIUM";
  signal: string;
  description: string;
}

const PATTERNS: {
  pattern: RegExp;
  category: DetectedPattern["category"];
  priority: DetectedPattern["priority"];
  description: string;
}[] = [
  // HTTP calls with auth headers or credentials
  {
    pattern: /\bcurl\b.*(-H|--header)\s+['"]?(Authorization|X-Api-Key|X-Token)/i,
    category: "api_call",
    priority: "HIGH",
    description: "curl with auth headers",
  },
  {
    pattern: /\bcurl\b.*(-u|--user)\b/i,
    category: "api_call",
    priority: "HIGH",
    description: "curl with credentials",
  },
  {
    pattern: /\bwget\b.*--header\s+['"]?(Authorization|X-Api-Key)/i,
    category: "api_call",
    priority: "HIGH",
    description: "wget with auth headers",
  },
  {
    pattern: /\bcurl\b.*\b(Bearer|token=|apikey=)\b/i,
    category: "api_call",
    priority: "HIGH",
    description: "curl with inline token/key",
  },

  // General HTTP API calls (no visible auth but still direct API usage)
  {
    pattern: /\bcurl\b\s+(-[sSkLfOXd]+\s+)*['"]?https?:\/\/(?!localhost|127\.0\.0\.1)/i,
    category: "api_call",
    priority: "MEDIUM",
    description: "curl to external endpoint",
  },
  {
    pattern: /\bwget\b\s+.*['"]?https?:\/\/(?!localhost|127\.0\.0\.1)/i,
    category: "api_call",
    priority: "MEDIUM",
    description: "wget to external endpoint",
  },
  {
    pattern: /\bhttp\s+(GET|POST|PUT|DELETE|PATCH)\b/i,
    category: "api_call",
    priority: "MEDIUM",
    description: "httpie API call",
  },

  // Remote access
  {
    pattern: /\bssh\b\s+(?!-o)[\w@]/i,
    category: "remote_access",
    priority: "HIGH",
    description: "SSH remote access",
  },
  {
    pattern: /\bscp\b\s+/i,
    category: "remote_access",
    priority: "MEDIUM",
    description: "SCP file transfer",
  },
  {
    pattern: /\brsync\b.*\w+@\w+:/i,
    category: "remote_access",
    priority: "MEDIUM",
    description: "rsync over SSH",
  },

  // Cloud CLIs
  {
    pattern: /\baz\s+(container|webapp|aks|acr|keyvault|storage|network|vm|group|account)\b/i,
    category: "cloud_cli",
    priority: "HIGH",
    description: "Azure CLI",
  },
  {
    pattern: /\baws\s+(s3|ec2|ecs|lambda|iam|cloudformation|rds|sqs|sns|dynamodb)\b/i,
    category: "cloud_cli",
    priority: "HIGH",
    description: "AWS CLI",
  },
  {
    pattern: /\bgcloud\s+(compute|container|functions|run|iam|sql|storage)\b/i,
    category: "cloud_cli",
    priority: "HIGH",
    description: "Google Cloud CLI",
  },
  {
    pattern: /\bkubectl\s+(apply|get|create|delete|exec|logs|port-forward)\b/i,
    category: "cloud_cli",
    priority: "MEDIUM",
    description: "Kubernetes CLI",
  },
  {
    pattern: /\bterraform\s+(apply|plan|destroy|init)\b/i,
    category: "cloud_cli",
    priority: "MEDIUM",
    description: "Terraform CLI",
  },
  {
    pattern: /\bansible(-playbook)?\s+/i,
    category: "cloud_cli",
    priority: "MEDIUM",
    description: "Ansible CLI",
  },

  // Database direct access
  {
    pattern: /\bpsql\b.*(-h|--host|postgresql:\/\/)/i,
    category: "database",
    priority: "HIGH",
    description: "PostgreSQL direct access",
  },
  {
    pattern: /\bmysql\b.*(-h|--host|mysql:\/\/)/i,
    category: "database",
    priority: "HIGH",
    description: "MySQL direct access",
  },
  {
    pattern: /\b(mongo|mongosh)\b\s+(mongodb:\/\/|--host)/i,
    category: "database",
    priority: "HIGH",
    description: "MongoDB direct access",
  },
  {
    pattern: /\bredis-cli\b.*(-h|--host)\b/i,
    category: "database",
    priority: "MEDIUM",
    description: "Redis direct access",
  },

  // Credential exposure in commands
  {
    pattern: /\b(API_KEY|API_SECRET|SECRET_KEY|ACCESS_TOKEN|AUTH_TOKEN)\s*=/i,
    category: "auth_exposure",
    priority: "HIGH",
    description: "Credential in environment variable",
  },

  // GitHub API (direct, not standard gh commands)
  {
    pattern: /\bgh\s+api\b/i,
    category: "api_call",
    priority: "MEDIUM",
    description: "GitHub API direct call",
  },
];

// Commands to never flag
const EXCLUSIONS: RegExp[] = [
  /\bcurl\b.*localhost/i,
  /\bcurl\b.*127\.0\.0\.1/i,
  /\bcurl\b.*0\.0\.0\.0/i,
  /\bcurl\b.*\bhealth\b/i,
  /\bnpm\b|\byarn\b|\bbun\s+(install|add|run|test)\b/i,
  /\bgit\s+(clone|pull|push|fetch|remote)\b/i,
  /--help\b|--version\b|\s-h\s*$/,  // -h only as trailing help flag
  /\bman\s+/i,
  /\bwhich\b|\bwhereis\b/i,
  // gh issue create from this very hook's subagent
  /gh\s+issue\s+create\s+--repo\s+["']?ThomkerNet\/TKNet-MCPServer/i,
];

function shouldExclude(command: string): boolean {
  return EXCLUSIONS.some((pattern) => pattern.test(command));
}

function detectPatterns(command: string): DetectedPattern[] {
  if (shouldExclude(command)) return [];

  const detected: DetectedPattern[] = [];
  const seenKeys = new Set<string>();

  for (const { pattern, category, priority, description } of PATTERNS) {
    const match = command.match(pattern);
    if (match) {
      const key = `${category}:${description}`;
      if (!seenKeys.has(key)) {
        seenKeys.add(key);
        detected.push({
          category,
          priority,
          signal: match[0],
          description,
        });
      }
    }
  }

  return detected;
}

// Known TKNet MCP servers for cross-reference
const EXISTING_SERVERS = [
  "tkn-cloudflare",
  "tkn-unraid",
  "tkn-aipeerreview",
  "tkn-authentik",
  "tkn-firecrawl",
  "tkn-gmail",
  "tkn-github-actions",
  "tkn-komodo",
  "tkn-tailscale",
  "tkn-usage",
  "tkn-azure",
  "tkn-litellm",
  "tkn-media",
  "tkn-ollama",
  "tkn-registry",
  "tkn-syncthing",
  "tkn-terraform",
  "tkn-unifi",
  "tkn-haos",
  "tkn-arr",
  "tkn-anythingllm",
];

async function main() {
  const input = await Bun.stdin.text();
  if (!input) process.exit(0);

  try {
    const hookData: HookInput = JSON.parse(input);
    const command = hookData.tool_input?.command || "";

    if (!command || command.length < 5) process.exit(0);

    const patterns = detectPatterns(command);
    if (patterns.length === 0) process.exit(0);

    const highestPriority = patterns.some((p) => p.priority === "HIGH")
      ? "HIGH"
      : "MEDIUM";
    const findings = patterns
      .map(
        (p) =>
          `- **${p.priority}** [${p.category}]: ${p.description} — \`${p.signal}\``
      )
      .join("\n");
    const truncatedCmd =
      command.length > 500 ? command.slice(0, 500) + "..." : command;

    const context = `<mcp-backlog-detected priority="${highestPriority}">
**Direct API/CLI call detected — potential MCP tooling opportunity.**

${findings}

**Command:**
\`\`\`bash
${truncatedCmd}
\`\`\`

**Action:** Dispatch a **background** Task subagent (\`model: "sonnet"\`, \`run_in_background: true\`) to evaluate this. The subagent prompt should include:

1. The command above and what it was used for (working dir: \`${hookData.cwd}\`)
2. Whether an existing TKNet MCP server already covers this: ${EXISTING_SERVERS.join(", ")}
3. If a new tool or server enhancement is warranted, create a GitHub issue:
   \`gh issue create --repo "ThomkerNet/TKNet-MCPServer" --title "MCP Backlog: <service> tooling" --label "enhancement" --label "mcp-server" --body "<body>"\`
   Use the standard backlog template: Session Analysis, Current Approach, Security Concern, Proposed MCP Tool (name, description, parameters, returns), Priority, Effort.
4. If not warranted (one-off, already covered, localhost, or trivial), skip silently and return "No backlog item needed."

Do NOT block or delay the current task for this — run it entirely in the background.
</mcp-backlog-detected>`;

    console.log(
      JSON.stringify({
        hookSpecificOutput: {
          additionalContext: context,
        },
      })
    );
  } catch (error) {
    console.error("MCP backlog detector error:", error);
    process.exit(0);
  }
}

main();
