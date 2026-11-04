import { NextResponse } from "next/server";
import { assertClientAccess } from "@/lib/central";
import { jsonError } from "@/lib/http";
import { setProviderDoorSelected } from "@/lib/access-service";

export async function PATCH(request: Request, context: { params: Promise<{ doorKey: string }> }) {
  try {
    await assertClientAccess(request);
    const body = await request.json() as { selected?: unknown };
    const doorKey = (await context.params).doorKey;
    if (typeof body.selected !== "boolean") throw new Error("选择状态无效");
    await setProviderDoorSelected(doorKey, body.selected);
    return NextResponse.json({ ok: true, data: { selected: body.selected } });
  } catch (error) { return jsonError(error); }
}
