import { NextResponse } from "next/server";
import { assertClientAccess } from "@/lib/central";
import { openPublicDoor } from "@/lib/access-service";
import { jsonError } from "@/lib/http";

export async function POST(request: Request, context: { params: Promise<{ doorHandle: string }> }) {
  try {
    await assertClientAccess(request);
    const result = await openPublicDoor((await context.params).doorHandle, request.headers.get("idempotency-key") || "");
    return NextResponse.json(result, { status: result.ok ? 200 : 400 });
  } catch (error) { return jsonError(error); }
}
