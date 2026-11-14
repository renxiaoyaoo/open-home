import { assertBrowserAccess } from "@/lib/central";
import { listDevices, revokeDevice } from "@/lib/client-auth";
import { jsonError } from "@/lib/http";

export async function GET(request: Request) {
  try { assertBrowserAccess(request); return Response.json({ ok: true, data: await listDevices() }); }
  catch (error) { return jsonError(error); }
}

export async function DELETE(request: Request) {
  try {
    assertBrowserAccess(request);
    const body = await request.json() as { deviceId?: string };
    if (!body.deviceId) throw new Error("Device ID is required");
    await revokeDevice(body.deviceId);
    return Response.json({ ok: true, data: { deviceId: body.deviceId } });
  } catch (error) { return jsonError(error); }
}
