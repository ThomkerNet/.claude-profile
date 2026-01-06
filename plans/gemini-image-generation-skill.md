# Plan: Gemini Image Generation Skill

**Status:** Implemented (pending API key configuration for testing)

## Overview

Implement a skill/capability for AI image generation using Google's Gemini native image generation. The skill emphasizes intent clarification, detailed specification, and iterative refinement.

## Peer Review Incorporated

- Changed from Imagen API to Gemini native image generation (`generateContent` endpoint)
- Model: `gemini-2.5-flash-preview-05-20` (verified from docs)
- No separate TypeScript implementation - skill uses direct API calls via curl
- Output directory created with proper structure

---

## API Research Summary

### Endpoint
```
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:predict
Header: x-goog-api-key: $GEMINI_API_KEY
```

### Available Models
| Model | Use Case |
|-------|----------|
| `imagen-4.0-generate-001` | Standard quality (recommended) |
| `imagen-4.0-ultra-generate-001` | Highest quality |
| `imagen-4.0-fast-generate-001` | Fast generation |
| `imagen-3.0-generate-002` | Previous generation |

### Parameters
| Parameter | Values | Default |
|-----------|--------|---------|
| `numberOfImages` | 1-4 | 4 |
| `aspectRatio` | `1:1`, `3:4`, `4:3`, `9:16`, `16:9` | `1:1` |
| `imageSize` | `1K`, `2K` | `1K` |
| `personGeneration` | `dont_allow`, `allow_adult`, `allow_all` | `allow_adult` |

### Free Tier Limits
- Generous daily quota for personal use
- Rate limiting applies
- SynthID watermark on all generated images

---

## Architecture

### File Structure
```
~/.claude/
├── skills/
│   └── imagen/
│       ├── SKILL.md           # Skill documentation & workflow
│       └── index.ts           # Bun implementation
├── commands/
│   └── imagen.md              # Slash command definition
└── output/
    └── images/                # Generated images stored here
```

### Credential Access
- API key stored in Bitwarden as `GEMINI_API_KEY`
- Retrieved via vault API or environment variable
- Fallback: prompt user to set `GEMINI_API_KEY` env var

---

## Workflow Design

### Phase 1: Intent Clarification

Before generating, the skill MUST clarify user intent through questions:

1. **Subject**: What is the main subject/focus?
2. **Context**: Background, environment, setting?
3. **Style**: Photo, illustration, painting, sketch, digital art?
4. **Mood/Tone**: Bright, dark, dramatic, whimsical, professional?
5. **Technical**: Aspect ratio, number of variations?

**Example dialogue:**
```
User: Generate an image of a coffee shop

Claude: I'll help you generate a coffee shop image. Let me clarify a few details:

**Subject & Context:**
- Interior or exterior view?
- Modern minimalist, cozy rustic, or urban industrial style?
- Empty or with customers?

**Style:**
- Photorealistic, illustration, watercolor, or other?

**Technical:**
- Aspect ratio? (1:1 square, 16:9 landscape, 9:16 portrait)
- How many variations? (1-4)
```

### Phase 2: Detailed Specification

After clarification, produce a detailed spec before generation:

```markdown
## Image Generation Specification

**Prompt:** A cozy rustic coffee shop interior with exposed brick walls,
warm Edison bulb lighting, wooden tables, and a barista behind an
espresso machine. Morning sunlight streaming through large windows.
Photorealistic style, 4K HDR quality.

**Parameters:**
- Model: imagen-4.0-generate-001
- Aspect Ratio: 16:9 (landscape)
- Image Size: 1K
- Variations: 4
- Person Generation: allow_adult

**Prompt Enhancements Applied:**
- Added lighting descriptor: "warm Edison bulb lighting"
- Added quality modifier: "4K HDR quality"
- Added time context: "morning sunlight"

Ready to generate? [Yes / Modify prompt / Change parameters]
```

### Phase 3: Generation & Output

1. Call Imagen API with constructed prompt
2. Save images to `~/.claude/output/images/` with timestamp
3. Display images (if terminal supports) or provide file paths
4. Open in default viewer (optional)

**Output format:**
```
Generated 4 images:
1. ~/.claude/output/images/imagen-2026-01-04-123456-1.png
2. ~/.claude/output/images/imagen-2026-01-04-123456-2.png
3. ~/.claude/output/images/imagen-2026-01-04-123456-3.png
4. ~/.claude/output/images/imagen-2026-01-04-123456-4.png

[View in Finder] [Iterate on #2] [New prompt]
```

### Phase 4: Iteration

User can iterate on any generated image:

```
User: Iterate on #2 - make it more moody with darker lighting

Claude: I'll refine image #2 with darker, moodier lighting.

**Updated Specification:**
- Base: Previous prompt for image #2
- Modification: "dim atmospheric lighting, shadows, moody ambiance"
- Removed: "morning sunlight streaming through windows"

Generating refined version...
```

**Iteration options:**
- Modify lighting/mood
- Change style (photo → illustration)
- Adjust composition
- Add/remove elements
- Change aspect ratio
- Upscale (2K resolution)

---

## Implementation Details

### index.ts Structure

```typescript
#!/usr/bin/env bun

interface ImagenConfig {
  model: string;
  prompt: string;
  numberOfImages: number;
  aspectRatio: string;
  imageSize: string;
  personGeneration: string;
}

interface GenerationSession {
  id: string;
  timestamp: string;
  spec: ImagenConfig;
  prompt: string;
  outputPaths: string[];
  iterations: GenerationSession[];
}

// Core functions:
// 1. getApiKey() - from env or vault
// 2. clarifyIntent(userPrompt) - ask clarifying questions
// 3. buildSpec(answers) - create detailed specification
// 4. enhancePrompt(basePrompt) - add quality modifiers
// 5. generateImages(spec) - call Imagen API
// 6. saveImages(base64Images) - save to output dir
// 7. iterate(sessionId, modification) - refine existing generation
```

### API Call Example

```typescript
async function generateImages(config: ImagenConfig): Promise<string[]> {
  const apiKey = await getApiKey();

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${config.model}:predict`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify({
        instances: [{ prompt: config.prompt }],
        parameters: {
          sampleCount: config.numberOfImages,
          aspectRatio: config.aspectRatio,
          // imageSize only for Ultra/Standard
          personGeneration: config.personGeneration,
        },
      }),
    }
  );

  const data = await response.json();
  return data.predictions.map((p: any) => p.bytesBase64Encoded);
}
```

### Session Persistence

Store session data for iteration support:

```
~/.claude/output/images/sessions/
└── 2026-01-04-123456.json
    {
      "id": "2026-01-04-123456",
      "spec": { ... },
      "prompt": "...",
      "outputPaths": ["..."],
      "iterations": []
    }
```

---

## Command Definition

### commands/imagen.md

```markdown
Generate images using Google's Imagen API.

**Usage:**
/imagen [prompt]           # Start with optional initial prompt
/imagen iterate <id> <mod> # Iterate on previous generation
/imagen list               # List recent generations
/imagen view <id>          # View previous generation

**Workflow:**
1. Clarify intent (subject, style, mood, technical params)
2. Review detailed specification
3. Generate images (1-4 variations)
4. Iterate as needed

**Examples:**
/imagen a futuristic cityscape
/imagen iterate 2026-01-04-123456 "add flying cars"
/imagen list
```

---

## Skill Documentation

### skills/imagen/SKILL.md

```markdown
---
name: imagen
description: Generate images using Google Imagen API. Clarifies intent,
produces detailed specs, supports iteration. Use for any image generation request.
---

# Imagen - AI Image Generation

## When This Skill Activates

- User asks to "generate an image", "create a picture", "make an illustration"
- User invokes /imagen command
- User asks to iterate on a previously generated image

## Workflow

1. **Clarify Intent** - Ask about subject, style, mood, technical preferences
2. **Build Specification** - Create detailed prompt with enhancements
3. **Confirm** - Show spec and get user approval
4. **Generate** - Call Imagen API, save outputs
5. **Iterate** - Refine based on user feedback

## Prompt Enhancement

Automatically enhance prompts with:
- Quality modifiers: "high-quality", "4K", "HDR", "professional"
- Lighting descriptors based on mood
- Composition guidance based on aspect ratio
- Style-specific keywords

## Available Parameters

| Parameter | Options |
|-----------|---------|
| Model | standard, ultra, fast |
| Aspect Ratio | 1:1, 3:4, 4:3, 9:16, 16:9 |
| Variations | 1-4 |
| Resolution | 1K, 2K |
| People | none, adults, all |

## Error Handling

- Rate limit: Wait and retry with backoff
- Content filter: Suggest prompt modifications
- API error: Display error and suggest alternatives
```

---

## Implementation Order

1. [ ] Create skill directory structure
2. [ ] Implement `index.ts` with core API functions
3. [ ] Add intent clarification logic (uses AskUserQuestion pattern)
4. [ ] Add prompt enhancement engine
5. [ ] Implement session persistence for iteration
6. [ ] Create `/imagen` command
7. [ ] Update CLAUDE.md with imagen capability
8. [ ] Test with various prompts
9. [ ] Get AI peer review

---

## Integration with Existing Profile

### CLAUDE.md Addition

```markdown
## Image Generation

**Imagen Skill:** Generate images via `/imagen` or natural language.

Workflow: Clarify intent → Review spec → Generate → Iterate

Uses Gemini API (free tier). API key from Bitwarden or `GEMINI_API_KEY` env.
```

### Credential Flow

1. Check `GEMINI_API_KEY` environment variable
2. If not set, attempt vault API (`/vault-get gemini-api-key`)
3. If vault unavailable, prompt user to set env var

---

## Security Considerations

- API key never logged or displayed
- Images saved locally only (no external upload)
- SynthID watermark preserved (Google requirement)
- Content filtering via API (personGeneration param)

---

## Testing Plan

1. **Basic generation**: Simple prompt → 4 images
2. **Intent clarification**: Vague prompt triggers questions
3. **Specification review**: User sees and approves spec
4. **Iteration**: Modify existing generation
5. **Error handling**: Rate limit, content filter, network error
6. **Credential fallback**: Env var → vault → prompt

---

## Future Enhancements

- [ ] Image-to-image editing (when API supports)
- [ ] Prompt templates for common use cases
- [ ] Gallery viewer for past generations
- [ ] Integration with Puppeteer for web preview
- [ ] Batch generation from file

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| API rate limiting | Implement exponential backoff |
| Prompt injection | Sanitize user input |
| Large file storage | Auto-cleanup old images (configurable) |
| API changes | Version lock model, monitor changelog |
| Content policy violations | Use personGeneration param, warn user |
