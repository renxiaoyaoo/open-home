import { NextResponse } from "next/server";
import { isAuthenticationExpired, UpstreamError, upstreamMessage } from "./provider";
import { ClientAuthorizationError } from "./client-auth";
export function jsonError(error: unknown) {
  const status = error instanceof ClientAuthorizationError || isAuthenticationExpired(error) ? 401 : 502;
  if (error instanceof UpstreamError && error.payload && typeof error.payload === "object" && !Array.isArray(error.payload)) {
    const payload = error.payload as Record<string, unknown>;
    return NextResponse.json({
      ok: false,
      message: upstreamMessage(payload, error.message),
      diagnostic: { code: payload.code ?? null, fields: Object.keys(payload).sort() },
    }, { status });
  }
  const message = error instanceof Error ? error.message : "请求失败";
  return NextResponse.json({ ok: false, message }, { status });
}
