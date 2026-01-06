Generate images using Google Gemini's native image generation.

## Workflow

1. **Clarify Intent** - Ask about subject, style, mood, aspect ratio
2. **Build Specification** - Create detailed prompt with enhancements
3. **Confirm** - Show spec and get user approval before generating
4. **Generate** - Call Gemini API with enhanced prompt
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

After user confirms spec, generate using:

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

1. Parse JSON response for `candidates[0].content.parts`
2. Find part with `inlineData.data` (base64 PNG)
3. Decode and save to `~/.claude/output/images/imagen-TIMESTAMP.png`
4. Use Read tool to display image to user
5. Offer iteration options

## Iteration

After generation, offer:
- Modify lighting/mood
- Change style
- Add/remove elements
- Adjust composition
- Try different aspect ratio

## Credential Check

Before first generation, verify `$GEMINI_API_KEY` is set:
```bash
[ -n "$GEMINI_API_KEY" ] && echo "API key configured" || echo "Set GEMINI_API_KEY from https://aistudio.google.com/apikey"
```

## Examples

```
/imagen a futuristic cityscape
/imagen logo for a coffee company
/imagen portrait of a robot artist
```

Start with: $ARGUMENTS
