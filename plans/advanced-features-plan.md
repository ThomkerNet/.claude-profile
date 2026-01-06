# Advanced Features Implementation Plan

## Overview

Implement 5 advanced features for BriefHours based on the specification:
1. Voice Note Reply Corrections
2. Weekly Insights
3. Case Health Dashboard
4. Smart Case Detection from Context
5. Solicitor Contact Book

**Total Estimated Effort:** 11-15 days

---

## Gemini Recommendations Summary

| Feature | Recommendation |
|---------|----------------|
| Voice Corrections | Use **separate lighter correction prompt**, not same extraction prompt |
| Weekly Insights | Generate **matplotlib images** for charts (cleaner than unicode blocks) |
| Case Dashboard | Start **on-demand**, build logic for proactive alerts as next step |
| Case Detection | Track `use_count` + `last_used_at` instead of decay algorithm |
| Solicitor Book | **Explicit association** only - auto-detection from transcripts too error-prone |

**General:** Build robust conversation state management for multi-step flows.

---

## Feature 1: Voice Note Reply Corrections

**Effort:** 2-3 days | **Priority:** High (core UX improvement)

### Current State
- `ConversationState` with `state_type` (idle, awaiting_confirmation, awaiting_correction)
- `VoiceHandler` checks state and blocks new entries if pending
- State persisted to PostgreSQL via `StateManager`

### Design Decisions

1. **Detection Method:** Check if incoming voice note is a reply to the bot's confirmation message using `message.reply_to_message`
2. **Separate Correction Prompt:** Use a lighter, targeted prompt (per Gemini) that constrains LLM to modification only
3. **State Enrichment:** Add `confirmation_message_id` to state for reply detection
4. **Correction History:** Track what was changed for audit trail

### Implementation Steps

**1.1 Update ConversationState Model** (`src/db/models.py`)
```python
class ConversationState(BaseModel):
    state_type: str
    pending_entries: list[TimeEntry] = Field(default_factory=list)
    original_transcript: str = ""
    submission_id: Optional[int] = None
    last_message_id: Optional[int] = None  # Keep for editing
    confirmation_message_id: Optional[int] = None  # NEW: for reply detection
    correction_history: list[dict] = Field(default_factory=list)  # NEW
    failed_operation: Optional[FailedOperation] = None
```

**1.2 Create Correction Extraction Service** (`src/services/correction.py`)
```python
CORRECTION_PROMPT = """
You are helping correct a time entry.

ORIGINAL EXTRACTION:
{original_json}

USER'S CORRECTION:
"{correction_transcript}"

Return ONLY the fields that should change. Set unchanged fields to null.
Output JSON: {"case_name": str|null, "hours": float|null, "activity": str|null,
              "date": str|null, "notes": str|null, "understood": bool,
              "clarification_needed": str|null}
"""

class CorrectionService:
    async def extract_corrections(
        self, original: dict, correction_transcript: str
    ) -> dict:
        """Extract field changes from correction voice note."""
```

**1.3 Update VoiceHandler** (`src/bot/handlers/voice.py`)
- Add `handle_correction_voice()` method
- Check `message.reply_to_message.message_id == state.confirmation_message_id`
- If correction: transcribe → extract corrections → apply changes → update state → edit message
- If new entry during pending state: ask user "Correction or new entry?"

**1.4 Update Formatting** (`src/bot/formatting.py`)
- `format_entries_grouped()`: Add hint "Reply with voice to correct"
- `format_extraction_with_changes()`: Highlight changed fields with "← changed"

**1.5 Add Correction History Table** (`src/db/schema.sql` - optional)
```sql
CREATE TABLE IF NOT EXISTS correction_history (
    id SERIAL PRIMARY KEY,
    submission_id INTEGER REFERENCES submissions(id),
    correction_transcript TEXT NOT NULL,
    changes_applied JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Edge Cases
- Ambiguous corrections ("the other case") → ask for clarification
- User sends unrelated voice note → offer choice: correct vs new entry
- Multiple rapid corrections → use state locking

---

## Feature 2: Weekly Insights

**Effort:** 2-3 days | **Priority:** High (engagement driver)

### Design Decisions

1. **Chart Rendering:** Use matplotlib for image generation (per Gemini)
2. **Scheduling:** APScheduler (already used for reminders) at Friday 6pm
3. **User Setting:** Add `weekly_insights_enabled` to user preferences
4. **Timezone Handling:** Use user's configured timezone for Friday detection

### Implementation Steps

**2.1 Add Dependencies** (`requirements.txt`)
```
matplotlib>=3.8.0
pandas>=2.0.0
```

**2.2 Create Insights Service** (`src/services/insights.py`)
```python
@dataclass
class WeeklyInsights:
    user_id: int
    week_start: date
    week_end: date
    total_hours: float
    case_count: int
    hours_by_case: list[tuple[str, float]]  # Top 5
    hours_by_activity: dict[str, float]
    hours_by_day: dict[date, float]
    previous_week_hours: float
    week_over_week_change: float
    busiest_day: tuple[date, float]
    hearing_count: int
    billable_amount: Decimal
    hours_by_funding: dict[str, float]

async def generate_weekly_insights(user_id: int, week_end: date = None) -> WeeklyInsights:
    """Generate insights for week ending on Friday."""
```

**2.3 Create Chart Generation** (`src/services/insights.py`)
```python
def generate_insights_chart(insights: WeeklyInsights) -> BytesIO:
    """Generate matplotlib chart image."""
    fig, axes = plt.subplots(2, 1, figsize=(8, 10))

    # Horizontal bar chart by case
    ax1 = axes[0]
    ax1.barh(case_names, hours, color='#4285F4')
    ax1.set_title('Hours by Case')

    # Activity breakdown pie chart
    ax2 = axes[1]
    ax2.pie(activity_hours, labels=activities, autopct='%1.0f%%')
    ax2.set_title('By Activity')

    buf = BytesIO()
    plt.savefig(buf, format='png', dpi=150, bbox_inches='tight')
    buf.seek(0)
    return buf
```

**2.4 Format Insights Message** (`src/bot/formatting.py`)
```python
def format_weekly_insights(insights: WeeklyInsights) -> str:
    """Format insights for Telegram caption."""
    # Include: total hours, week-over-week change, busiest day, billing summary
```

**2.5 Schedule Weekly Send** (`src/services/reminder.py`)
```python
async def send_weekly_insights_to_all(context):
    """Send Friday 6pm insights to all enabled users."""
    users = await repo.get_users_with_weekly_insights_enabled()
    for user in users:
        insights = await generate_weekly_insights(user.id)
        if insights.total_hours > 0:
            chart = generate_insights_chart(insights)
            caption = format_weekly_insights(insights)
            await context.bot.send_photo(
                chat_id=user.telegram_id,
                photo=chart,
                caption=caption
            )
```

**2.6 Add User Setting** (`src/db/schema.sql`)
```sql
ALTER TABLE users ADD COLUMN weekly_insights BOOLEAN DEFAULT TRUE;
```

**2.7 Add /week Command Enhancement** (`src/bot/handlers/commands.py`)
- Add "Previous Week" button
- Generate chart on demand

---

## Feature 3: Case Health Dashboard

**Effort:** 2-3 days | **Priority:** Medium (practice management value)

### Design Decisions

1. **On-Demand First:** `/case [name]` shows dashboard (per Gemini)
2. **Proactive Alerts:** Add later as scheduled job checking fixed-fee cases
3. **Profitability Threshold:** Default £100/hr, configurable per user

### Implementation Steps

**3.1 Create Dashboard Service** (`src/services/dashboard.py`)
```python
@dataclass
class CaseDashboard:
    case_id: int
    short_name: str
    funding_type: FundingType
    hourly_rate: Optional[Decimal]
    fixed_fee_amount: Optional[Decimal]
    total_hours: float
    this_month_hours: float
    last_month_hours: float
    total_billed: Decimal
    effective_rate: Decimal
    profitability_status: str  # 'good', 'warning', 'poor'
    hours_by_activity: dict[str, float]
    hours_by_month: list[tuple[str, float]]
    recent_entries: list[dict]
    upcoming_hearings: list[dict]
    weekly_effective_rates: list[tuple[date, Decimal]]  # For trend

async def generate_case_dashboard(case_id: int) -> CaseDashboard:
    """Generate comprehensive case analytics."""
```

**3.2 Add Case Schema Fields** (`src/db/schema.sql`)
```sql
ALTER TABLE cases ADD COLUMN hourly_rate NUMERIC(10,2);
ALTER TABLE cases ADD COLUMN fixed_fee_amount NUMERIC(10,2);
ALTER TABLE cases ADD COLUMN case_ref TEXT;
```

**3.3 Format Dashboard** (`src/bot/formatting.py`)
```python
def format_case_dashboard(dashboard: CaseDashboard) -> str:
    """Format case dashboard with profitability indicators."""
```

**3.4 Update /case Command** (`src/bot/handlers/commands.py`)
- `/case` → list all cases with quick stats
- `/case [name]` → show full dashboard
- Add buttons: Add Time, Export, Edit, Archive

**3.5 Add Profitability Alert (Future)**
```python
async def check_case_profitability_alerts():
    """Daily job to check fixed-fee case profitability."""
    fixed_fee_cases = await repo.get_active_fixed_fee_cases()
    for case in fixed_fee_cases:
        effective_rate = case.fixed_fee_amount / case.total_hours
        if effective_rate < user.profitability_threshold:
            await send_profitability_alert(case)
```

---

## Feature 4: Smart Case Detection from Context

**Effort:** 3-4 days | **Priority:** Medium (learning UX)

### Design Decisions

1. **Dedicated Alias Table:** Separate `case_aliases` table (not just JSONB column) for better querying
2. **Tracking:** `use_count` + `last_used_at` (per Gemini, no decay algorithm)
3. **Match Priority:** Exact → Alias → Fuzzy
4. **Learning Sources:** User confirmation, corrections, proactive extraction

### Implementation Steps

**4.1 Create Alias Table** (`src/db/schema.sql`)
```sql
CREATE TABLE IF NOT EXISTS case_aliases (
    id SERIAL PRIMARY KEY,
    case_id INTEGER REFERENCES cases(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,
    alias_normalized TEXT NOT NULL,
    source TEXT NOT NULL,  -- 'user_created', 'learned', 'extracted'
    use_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    UNIQUE(case_id, alias_normalized)
);
CREATE INDEX idx_case_aliases_normalized ON case_aliases(alias_normalized);
```

**4.2 Update Repository** (`src/db/repository.py`)
```python
async def find_case_with_aliases(self, user_id: int, query: str) -> Optional[Case]:
    """Find case by name, alias, or fuzzy match."""
    normalized = normalize_case_name(query)

    # 1. Exact match on short_name
    case = await self.find_exact_case(user_id, query)
    if case:
        return case

    # 2. Exact match on aliases
    case = await self.find_by_alias(user_id, normalized)
    if case:
        await self.record_alias_usage(case.id, normalized)
        return case

    # 3. Fuzzy match (existing logic)
    return await self.find_case_fuzzy(user_id, query)

async def create_alias(self, case_id: int, alias: str, source: str = 'learned'):
    """Create or update alias for a case."""

async def record_alias_usage(self, case_id: int, alias_normalized: str):
    """Increment use_count and update last_used_at."""
```

**4.3 Handle Unknown Case Flow** (`src/bot/handlers/callbacks.py`)
```python
async def handle_unknown_case(update, context, case_reference: str, pending_entry):
    """Show case selection when reference doesn't match."""
    recent_cases = await repo.get_recent_cases(user_id, limit=5)

    keyboard = [
        [InlineKeyboardButton("➕ New Case", callback_data="case_new")],
        *[[InlineKeyboardButton(c.short_name, callback_data=f"case_link_{c.id}")]
          for c in recent_cases]
    ]

    await update.message.reply_text(
        f"🤔 I don't recognise \"{case_reference}\"\n\nIs this new, or one of these?",
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

    # Store reference for learning
    context.user_data['unknown_case_reference'] = case_reference
```

**4.4 Learn Alias on Link** (`src/bot/handlers/callbacks.py`)
```python
@callback_query_handler(pattern="^case_link_")
async def link_case_to_alias(callback, context):
    """Link unknown reference to existing case and learn alias."""
    case_id = int(callback.data.split('_')[2])
    alias = context.user_data.get('unknown_case_reference')

    await repo.create_alias(case_id, alias, source='learned')
    # Update pending entry with correct case
```

**4.5 Add /aliases Command** (`src/bot/handlers/commands.py`)
```python
async def aliases_command(update, context):
    """View and manage case aliases."""
    # /aliases → list all
    # /aliases Smith remove "the fraud case" → remove alias
```

**4.6 Proactive Learning** (after entry confirmation)
```python
async def learn_from_confirmed_entry(entry: Entry, transcript: str):
    """Extract and learn potential aliases from transcript."""
    # Use LLM to extract alternative references
    # Create low-confidence aliases for descriptors
```

### Edge Cases
- Ambiguous match (multiple "Smith" cases) → disambiguation keyboard
- Very short aliases (< 3 chars) → skip
- Common words ("the case", "that one") → skip

---

## Feature 5: Solicitor Contact Book

**Effort:** 2-3 days | **Priority:** Low (nice to have)

### Design Decisions

1. **Explicit Association Only:** No auto-detection from transcripts (per Gemini)
2. **Firm-Centric Model:** Solicitors belong to firms, linked to cases
3. **Simple CRUD:** Conversational flows, inline keyboards

### Implementation Steps

**5.1 Create Tables** (`src/db/schema.sql`)
```sql
CREATE TABLE IF NOT EXISTS solicitors (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    firm_name TEXT NOT NULL,
    firm_name_normalized TEXT NOT NULL,
    contact_name TEXT,
    contact_email TEXT,
    contact_phone TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, firm_name_normalized)
);
CREATE INDEX idx_solicitors_user ON solicitors(user_id);

-- Link cases to solicitors
ALTER TABLE cases ADD COLUMN solicitor_id INTEGER REFERENCES solicitors(id);
```

**5.2 Create Solicitor Models** (`src/db/models.py`)
```python
class Solicitor(BaseModel):
    id: int
    user_id: int
    firm_name: str
    contact_name: Optional[str] = None
    contact_email: Optional[str] = None
    contact_phone: Optional[str] = None
    notes: Optional[str] = None

class SolicitorStats(BaseModel):
    solicitor_id: int
    firm_name: str
    total_cases: int
    active_cases: int
    total_hours: float
    total_billed: Decimal
```

**5.3 Create Repository Methods** (`src/db/repository.py`)
```python
async def create_solicitor(self, user_id: int, firm_name: str, ...) -> int
async def get_solicitors(self, user_id: int) -> list[Solicitor]
async def get_solicitor_stats(self, solicitor_id: int) -> SolicitorStats
async def link_case_to_solicitor(self, case_id: int, solicitor_id: int)
```

**5.4 Add Commands** (`src/bot/handlers/commands.py`)
```python
async def solicitors_command(update, context):
    """List all solicitors or show details."""
    # /solicitors → list with stats
    # /solicitor [name] → show details

async def addsolicitor_command(update, context):
    """Add new solicitor (conversational flow)."""
```

**5.5 Integrate with Case Creation**
- When creating new case, ask "Who is the instructing solicitor?"
- Show recent solicitors as buttons + "New Solicitor" option

**5.6 Format Solicitor Details** (`src/bot/formatting.py`)
```python
def format_solicitor_details(solicitor: Solicitor, stats: SolicitorStats) -> str:
    """Format solicitor profile with stats."""
```

---

## Implementation Order

| Phase | Feature | Days | Dependencies |
|-------|---------|------|--------------|
| 1 | Voice Reply Corrections | 2-3 | None |
| 2 | Weekly Insights | 2-3 | None |
| 3 | Case Health Dashboard | 2-3 | None |
| 4 | Smart Case Detection | 3-4 | None (enhances existing) |
| 5 | Solicitor Contact Book | 2-3 | None |

**Parallelization:** Features 1-3 can be done in parallel. Feature 4 builds on existing case matching. Feature 5 is standalone.

---

## Database Migrations Summary

```sql
-- Feature 1: Voice Corrections
-- (No schema changes, uses existing state_data JSONB)

-- Feature 2: Weekly Insights
ALTER TABLE users ADD COLUMN weekly_insights BOOLEAN DEFAULT TRUE;

-- Feature 3: Case Dashboard
ALTER TABLE cases ADD COLUMN hourly_rate NUMERIC(10,2);
ALTER TABLE cases ADD COLUMN fixed_fee_amount NUMERIC(10,2);
ALTER TABLE cases ADD COLUMN case_ref TEXT;

-- Feature 4: Smart Case Detection
CREATE TABLE case_aliases (...);

-- Feature 5: Solicitor Book
CREATE TABLE solicitors (...);
ALTER TABLE cases ADD COLUMN solicitor_id INTEGER REFERENCES solicitors(id);
```

---

## New Dependencies

```
# requirements.txt additions
matplotlib>=3.8.0
pandas>=2.0.0
```

---

## Files to Create/Modify

| File | Changes |
|------|---------|
| `src/services/correction.py` | NEW: Correction extraction service |
| `src/services/insights.py` | NEW: Weekly insights + chart generation |
| `src/services/dashboard.py` | NEW: Case dashboard analytics |
| `src/db/models.py` | Update ConversationState, add Solicitor models |
| `src/db/repository.py` | Add alias methods, solicitor CRUD, dashboard queries |
| `src/db/schema.sql` | New tables, column additions |
| `src/db/connection.py` | Migrations for new columns/tables |
| `src/bot/handlers/voice.py` | Voice correction flow |
| `src/bot/handlers/commands.py` | /week enhancement, /case dashboard, /aliases, /solicitors |
| `src/bot/handlers/callbacks.py` | Unknown case flow, alias linking |
| `src/bot/formatting.py` | New formatters for all features |
| `src/bot/keyboards.py` | New keyboards for case selection, solicitor selection |
| `requirements.txt` | matplotlib, pandas |

---

## Testing Checklist

### Voice Corrections
- [ ] Reply to confirmation with correction updates entry
- [ ] Multiple field correction works
- [ ] Implicit single-word correction works ("Jones")
- [ ] Ambiguous correction prompts for clarification
- [ ] Correction history tracked

### Weekly Insights
- [ ] Chart generates correctly
- [ ] Empty week handled gracefully
- [ ] Week-over-week comparison accurate
- [ ] Scheduled send at Friday 6pm works
- [ ] User can disable via settings

### Case Dashboard
- [ ] All funding types display correctly
- [ ] Fixed fee profitability calculation accurate
- [ ] Activity breakdown correct
- [ ] Recent entries show
- [ ] Archive/export buttons work

### Smart Case Detection
- [ ] Exact match works
- [ ] Alias match works
- [ ] Fuzzy match works
- [ ] New alias learned on link
- [ ] Alias management command works
- [ ] Ambiguous cases show disambiguation

### Solicitor Book
- [ ] CRUD operations work
- [ ] Stats calculate correctly
- [ ] Case linking works
- [ ] Search works
