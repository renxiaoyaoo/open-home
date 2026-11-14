import { assertAdmin, configuredPublicAPIURL, createActivation } from "@/lib/client-auth";
import { assertBrowserAccess } from "@/lib/central";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({})) as { publicAPIURL?: string; lifetimeMinutes?: number };
    const administrator = Boolean(request.headers.get("authorization"));
    if (administrator) assertAdmin(request); else assertBrowserAccess(request);
    const publicAPIURL = administrator && body.publicAPIURL ? String(body.publicAPIURL) : configuredPublicAPIURL();
    return Response.json({ ok: true, data: await createActivation(publicAPIURL, Number(body.lifetimeMinutes || 10)) });
  }
  catch (error) { return Response.json({ ok: false, message: error instanceof Error ? error.message : "Activation creation failed" }, { status: 401 }); }
}
