import { NextResponse } from "next/server";
import { assertClientAccess } from "@/lib/central";
import { setProviderDoorOrder } from "@/lib/access-service";
import { jsonError } from "@/lib/http";

export async function PUT(request: Request) {
  try {
    await assertClientAccess(request);
    const body = await request.json() as { ids?: unknown; previousIds?: unknown };
    const ids = stringList(body.ids);
    const previousIds = stringList(body.previousIds ?? []);
    await setProviderDoorOrder(ids, previousIds);
    return NextResponse.json({ ok: true, data: { ids } });
  } catch (error) { return jsonError(error); }
}

function stringList(value: unknown) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string" || !item)) throw new Error("门禁顺序无效");
  return value as string[];
}
