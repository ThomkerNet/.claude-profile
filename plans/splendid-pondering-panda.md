# BriefHours Onboarding Flow Implementation Plan

## Overview

Implement guided onboarding to achieve **first successful entry in under 60 seconds**.

**Target Metric:** Activation rate (3+ entries in first 7 days)

---

## Critical Issues Identified (from review)

| Issue | Fix |
|-------|-----|
| Callback routing conflict - existing handler is catch-all | Integrate into `CallbackHandler` with prefix routing, ensure prefix checks come BEFORE catch-all |
| NULL onboarding_state for existing users | Default to `'onboarding_complete'` in migration (not NULL) so existing users skip onboarding |
| Quick-add state lost on restart | Use `context.user_data` (single-worker PTB is fine; note: multi-worker needs DB/Redis backend) |
| Test entry cache persistence | Store entry_id on User model (simple for single-user); ~~OR ephemeral table for multi-user~~ |
| Message constants scattered | Move to `formatting.py` |
| Telegram callback_data limit | Keep callback_data under 64 bytes (current prefixes are fine) |
| First voice idempotency | Handle re-sends gracefully - check if pending entry exists before creating new |
| Onboarding events retention | Add created_at index, consider 90-day retention policy later |

## Phase 1: Database Changes

### 1.1 Add Onboarding State to Users Table

**File:** `src/db/models.py`
```python
class User(BaseModel):
    # ... existing fields ...
    # States: new, awaiting_first_voice, onboarding_complete
    # DB default is 'onboarding_complete' for existing users
    # New users get 'new' set explicitly in get_or_create_user()
    onboarding_state: str = "onboarding_complete"
    onboarding_started_at: Optional[datetime] = None
    onboarding_completed_at: Optional[datetime] = None
    test_entry_id: Optional[int] = None  # For "delete test entry" feature
```

**File:** `src/db/connection.py` - Add migrations:
```python
# Migration: Add onboarding_state to users
# IMPORTANT: Default 'onboarding_complete' so existing users skip onboarding
# New users will have state set to 'new' explicitly in get_or_create_user()
if not await column_exists('users', 'onboarding_state'):
    await conn.execute("ALTER TABLE users ADD COLUMN onboarding_state TEXT DEFAULT 'onboarding_complete'")

if not await column_exists('users', 'onboarding_started_at'):
    await conn.execute("ALTER TABLE users ADD COLUMN onboarding_started_at TIMESTAMPTZ")

if not await column_exists('users', 'onboarding_completed_at'):
    await conn.execute("ALTER TABLE users ADD COLUMN onboarding_completed_at TIMESTAMPTZ")

if not await column_exists('users', 'test_entry_id'):
    await conn.execute("ALTER TABLE users ADD COLUMN test_entry_id INTEGER REFERENCES time_entries(id) ON DELETE SET NULL")
```

### 1.2 Add Onboarding Events Table

**File:** `src/db/schema.sql` - Add table:
```sql
CREATE TABLE IF NOT EXISTS onboarding_events (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    event_type TEXT NOT NULL,
    event_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_onboarding_events_user ON onboarding_events(user_id);
```

**File:** `src/db/connection.py` - Add migration:
```python
# Migration: Create onboarding_events table
await conn.execute("""
    CREATE TABLE IF NOT EXISTS onboarding_events (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id),
        event_type TEXT NOT NULL,
        event_data JSONB,
        created_at TIMESTAMPTZ DEFAULT NOW()
    )
""")
await conn.execute("CREATE INDEX IF NOT EXISTS idx_onboarding_events_user ON onboarding_events(user_id)")
```

---

## Phase 2: Repository Updates

**File:** `src/db/repository.py`

### 2.1 Update User Methods
- Update `get_or_create_user()` to read onboarding fields
- Update `get_user_by_telegram_id()` to include onboarding fields
- Add `update_onboarding_state(user_id, state, completed=False)`

### 2.2 Add Event Logging
```python
async def log_onboarding_event(
    self,
    user_id: int,
    event_type: str,
    event_data: Optional[dict] = None,
) -> int:
    """Log onboarding event for analytics."""
```

### 2.3 Add Test Entry Tracking
```python
async def mark_entry_as_test(self, entry_id: int) -> bool:
    """Mark an entry as a test entry (for deletion)."""

async def delete_test_entry(self, entry_id: int, user_id: int) -> bool:
    """Delete a test entry created during onboarding."""
```

---

## Phase 3: Onboarding Keyboards

**File:** `src/bot/keyboards.py` - Add new keyboards:

```python
def build_welcome_keyboard() -> InlineKeyboardMarkup:
    """Welcome message keyboard."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("I'll send a voice note", callback_data="onboard_ready")],
        [InlineKeyboardButton("Show me how it works first", callback_data="onboard_demo")],
    ])

def build_demo_keyboard() -> InlineKeyboardMarkup:
    """After demo keyboard."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("Send a voice note", callback_data="onboard_ready")],
        [InlineKeyboardButton("Maybe later", callback_data="onboard_later")],
    ])

def build_first_confirm_keyboard(pending_id: int) -> InlineKeyboardMarkup:
    """First entry confirmation keyboard."""
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("Looks right!", callback_data=f"onboard_confirm:{pending_id}"),
            InlineKeyboardButton("Not quite", callback_data=f"onboard_edit:{pending_id}"),
        ]
    ])

def build_first_success_keyboard() -> InlineKeyboardMarkup:
    """After first entry success."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("Add my cases now", callback_data="onboard_add_cases")],
        [InlineKeyboardButton("Delete this test entry", callback_data="onboard_delete_test")],
        [InlineKeyboardButton("I'm all set", callback_data="onboard_complete")],
    ])

def build_quick_activity_keyboard(recent_cases: list) -> InlineKeyboardMarkup:
    """Quick-tap daily reminder keyboard."""
    buttons = [
        [InlineKeyboardButton("Voice note", callback_data="reminder_voice")]
    ]
    buttons.append([
        InlineKeyboardButton("Hearing", callback_data="quick_hearing"),
        InlineKeyboardButton("Drafting", callback_data="quick_drafting"),
    ])
    buttons.append([
        InlineKeyboardButton("Conference", callback_data="quick_conference"),
        InlineKeyboardButton("Prep", callback_data="quick_prep"),
    ])
    buttons.append([
        InlineKeyboardButton("That's everything", callback_data="reminder_done"),
    ])
    return InlineKeyboardMarkup(buttons)

def build_quick_case_keyboard(pending_id: int, cases: list) -> InlineKeyboardMarkup:
    """Case selection for quick-add."""
    buttons = []
    for case in cases[:5]:
        buttons.append([
            InlineKeyboardButton(case.short_name, callback_data=f"quick_case:{case.id}")
        ])
    buttons.append([InlineKeyboardButton("Other case", callback_data="quick_case_other")])
    buttons.append([InlineKeyboardButton("Back", callback_data="quick_back")])
    return InlineKeyboardMarkup(buttons)

def build_quick_hours_keyboard(activity: str) -> InlineKeyboardMarkup:
    """Duration selection for quick-add."""
    if activity in ['hearing', 'trial']:
        buttons = [
            [
                InlineKeyboardButton("Half day (3h)", callback_data="quick_hours:3"),
                InlineKeyboardButton("Full day (6h)", callback_data="quick_hours:6"),
            ],
            [
                InlineKeyboardButton("1h", callback_data="quick_hours:1"),
                InlineKeyboardButton("2h", callback_data="quick_hours:2"),
                InlineKeyboardButton("4h", callback_data="quick_hours:4"),
            ],
        ]
    else:
        buttons = [
            [
                InlineKeyboardButton("30m", callback_data="quick_hours:0.5"),
                InlineKeyboardButton("1h", callback_data="quick_hours:1"),
                InlineKeyboardButton("1.5h", callback_data="quick_hours:1.5"),
            ],
            [
                InlineKeyboardButton("2h", callback_data="quick_hours:2"),
                InlineKeyboardButton("3h", callback_data="quick_hours:3"),
                InlineKeyboardButton("4h", callback_data="quick_hours:4"),
            ],
        ]
    buttons.append([InlineKeyboardButton("Custom", callback_data="quick_hours_custom")])
    buttons.append([InlineKeyboardButton("Back", callback_data="quick_back_case")])
    return InlineKeyboardMarkup(buttons)
```

---

## Phase 4: Integrate Onboarding into Existing CallbackHandler

**File:** `src/bot/handlers/callbacks.py` (MODIFY - not new file)

Add onboarding callback routing to existing `handle()` method:

```python
async def handle(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Route callbacks based on prefix."""
    query = update.callback_query
    await query.answer()

    # ... existing routing ...

    # Onboarding callbacks
    if query.data.startswith("onboard_"):
        await self._handle_onboarding_callback(query, db_user, context)
        return

    # Quick-add callbacks (for daily prompts)
    if query.data.startswith("quick_") or query.data.startswith("reminder_"):
        await self._handle_quick_add_callback(query, db_user, context)
        return

    # ... rest of existing code ...

async def _handle_onboarding_callback(self, query, db_user, context):
    """Handle onboarding flow callbacks."""
    if query.data == "onboard_ready":
        await self._onboard_ready(query)
    elif query.data == "onboard_demo":
        await self._onboard_demo(query)
    elif query.data == "onboard_later":
        await self._onboard_later(query)
    elif query.data.startswith("onboard_confirm:"):
        await self._onboard_first_confirm(query, db_user, context)
    elif query.data.startswith("onboard_edit:"):
        await self._onboard_first_edit(query, db_user)
    elif query.data == "onboard_delete_test":
        await self._onboard_delete_test(query, db_user)
    elif query.data == "onboard_add_cases":
        await self._onboard_add_cases(query, db_user)
    elif query.data == "onboard_complete":
        await self._onboard_complete(query, db_user)

async def _handle_quick_add_callback(self, query, db_user, context):
    """Handle quick-tap entry callbacks from daily prompts."""
    # Use context.user_data for state persistence (survives restarts via PTB)
    if query.data.startswith("quick_"):
        action = query.data[6:]  # Remove "quick_" prefix
        if action in ("hearing", "drafting", "conference", "prep"):
            await self._quick_activity_select(query, db_user, action, context)
        elif action.startswith("case:"):
            await self._quick_case_select(query, db_user, context)
        elif action.startswith("hours:"):
            await self._quick_hours_select(query, db_user, context)
        # ... etc
    elif query.data == "reminder_done":
        await self._reminder_done(query, db_user)
```

**Key Change:** Use `context.user_data` for quick-add state (persisted by PTB):

---

## Phase 5: Update Commands Handler

**File:** `src/bot/handlers/commands.py`

### 5.1 Update `/start` Command

```python
async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Welcome message with onboarding flow."""
    user = update.effective_user
    db_user = await self.repo.get_or_create_user(...)

    # Check onboarding state
    if db_user.onboarding_state == "onboarding_complete":
        # Returning user - simple welcome
        await update.message.reply_text(
            "Welcome back! Send a voice note to log time, or /help for commands."
        )
        return

    # New user - start guided onboarding
    await self.repo.update_onboarding_state(db_user.id, "awaiting_first_voice")
    await self.repo.log_onboarding_event(db_user.id, "onboarding_started")

    await update.message.reply_text(
        WELCOME_MESSAGE,
        parse_mode='Markdown',
        reply_markup=build_welcome_keyboard()
    )
```

### 5.2 Message Constants

```python
WELCOME_MESSAGE = """
Welcome to BriefHours!

I help barristers track time with voice notes.

Let's try it now - takes 30 seconds.

*Send me a voice note saying something like:*

_"2 hours on Smith this morning, drafting a skeleton"_

Just make it up if you like. You can delete it after.
"""

DEMO_MESSAGE = """
*Here's how it works:*

*1. You send a voice note:*
_"Hour and a half on Jones, conference with the sol"_

*2. I extract the details:*
- Case: Jones
- Hours: 1.5h
- Activity: Conference

*3. You confirm with one tap*

*4. End of month:* /export gives you a PDF for your clerks

That's it. No forms, no typing, no app to open.

Ready to try?
"""

FIRST_SUCCESS_MESSAGE = """
*That's it. That's the whole thing.*

You just logged time without:
- Opening an app
- Typing anything
- Filling in forms

From now on, just send voice notes anytime.

I'll prompt you at 6pm if you forget.

*Quick setup (optional):*
- /cases - add your current matters
- /settings - change reminder time
- /help - see all commands

Or just keep sending voice notes. I'll learn your cases as you go.
"""
```

---

## Phase 6: Update Voice Handler

**File:** `src/bot/handlers/voice.py`

### 6.1 Add First Voice Note Special Handling

```python
async def handle(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
    # ... existing code ...

    # Check if this is user's first voice note (onboarding)
    if db_user.onboarding_state in ("new", "awaiting_first_voice"):
        await self._handle_first_voice_note(update, context, db_user)
        return

    # ... existing regular voice handling ...

async def _handle_first_voice_note(self, update, context, db_user):
    """Handle first voice note during onboarding."""
    # IDEMPOTENCY: Check if pending entry already exists (user re-sent voice)
    # If so, update it rather than creating duplicate

    # Similar to regular flow but with:
    # - Onboarding-specific confirmation message
    # - First confirm keyboard (build_first_confirm_keyboard)
    # - Track onboarding event
    # - Store entry_id on user.test_entry_id for potential deletion
```

---

## Phase 7: Update Scheduler for Quick-Tap Prompts

**File:** `src/services/scheduler.py`

### 7.1 Update `_send_reminder` Method

```python
async def _send_reminder(self, context):
    """Send context-aware reminder with quick-tap options."""
    # ... existing setup ...

    today_entries = await self.repo.get_entries_for_date(user_id, today)
    recent_cases = await self.repo.get_recent_cases(user_id, limit=4)

    if today_entries:
        total_hours = sum(e.get("hours", 0) for e in today_entries)
        message = self._format_reminder_with_entries(total_hours, today_entries)
    else:
        message = self._format_reminder_empty()

    keyboard = build_quick_activity_keyboard(recent_cases)

    await context.bot.send_message(
        chat_id=telegram_id,
        text=message,
        parse_mode='Markdown',
        reply_markup=keyboard
    )
```

---

## Phase 8: Quick-Add Handler

**File:** `src/bot/handlers/quick_add.py` (NEW)

```python
class QuickAddHandler:
    """Handles quick-tap time entry from daily prompts."""

    def __init__(self, repo: Repository, state: StateManager):
        self.repo = repo
        self.state = state
        self._quick_add_cache = {}  # user_id -> {activity, case_id, case_name}

    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Route quick-add callbacks."""
        query = update.callback_query
        await query.answer()

        if query.data.startswith("quick_"):
            activity = query.data.replace("quick_", "")
            if activity in ("hearing", "drafting", "conference", "prep"):
                await self._handle_activity_select(query, activity)
            elif activity.startswith("case:"):
                await self._handle_case_select(query)
            elif activity.startswith("hours:"):
                await self._handle_hours_select(query)
            elif activity == "case_other":
                await self._handle_case_other(query)
            elif activity == "hours_custom":
                await self._handle_hours_custom(query)
            elif activity == "back":
                await self._handle_back(query)
            elif activity == "back_case":
                await self._handle_back_case(query)
        elif query.data == "reminder_voice":
            await self._handle_voice_prompt(query)
        elif query.data == "reminder_done":
            await self._handle_done(query)
```

---

## Phase 9: Case Priming Flow

**File:** `src/bot/handlers/onboarding.py` - Add methods:

```python
async def _handle_add_cases(self, query):
    """Start case priming flow."""
    await query.edit_message_text(
        CASE_PRIMING_MESSAGE,
        parse_mode='Markdown'
    )
    # Set state to awaiting case input
    await self.state.set_state(user_id, ConversationState(
        state_type="awaiting_case_priming"
    ))
```

**File:** `src/bot/handlers/text.py` - Handle case priming input:

```python
async def handle(self, update, context):
    # ... existing code ...

    if current_state.state_type == "awaiting_case_priming":
        await self._handle_case_priming(update, db_user)
        return

    # ... rest of existing code ...

async def _handle_case_priming(self, update, db_user):
    """Extract and create cases from user input."""
    text = update.effective_message.text
    cases = await self._extract_case_names(text)

    if not cases:
        await update.message.reply_text("I couldn't find any case names. Try listing them one per line.")
        return

    # Create cases
    for case_name in cases:
        await self.repo.create_case(db_user.id, case_name, source="priming")

    await update.message.reply_text(
        f"*{len(cases)} cases added:*\n\n" + "\n".join(f"- {c}" for c in cases),
        parse_mode='Markdown'
    )

    await self.state.clear_state(db_user.id)
```

---

## Phase 10: Register New Handlers

**File:** `src/bot/main.py`

```python
# Import new handlers
from src.bot.handlers.onboarding import OnboardingHandler
from src.bot.handlers.quick_add import QuickAddHandler

# Create instances
onboarding_handler = OnboardingHandler(repo, state_manager)
quick_add_handler = QuickAddHandler(repo, state_manager)

# Register callback handlers (add to existing callback routing)
application.add_handler(CallbackQueryHandler(
    onboarding_handler.handle_callback,
    pattern="^onboard_"
))
application.add_handler(CallbackQueryHandler(
    quick_add_handler.handle_callback,
    pattern="^(quick_|reminder_)"
))
```

---

## Implementation Order

1. **Database changes** (Phase 1) - migrations, schema
2. **Repository updates** (Phase 2) - new methods
3. **Keyboards** (Phase 3) - UI building blocks
4. **Commands /start update** (Phase 5) - entry point
5. **Voice handler update** (Phase 6) - first voice flow
6. **Onboarding handler** (Phase 4) - callback routing
7. **Scheduler update** (Phase 7) - quick-tap prompts
8. **Quick-add handler** (Phase 8) - tap-based entry
9. **Case priming** (Phase 9) - bulk case setup
10. **Main.py registration** (Phase 10) - wire it up

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `src/db/models.py` | Add onboarding fields to User |
| `src/db/schema.sql` | Add onboarding_events table |
| `src/db/connection.py` | Add migrations |
| `src/db/repository.py` | Add onboarding methods |
| `src/bot/keyboards.py` | Add 6 new keyboard builders |
| `src/bot/handlers/commands.py` | Update /start, add constants |
| `src/bot/handlers/voice.py` | Add first voice handling |
| `src/bot/handlers/text.py` | Add case priming handling |
| `src/bot/handlers/callbacks.py` | Route to new handlers |
| `src/services/scheduler.py` | Update reminder format |
| `src/bot/handlers/onboarding.py` | NEW - onboarding callbacks |
| `src/bot/handlers/quick_add.py` | NEW - quick-tap callbacks |
| `src/bot/main.py` | Register new handlers |

---

## Testing Plan

1. **Unit tests** - Add to `tests/test_v080_features.py`:
   - `TestOnboardingFlow` - state transitions
   - `TestQuickAddFlow` - activity -> case -> hours flow
   - `TestCasePriming` - case extraction

2. **E2E tests** - Add to `tests/test_e2e_harness.py`:
   - `test_new_user_onboarding_flow`
   - `test_returning_user_welcome`
   - `test_quick_tap_entry`
   - `test_delete_test_entry`

---

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Database + Migrations | 1 hour |
| Repository Methods | 1 hour |
| Keyboards | 30 mins |
| /start + Voice Updates | 2 hours |
| Onboarding Handler | 2 hours |
| Scheduler + Quick-Add | 3 hours |
| Case Priming | 1 hour |
| Testing | 2 hours |
| **Total** | **~12 hours** |
