import { randomUUID } from "node:crypto";
import { assertCentralEnabled, loadProviderSession, removeProviderAccount, saveProviderSession } from "./central";
import { DirectOpenAutoProvider, type OpenAutoSession } from "./openauto-provider";

export async function callOpenAuto(operation: string, request: Request) {
  assertCentralEnabled();
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
  if (operation === "summary") { const vehicleId = url.searchParams.get("vehicleId") || ""; if (!vehicleId) throw new Error("缺少车辆标识"); return Response.json({ ok: true, data: await provider.summary(vehicleId) }); }
  throw new Error("不支持的 OpenAuto 操作");
}
