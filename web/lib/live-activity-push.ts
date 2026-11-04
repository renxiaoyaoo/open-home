import { createHash, sign } from "node:crypto";
import { liveActivityTargets, markLiveActivityPushed, removeLiveActivityTarget, type LiveActivityEnvironment, type LiveActivityProvider } from "./live-activities.ts";

const APPLE_REFERENCE_DATE_OFFSET = 978_307_200;

export type LiveActivityState = {
  title: string;
  state: string;
  detail?: string | null;
  progress?: number | null;
  expectedEnd?: Date | null;
};

export type APNsConfiguration = { keyId: string; teamId: string; bundleId: string; privateKey: string };
export type APNsRequest = { url: string; headers: Record<string, string>; body: string };
export type APNsResult = { status: number; reason?: string };
export interface LiveActivityPushTransport { send(request: APNsRequest): Promise<APNsResult> }

export class FetchLiveActivityPushTransport implements LiveActivityPushTransport {
  private readonly request: typeof fetch;
  constructor(request: typeof fetch = fetch) { this.request = request; }
  async send(request: APNsRequest): Promise<APNsResult> {
    const response = await this.request(request.url, { method: "POST", headers: request.headers, body: request.body });
    const payload = await response.json().catch(() => ({})) as { reason?: unknown };
    return { status: response.status, reason: typeof payload.reason === "string" ? payload.reason : undefined };
  }
}

export class APNsProviderTokenCache {
  private cached?: { identity: string; issuedAt: number; token: string };
  token(configuration: Pick<APNsConfiguration, "keyId" | "teamId" | "privateKey">, now = Math.floor(Date.now() / 1000)) {
    const identity = `${configuration.keyId}:${configuration.teamId}:${configuration.privateKey}`;
    if (!this.cached || this.cached.identity !== identity || now < this.cached.issuedAt || now - this.cached.issuedAt >= 50 * 60) {
      this.cached = { identity, issuedAt: now, token: createAPNsProviderToken(configuration, now) };
    }
    return this.cached.token;
  }
}

const providerTokenCache = new APNsProviderTokenCache();

function base64url(value: string | Buffer) { return Buffer.from(value).toString("base64url"); }
function required(value: string, pattern: RegExp, label: string) { if (!pattern.test(value)) throw new Error(`${label} is invalid`); return value; }

export function apnsConfiguration(environment: NodeJS.ProcessEnv = process.env): APNsConfiguration {
  const encodedKey = environment.OPENHOME_APNS_PRIVATE_KEY_BASE64 || "";
  let privateKey = "";
  try { privateKey = Buffer.from(encodedKey, "base64").toString("utf8"); } catch { throw new Error("APNs private key is invalid"); }
  if (!privateKey.includes("BEGIN PRIVATE KEY")) throw new Error("APNs private key is not configured");
  return {
    keyId: required(environment.OPENHOME_APNS_KEY_ID || "", /^[A-Z0-9]{10}$/, "APNs key ID"),
    teamId: required(environment.OPENHOME_APPLE_TEAM_ID || "", /^[A-Z0-9]{10}$/, "Apple team ID"),
    bundleId: required(environment.OPENHOME_IOS_BUNDLE_ID || "", /^[A-Za-z0-9.-]{3,255}$/, "Bundle ID"),
    privateKey,
  };
}

export function createAPNsProviderToken(configuration: Pick<APNsConfiguration, "keyId" | "teamId" | "privateKey">, issuedAt = Math.floor(Date.now() / 1000)) {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: required(configuration.keyId, /^[A-Z0-9]{10}$/, "APNs key ID") }));
  const claims = base64url(JSON.stringify({ iss: required(configuration.teamId, /^[A-Z0-9]{10}$/, "Apple team ID"), iat: issuedAt }));
  const message = `${header}.${claims}`;
  const signature = sign("sha256", Buffer.from(message), { key: configuration.privateKey, dsaEncoding: "ieee-p1363" });
  return `${message}.${base64url(signature)}`;
}

export function liveActivityPayload(state: LiveActivityState, event: "update" | "end" = "update", now = new Date()) {
  const contentState: Record<string, unknown> = { title: state.title, state: state.state, detail: state.detail ?? null, progress: state.progress ?? null, expectedEnd: state.expectedEnd ? state.expectedEnd.getTime() / 1000 - APPLE_REFERENCE_DATE_OFFSET : null };
  const aps: Record<string, unknown> = { timestamp: Math.floor(now.getTime() / 1000), event, "content-state": contentState };
  if (state.expectedEnd && event === "update") aps["stale-date"] = Math.floor(state.expectedEnd.getTime() / 1000);
  return { aps };
}

export function apnsLiveActivityRequest(configuration: APNsConfiguration, environment: LiveActivityEnvironment, pushToken: string, state: LiveActivityState, event: "update" | "end" = "update", priority: 5 | 10 = 5, now = new Date(), tokenCache: APNsProviderTokenCache = providerTokenCache): APNsRequest {
  const bundleId = required(configuration.bundleId, /^[A-Za-z0-9.-]{3,255}$/, "Bundle ID");
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  return {
    url: `https://${host}/3/device/${pushToken}`,
    headers: {
      authorization: `bearer ${tokenCache.token(configuration, Math.floor(now.getTime() / 1000))}`,
      "apns-topic": `${bundleId}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": String(priority),
      "content-type": "application/json",
    },
    body: JSON.stringify(liveActivityPayload(state, event, now)),
  };
}

export async function publishLiveActivity(provider: LiveActivityProvider, resourceId: string, state: LiveActivityState, event: "update" | "end", configuration: APNsConfiguration, transport: LiveActivityPushTransport) {
  const targets = await liveActivityTargets(provider, resourceId);
  const stateHash = createHash("sha256").update(JSON.stringify({ event, state: { ...state, expectedEnd: state.expectedEnd?.toISOString() ?? null } })).digest("hex");
  const results = await Promise.all(targets.map(async (target) => {
    if (event === "update" && target.lastStateHash === stateHash) return { activityId: target.activityId, status: 304, skipped: true };
    const result = await transport.send(apnsLiveActivityRequest(configuration, target.environment, target.pushToken, state, event));
    if (result.status === 410 || result.reason === "BadDeviceToken" || result.reason === "Unregistered" || (event === "end" && result.status >= 200 && result.status < 300)) await removeLiveActivityTarget(target.activityId);
    else if (result.status >= 200 && result.status < 300) await markLiveActivityPushed(target.activityId, stateHash);
    return { activityId: target.activityId, ...result, skipped: false };
  }));
  return results;
}
