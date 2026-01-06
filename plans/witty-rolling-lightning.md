# BriefHours-Inference Refactor Plan

## Summary

Transform BriefHours-Inference from a domain-specific time entry extraction service into a **pure Model Runner API** with no business logic. All BriefHours-specific logic moves to BriefHours-App.

**Key Changes:**
- Remove: `/v1/extract`, `/v1/pipeline` endpoints
- Add: `/v1/generate` (generic LLM endpoint)
- Delete: BriefHours-specific prompts and domain models
- Keep: `/v1/transcribe` (unchanged), health/metrics endpoints

---

## Phase 1: Delete Domain-Specific Files

### Step 1.1: Delete `src/utils/prompts.py`
- Contains `EXTRACTION_SYSTEM_PROMPT`, `EXTRACTION_USER_PROMPT`, `build_extraction_prompt()`
- 107 lines of BriefHours-specific code

### Step 1.2: Delete `src/models/time_entry.py`
- Contains `TimeEntry`, `ConfidenceScores`, `Ambiguity` dataclasses
- 67 lines of domain models
- **Note:** `TranscriptionResult` class may need to be preserved or moved

---

## Phase 2: Create New LLM Service

### Step 2.1: Create `src/services/llm.py` (new file)
Use the exact code from REFACTOR_SPEC.md:
- `LLMError` exception class
- `LLMService` class with:
  - `verify_connection()` - check Ollama availability
  - `generate(prompt, system_prompt, format, temperature)` - generic LLM call
  - `health_check()` - health status

### Step 2.2: Delete `src/services/extraction.py`
- Current file has 327 lines of extraction-specific logic
- Fully replaced by simpler `llm.py`

---

## Phase 3: Update Schemas

### Step 3.1: Modify `src/api/schemas.py`

**Remove these classes:**
- `ExtractionContext` (lines 37-50)
- `ExtractRequest` (lines 53-57)
- `PipelineRequest` (lines 60-72)
- `ConfidenceScores` (lines 107-114)
- `ExtractedEntry` (lines 117-127)
- `Ambiguity` (lines 130-135)
- `ExtractionResponse` (lines 138-145)
- `TranscriptionSummary` (lines 148-154)
- `EntrySummary` (lines 157-164)
- `PipelineResponse` (lines 168-174)

**Add these classes:**
```python
class GenerateRequest(BaseModel):
    prompt: str = Field(..., max_length=50000)
    system_prompt: str | None = Field(None, max_length=10000)
    format: Literal["json"] | None = None
    temperature: float = Field(0.1, ge=0.0, le=2.0)

class GenerateResponse(BaseModel):
    success: bool = True
    content: str
    model: str
    tokens: int
    processing_time_ms: int
```

---

## Phase 4: Update Routes

### Step 4.1: Modify `src/api/routes.py`

**Remove endpoints:**
- `/v1/extract` (lines 192-257)
- `/v1/pipeline` (lines 260-365)

**Add endpoint:**
- `/v1/generate` - generic LLM generation (code from spec)

**Update imports:**
- Remove extraction-specific schema imports
- Add `GenerateRequest`, `GenerateResponse`
- Change `ExtractionError` → `LLMError`

---

## Phase 5: Update Supporting Files

### Step 5.1: Simplify `src/services/pipeline.py`
Simplify to just GPU serialization:
- Keep the `asyncio.Semaphore(1)` for GPU memory contention prevention
- Remove all orchestration logic (combined transcription + extraction)
- Export a simple `with_gpu_lock()` helper for routes to use

### Step 5.2: Update `src/services/__init__.py`
```python
from src.services.transcription import WhisperService, TranscriptionError
from src.services.llm import LLMService, LLMError
from src.services.lifecycle import LifecycleManager
```

### Step 5.3: Update `src/main.py`
- Change `extraction` import to `llm`
- Update lifespan to initialize `LLMService` instead of extraction service

### Step 5.4: Update `src/services/lifecycle.py`
- Change import from `extraction` to `llm`
- Update service initialization

### Step 5.5: Update `src/config.py`
- Remove `max_known_clients`, `max_known_cases` config options (lines 45-46)

---

## Phase 6: Update Tests

### Step 6.1: Update `tests/conftest.py`
- Remove `TimeEntry`, `ExtractionResult`, `Ambiguity` imports
- Update `mock_llm_service` fixture for new `LLMService` interface

### Step 6.2: Update `tests/test_api.py`
- Remove `TestExtractEndpoint` class
- Remove pipeline endpoint tests
- Add `TestGenerateEndpoint` class with tests for `/v1/generate`

### Step 6.3: Delete extraction tests
Delete `tests/test_extraction.py` - extraction logic is being removed entirely. New LLM tests will be in `test_api.py`.

---

## Phase 7: Update Documentation

### Step 7.1: Update `README.md`
- Remove `/v1/extract` and `/v1/pipeline` documentation
- Add `/v1/generate` documentation with request/response examples

---

## Validation Checklist

After implementation:
- [ ] `poetry run pytest` passes
- [ ] `poetry run ruff check src/` passes
- [ ] `/health/ready` returns healthy
- [ ] `/v1/transcribe` still works
- [ ] `/v1/generate` works with prompts
- [ ] `/v1/generate` with `format: "json"` returns valid JSON
- [ ] `/v1/extract` returns 404
- [ ] `/v1/pipeline` returns 404
- [ ] No `TimeEntry`, `ExtractionContext` references remain
- [ ] No BriefHours-specific prompts remain

---

## Files Summary

| Action | File |
|--------|------|
| DELETE | `src/utils/prompts.py` |
| DELETE | `src/models/time_entry.py` |
| DELETE | `src/services/extraction.py` |
| CREATE | `src/services/llm.py` |
| MODIFY | `src/api/schemas.py` |
| MODIFY | `src/api/routes.py` |
| SIMPLIFY | `src/services/pipeline.py` |
| DELETE | `tests/test_extraction.py` |
| MODIFY | `src/services/__init__.py` |
| MODIFY | `src/main.py` |
| MODIFY | `src/services/lifecycle.py` |
| MODIFY | `src/config.py` |
| MODIFY | `tests/conftest.py` |
| MODIFY | `tests/test_api.py` |
| MODIFY | `README.md` |

---

## Notes

1. **GPU Serialization:** Keep semaphore for both transcription AND generation to prevent memory contention
2. **Breaking Change:** BriefHours-App must be updated to use `/v1/generate` before deploying this
3. **TranscriptionResult:** Check if this is used elsewhere and needs to be preserved
