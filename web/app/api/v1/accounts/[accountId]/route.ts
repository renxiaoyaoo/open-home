import { NextResponse } from "next/server";
import { assertClientAccess, removeAccount, validAccountId } from "@/lib/central";
import { jsonError } from "@/lib/http";

export async function DELETE(request: Request, context: { params: Promise<{ accountId: string }> }) {
  let accountId = "";
  try {
    await assertClientAccess(request);
    accountId = validAccountId((await context.params).accountId);
    await removeAccount(accountId);
    return NextResponse.json({ ok: true, message: "账号已退出" });
  } catch (error) {
    return jsonError(error);
  }
}
