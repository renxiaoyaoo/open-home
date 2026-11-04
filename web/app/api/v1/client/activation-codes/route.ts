import { assertAdmin, createActivation } from "@/lib/client-auth";

export async function POST(request: Request) {
  try { assertAdmin(request); const body = await request.json().catch(() => ({})) as { publicAPIURL?: string; lifetimeMinutes?: number }; return Response.json({ ok: true, data: await createActivation(String(body.publicAPIURL || ""), Number(body.lifetimeMinutes || 10)) }); }
  catch (error) { return Response.json({ ok: false, message: error instanceof Error ? error.message : "Activation creation failed" }, { status: 401 }); }
}
