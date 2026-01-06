/**
 * SQLite database for Telegram integration.
 * Handles sessions, instructions, questions, and approvals.
 */

import { Database } from "bun:sqlite";
import { existsSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { homedir } from "os";
import { randomUUID } from "crypto";

const DB_PATH = join(homedir(), ".claude", "hooks", "telegram-bun", "telegram.db");

// Ensure directory exists
const dbDir = dirname(DB_PATH);
if (!existsSync(dbDir)) {
  mkdirSync(dbDir, { recursive: true });
}

export const db = new Database(DB_PATH, { create: true });

// ============================================
// Schema initialization
// ============================================

db.run(`
  CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    description TEXT,
    pid INTEGER,
    status TEXT DEFAULT 'active',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_activity TEXT DEFAULT CURRENT_TIMESTAMP
  )
`);

db.run(`
  CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
  )
`);

db.run(`
  CREATE TABLE IF NOT EXISTS instructions (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    text TEXT,
    message_id INTEGER,
    queued_message_id INTEGER,
    received_at TEXT DEFAULT CURRENT_TIMESTAMP,
    acknowledged INTEGER DEFAULT 0,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
  )
`);

// Migration: add message_id column if it doesn't exist
try {
  db.run("ALTER TABLE instructions ADD COLUMN message_id INTEGER");
} catch {
  // Column already exists
}

// Migration: add queued_message_id column if it doesn't exist
try {
  db.run("ALTER TABLE instructions ADD COLUMN queued_message_id INTEGER");
} catch {
  // Column already exists
}

db.run(`
  CREATE TABLE IF NOT EXISTS pending_questions (
    id TEXT PRIMARY KEY,
    session_id TEXT UNIQUE,
    text TEXT,
    asked_at TEXT DEFAULT CURRENT_TIMESTAMP,
    answered INTEGER DEFAULT 0,
    answer TEXT,
    answered_at TEXT,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
  )
`);

db.run(`
  CREATE TABLE IF NOT EXISTS approvals (
    id TEXT PRIMARY KEY,
    category TEXT DEFAULT 'general',
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    options TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    response_value TEXT,
    telegram_message_id INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    responded_at TEXT
  )
`);

// Create index for faster lookups
db.run(`CREATE INDEX IF NOT EXISTS idx_approvals_status ON approvals(status)`);

// ============================================
// Config helpers
// ============================================

export function getConfig(key: string): string | null {
  const row = db.query("SELECT value FROM config WHERE key = ?").get(key) as { value: string } | null;
  return row?.value ?? null;
}

export function setConfig(key: string, value: string): void {
  db.run("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [key, value]);
}

// ============================================
// Session helpers
// ============================================

export function generateSessionId(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let id = "";
  for (let i = 0; i < 3; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

export function createSession(description: string, pid: number): string {
  let id = generateSessionId();

  // Ensure unique
  while (db.query("SELECT id FROM sessions WHERE id = ?").get(id)) {
    id = generateSessionId();
  }

  db.run(
    "INSERT INTO sessions (id, description, pid) VALUES (?, ?, ?)",
    [id, description, pid]
  );

  // Always set new session as default
  setConfig("default_session", id);

  return id;
}

export function deleteSession(id: string): void {
  db.run("DELETE FROM sessions WHERE id = ?", [id]);
  db.run("DELETE FROM instructions WHERE session_id = ?", [id]);
  db.run("DELETE FROM pending_questions WHERE session_id = ?", [id]);

  // Update default if needed
  if (getConfig("default_session") === id) {
    const next = db.query("SELECT id FROM sessions LIMIT 1").get() as { id: string } | null;
    setConfig("default_session", next?.id ?? "");
  }
}

export function getSession(id: string) {
  return db.query("SELECT * FROM sessions WHERE id = ?").get(id);
}

export function getSessionByPid(pid: number) {
  return db.query("SELECT * FROM sessions WHERE pid = ? AND status = 'active'").get(pid) as { id: string; description: string; pid: number } | null;
}

export function getAllSessions() {
  return db.query("SELECT * FROM sessions WHERE status = 'active'").all();
}

/**
 * Clean up stale sessions that are older than maxAgeHours
 */
export function cleanupStaleSessions(maxAgeHours: number = 24): number {
  const cutoff = new Date(Date.now() - maxAgeHours * 60 * 60 * 1000).toISOString();
  const oldResult = db.run(
    "DELETE FROM sessions WHERE created_at < ? AND status = 'active'",
    [cutoff]
  );

  // Clean up orphaned instructions and questions
  db.run("DELETE FROM instructions WHERE session_id NOT IN (SELECT id FROM sessions)");
  db.run("DELETE FROM pending_questions WHERE session_id NOT IN (SELECT id FROM sessions)");

  return oldResult.changes;
}

/**
 * Check if a process is still running
 */
export function isProcessRunning(pid: number): boolean {
  if (pid === 0) return false;

  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Remove sessions whose PIDs are no longer running
 */
export function cleanupDeadProcessSessions(): string[] {
  const sessions = db.query(
    "SELECT id, pid FROM sessions WHERE status = 'active' AND pid > 0"
  ).all() as { id: string; pid: number }[];

  const removed: string[] = [];
  for (const session of sessions) {
    if (!isProcessRunning(session.pid)) {
      db.run("DELETE FROM sessions WHERE id = ?", [session.id]);
      removed.push(session.id);
    }
  }

  // Clean up orphaned data
  if (removed.length > 0) {
    db.run("DELETE FROM instructions WHERE session_id NOT IN (SELECT id FROM sessions)");
    db.run("DELETE FROM pending_questions WHERE session_id NOT IN (SELECT id FROM sessions)");

    // Update default session if it was removed
    const defaultSession = getConfig("default_session");
    if (defaultSession && removed.includes(defaultSession)) {
      const next = db.query("SELECT id FROM sessions WHERE status = 'active' LIMIT 1").get() as { id: string } | null;
      setConfig("default_session", next?.id ?? "");
    }
  }

  return removed;
}

export function getDefaultSession(): string | null {
  return getConfig("default_session");
}

export function setDefaultSession(id: string): boolean {
  if (db.query("SELECT id FROM sessions WHERE id = ?").get(id)) {
    setConfig("default_session", id);
    return true;
  }
  return false;
}

// ============================================
// Instruction helpers
// ============================================

export function addInstruction(sessionId: string, text: string, messageId?: number, queuedMessageId?: number): string {
  const id = randomUUID();
  db.run(
    "INSERT INTO instructions (id, session_id, text, message_id, queued_message_id) VALUES (?, ?, ?, ?, ?)",
    [id, sessionId, text, messageId ?? null, queuedMessageId ?? null]
  );
  return id;
}

export function getPendingInstructions(sessionId: string) {
  return db.query(
    "SELECT * FROM instructions WHERE session_id = ? AND acknowledged = 0"
  ).all(sessionId);
}

export function acknowledgeInstruction(id: string): void {
  db.run("UPDATE instructions SET acknowledged = 1 WHERE id = ?", [id]);
}

export function acknowledgeAllInstructions(sessionId: string): void {
  db.run("UPDATE instructions SET acknowledged = 1 WHERE session_id = ?", [sessionId]);
}

// ============================================
// Question helpers
// ============================================

export function setPendingQuestion(sessionId: string, text: string): string {
  const id = randomUUID();
  db.run(
    "INSERT OR REPLACE INTO pending_questions (id, session_id, text) VALUES (?, ?, ?)",
    [id, sessionId, text]
  );
  return id;
}

export function getPendingQuestion(sessionId: string) {
  return db.query(
    "SELECT * FROM pending_questions WHERE session_id = ? AND answered = 0"
  ).get(sessionId);
}

export function answerQuestion(sessionId: string, answer: string): boolean {
  const result = db.run(
    "UPDATE pending_questions SET answered = 1, answer = ?, answered_at = CURRENT_TIMESTAMP WHERE session_id = ? AND answered = 0",
    [answer, sessionId]
  );
  return result.changes > 0;
}

export function getAnswer(sessionId: string) {
  const row = db.query(
    "SELECT answer FROM pending_questions WHERE session_id = ? AND answered = 1"
  ).get(sessionId) as { answer: string } | null;

  if (row) {
    // Clear the question
    db.run("DELETE FROM pending_questions WHERE session_id = ?", [sessionId]);
    return row.answer;
  }
  return null;
}

export function clearPendingQuestion(sessionId: string): void {
  db.run("DELETE FROM pending_questions WHERE session_id = ?", [sessionId]);
}

/**
 * Atomically get any answer that arrived, or clear the question if none.
 */
export function getAnswerOrClear(sessionId: string): string | null {
  const tx = db.transaction(() => {
    const row = db.query(
      "SELECT answer FROM pending_questions WHERE session_id = ? AND answered = 1"
    ).get(sessionId) as { answer: string } | null;

    db.run("DELETE FROM pending_questions WHERE session_id = ?", [sessionId]);

    return row?.answer ?? null;
  });

  return tx();
}

// ============================================
// Approvals
// ============================================

export interface ApprovalOption {
  label: string;
  value: string;
}

export interface Approval {
  id: string;
  category: string;
  title: string;
  message: string;
  options: ApprovalOption[];
  status: "pending" | "responded" | "expired";
  response_value: string | null;
  telegram_message_id: number | null;
  created_at: string;
  responded_at: string | null;
}

export function createApproval(
  category: string,
  title: string,
  message: string,
  options: ApprovalOption[]
): string {
  const id = randomUUID().slice(0, 8); // Short ID for callback_data
  db.run(
    `INSERT INTO approvals (id, category, title, message, options) VALUES (?, ?, ?, ?, ?)`,
    [id, category, title, message, JSON.stringify(options)]
  );
  return id;
}

export function getApproval(id: string): Approval | null {
  const row = db.query("SELECT * FROM approvals WHERE id = ?").get(id) as any;
  if (!row) return null;
  return {
    ...row,
    options: JSON.parse(row.options),
  };
}

export function setApprovalTelegramMessageId(id: string, messageId: number): void {
  db.run("UPDATE approvals SET telegram_message_id = ? WHERE id = ?", [messageId, id]);
}

/**
 * Atomically respond to an approval (only if still pending).
 */
export function respondToApproval(id: string, value: string): boolean {
  const result = db.run(
    `UPDATE approvals
     SET status = 'responded', response_value = ?, responded_at = datetime('now')
     WHERE id = ? AND status = 'pending'`,
    [value, id]
  );
  return result.changes > 0;
}

export function expireApproval(id: string): void {
  db.run(
    `UPDATE approvals SET status = 'expired' WHERE id = ? AND status = 'pending'`,
    [id]
  );
}

export function getApprovalStatus(id: string): { status: string; response_value: string | null; responded_at: string | null } | null {
  return db.query(
    "SELECT status, response_value, responded_at FROM approvals WHERE id = ?"
  ).get(id) as any;
}

export function getPendingApprovals(): Approval[] {
  const rows = db.query("SELECT * FROM approvals WHERE status = 'pending' ORDER BY created_at DESC").all() as any[];
  return rows.map(row => ({
    ...row,
    options: JSON.parse(row.options),
  }));
}

export function cleanupOldApprovals(maxAgeMinutes: number = 60): number {
  const result = db.run(
    `DELETE FROM approvals WHERE created_at < datetime('now', '-' || ? || ' minutes')`,
    [maxAgeMinutes]
  );
  return result.changes;
}
