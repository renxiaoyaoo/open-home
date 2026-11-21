import { NextResponse } from "next/server";
import { assertClientAccess } from "@/lib/central";
import { jsonError } from "@/lib/http";
import { setProviderDoorSelected } from "@/lib/access-service";

export async function PATCH(request: Request, context: { params: Promise<{ doorHandle: string }> }) {
  try {
    await assertClientAccess(request);
    const body = await request.json() as { selected?: unknown };
    const doorHandle = (await context.params).doorHandle;
    if (typeof body.selected !== "boolean") throw new Error("选择状态无效");
    const verified = await setProviderDoorSelected(doorHandle, body.selected);
    return NextResponse.json({ ok: true, data: verified.doors, message: verified.message }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) { return jsonError(error); }
}
