---
name: imagen
description: Generate images using Google Gemini's native image generation. Clarifies intent, produces detailed specs, supports iteration. Use for any "generate image", "create picture", or "make illustration" request.
---

# Imagen - AI Image Generation

Generate images using Gemini's native image generation capability.

## When This Skill Activates

- User asks to "generate an image", "create a picture", "make an illustration"
- User invokes `/imagen` command
- User asks to iterate on a previously generated image

## API Configuration

### Azure OpenAI DALL-E 3 (Primary - No Geographic Restrictions)

**Endpoint:** `https://oai-bnx-shared.openai.azure.com/openai/deployments/dall-e-3/images/generations?api-version=2024-02-01`

**API Key Retrieval:**
```bash
az keyvault secret show --vault-name kv-bnx-shared --name openai-api-key --query value -o tsv
```

**Required Header:** `api-key: <key from above>`

### Gemini (Fallback - Geographic Restrictions Apply)

**Models:**
- `gemini-2.5-flash-preview-05-20` - Fast text-to-image
- `gemini-3-pro-image-preview` - Multi-turn editing, higher quality

**Endpoint:** `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`

**Required Header:** `x-goog-api-key: $GEMINI_API_KEY`

## Workflow

### Phase 1: Clarify Intent

Before generating, ASK the user about:

1. **Subject**: What is the main focus?
2. **Context**: Background, environment, setting?
3. **Style**: Photo, illustration, painting, sketch, digital art, 3D render?
4. **Mood**: Bright, dark, dramatic, whimsical, professional, vintage?
5. **Technical**: Aspect ratio (1:1, 16:9, 9:16, 4:3, 3:4)?

Use AskUserQuestion tool with options like:
```
Style: [Photorealistic, Digital Art, Illustration, Watercolor]
Aspect Ratio: [1:1 Square, 16:9 Landscape, 9:16 Portrait, 4:3 Standard]
```

### Phase 2: Build Specification

After clarification, show the user a detailed spec:

```markdown
## Image Generation Specification

**Prompt:** [Enhanced prompt with style, lighting, quality modifiers]

**Parameters:**
- Model: gemini-2.5-flash-preview-05-20
- Aspect Ratio: 16:9
- Resolution: 1K

**Enhancements Applied:**
- Added: "high quality, detailed, professional"
- Style keywords: [based on user choice]

Ready to generate? [Yes / Modify]
```

### Phase 3: Generate

**Azure DALL-E 3 (Primary):**

```bash
# Get API key
AZURE_OPENAI_KEY=$(az keyvault secret show --vault-name kv-bnx-shared --name openai-api-key --query value -o tsv)

curl -s -X POST \
  "https://oai-bnx-shared.openai.azure.com/openai/deployments/dall-e-3/images/generations?api-version=2024-02-01" \
  -H "api-key: $AZURE_OPENAI_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "PROMPT_HERE",
    "size": "1024x1024",
    "quality": "standard",
    "n": 1
  }'
```

DALL-E 3 sizes: `1024x1024`, `1792x1024` (landscape), `1024x1792` (portrait)

**Gemini (Fallback):**

```bash
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{"parts": [{"text": "PROMPT_HERE"}]}],
    "generationConfig": {
      "responseModalities": ["TEXT", "IMAGE"]
    }
  }'
```

### Phase 4: Save & Display

**For Azure DALL-E 3:**
1. Parse response for `data[0].url` (temporary URL valid ~1 hour)
2. Download with curl and save to `~/.claude/output/images/imagen-TIMESTAMP.png`
3. Use Read tool to display the image to user
4. Offer iteration options

**For Gemini:**
1. Parse response for `inlineData.data` (base64 image)
2. Decode and save to `~/.claude/output/images/imagen-TIMESTAMP.png`
3. Use Read tool to display the image to user
4. Offer iteration options

### Phase 5: Iteration

For iterations, modify the prompt and regenerate:
- "Make it darker/brighter"
- "Change to illustration style"
- "Add/remove elements"
- "Different angle/perspective"

## Prompt Enhancement

Automatically enhance prompts with:

| Style | Add Keywords |
|-------|-------------|
| Photo | "photorealistic, 4K, HDR, professional photography" |
| Illustration | "digital illustration, detailed, vibrant colors" |
| Watercolor | "watercolor painting, soft edges, artistic" |
| 3D | "3D render, octane render, volumetric lighting" |
| Sketch | "pencil sketch, detailed linework, shading" |

## Aspect Ratios

| Ratio | Use Case |
|-------|----------|
| `1:1` | Social media, icons |
| `16:9` | Landscape, presentations |
| `9:16` | Mobile, stories, portraits |
| `4:3` | Standard photos |
| `3:4` | Portrait orientation |

## Credential Handling

Check for API key in order:
1. `$GEMINI_API_KEY` environment variable
2. If not set, instruct user: "Set GEMINI_API_KEY environment variable with your Gemini API key from https://aistudio.google.com/apikey"

## Geographic Availability

**Azure DALL-E 3:** No geographic restrictions - works globally. Use as primary.

**Gemini:** Geo-restricted by IP address.
- Blocked: UK, EU, Australia, other regions
- Error: `"Image generation is not available in your country"`
- Solution: Use Azure DALL-E 3 instead (already configured above)

## Error Handling

| Error | Action |
|-------|--------|
| 400 "not available in your country" | Geographic restriction - see above |
| 403 Permission Denied | API key invalid or not set |
| 429 Rate Limited | Wait and retry with backoff |
| Content filtered | Suggest prompt modifications |
| Empty response | Retry or simplify prompt |

## Output Directory

Images saved to: `~/.claude/output/images/`
Filename format: `imagen-YYYY-MM-DD-HHMMSS.png`

## Example Session

```
User: Generate an image of a coffee shop

Claude: I'll help you create a coffee shop image. Let me clarify:

[AskUserQuestion]
- Style: Photorealistic / Illustration / Watercolor
- View: Interior / Exterior
- Mood: Cozy warm / Modern minimal / Vintage rustic
- Aspect: Square / Landscape / Portrait

User: Photorealistic interior, cozy warm, landscape

Claude: ## Image Specification

**Prompt:** A cozy coffee shop interior with warm Edison bulb lighting,
exposed brick walls, wooden tables and chairs, steam rising from coffee cups,
morning sunlight through large windows. Photorealistic, 4K, HDR,
professional interior photography.

**Parameters:** gemini-2.5-flash-preview-05-20, 16:9, 1K

Ready to generate?

User: Yes

Claude: [Generates image, saves to file, displays]

Generated: ~/.claude/output/images/imagen-2026-01-04-131500.png

Would you like to:
- Iterate (darker lighting, different angle, add people)
- Generate new variations
- Start fresh with new prompt
```
