import handler from "vinext/server/fetch-handler";
import { withDatabase } from "./db";
import { refreshLiveActivities } from "./lib/live-activity-refresh";
import { isNativeAPIOrigin } from "./lib/native-api-origin";

const worker = {
  fetch(request: Request, env: Cloudflare.Env, ctx: ExecutionContext) {
    if (isNativeAPIOrigin(request.url, env.OPENHOME_PUBLIC_API_URL) && !new URL(request.url).pathname.startsWith("/api/v1/")) {
      return new Response("Not found", { status: 404 });
    }
    return withDatabase(env.DB as import("./db").Database, () => handler.fetch(request, env, ctx));
  },
  scheduled(_controller: ScheduledController, env: Cloudflare.Env, ctx: ExecutionContext) {
    ctx.waitUntil(withDatabase(env.DB as import("./db").Database, () => refreshLiveActivities()).then(() => undefined));
  },
};

export default worker;
