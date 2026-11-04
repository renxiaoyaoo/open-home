import { getDb } from "../db/index.ts";

export type LiveActivityProvider = "living" | "auto";
export type LiveActivityEnvironment = "sandbox" | "production";

function identifier(value: unknown, label: string) {
  const text = String(value || "").trim();
  if (!text || text.length > 160 || !/^[A-Za-z0-9._:-]+$/.test(text)) throw new Error(`${label} is invalid`);
  return text;
}

function provider(value: unknown): LiveActivityProvider {
  if (value !== "living" && value !== "auto") throw new Error("Live Activity provider is invalid");
  return value;
}

function environment(value: unknown): LiveActivityEnvironment {
  if (value !== "sandbox" && value !== "production") throw new Error("Live Activity environment is invalid");
  return value;
}

function pushToken(value: unknown) {
  const token = String(value || "").toLowerCase();
  if (!/^[0-9a-f]{64,512}$/.test(token) || token.length % 2 !== 0) throw new Error("Live Activity push token is invalid");
  return token;
}

export async function registerLiveActivity(deviceId: string, input: { activityId?: unknown; provider?: unknown; resourceId?: unknown; pushToken?: unknown; environment?: unknown }) {
  const activityId = identifier(input.activityId, "Live Activity ID");
  const resourceId = identifier(input.resourceId, "Live Activity resource ID");
  const providerId = provider(input.provider);
  const token = pushToken(input.pushToken);
  const targetEnvironment = environment(input.environment);
  const now = Date.now();
  await (await getDb()).prepare("INSERT INTO live_activities (activity_id,device_id,provider,resource_id,push_token,environment,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(device_id,provider,resource_id) DO UPDATE SET activity_id=excluded.activity_id,push_token=excluded.push_token,environment=excluded.environment,updated_at=excluded.updated_at").bind(activityId, deviceId, providerId, resourceId, token, targetEnvironment, now, now).run();
  return { activityId };
}

export async function unregisterLiveActivity(deviceId: string, rawActivityId: unknown) {
  const activityId = identifier(rawActivityId, "Live Activity ID");
  await (await getDb()).prepare("DELETE FROM live_activities WHERE activity_id=? AND device_id=?").bind(activityId, deviceId).run();
  return { activityId };
}

export async function liveActivityTargets(providerId: LiveActivityProvider, resourceId: string) {
  const rows = (await (await getDb()).prepare("SELECT l.activity_id AS activityId,l.push_token AS pushToken,l.environment FROM live_activities l JOIN client_devices d ON d.id=l.device_id WHERE l.provider=? AND l.resource_id=? AND d.revoked_at IS NULL").bind(providerId, resourceId).all<{ activityId: string; pushToken: string; environment: LiveActivityEnvironment }>()).results;
  return rows.map((row) => ({ activityId: row.activityId, pushToken: row.pushToken, environment: row.environment }));
}
