# BriefHours Web Application Implementation Plan

## Overview

Build a Next.js 14+ web application at `app.briefhours.com` providing:
- User registration/authentication (Google, Apple, Email/Password)
- Dashboard with time entries, cases, analytics
- Stripe subscription billing (£12/month, 14-day trial)
- Telegram bot account linking
- Real-time updates via PostgreSQL NOTIFY/LISTEN + SSE

**Target Directory:** `/Users/sbarker/git-bnx/BriefHours-WebApp/`

**Key Decisions:**
- ORM: Drizzle (user choice)
- Database: Existing PostgreSQL with bot data (need migrations)
- Real-time: Yes, using PostgreSQL NOTIFY + SSE
- Scope: Full spec implementation

---

## Tech Stack

| Category | Technology |
|----------|------------|
| Framework | Next.js 14+ (App Router) |
| Language | TypeScript |
| Database | PostgreSQL (existing Patroni cluster) |
| ORM | Drizzle ORM |
| Auth | Auth.js v5 (NextAuth) |
| Styling | Tailwind CSS |
| Components | shadcn/ui |
| Forms | React Hook Form + Zod |
| Data Fetching | TanStack Query (React Query) |
| Charts | Recharts |
| Payments | Stripe |
| Real-time | PostgreSQL NOTIFY + SSE |

---

## Phase 1: Project Foundation

### 1.1 Initialize Project
```bash
cd /Users/sbarker/git-bnx/BriefHours-WebApp
npx create-next-app@latest . --typescript --tailwind --eslint --app --src-dir
```

### 1.2 Install Dependencies
```bash
# Core
npm install drizzle-orm postgres @auth/core @auth/drizzle-adapter next-auth@beta
npm install @tanstack/react-query zod react-hook-form @hookform/resolvers
npm install stripe @stripe/stripe-js bcryptjs date-fns recharts

# Dev
npm install -D drizzle-kit @types/bcryptjs
```

### 1.3 Project Structure
```
src/
├── app/
│   ├── (auth)/                    # Auth routes (no sidebar)
│   │   ├── login/page.tsx
│   │   ├── register/page.tsx
│   │   ├── verify-email/page.tsx
│   │   ├── forgot-password/page.tsx
│   │   └── layout.tsx
│   ├── (dashboard)/               # Authenticated routes
│   │   ├── layout.tsx             # Sidebar + header
│   │   ├── page.tsx               # Dashboard home
│   │   ├── entries/
│   │   ├── cases/
│   │   ├── insights/
│   │   └── settings/
│   └── api/
│       ├── auth/[...nextauth]/route.ts
│       ├── entries/
│       ├── cases/
│       ├── telegram/
│       ├── stripe/
│       └── events/route.ts        # SSE endpoint
├── auth.ts                        # Auth.js config
├── middleware.ts                  # Route protection
├── db/
│   ├── index.ts                   # Drizzle client
│   ├── schema/
│   │   ├── auth.ts
│   │   ├── entries.ts
│   │   ├── cases.ts
│   │   ├── subscriptions.ts
│   │   └── index.ts
│   └── migrations/
├── components/
│   ├── ui/                        # shadcn/ui
│   ├── layout/
│   ├── dashboard/
│   ├── entries/
│   ├── cases/
│   └── insights/
├── lib/
│   ├── stripe.ts
│   ├── subscription.ts
│   └── utils.ts
└── hooks/
    ├── use-entries.ts
    ├── use-cases.ts
    └── use-realtime.ts
```

### 1.4 Environment Variables
Create `.env.local`:
```env
# Database
DATABASE_URL="postgresql://..."

# Auth.js
AUTH_SECRET="..."
AUTH_URL="http://localhost:3000"
AUTH_GOOGLE_ID="..."
AUTH_GOOGLE_SECRET="..."
AUTH_APPLE_ID="..."
AUTH_APPLE_SECRET="..."

# Stripe
STRIPE_SECRET_KEY="sk_..."
STRIPE_WEBHOOK_SECRET="whsec_..."
STRIPE_PRICE_ID="price_..."
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY="pk_..."

# Bot Integration
BOT_API_SECRET="..."
TELEGRAM_BOT_USERNAME="BriefHoursBot"

# App
NEXT_PUBLIC_APP_URL="http://localhost:3000"
```

---

## Phase 2: Database Schema & Migrations

### 2.1 New Tables (Non-Breaking)

**`src/db/schema/auth.ts`** - Auth.js compatible tables:
- `web_users` - Primary user identity (TEXT id for Auth.js)
- `auth_accounts` - OAuth providers
- `sessions` - Database sessions
- `verification_tokens` - Email verification
- `user_credentials` - Password hashes
- `telegram_link_tokens` - Telegram linking tokens

**`src/db/schema/subscriptions.ts`**:
- `subscriptions` - Stripe subscription data
- `stripe_webhook_events` - Idempotency tracking

**`src/db/schema/preferences.ts`**:
- `user_preferences` - App settings

### 2.2 Migration Strategy

**Step 1:** Add `web_user_id TEXT` column to existing tables:
- `entries`
- `cases`
- `solicitors`
- `pending_entries`
- `submissions`
- `expenses`
- `travel_entries`

**Step 2:** Create migration function:
```sql
CREATE FUNCTION migrate_telegram_user_to_web(
  p_telegram_id BIGINT,
  p_web_user_id TEXT
) RETURNS VOID AS $$
-- Updates all user data with web_user_id
-- Links telegram account
-- Copies preferences
$$
```

**Step 3:** Create NOTIFY trigger for real-time:
```sql
CREATE TRIGGER entries_notify_trigger
  AFTER INSERT OR UPDATE OR DELETE ON entries
  FOR EACH ROW EXECUTE FUNCTION notify_entry_change();
```

---

## Phase 3: Authentication

### 3.1 Auth.js Configuration (`src/auth.ts`)
- Google OAuth provider
- Apple OAuth provider
- Credentials provider (email/password)
- DrizzleAdapter for database storage
- JWT session strategy
- Callbacks for subscription status in session

### 3.2 Auth Routes
| Route | Purpose |
|-------|---------|
| `POST /api/auth/register` | Email/password signup |
| `POST /api/auth/verify-email` | Email verification |
| `POST /api/auth/forgot-password` | Password reset request |
| `POST /api/auth/reset-password` | Password reset |

### 3.3 Middleware (`src/middleware.ts`)
- Protect dashboard routes
- Allow public routes (/, /pricing, /auth/*)
- Allow bot API routes (validated by X-Bot-Secret)

---

## Phase 4: Telegram Integration

### 4.1 Link Generation
`POST /api/telegram/link` - Generate 15-min token, return deep link:
```
t.me/BriefHoursBot?start=LINK_{token}
```

### 4.2 Bot Validation API
`POST /api/bot/telegram/validate-link` - Bot calls to validate token:
- Verify X-Bot-Secret header
- Check token validity
- Link telegram_id to user
- Return user info

### 4.3 Migration Flow
`POST /api/bot/telegram/claim-account` - For existing Telegram users:
- Check if telegram_id exists
- Create placeholder account if new
- Return claim URL for web signup

---

## Phase 5: Stripe Billing

### 5.1 API Routes
| Route | Purpose |
|-------|---------|
| `POST /api/stripe/checkout` | Create checkout session |
| `POST /api/stripe/portal` | Create billing portal session |
| `POST /api/stripe/webhook` | Handle Stripe webhooks |

### 5.2 Webhook Events
- `checkout.session.completed` → Create subscription
- `invoice.paid` → Update period
- `invoice.payment_failed` → Mark past_due
- `customer.subscription.updated` → Sync status
- `customer.subscription.deleted` → Mark canceled

### 5.3 Access Control (`src/lib/subscription.ts`)
```typescript
function checkSubscriptionAccess(userId: string): {
  hasAccess: boolean
  status: 'trial' | 'active' | 'past_due' | 'canceled' | 'expired' | 'none'
  trialDaysRemaining: number | null
  canUseService: boolean
}
```

---

## Phase 6: Dashboard Pages

### 6.1 Dashboard Home (`/`)
- Stats cards: Today's hours, This week, This month
- Recent entries (last 5)
- Active cases summary
- Quick actions (New Entry, New Case)

### 6.2 Entries (`/entries`)
- Data table with pagination
- Filters: date range, case, activity type
- Search by description/transcript
- CRUD operations

### 6.3 Entry Detail (`/entries/[id]`)
- View/edit form
- Original transcript display
- Delete with confirmation

### 6.4 Cases (`/cases`)
- Grid/list view toggle
- Filter: active/archived, fee type
- Stats per case (hours, entries)

### 6.5 Case Detail (`/cases/[id]`)
- Case info header
- Entries for this case
- Case-specific analytics

### 6.6 Insights (`/insights`)
- Date range selector
- Hours trend chart (line)
- Hours by case (pie)
- Hours by activity (bar)

### 6.7 Weekly Summary (`/insights/weekly`)
- Week selector
- Daily breakdown
- Comparison to previous week

### 6.8 Export (`/insights/export`)
- Date range picker
- Case filter
- Format: PDF, CSV, Excel

### 6.9 Settings (`/settings`)
- Profile settings
- Telegram link/unlink (`/settings/telegram`)
- Billing management (`/settings/billing`)

---

## Phase 7: Real-Time Updates

### 7.1 SSE Endpoint (`/api/events`)
- Listen to PostgreSQL NOTIFY
- Filter by user's web_user_id
- Stream entry changes to client

### 7.2 Client Hook (`use-realtime.ts`)
- EventSource subscription
- Invalidate React Query on events
- Toast notifications for new entries

---

## Phase 8: UI Components

### 8.1 shadcn/ui Components to Install
```bash
npx shadcn@latest init
npx shadcn@latest add button card dialog dropdown-menu input select \
  skeleton table toast tabs avatar badge calendar popover separator \
  sheet sidebar form label textarea
```

### 8.2 Custom Components
- `AppSidebar` - Navigation sidebar
- `AppHeader` - Top header with user menu
- `MobileNav` - Bottom navigation for mobile
- `StatsCard` - Dashboard metric card
- `EntryForm` - Create/edit entry form
- `CaseCard` - Case display card
- `DateRangePicker` - Date range selection
- `HoursChart` - Time trend chart
- `EmptyState` - No data display
- `LoadingSkeleton` - Loading placeholders

### 8.3 Theme (Dark Mode)
Extend existing marketing site theme:
- Background: `#000000`
- Card: `#0a0a0a`
- Primary accent: `#c9a227` (gold)
- Text: `#ffffff` / `#a1a1a6`

---

## Implementation Order

### Week 1: Foundation
1. [ ] Project setup (Next.js, Tailwind, shadcn/ui)
2. [ ] Drizzle schema for new tables
3. [ ] Database migrations (add web_user_id)
4. [ ] Auth.js configuration
5. [ ] Base layout (sidebar, header)
6. [ ] Protected routes middleware

### Week 2: Core Features
1. [ ] Dashboard page with stats
2. [ ] Entries list with filters
3. [ ] Entry detail/edit
4. [ ] Manual entry creation
5. [ ] React Query hooks

### Week 3: Cases & Settings
1. [ ] Cases list/grid
2. [ ] Case detail page
3. [ ] Case CRUD operations
4. [ ] Settings pages (profile, preferences)
5. [ ] Telegram link/unlink UI

### Week 4: Billing & Telegram
1. [ ] Stripe checkout integration
2. [ ] Webhook handlers
3. [ ] Subscription management UI
4. [ ] Telegram link token API
5. [ ] Bot validation endpoints

### Week 5: Analytics & Export
1. [ ] Insights dashboard
2. [ ] Weekly summary view
3. [ ] Chart components (Recharts)
4. [ ] PDF export
5. [ ] CSV/Excel export

### Week 6: Real-Time & Polish
1. [ ] PostgreSQL NOTIFY triggers
2. [ ] SSE endpoint
3. [ ] Real-time client hook
4. [ ] Loading skeletons
5. [ ] Toast notifications
6. [ ] Mobile responsiveness
7. [ ] Error boundaries

---

## Critical Files

| File | Purpose |
|------|---------|
| `src/auth.ts` | Auth.js configuration |
| `src/middleware.ts` | Route protection |
| `src/db/schema/auth.ts` | User/session tables |
| `src/db/schema/entries.ts` | Entries with web_user_id |
| `src/app/api/stripe/webhook/route.ts` | Stripe webhook handler |
| `src/app/api/events/route.ts` | SSE endpoint |
| `src/lib/subscription.ts` | Access control logic |
| `src/app/(dashboard)/layout.tsx` | Dashboard layout |

---

## Bot Integration Points

The Telegram bot needs to:
1. Call `/api/bot/telegram/validate-link` when receiving `/start LINK_{token}`
2. Call `/api/bot/user/[telegramId]/subscription` to check access
3. Write `web_user_id` when creating entries (after linking)
4. Call migration function when user claims placeholder account

Bot API authentication: `X-Bot-Secret` header with shared secret.

---

## Success Criteria

- [ ] Users can register via Google, Apple, or Email
- [ ] Users can link/unlink Telegram account
- [ ] Dashboard shows real-time entry updates from bot
- [ ] Entries CRUD works with filtering and pagination
- [ ] Cases CRUD with analytics
- [ ] Insights charts render correctly
- [ ] Export generates PDF/CSV/Excel
- [ ] Stripe checkout and subscription management works
- [ ] Access control enforces trial/subscription status
- [ ] Mobile responsive on all pages
