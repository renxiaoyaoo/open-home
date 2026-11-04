import { authenticateDevice } from "@/lib/client-auth";
import { jsonError } from "@/lib/http";
import { registerLiveActivity, unregisterLiveActivity } from "@/lib/live-activities";

export async function POST(request: Request) {
  try {
    const { deviceID } = await authenticateDevice(request);
    return Response.json({ ok: true, data: await registerLiveActivity(deviceID, await request.json()) });
  } catch (error) { return jsonError(error); }
}

export async function DELETE(request: Request) {
  try {
    const { deviceID } = await authenticateDevice(request);
    const body = await request.json() as { activityId?: unknown };
    return Response.json({ ok: true, data: await unregisterLiveActivity(deviceID, body.activityId) });
  } catch (error) { return jsonError(error); }
}
