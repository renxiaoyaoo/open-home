import { createHmac, randomUUID } from "node:crypto";
import { getDb } from "../db/index.ts";
import type { ProviderRequestContext } from "./provider.ts";
import { openSession, sealSession } from "./session-crypto.ts";
import { authenticateDevice } from "./client-auth.ts";

export type ProviderId = "opengate" | "opendevice" | "openlock" | "openauto";
export type CentralSession = { sessionId: string; signingToken: string; openId: string; context: ProviderRequestContext };

export function assertCentralEnabled() { if (process.env.OPENHOME_ACCESS_ENABLED !== "1") throw new Error("OpenAPI is disabled until access control is configured"); }
export function assertBrowserAccess(request: Request) {
  assertCentralEnabled();
  const boundaryHeader = (process.env.OPENHOME_BROWSER_IDENTITY_HEADER || "cf-access-jwt-assertion").toLowerCase();
  if (process.env.NODE_ENV === "production" && !request.headers.get(boundaryHeader)) throw new Error("Browser access boundary is missing");
}
export async function assertClientAccess(request: Request) {
  assertCentralEnabled();
  const authorization = request.headers.get("authorization");
  if (authorization) { await authenticateDevice(request); return; }
  assertBrowserAccess(request);
}
function encryptionKey() { const value = process.env.OPENHOME_SESSION_ENCRYPTION_KEY || ""; const key = /^[0-9a-f]{64}$/i.test(value) ? Buffer.from(value, "hex") : Buffer.from(value, "base64"); if (key.length !== 32) throw new Error("Session encryption key is not configured"); return key; }
export function validAccountId(value: string) { if (!/^[a-z0-9][a-z0-9_-]{0,47}$/i.test(value)) throw new Error("Invalid account ID"); return value; }
export function maskMobile(mobile: string) { return `${mobile.slice(0, 3)}****${mobile.slice(-4)}`; }
function mobileFingerprint(provider: ProviderId, mobile: string) { return createHmac("sha256", encryptionKey()).update(`${provider}:${mobile}`).digest("hex"); }

export async function saveProviderSession<T>(provider: ProviderId, accountId: string, mobile: string, displayName: string | null, session: T) { const db = await getDb(); const now = Date.now(); const fingerprint = mobileFingerprint(provider, mobile); const existing = await db.prepare("SELECT id FROM accounts WHERE provider=? AND mobile_fingerprint=?").bind(provider, fingerprint).first<{ id: string }>(); const id = existing?.id || accountId; await db.prepare("INSERT INTO accounts (id,provider,mobile_fingerprint,mobile_mask,display_name,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET provider=excluded.provider,mobile_fingerprint=excluded.mobile_fingerprint,mobile_mask=excluded.mobile_mask,display_name=excluded.display_name,status='active',updated_at=excluded.updated_at").bind(id, provider, fingerprint, maskMobile(mobile), displayName, "active", now, now).run(); await db.prepare("INSERT INTO sessions (account_id,encrypted_state,verified_at,updated_at) VALUES (?,?,?,?) ON CONFLICT(account_id) DO UPDATE SET encrypted_state=excluded.encrypted_state,verified_at=excluded.verified_at,updated_at=excluded.updated_at").bind(id, sealSession(session), now, now).run(); return id; }
export async function saveCentralSession(accountId: string, mobile: string, displayName: string | null, session: CentralSession) { return saveProviderSession("opengate", accountId, mobile, displayName, session); }
export async function loadProviderSession<T>(provider: ProviderId, accountId?: string) { const db = await getDb(); const row = accountId ? await db.prepare("SELECT s.encrypted_state AS encryptedState,a.id AS accountId FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE a.id=? AND a.provider=? AND a.status='active'").bind(accountId, provider).first<{ encryptedState: string; accountId: string }>() : await db.prepare("SELECT s.encrypted_state AS encryptedState,a.id AS accountId FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE a.provider=? AND a.status='active' ORDER BY a.updated_at DESC LIMIT 1").bind(provider).first<{ encryptedState: string; accountId: string }>(); if (!row) throw new Error("Account is not signed in"); return { accountId: row.accountId, session: openSession<T>(row.encryptedState) }; }
export async function loadCentralSession(accountId: string) { return (await loadProviderSession<CentralSession>("opengate", accountId)).session; }
export async function persistProviderSession<T>(provider: ProviderId, accountId: string, session: T) { const result = await (await getDb()).prepare("UPDATE sessions SET encrypted_state=?,updated_at=? WHERE account_id=? AND EXISTS (SELECT 1 FROM accounts WHERE id=? AND provider=?)").bind(sealSession(session), Date.now(), accountId, accountId, provider).run(); return result; }
export async function refreshProviderSession<T extends { accessToken?: string }>(provider: ProviderId, accountId: string, staleAccessToken: string | undefined, refresh: (latest: T) => Promise<T>) {
  const db = await getDb(); const owner = randomUUID(); const deadline = Date.now() + 15_000;
  while (true) {
    const now = Date.now();
    await db.prepare("INSERT INTO provider_leases (account_id,owner,expires_at) VALUES (?,?,?) ON CONFLICT(account_id) DO UPDATE SET owner=excluded.owner,expires_at=excluded.expires_at WHERE provider_leases.expires_at<? OR provider_leases.owner=?").bind(accountId, owner, now + 20_000, now, owner).run();
    const lease = await db.prepare("SELECT owner FROM provider_leases WHERE account_id=?").bind(accountId).first<{ owner: string }>();
    if (lease?.owner === owner) break;
    if (now >= deadline) throw new Error("Provider session refresh is busy");
    await new Promise((resolve) => setTimeout(resolve, 75));
  }
  try {
    const latest = await loadProviderSession<T>(provider, accountId);
    if (latest.session.accessToken && latest.session.accessToken !== staleAccessToken) return latest.session;
    // Refresh credentials may rotate. Always refresh from the session loaded
    // after acquiring the cross-instance lease, never from the request's
    // potentially stale in-memory copy.
    const updated = await refresh(latest.session);
    await persistProviderSession(provider, accountId, updated);
    return updated;
  } finally { await db.prepare("DELETE FROM provider_leases WHERE account_id=? AND owner=?").bind(accountId, owner).run(); }
}
export async function persistCentralSession(accountId: string, session: CentralSession) { return persistProviderSession("opengate", accountId, session); }
export async function listAccounts(provider?: ProviderId) { const db = await getDb(); const sql = `SELECT id,provider,display_name AS displayName,mobile_mask AS mobileMask,status,updated_at AS updatedAt FROM accounts${provider ? " WHERE provider=?" : ""} ORDER BY updated_at DESC`; return (provider ? await db.prepare(sql).bind(provider).all<{ id: string; provider: ProviderId; displayName: string | null; mobileMask: string; status: string; updatedAt: number }>() : await db.prepare(sql).all<{ id: string; provider: ProviderId; displayName: string | null; mobileMask: string; status: string; updatedAt: number }>()).results; }
export async function publicAccounts(provider: ProviderId = "opengate") { return (await listAccounts(provider)).filter((row) => row.status === "active").map((row) => ({ id: row.id, provider: row.provider, username: row.displayName || row.mobileMask })); }
export async function removeAccount(accountId: string) { const db = await getDb(); const row = await db.prepare("SELECT id FROM accounts WHERE id=?").bind(accountId).first(); if (!row) throw new Error("Account not found"); await db.prepare("DELETE FROM accounts WHERE id=?").bind(accountId).run(); }
export async function removeProviderAccount(provider: ProviderId, accountId?: string) { const db = await getDb(); if (accountId) return db.prepare("DELETE FROM accounts WHERE id=? AND provider=?").bind(accountId, provider).run(); const row = await db.prepare("SELECT id FROM accounts WHERE provider=? AND status='active' ORDER BY updated_at DESC LIMIT 1").bind(provider).first<{ id: string }>(); if (!row) throw new Error("Account not found"); return db.prepare("DELETE FROM accounts WHERE id=?").bind(row.id).run(); }
export async function listActiveAccountIds() { return (await (await getDb()).prepare("SELECT id FROM accounts WHERE status='active' AND provider='opengate'").all<{ id: string }>()).results.map((row) => row.id); }
