import { randomUUID } from "node:crypto";
import { assertClientAccess, loadProviderSession, removeProviderAccount, saveProviderSession } from "./central";
import { DirectOpenAutoProvider, type OpenAutoSession } from "./openauto-provider";

export async function readOpenAutoStatus(vehicleId: string, accountId?: string) {
  if (!vehicleId) throw new Error("缺少车辆标识");
  const stored = await loadProviderSession<OpenAutoSession>("openauto", accountId);
  return await new DirectOpenAutoProvider(stored.session).liveStatus(vehicleId);
}

export async function callOpenAuto(operation: string, request: Request) {
  await assertClientAccess(request);
  if (operation === "login") {
    const body = await request.json() as { phone?: string; password?: string };
    const session = await new DirectOpenAutoProvider().passwordLogin(String(body.phone || ""), String(body.password || ""));
    const accountId = await saveProviderSession("openauto", `oa-${randomUUID()}`, String(body.phone || ""), session.displayName || null, session);
    return Response.json({ ok: true, data: { accountId, displayName: session.displayName } });
  }
  const url = new URL(request.url);
  if (operation === "logout") { await removeProviderAccount("openauto", url.searchParams.get("accountId") || undefined); return Response.json({ ok: true }); }
  const stored = await loadProviderSession<OpenAutoSession>("openauto", url.searchParams.get("accountId") || undefined);
  const provider = new DirectOpenAutoProvider(stored.session);
  if (operation === "profile") return Response.json({ ok: true, data: { accountId: stored.accountId, displayName: stored.session.displayName } });
  if (operation === "bootstrap") return Response.json({ ok: true, data: await provider.bootstrap() });
  if (operation === "vehicles") return Response.json({ ok: true, data: await provider.vehicles() });
  if (operation === "status") { const vehicleId = url.searchParams.get("vehicleId") || ""; if (!vehicleId) throw new Error("缺少车辆标识"); return Response.json({ ok: true, data: await provider.liveStatus(vehicleId) }); }
  if (operation === "summary") { const vehicleId = url.searchParams.get("vehicleId") || ""; if (!vehicleId) throw new Error("缺少车辆标识"); return Response.json({ ok: true, data: await provider.summary(vehicleId) }); }
  throw new Error("不支持的 OpenAuto 操作");
}
