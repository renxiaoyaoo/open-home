import { randomUUID } from "node:crypto";
import { OpenLockProvider, type OpenLockSession } from "./openlock-provider";
import { assertClientAccess, loadProviderSession, persistProviderSession, removeProviderAccount, saveProviderSession } from "./central";
import { openSession } from "./session-crypto.ts";
import { lockMediaUrl, proxyLockMedia } from "./lock-media.ts";

const LEGACY_COOKIE = "openhome_openlock_session";
function legacyCookie(request: Request) { return request.headers.get("cookie")?.split(/;\s*/).find((part) => part.startsWith(`${LEGACY_COOKIE}=`))?.slice(LEGACY_COOKIE.length + 1); }
async function storedSession(request: Request, accountId?: string) { try { return { ...(await loadProviderSession<OpenLockSession>("openlock", accountId)), migrated: false }; } catch (error) { const raw = legacyCookie(request); if (!raw || accountId) throw error; const session = openSession<OpenLockSession>(decodeURIComponent(raw)); const id = await saveProviderSession("openlock", `ol-${randomUUID()}`, "", session.displayName || null, session); return { accountId: id, session, migrated: true }; } }
function clearLegacy(response: Response) { response.headers.append("set-cookie", `${LEGACY_COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`); return response; }

export async function callOpenLock(operation: string, request: Request) {
  await assertClientAccess(request);
  if (operation === "login") {
    const { phone, password } = await request.json() as { phone?: string; password?: string };
    const next = await new OpenLockProvider().passwordLogin(phone || "", password || "");
    const accountId = await saveProviderSession("openlock", `ol-${randomUUID()}`, phone || "", next.displayName || null, next);
    return Response.json({ ok: true, data: { accountId, displayName: next.displayName } });
  }
  const url = new URL(request.url);
  if (operation === "logout") { const body = await request.json().catch(() => ({})) as { accountId?: string }; await removeProviderAccount("openlock", body.accountId); return clearLegacy(Response.json({ ok: true })); }
  const stored = await storedSession(request, url.searchParams.get("accountId") || undefined);
  if (operation === "media") return proxyLockMedia(request, url.searchParams.get("token") || "");
  const provider = new OpenLockProvider(stored.session);
  const lockId = url.searchParams.get("lockId") || "";
  const cursor = url.searchParams.get("cursor") || "";
  const page = Math.max(1, Number.parseInt(cursor || "1", 10) || 1);
  let data: unknown;
  if (operation === "profile") { const response = Response.json({ ok: true, data: { accountId: stored.accountId, displayName: stored.session.displayName } }); return stored.migrated ? clearLegacy(response) : response; }
  else if (operation === "devices") data = await provider.devices();
  else if (!lockId) throw new Error("缺少设备标识");
  else if (operation === "detail") data = await provider.detail(lockId);
  else if (operation === "lock-dynamics") data = await provider.lockDynamics(lockId, page);
  else if (operation === "security-logs") data = await provider.securityLogs(lockId, page);
  else if (operation === "operation-logs") data = await provider.operationLogs(lockId, page);
  else if (operation === "temporary-password") data = await provider.temporaryPasswordCount(lockId);
  else if (operation === "temporary-password-create") {
    if (request.method !== "POST") throw new Error("临时密码生成必须使用 POST");
    data = await provider.createTemporaryPassword(lockId);
  }
  else if (operation === "captures") {
    data = await provider.captures(lockId, cursor);
    data = { ...(data as { items: Array<{ video?: string }> }), items: (data as { items: Array<{ video?: string }> }).items.map((item) => item.video ? { ...item, video: lockMediaUrl(item.video) } : item) };
    const refreshed = provider.sessionState();
    if (refreshed) await persistProviderSession("openlock", stored.accountId, refreshed);
  }
  else throw new Error("不支持的 OpenLock 操作");
  return Response.json({ ok: true, data });
}
