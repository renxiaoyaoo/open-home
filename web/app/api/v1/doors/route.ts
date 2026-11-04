import { NextResponse } from "next/server";
import { assertClientAccess } from "@/lib/central";
import { refreshPublicDoors } from "@/lib/access-service";
import { jsonError } from "@/lib/http";

export async function GET(request: Request) {
  try {
    await assertClientAccess(request);
    const result = await refreshPublicDoors();
    return NextResponse.json({ ok: true, data: result.doors, meta: { accountCount: result.accountCount, failedAccountCount: result.failedAccountCount, expiredAccountCount: result.expiredAccountCount } });
  } catch (error) { return jsonError(error); }
}
