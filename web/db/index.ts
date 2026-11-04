import { AsyncLocalStorage } from "node:async_hooks";

export interface Statement {
  bind(...values: SqlValue[]): Statement;
  first<T>(): Promise<T | null>;
  all<T>(): Promise<{ results: T[] }>;
  run(): Promise<unknown>;
}
type SqlValue = string | number | bigint | Uint8Array | null;
export interface Database { prepare(sql: string): Statement; }

const runtimeDatabase = new AsyncLocalStorage<Database>();
let nodeDatabase: Promise<Database> | undefined;

export function withDatabase<T>(database: Database, operation: () => T): T { return runtimeDatabase.run(database, operation); }
export async function getDb(): Promise<Database> { const bound = runtimeDatabase.getStore(); if (bound) return bound; nodeDatabase ??= createNodeDatabase(); return nodeDatabase; }

async function createNodeDatabase(): Promise<Database> {
  const [{ DatabaseSync }, { mkdir }, { dirname, resolve }] = await Promise.all([import("node:sqlite"), import("node:fs/promises"), import("node:path")]);
  const filename = resolve(process.env.OPENHOME_DATABASE_PATH || "./data/open-home.sqlite");
  await mkdir(dirname(filename), { recursive: true });
  const sqlite = new DatabaseSync(filename);
  sqlite.exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;"); sqlite.exec(SCHEMA);
  const accountColumns = sqlite.prepare("PRAGMA table_info(accounts)").all() as Array<{ name: string }>;
  if (!accountColumns.some(({ name }) => name === "provider")) sqlite.exec("ALTER TABLE accounts ADD COLUMN provider TEXT NOT NULL DEFAULT 'opengate';");
  const liveActivityColumns = sqlite.prepare("PRAGMA table_info(live_activities)").all() as Array<{ name: string }>;
  if (!liveActivityColumns.some(({ name }) => name === "last_state_hash")) sqlite.exec("ALTER TABLE live_activities ADD COLUMN last_state_hash TEXT;");
  if (!liveActivityColumns.some(({ name }) => name === "last_pushed_at")) sqlite.exec("ALTER TABLE live_activities ADD COLUMN last_pushed_at INTEGER;");
  sqlite.exec("DROP INDEX IF EXISTS accounts_mobile_fingerprint; CREATE UNIQUE INDEX IF NOT EXISTS accounts_provider_mobile_fingerprint ON accounts(provider, mobile_fingerprint);");
  sqlite.exec(LEGACY_CLEANUP);
  return { prepare(sql) { const statement = sqlite.prepare(sql); let values: SqlValue[] = []; return { bind(...next) { values = next; return this; }, async first<T>() { return (statement.get(...values) as T | undefined) ?? null; }, async all<T>() { return { results: statement.all(...values) as T[] }; }, async run() { return statement.run(...values); } }; } };
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, provider TEXT NOT NULL DEFAULT 'opengate', mobile_fingerprint TEXT, mobile_mask TEXT NOT NULL, display_name TEXT, status TEXT NOT NULL DEFAULT 'pending', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE, encrypted_state TEXT NOT NULL, verified_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS provider_leases (account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE, owner TEXT NOT NULL, expires_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS activation_codes (id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL UNIQUE, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS client_devices (id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, last_seen_at INTEGER NOT NULL, revoked_at INTEGER);
CREATE TABLE IF NOT EXISTS live_activities (activity_id TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES client_devices(id) ON DELETE CASCADE, provider TEXT NOT NULL, resource_id TEXT NOT NULL, push_token TEXT NOT NULL, environment TEXT NOT NULL, last_state_hash TEXT, last_pushed_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS live_activities_device_resource ON live_activities(device_id, provider, resource_id);
`;

const LEGACY_CLEANUP = `
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS door_preferences;
DROP TABLE IF EXISTS doors;
`;
