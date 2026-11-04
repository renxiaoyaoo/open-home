import { randomUUID } from "node:crypto";
import { OpenDeviceProvider, type OpenDeviceSession } from "./opendevice-provider.ts";
import { assertClientAccess, loadProviderSession, refreshProviderSession, removeProviderAccount, saveProviderSession } from "./central.ts";
import { openSession } from "./session-crypto.ts";

const LEGACY_COOKIE = "openhome_opendevice";
const OPERATIONS = { sms: "POST", login: "POST", logout: "POST", profile: "GET", homes: "GET", devices: "GET", capabilities: "GET", status: "GET", program: "POST", power: "POST", action: "POST" } as const;
export type DryerOperation = keyof typeof OPERATIONS;
export function dryerOperation(value: string) { if (!(value in OPERATIONS)) throw new Error("不支持的干衣机操作"); return { method: OPERATIONS[value as DryerOperation] }; }
async function json(request: Request) { return await request.json().catch(() => ({})) as Record<string, unknown>; }
function id(value: unknown, label: string) { const text = String(value || ""); if (!/^[A-Za-z0-9_-]{1,128}$/.test(text)) throw new Error(`${label}无效`); return text; }
function legacyCookie(request: Request) { return request.headers.get("cookie")?.split(/;\s*/).find((part) => part.startsWith(`${LEGACY_COOKIE}=`))?.slice(LEGACY_COOKIE.length + 1); }
async function storedSession(request: Request, accountId?: string) { try { return { ...(await loadProviderSession<OpenDeviceSession>("opendevice", accountId)), migrated: false }; } catch (error) { const raw = legacyCookie(request); if (!raw || accountId) throw error; const session = openSession<OpenDeviceSession>(decodeURIComponent(raw)); const id = await saveProviderSession("opendevice", `od-${randomUUID()}`, "", session.displayName || null, session); return { accountId: id, session, migrated: true }; } }
function clearLegacy(response: Response) { response.headers.append("set-cookie", `${LEGACY_COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0`); return response; }

export async function callDryerAdapter(operation: DryerOperation, request: Request) {
  await assertClientAccess(request);
  const expected = OPERATIONS[operation]; if (request.method !== expected) return Response.json({ ok: false, message: "请求方法不支持" }, { status: 405 });
  const url = new URL(request.url); const body = expected === "POST" ? await json(request) : {};
  if (operation === "sms") { const mobile = String(body.mobile || ""); if (!/^1\d{10}$/.test(mobile)) throw new Error("手机号无效"); return Response.json({ ok: true, data: await new OpenDeviceProvider().requestSms(mobile) }); }
  if (operation === "login") { const mobile = String(body.mobile || ""); const code = String(body.code || ""); if (!/^1\d{10}$/.test(mobile) || !/^\d{6}$/.test(code)) throw new Error("手机号或验证码无效"); const session = await new OpenDeviceProvider().smsLogin(mobile, code); const accountId = await saveProviderSession("opendevice", `od-${randomUUID()}`, mobile, session.displayName || null, session); return Response.json({ ok: true, data: { connected: true, accountId } }); }
  if (operation === "logout") { await removeProviderAccount("opendevice", String(body.accountId || "") || undefined); return clearLegacy(Response.json({ ok: true })); }
  const stored = await storedSession(request, url.searchParams.get("accountId") || undefined);
  if (operation === "profile") return stored.migrated ? clearLegacy(Response.json({ ok: true, data: { accountId: stored.accountId, displayName: stored.session.displayName || "OpenLiving 账号" } })) : Response.json({ ok: true, data: { accountId: stored.accountId, displayName: stored.session.displayName || "OpenLiving 账号" } });
  const client = new OpenDeviceProvider(stored.session, (staleAccessToken, refresh) => refreshProviderSession("opendevice", stored.accountId, staleAccessToken, async () => ({ ...stored.session, ...await refresh() }))); let data: unknown;
  if (operation === "homes") data = await client.listHomes();
  else if (operation === "devices") data = await client.listDevices(id(url.searchParams.get("homeId"), "家庭"));
  else if (operation === "capabilities") data = await client.capabilities(id(url.searchParams.get("homeId"), "家庭"), id(url.searchParams.get("deviceId"), "设备"));
  else { const deviceId = id(expected === "GET" ? url.searchParams.get("deviceId") : body.deviceId, "设备"); if (operation === "status") data = await client.status(deviceId); else if (operation === "program") data = body.parameters && typeof body.parameters === "object" ? await client.configureProgram(deviceId, Number(body.programId), body.parameters as Record<string, number>) : await client.program(deviceId, Number(body.programId)); else if (operation === "power") data = await client.power(deviceId, Boolean(body.power)); else { const requested = String(body.action || ""); const actions = { startDrying: "start", pauseDrying: "pause", appointmentDrying: "schedule", cancelAppointmentDrying: "cancelSchedule" } as const; const action = actions[requested as keyof typeof actions]; if (!action) throw new Error("不支持的设备操作"); if (action === "schedule") await client.power(deviceId, true); data = await client.action(deviceId, action, body.data || {}); } }
  return Response.json({ ok: true, data });
}
