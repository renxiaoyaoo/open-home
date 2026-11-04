import { assertAdmin } from "@/lib/client-auth";
import { jsonError } from "@/lib/http";
import { refreshLiveActivities } from "@/lib/live-activity-refresh";

export async function POST(request: Request) {
  try {
    assertAdmin(request);
    return Response.json({ ok: true, data: await refreshLiveActivities() });
  } catch (error) { return jsonError(error); }
}
