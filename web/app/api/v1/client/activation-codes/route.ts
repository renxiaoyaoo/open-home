import { activationStatus, assertAdmin, configuredPublicAPIURL, createActivation } from "@/lib/client-auth";
import { assertBrowserAccess } from "@/lib/central";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({})) as { publicAPIURL?: string; lifetimeMinutes?: number };
    const administrator = Boolean(request.headers.get("authorization"));
    if (administrator) assertAdmin(request); else assertBrowserAccess(request);
    const publicAPIURL = administrator && body.publicAPIURL ? String(body.publicAPIURL) : configuredPublicAPIURL(request.url);
    return Response.json({ ok: true, data: await createActivation(publicAPIURL, Number(body.lifetimeMinutes || 10)) });
  }
  catch (error) { return Response.json({ ok: false, message: error instanceof Error ? error.message : "Activation creation failed" }, { status: 401 }); }
}

export async function GET(request: Request) {
  try {
    const administrator = Boolean(request.headers.get("authorization"));
    if (administrator) assertAdmin(request); else assertBrowserAccess(request);
    const id = new URL(request.url).searchParams.get("id") || "";
    return Response.json({ ok: true, data: await activationStatus(id) });
  }
  catch (error) { return Response.json({ ok: false, message: error instanceof Error ? error.message : "Activation status failed" }, { status: 401 }); }
}
