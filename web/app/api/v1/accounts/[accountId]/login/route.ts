import { NextResponse } from "next/server";
import { assertClientAccess, validAccountId } from "@/lib/central";
import { centralLogin } from "@/lib/provider-service";
import { jsonError } from "@/lib/http";

export async function POST(request: Request, context: { params: Promise<{ accountId: string }> }) {
  let accountId = "";
  try {
    await assertClientAccess(request); accountId = validAccountId((await context.params).accountId);
    const { mobile, smsCode } = await request.json() as { mobile?: string; smsCode?: string };
    if (!mobile || !/^1\d{10}$/.test(mobile) || !smsCode || !/^\d{6}$/.test(smsCode)) return NextResponse.json({ ok: false, message: "手机号或 6 位验证码格式错误" }, { status: 400 });
    await centralLogin(accountId, mobile, smsCode); return NextResponse.json({ ok: true });
  } catch (error) { return jsonError(error); }
}
