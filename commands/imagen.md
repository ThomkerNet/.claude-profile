Generate images using Azure DALL-E 3 (primary) or Google Gemini (fallback).

## Workflow

1. **Clarify Intent** - Ask about subject, style, mood, aspect ratio
2. **Build Specification** - Create detailed prompt with enhancements
3. **Confirm** - Show spec and get user approval before generating
4. **Generate** - Call Azure DALL-E 3 (or Gemini fallback) with enhanced prompt
5. **Iterate** - Refine based on user feedback

## Intent Clarification

Before generating, use AskUserQuestion to clarify:

**Style Options:**
- Photorealistic (add: "4K, HDR, professional photography")
- Digital Art (add: "digital illustration, vibrant, detailed")
- Watercolor (add: "watercolor painting, soft, artistic")
- 3D Render (add: "octane render, volumetric lighting")
- Sketch (add: "pencil sketch, linework, shading")

**Aspect Ratio Options:**
- 1:1 Square (social media, icons)
- 16:9 Landscape (presentations, banners)
- 9:16 Portrait (mobile, stories)
- 4:3 Standard (photos)

**Mood Options:**
- Bright & Cheerful
- Dark & Moody
- Warm & Cozy
- Cool & Professional
- Vintage & Nostalgic

## Generation

### Azure DALL-E 3 (Primary - No Geographic Restrictions)

```bash
AZURE_OPENAI_KEY=$(az keyvault secret show --vault-name kv-bnx-shared --name openai-api-key --query value -o tsv)

curl -s -X POST \
  "https://oai-bnx-shared.openai.azure.com/openai/deployments/dall-e-3/images/generations?api-version=2024-02-01" \
  -H "api-key: $AZURE_OPENAI_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "ENHANCED_PROMPT",
    "size": "1024x1024",
    "quality": "standard",
    "n": 1
  }'
```

DALL-E 3 sizes: `1024x1024`, `1792x1024` (landscape), `1024x1792` (portrait)

### Gemini (Fallback - Geographic Restrictions Apply)

```bash
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{"parts": [{"text": "ENHANCED_PROMPT"}]}],
    "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]}
  }'
```

## Output Handling

**Azure:** Parse `data[0].url` (temporary URL ~1 hour), download and save.
**Gemini:** Parse `candidates[0].content.parts` for `inlineData.data` (base64 PNG), decode and save.

Save to `~/.claude/output/images/imagen-TIMESTAMP.png`, then use Read tool to display.

## Iteration

After generation, offer:
- Modify lighting/mood
- Change style
- Add/remove elements
- Adjust composition
- Try different aspect ratio

## Examples

```
/imagen a futuristic cityscape
/imagen logo for a coffee company
/imagen portrait of a robot artist
```

Start with: $ARGUMENTS
