import { NextResponse } from "next/server";
import { assertClientAccess } from "@/lib/central";
import { publicDoorPassword } from "@/lib/access-service";
import { jsonError } from "@/lib/http";

export async function GET(request: Request, context: { params: Promise<{ doorKey: string }> }) {
  try { await assertClientAccess(request); return NextResponse.json({ ok: true, data: await publicDoorPassword((await context.params).doorKey) }); }
  catch (error) { return jsonError(error); }
}
