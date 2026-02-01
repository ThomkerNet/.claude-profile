# Repository Coupling Policies

**Scope:** How repositories interact, dependency management, interface contracts

---

## Philosophy

**Default to loose coupling.** Repositories should be independently deployable, testable, and versioned unless there's a compelling reason for tight coupling.

---

## Repository Topology

```
~/git-bnx/
├── TKN/          # Personal/homelab (independent)
├── BNX/          # BoroughNexus company projects
└── BriefHours/   # BriefHours product
```

### Organizational Relationships

| Relationship | Coupling Level | Description |
|--------------|----------------|-------------|
| **TKN ↔ BNX/BriefHours** | None | Separate concerns, no shared code |
| **BNX ↔ BriefHours** | Cousins | May share patterns, but can diverge |
| **BNX siblings** | Managed | Shared by contract, not by code copy |

---

## Coupling Rules

### ✅ Loose Coupling (Default)

**When to use:**
- Repos have different deployment schedules
- Services owned by different teams (even if just you/Charlotte)
- Different tech stacks
- Different lifecycles (stable vs experimental)

**How to implement:**
- Shared code → Published npm packages or Docker images
- Communication via versioned APIs (REST, GraphQL, message queues)
- Explicit dependency declarations in `package.json`/`requirements.txt`
- Semantic versioning for all shared artifacts

**Example:**
```json
// package.json in BNX/project-a
{
  "dependencies": {
    "@boroughnexus/shared-utils": "^2.1.0"  // Versioned, published package
  }
}
```

---

### ⚠️ Managed Coupling (Requires Justification)

**When acceptable:**
- Monorepo structure with shared tooling (Nx, Turborepo, etc.)
- Tightly coordinated services that always deploy together
- Shared configuration or infrastructure-as-code

**Required documentation:**
- Architectural Decision Record (ADR) explaining why
- Documented API contracts between coupled services
- Clear ownership and change approval process

**How to implement:**
- Use monorepo tools for dependency management
- Automated tests that verify interface contracts
- Shared CI/CD pipeline with atomic deployments

---

### ❌ Tight Coupling (Avoid)

**Anti-patterns to avoid:**
- Copy-pasting code between repos
- Direct file system access across repo boundaries
- Implicit dependencies on internal implementation details
- Deploying multiple repos in lockstep without tooling

**If you find yourself doing this:** Refactor into a shared library.

---

## Sibling Repository Checklist

**Before importing code from a sibling repo**, ask:

1. **Could this be a shared library?**
   - If yes → Extract to `@boroughnexus/shared-*` package
   - If no → Proceed with caution

2. **Is the interface stable?**
   - If yes → Version it and publish
   - If no → Keep it internal until stable

3. **What's the deployment coupling cost?**
   - Independent deployment → Loose coupling preferred
   - Always deploy together → Consider monorepo

4. **Who owns the shared code?**
   - Clear ownership → Document in package README
   - Unclear → Needs architectural decision

---

## Shared Code Patterns

### Pattern 1: Published NPM Package

**Use for:** Stable, reusable utilities, types, or components

**Structure:**
```
~/git-bnx/BNX/shared-utils/
├── package.json          # "@boroughnexus/shared-utils"
├── src/
│   ├── index.ts
│   └── utils/
├── tsconfig.json
└── README.md             # API documentation
```

**Publishing:**
```bash
npm version patch  # or minor/major
npm publish
```

**Consuming:**
```bash
npm install @boroughnexus/shared-utils@latest
```

---

### Pattern 2: Monorepo (Managed Coupling)

**Use for:** Highly coordinated projects that share infrastructure

**Structure:**
```
~/git-bnx/BNX/platform-monorepo/
├── package.json          # Workspace root
├── packages/
│   ├── api/              # Service A
│   ├── web/              # Service B
│   └── shared/           # Internal shared code
└── turbo.json            # Build orchestration
```

**Benefits:**
- Atomic commits across services
- Shared tooling (ESLint, TypeScript config)
- Easier refactoring

**Costs:**
- Larger repository
- More complex CI/CD
- All-or-nothing deployment risk

---

### Pattern 3: API Contract (Loose Coupling)

**Use for:** Services that need to communicate but deploy independently

**Contract definition (OpenAPI/GraphQL schema):**
```yaml
# api-contract.yaml
openapi: 3.0.0
info:
  title: BNX Internal API
  version: 1.2.0
paths:
  /api/users/{id}:
    get:
      summary: Get user by ID
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
```

**Consumer:**
```typescript
// Uses contract via HTTP, not direct code import
const user = await fetch(`${API_URL}/api/users/${id}`);
```

**Testing:**
- Contract tests (Pact, Dredd) to verify compatibility
- Mock servers for development

---

## BNX ↔ BriefHours Relationship

**Status:** Cousins - related but can diverge

**Shared:**
- Architectural patterns (where beneficial)
- Learning and best practices
- Development tooling preferences

**Not Shared:**
- Code (separate codebases)
- Infrastructure (BriefHours on Azure, others on homelab)
- Deployment schedules
- Product roadmaps

**Communication:**
- Lessons learned documented in Obsidian vault
- Architecture decisions recorded in ADRs
- No code copy-paste between orgs

---

## Dependency Management

### Allowed Dependencies

| Dependency Type | BNX Projects | BriefHours | TKN/Homelab |
|-----------------|--------------|------------|-------------|
| **Public npm packages** | ✅ | ✅ | ✅ |
| **@boroughnexus/* packages** | ✅ | ❌ | ❌ |
| **Direct code import** | ❌ (use packages) | ❌ | ✅ (personal) |

---

## Contract Evolution

When changing shared interfaces:

1. **Backward compatible change (patch/minor):**
   - Add optional fields
   - Deprecate (don't remove) old fields
   - Update version, publish

2. **Breaking change (major):**
   - Increment major version
   - Document migration path
   - Support old version during transition
   - Coordinate with consumers before deploying

3. **API versioning:**
   - Use `/v1/`, `/v2/` URL prefixes for REST APIs
   - Support N-1 version during transition period

---

## Examples

### ✅ Good: Shared Library

```bash
# Create shared package
cd ~/git-bnx/BNX/
mkdir shared-types && cd shared-types
npm init -y
# ... develop package ...
npm publish

# Use in projects
cd ~/git-bnx/BNX/project-a
npm install @boroughnexus/shared-types
```

### ✅ Good: API-Based Integration

```typescript
// Service A exposes API
app.get('/api/data', async (req, res) => {
  res.json({ data: await fetchData() });
});

// Service B consumes via HTTP
const response = await fetch('http://service-a/api/data');
const { data } = await response.json();
```

### ❌ Bad: Direct File Import Across Repos

```typescript
// In ~/git-bnx/BNX/project-a/
import { utils } from '../../project-b/src/utils';  // ❌ NEVER
```

### ❌ Bad: Copy-Paste

```bash
# ❌ NEVER DO THIS
cp ~/git-bnx/BNX/project-a/src/utils.ts \
   ~/git-bnx/BNX/project-b/src/utils.ts
```

---

## Architectural Decision Records (ADRs)

For significant coupling decisions, create an ADR:

**Location:** `docs/adr/` in the relevant project

**Template:**
```markdown
# ADR-001: Tightly Couple Project A and Project B

## Status
Accepted

## Context
[Why this decision is needed]

## Decision
[What we decided to do]

## Consequences
[Trade-offs, risks, benefits]

## Alternatives Considered
[Other options and why rejected]
```

---

## Questions?

- Project structure: See `~/.claude/architecture/TOPOLOGY.md`
- Deployment coordination: See `~/.claude/policies/DEPLOYMENT.md`
- Infrastructure separation: See `~/.claude/architecture/INFRASTRUCTURE.md`
