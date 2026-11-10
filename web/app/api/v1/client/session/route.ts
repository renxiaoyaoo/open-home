import { authenticateDevice, revokeDevice } from "@/lib/client-auth";
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

export async function DELETE(request: Request) {
  try {
    const device = await authenticateDevice(request);
    await revokeDevice(device.deviceID);
    return Response.json({ ok: true, data: { deviceId: device.deviceID } });
  } catch (error) {
    return jsonError(error);
  }
}
