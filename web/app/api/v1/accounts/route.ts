import { NextResponse } from "next/server";
import { assertClientAccess, publicAccounts } from "@/lib/central";
import { jsonError } from "@/lib/http";

export async function GET(request: Request) {
  try { await assertClientAccess(request); return NextResponse.json({ ok: true, data: await publicAccounts() }); }
  catch (error) { return jsonError(error); }
}
