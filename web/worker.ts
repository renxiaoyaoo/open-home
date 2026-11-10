import handler from "vinext/server/fetch-handler";
import { withDatabase } from "./db";
import { refreshLiveActivities } from "./lib/live-activity-refresh";

const worker = {
  fetch(request: Request, env: Cloudflare.Env, ctx: ExecutionContext) {
    return withDatabase(env.DB as import("./db").Database, () => handler.fetch(request, env, ctx));
  },
  scheduled(_controller: ScheduledController, env: Cloudflare.Env, ctx: ExecutionContext) {
    ctx.waitUntil(withDatabase(env.DB as import("./db").Database, () => refreshLiveActivities()).then(() => undefined));
  },
};

export default worker;
