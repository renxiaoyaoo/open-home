import { callOpenAuto } from "@/lib/openauto-adapter";
import { OpenAutoUpstreamError } from "@/lib/openauto-provider";

type Context = { params: Promise<{ operation: string }> };
async function handle(request: Request, context: Context) {
  try { return await callOpenAuto((await context.params).operation, request); }
  catch (error) { const message = error instanceof Error ? error.message : "车辆请求失败"; const code = error instanceof OpenAutoUpstreamError ? error.code : undefined; console.warn("OpenAuto request failed", { operation: (await context.params).operation, code, message }); const expired = code === "224" || /account is not signed in|登录.*失效|token.*(?:失效|过期)/i.test(message); return Response.json({ ok: false, message: expired ? "登录已失效，请重新登录" : message }, { status: expired ? 401 : message.includes("配置") ? 503 : 502 }); }
}
export const GET = handle;
export const POST = handle;
