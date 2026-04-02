---
name: research
description: Deep research brief — web search, content extraction, and AI peer validation synthesized into a structured report
argument-hint: "[topic or question] [--quick]"
---

# /research — Deep Research Brief

> Gather sources, extract content, validate with external AI models, synthesize into a structured brief.

## Arguments

- `$ARGUMENTS` — the research topic or question
- `--quick` or `-q` — fast mode: fewer sources, skip deep scrape, use quick_consult

Strip flags from `$ARGUMENTS` before using as query.

---

## Stage 1: Intent Detection (no tools)

Classify the query to adjust emphasis:

| Signal | Intent | Adjustments |
|--------|--------|-------------|
| "how to", "implement", "build", "setup", "configure" | **Implementation** | Prefer official docs, include steps/examples. Trigger context7. |
| "vs", "compare", "difference", "which", "or" | **Comparison** | Ensure symmetric sourcing. Add comparison table. |
| "what is", "when did", "who", "define" | **Factual** | Prefer encyclopedic/primary sources. Fewer sources needed. |
| "latest", "new", "current", "2026" | **Freshness** | Bias toward recency. Note staleness risks. |
| Default | **Exploratory** | Cast wide net. |

If query mentions a **library, framework, or tool name** (e.g. React, FastAPI, Prisma, Terraform, LangChain) or contains "API", "SDK", "docs", "method", "config":
- Set **context7_relevant = true**

---

## Stage 2: Source Discovery (run ALL in parallel)

Launch these tool calls simultaneously:

**2a — WebSearch:**
```
WebSearch(query: "<research query>")
```

**2b — Firecrawl search:**
```
mcp__tkn-firecrawl__search_web(query: "<research query>", limit: 5)
```

**2c — context7 (only if context7_relevant):**
```
mcp__context7__resolve-library-id(libraryName: "<library name>")
→ mcp__context7__query-docs(libraryId: <result>, topic: "<research query>")
```

Collect all URLs and content from results.

---

## Stage 3: Merge, Deduplicate, Rank

Combine URLs from WebSearch and Firecrawl. Apply these heuristics:

**Dedup:** Strip UTM params, normalize www/trailing slashes. If same domain+path appears twice, keep the version with more content.

**Rank by:**
1. **Authority** — official docs, .gov, .edu, vendor blogs > random blogs > SEO farms
2. **Relevance** — title/headings directly address query > tangential mentions
3. **Recency** — prefer last 2 years unless historical topic
4. **Corroboration** — claims verified by multiple sources rank higher

Select top URLs for deep scraping:
- `--quick`: top 3
- Default: top 5-7

---

## Stage 4: Deep Scrape (parallel, selective)

Skip in `--quick` mode.

For each selected URL that does NOT already have full markdown content from Firecrawl search results:

```
mcp__tkn-firecrawl__scrape_url(url: "<url>", only_main_content: true)
```

Run these in parallel. Reuse content already returned by Firecrawl search — don't re-scrape.

If a specific page needs targeted extraction (e.g. a pricing table, API signature, or specific section buried in a large page):
```
WebFetch(url: "<url>", prompt: "<what to extract>")
```

---

## Stage 5: Draft Synthesis (no tools)

Synthesize all gathered content into a draft brief following the output template below. Include inline citations `[Source N]` for all claims.

Identify:
- Areas where sources **agree** (high confidence)
- Areas where sources **conflict** (flag explicitly)
- **Gaps** — what the research couldn't answer

---

## Stage 6: Peer Validation

**Default mode** — call `peer_consult` with the draft:

```
mcp__tkn-aipeer__peer_consult(
  question: "I've researched the following topic. Review my findings for errors, outdated information, missing perspectives, and weakly-supported assumptions. Rate confidence in the main conclusions (high/medium/low).",
  context: {"topic": "<query>", "findings": "<draft key findings + sources>"},
  consultation_type: "<match intent: implementation/architecture/general>"
)
```

**`--quick` mode** — use `quick_consult` instead:

```
mcp__tkn-aipeer__quick_consult(
  question: "Check these findings for errors or missing perspectives: <draft key findings>",
  consultation_type: "general"
)
```

Integrate peer feedback into the final brief. Note where peers disagreed or added new information.

---

## Output Template

Always produce this structure. Adapt section emphasis based on intent.

```markdown
## Research Brief: {query}

### TL;DR
[2-5 bullet executive summary]

### Key Findings
- [Finding 1] [Source 1, 3]
- [Finding 2] [Source 2]
- ...

### {Intent-Specific Section}
<!-- Implementation → "Recommended Approach" with steps -->
<!-- Comparison → "Options Matrix" table + "When to Choose Which" -->
<!-- Factual → "Verified Facts" with confidence levels -->
<!-- Exploratory → "Key Themes" -->

### Conflicting Information
[Where sources disagree, what each claims, and which seems more credible]
<!-- If none: "No significant conflicts found across sources." -->

### Peer Validation Notes
[What the external AI models confirmed, corrected, or added]

### Gaps & Unknowns
[What the research couldn't answer or where confidence is low]

### Sources
1. [Title](URL) — brief reliability/authority note
2. [Title](URL) — ...
```

---

## Mode Summary

| Aspect | Default | `--quick` |
|--------|---------|-----------|
| Discovery | WebSearch + Firecrawl (parallel) | WebSearch + Firecrawl (parallel) |
| context7 | If library detected | If library detected |
| Deep scrape | Top 5-7 URLs | Skip |
| Peer validation | `peer_consult` (multi-model) | `quick_consult` (single model) |
| Output | Full brief | TL;DR + Key Findings + Sources |

---

## Notes

- All discovery calls (Stage 2) run in parallel — don't wait for one before starting others
- Deep scrape calls (Stage 4) also run in parallel
- Peer consult happens AFTER synthesis — it validates evidence-backed findings, not cold questions
- If any tool is unavailable, continue with remaining tools and note the gap
- Do not fabricate sources — only cite URLs actually retrieved
