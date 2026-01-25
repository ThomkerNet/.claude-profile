---
name: tts
description: Generate speech from text using Azure AI Speech. Creates audio files for testing Whisper transcription or voice notes. Supports British/American voices, prosody controls, WAV/MP3 output.
---

# TTS - Text-to-Speech Generation

Generate synthetic speech from text using Azure AI Speech service.

## When This Skill Activates

- User asks to "generate speech", "create audio", "text to speech"
- User invokes `/tts` command
- User wants to create test audio for Whisper transcription
- User needs synthetic voice notes

## API Configuration

**Endpoint:** `https://uksouth.tts.speech.microsoft.com/cognitiveservices/v1`

**API Key Retrieval:**
```bash
az keyvault secret show --vault-name kv-bnx-shared-01 --name speech-api-key --query value -o tsv
```

**Required Header:** `Ocp-Apim-Subscription-Key: <key from above>`

## CLI Tool

A CLI tool is available at `~/.claude/tools/azure-speech/tts`

```bash
tts [options] "text" [output_file]

Options:
  -v, --voice VOICE     Voice name (default: en-GB-SoniaNeural)
  -f, --format FORMAT   Output format: wav, mp3 (default: wav)
  -r, --rate RATE       Speech rate: x-slow, slow, medium, fast, x-fast
  -p, --pitch PITCH     Voice pitch: x-low, low, medium, high, x-high
  -l, --list-voices     List available voices
  --dry-run             Output SSML without calling API
  -h, --help            Show help
```

## Workflow

### Phase 1: Clarify Intent

Before generating, ASK the user about:

1. **Text**: What should be spoken?
2. **Voice**: Male or female? British or American?
3. **Format**: WAV (quality) or MP3 (smaller)?
4. **Prosody**: Fast/slow? High/low pitch?

Use AskUserQuestion tool with options like:
```
Voice: [Sonia (Female British), Ryan (Male British), Jenny (Female American)]
Format: [WAV (Best Quality), MP3 (Smaller File)]
Speed: [Normal, Fast, Slow]
```

### Phase 2: Build Specification

After clarification, show the user a detailed spec:

```markdown
## Speech Generation Specification

**Text:** [The text to synthesize]

**Parameters:**
- Voice: en-GB-SoniaNeural (Female, British)
- Format: WAV (riff-24khz-16bit-mono-pcm)
- Rate: medium
- Pitch: medium

**Output:** ~/.claude/output/audio/tts_20260122_143000.wav

Ready to generate? [Yes / Modify]
```

### Phase 3: Generate

**Using CLI tool (Preferred):**

```bash
# Simple usage
tts "Hello, this is a test of the speech synthesis system." output.wav

# With options
tts -v en-GB-RyanNeural -f mp3 -r fast "Quick announcement" announcement.mp3
```

**Using curl directly:**

```bash
# Get API key
AZURE_SPEECH_KEY=$(az keyvault secret show --vault-name kv-bnx-shared-01 --name speech-api-key --query value -o tsv)

curl -s -X POST "https://uksouth.tts.speech.microsoft.com/cognitiveservices/v1" \
  -H "Ocp-Apim-Subscription-Key: ${AZURE_SPEECH_KEY}" \
  -H "Content-Type: application/ssml+xml" \
  -H "X-Microsoft-OutputFormat: riff-24khz-16bit-mono-pcm" \
  -d '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-GB">
        <voice name="en-GB-SoniaNeural">Hello world</voice>
      </speak>' \
  -o output.wav
```

### Phase 4: Save & Verify

1. Audio saved to `~/.claude/output/audio/tts_TIMESTAMP.{wav,mp3}`
2. Verify file is non-empty
3. Report file path and size to user
4. Offer iteration options

### Phase 5: Iteration

For iterations, modify parameters and regenerate:
- "Try a male voice"
- "Make it faster"
- "Convert to MP3"
- "Different text"

## Available Voices

| Voice | Gender | Accent | Notes |
|-------|--------|--------|-------|
| `en-GB-SoniaNeural` | Female | British | Default, natural |
| `en-GB-RyanNeural` | Male | British | Professional |
| `en-GB-LibbyNeural` | Female | British | Warm |
| `en-GB-ThomasNeural` | Male | British | Mature |
| `en-US-JennyNeural` | Female | American | Clear |
| `en-US-GuyNeural` | Male | American | Conversational |

## Output Formats

| Format | Header | Use Case |
|--------|--------|----------|
| WAV | `riff-24khz-16bit-mono-pcm` | Best quality, testing |
| MP3 | `audio-24khz-160kbitrate-mono-mp3` | Smaller size, sharing |

## Prosody Controls

### Rate
| Value | Description |
|-------|-------------|
| `x-slow` | Very slow, deliberate |
| `slow` | Slower than normal |
| `medium` | Normal speed (default) |
| `fast` | Faster than normal |
| `x-fast` | Very fast |

### Pitch
| Value | Description |
|-------|-------------|
| `x-low` | Very deep |
| `low` | Deeper than normal |
| `medium` | Normal pitch (default) |
| `high` | Higher than normal |
| `x-high` | Very high |

## SSML Reference

For advanced control, SSML (Speech Synthesis Markup Language) is used:

```xml
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-GB">
    <voice name="en-GB-SoniaNeural">
        <prosody rate="fast" pitch="high">
            This text will be spoken quickly with a higher pitch.
        </prosody>
    </voice>
</speak>
```

## Credential Handling

Check for API key in order:
1. `$AZURE_SPEECH_KEY` environment variable
2. Key Vault fallback: `az keyvault secret show --vault-name kv-bnx-shared-01 --name speech-api-key`

## Error Handling

| Error | Action |
|-------|--------|
| 401 Unauthorized | API key invalid or not set |
| 429 Rate Limited | Wait and retry |
| Empty response | Check SSML syntax |
| Network timeout | Retry with longer timeout |
| Key Vault access denied | Check `az login` and permissions |

## Output Directory

Audio saved to: `~/.claude/output/audio/`
Filename format: `tts_YYYYMMDD_HHMMSS.{wav,mp3}`

## Use Case: BriefHours Testing

Primary purpose is generating test audio for Whisper transcription testing:

```bash
# Generate test voice note
tts "This is a test meeting note. The project deadline is next Friday. We need to complete the API integration by Wednesday." test_note.wav

# Test with Whisper
# (Use BriefHours Whisper batch transcription service)
```

## Example Session

```
User: Generate some test audio

Claude: I'll help you create test audio. Let me clarify:

[AskUserQuestion]
- Voice: Sonia (Female British) / Ryan (Male British) / Jenny (Female American)
- Format: WAV (Best Quality) / MP3 (Smaller)
- Speed: Normal / Fast / Slow

User: Sonia, WAV, Normal

Claude: What text should be spoken?

User: "Hello, this is a test of the BriefHours transcription system."

Claude: ## Speech Generation Specification

**Text:** Hello, this is a test of the BriefHours transcription system.

**Parameters:**
- Voice: en-GB-SoniaNeural (Female, British)
- Format: WAV
- Rate: medium

Ready to generate?

User: Yes

Claude: [Executes tts command]

Generated: ~/.claude/output/audio/tts_20260122_143500.wav (45.2 KB)

Would you like to:
- Generate with a different voice
- Change the text
- Convert to MP3
```
