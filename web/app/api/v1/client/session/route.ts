import { authenticateDevice } from "@/lib/client-auth";
import { jsonError } from "@/lib/http";

export async function GET(request: Request) {
  try {
    const device = await authenticateDevice(request);
    return Response.json({
      ok: true,
      data: {
        deviceId: device.deviceID,
        deviceName: device.deviceName,
        createdAt: new Date(device.createdAt).toISOString(),
        serverTime: new Date().toISOString(),
      },
    });
  } catch (error) {
    return jsonError(error);
  }
}
