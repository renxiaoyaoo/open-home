import { activateClient } from "@/lib/client-auth";

export async function POST(request: Request) {
  try { const body = await request.json() as { code?: string; deviceName?: string; instanceID?: string }; return Response.json({ ok: true, data: await activateClient(String(body.code || ""), body.deviceName, body.instanceID) }); }
  catch (error) { return Response.json({ ok: false, message: error instanceof Error ? error.message : "Activation failed" }, { status: 401 }); }
}
