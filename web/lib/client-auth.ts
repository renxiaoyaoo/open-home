import { createHmac, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { getDb } from "../db/index.ts";

const ACTIVATION_PREFIX = "oh1.";
export class ClientAuthorizationError extends Error {}

function key() {
  const value = process.env.OPENHOME_SESSION_ENCRYPTION_KEY || "";
  const decoded = /^[0-9a-f]{64}$/i.test(value) ? Buffer.from(value, "hex") : Buffer.from(value, "base64");
  if (decoded.length !== 32) throw new Error("Session encryption key is not configured");
  return decoded;
}
function digest(purpose: string, value: string) { return createHmac("sha256", key()).update(`${purpose}:${value}`).digest("hex"); }
function safeEqual(left: string, right: string) { const a = Buffer.from(left); const b = Buffer.from(right); return a.length === b.length && timingSafeEqual(a, b); }
function deviceName(value: unknown) { const name = String(value || "").trim(); if (!name || name.length > 80) throw new Error("Device name is invalid"); return name; }
function apiBaseURL(value: string) { const url = new URL(value); if (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname))) throw new Error("Public API URL must use HTTPS"); return url.toString().replace(/\/$/, ""); }

export function assertAdmin(request: Request) {
  const expected = digest("admin", "activation-issuer");
  const supplied = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") || "";
  if (!safeEqual(expected, supplied)) throw new Error("Administrator authorization failed");
}

export async function createActivation(publicAPIURL: string, lifetimeMinutes = 10) {
  const baseURL = apiBaseURL(publicAPIURL);
  const secret = randomBytes(24).toString("base64url");
  const now = Date.now();
  const expiresAt = now + Math.min(Math.max(lifetimeMinutes, 1), 60) * 60_000;
  await (await getDb()).prepare("INSERT INTO activation_codes (id,secret_hash,expires_at,created_at) VALUES (?,?,?,?)").bind(randomUUID(), digest("activation", secret), expiresAt, now).run();
  const payload = Buffer.from(JSON.stringify({ baseURL, code: secret }), "utf8").toString("base64url");
  return { activationCode: `${ACTIVATION_PREFIX}${payload}`, expiresAt };
}

export async function activateClient(code: string, rawName: unknown) {
  if (!/^[A-Za-z0-9_-]{32}$/.test(code)) throw new Error("Activation code is invalid");
  const db = await getDb(); const now = Date.now();
  const consumed = await db.prepare("DELETE FROM activation_codes WHERE secret_hash=? AND expires_at>=? RETURNING id").bind(digest("activation", code), now).first<{ id: string }>();
  if (!consumed) throw new Error("Activation code is invalid or expired");
  const id = randomUUID(); const secret = randomBytes(32).toString("base64url");
  await db.prepare("INSERT INTO client_devices (id,name,token_hash,created_at,last_seen_at,revoked_at) VALUES (?,?,?,?,?,NULL)").bind(id, deviceName(rawName), digest("device", secret), now, now).run();
  return { deviceID: id, deviceToken: `${id}.${secret}` };
}

export async function authenticateDevice(request: Request) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") || "";
  const match = /^([0-9a-f-]{36})\.([A-Za-z0-9_-]{43})$/i.exec(token);
  if (!match) throw new ClientAuthorizationError("Device authorization failed");
  const db = await getDb(); const row = await db.prepare("SELECT id,name,token_hash AS tokenHash,created_at AS createdAt FROM client_devices WHERE id=? AND revoked_at IS NULL").bind(match[1]).first<{ id: string; name: string; tokenHash: string; createdAt: number }>();
  if (!row || !safeEqual(row.tokenHash, digest("device", match[2]))) throw new ClientAuthorizationError("Device authorization failed");
  await db.prepare("UPDATE client_devices SET last_seen_at=? WHERE id=?").bind(Date.now(), row.id).run();
  return { deviceID: row.id, deviceName: row.name, createdAt: row.createdAt };
}
