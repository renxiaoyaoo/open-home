import { callDryerAdapter, dryerOperation, type DryerOperation } from "@/lib/dryer-adapter";
import { isAuthenticationExpired } from "@/lib/provider";

type Context = { params: Promise<{ operation: string }> };

async function handle(request: Request, context: Context) {
  try {
    const { operation } = await context.params;
    dryerOperation(operation);
    return await callDryerAdapter(operation as DryerOperation, request);
  } catch (error) {
    const message = error instanceof Error ? error.message : "干衣机请求失败";
    const sessionExpired = isAuthenticationExpired(error) || /65012|令牌密码无效|account is not signed in|invalid session data|unable to authenticate data/i.test(message);
    return Response.json({ ok: false, message: sessionExpired ? "登录已失效，请重新登录" : message }, { status: sessionExpired ? 401 : message.includes("配置") ? 503 : 502 });
  }
}

export const GET = handle;
export const POST = handle;
