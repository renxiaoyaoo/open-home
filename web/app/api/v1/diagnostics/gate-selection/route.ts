import { assertAdmin } from "@/lib/client-auth";
import { assertCentralEnabled } from "@/lib/central";
import { probeGateRules } from "@/lib/gate-rule-probe";

export async function POST(request: Request) {
  try {
    assertCentralEnabled();
    assertAdmin(request);
    const body = await request.json() as { mode?: unknown };
    if (body.mode !== "inspect" && body.mode !== "below-minimum" && body.mode !== "remove-one") return Response.json({ ok: false, message: "Unsupported probe" }, { status: 400 });
    return Response.json({ ok: true, result: await probeGateRules(body.mode) }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    return Response.json({ ok: false, message: error instanceof Error ? error.message : "Probe failed" }, { status: 400, headers: { "Cache-Control": "no-store" } });
  }
}
