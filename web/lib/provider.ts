import { createCipheriv, createHash, randomInt, randomUUID } from "node:crypto";
import { providerBundle } from "./provider-bundle.ts";
type JsonMap = Record<string, unknown>;
export type ProviderRequestContext = { cookies: Record<string, string> };

export class UpstreamError extends Error {
  readonly payload?: unknown;
  constructor(message: string, payload?: unknown) { super(message); this.payload = payload; }
}

function assertSecrets(names: Array<"appid" | "secret" | "aes">) {
  const credentials = providerBundle().access.credentials;
  const APP_ID = credentials.appId; const APP_SECRET = credentials.appSecret; const MOBILE_AES_KEY = credentials.encryptionKey;
  const missing = names.filter((name) => name === "appid" ? !APP_ID : name === "secret" ? !APP_SECRET : !MOBILE_AES_KEY);
  if (missing.length) throw new UpstreamError("Provider configuration is incomplete");
}

export function signHeaders(params: JsonMap): Record<string, string> {
  assertSecrets(["appid", "secret"]);
  const { appId: APP_ID, appSecret: APP_SECRET } = providerBundle().access.credentials;
  const base = { appid: APP_ID, nonce: String(randomInt(1000, 10000)), timestamp: String(Date.now()), version: "v2" };
  const signing: Record<string, unknown> = { ...base, ...params };
  const canonical = Object.keys(signing).sort().map((key) => `${key}=${String(signing[key] ?? "")}`).join("&");
  return { ...base, sign: createHash("md5").update(`${canonical}&appsecret=${APP_SECRET}`).digest("hex").toUpperCase() };
}

type MobileSignOptions = { nonce?: string; timestamp?: number; token?: string; version?: string; exclude?: string[] };

/** Build the provider's signed mobile request body. */
export function signMobileBody(params: JsonMap, options: MobileSignOptions = {}): JsonMap {
  const { signingKey: MOBILE_SIGNING_KEY } = providerBundle().access.credentials;
  const { version: APP_VERSION } = providerBundle().access.client;
  if (!MOBILE_SIGNING_KEY) throw new UpstreamError("Provider signing key is not configured");
  const nonce = options.nonce ?? String(randomInt(0, 100000)).padStart(5, "0");
  if (!/^\d{5}$/.test(nonce)) throw new UpstreamError("随机数格式错误");
  const fixed: JsonMap = {
    ...(options.token ? { token: options.token } : {}),
    timestamp: options.timestamp ?? Date.now(),
    version: options.version ?? APP_VERSION,
    nonce,
  };
  const result: JsonMap = { ...params, ...fixed };
  const excluded = new Set(options.exclude ?? []);
  const canonical = Object.keys(result)
    .filter((key) => !excluded.has(key))
    .sort()
    .map((key) => `${key}=${String(result[key] ?? "")}`)
    .join("&");
  // The provider app uppercases the hexadecimal digest before putting it on the wire.
  // Login happens to tolerate lowercase, but authenticated endpoints do not.
  result.sign = createHash("md5").update(`${canonical}&key=${MOBILE_SIGNING_KEY}`).digest("hex").toUpperCase();
  // The app signs with the stored session as `token`, then removes `token`
  // before sending. Authentication on the wire is the `sessionId` query
  // parameter; timestamp/version/nonce/sign remain in the body.
  delete result.token;
  return result;
}

export function encryptMobile(mobile: string): string {
  assertSecrets(["aes"]);
  const MOBILE_AES_KEY = providerBundle().access.credentials.encryptionKey;
  if (!/^[0-9a-fA-F]{32}$/.test(MOBILE_AES_KEY)) throw new UpstreamError("手机号加密参数格式错误");
  // The configured 32-character key is hexadecimal AES-128 key material.
  const key = Buffer.from(MOBILE_AES_KEY, "hex");
  // Cloudflare's Node crypto compatibility layer rejects null even though ECB
  // does not use an IV. A zero-length buffer is accepted by both runtimes.
  const cipher = createCipheriv("aes-128-ecb", key, Buffer.alloc(0));
  cipher.setAutoPadding(true);
  // The provider expects uppercase hexadecimal output, not Base64.
  return Buffer.concat([cipher.update(mobile, "utf8"), cipher.final()]).toString("hex").toUpperCase();
}

export function deviceId(value?: string) { return value && /^[0-9a-f-]{36}$/i.test(value) ? value : randomUUID(); }

export type ProviderService = "mobile" | "app" | "gateway";

export function providerUrl(service: ProviderService, path: string) {
  if (path.startsWith("/") || path.includes("://")) throw new UpstreamError("上游接口路径无效");
  const base = providerBundle().access.baseUrls[service];
  if (!base) throw new UpstreamError(`Provider endpoint is not configured: ${service}`);
  return new URL(path, base);
}

export function appendRawSessionId(url: URL, sessionId?: string) {
  if (!sessionId) return url.toString();
  // Preserve literal query behavior while rejecting delimiters.
  if (!/^[0-9A-Za-z:._~-]+$/.test(sessionId)) throw new UpstreamError("登录凭据格式错误");
  return `${url.toString()}${url.search ? "&" : "?"}sessionId=${sessionId}`;
}

export function absorbSetCookies(context: ProviderRequestContext, values: string[]) {
  for (const value of values) {
    for (const cookie of value.split(/,(?=\s*[^;,=\s]+=[^;,]*)/)) {
      const pair = cookie.split(";", 1)[0]?.trim();
      const separator = pair?.indexOf("=") ?? -1;
      if (!pair || separator <= 0) continue;
      context.cookies[pair.slice(0, separator).trim()] = pair.slice(separator + 1).trim();
    }
  }
}

export function cookieHeader(context: ProviderRequestContext) {
  return Object.entries(context.cookies).map(([name, value]) => `${name}=${value}`).join("; ");
}

export async function providerPost(service: ProviderService, path: string, body: JsonMap, options?: { sessionId?: string; signingToken?: string | null; signing?: "legacy-header" | "mobile-body"; signingExclude?: string[]; openId?: string; encoding?: "json" | "form" | "multipart" | "query"; context?: ProviderRequestContext }) {
  const client = providerBundle().access.client;
  const url = providerUrl(service, path);
  const signingToken = options?.signingToken === undefined ? options?.sessionId : options.signingToken ?? undefined;
  const requestBody = options?.signing === "mobile-body" ? signMobileBody(body, { token: signingToken, exclude: options.signingExclude }) : body;
  const signedHeaders = options?.signing === "legacy-header" ? signHeaders(body) : {};
  const encoding = options?.encoding ?? "json";
  const headers: Record<string, string> = {
    ...(encoding === "multipart" ? {} : { "content-type": encoding === "form" ? "application/x-www-form-urlencoded" : "application/json; charset=utf-8" }), accept: "application/json", qversioncode: client.versionCode,
    qchannel: client.channel, qplatform: client.platform, openId: options?.openId || randomUUID(), qvendor: client.vendor,
    ...signedHeaders,
  };
  const cookies = options?.context ? cookieHeader(options.context) : "";
  if (cookies) headers.cookie = cookies;
  const serialized = new URLSearchParams(Object.entries(requestBody).map(([key, value]) => [key, String(value ?? "")]));
  // customType=0 business tasks append the current session literally. Login
  // uses customType=1, so it does not append an empty sessionId parameter.
  // For query-body calls the provider app puts sessionId before the signed fields.
  let requestUrl: string;
  if (encoding === "query") {
    const queryUrl = new URL(appendRawSessionId(url, options?.sessionId));
    for (const [key, value] of serialized) queryUrl.searchParams.set(key, value);
    requestUrl = queryUrl.toString();
  } else {
    requestUrl = appendRawSessionId(url, options?.sessionId);
  }
  const multipart = new FormData();
  if (encoding === "multipart") for (const [key, value] of Object.entries(requestBody)) multipart.set(key, String(value ?? ""));
  const requestData = encoding === "query" ? undefined : encoding === "form" ? serialized.toString() : encoding === "multipart" ? multipart : JSON.stringify(requestBody);
  const response = await fetch(requestUrl, { method: "POST", headers, body: requestData });
  if (options?.context) {
    const responseHeaders = response.headers as Headers & { getSetCookie?: () => string[] };
    const setCookies = responseHeaders.getSetCookie?.() ?? (response.headers.get("set-cookie") ? [response.headers.get("set-cookie")!] : []);
    absorbSetCookies(options.context, setCookies);
  }
  const payload = await response.json().catch(() => null) as JsonMap | null;
  if (!response.ok) throw new UpstreamError(`上游服务响应 ${response.status}`, payload);
  if (!payload) throw new UpstreamError("上游服务返回了无法识别的内容");
  return payload;
}

export function upstreamMessage(payload: JsonMap, fallback: string) {
  const message = payload.message ?? payload.msg;
  return typeof message === "string" && message.trim() ? message : fallback;
}

/** Recognize the provider's authenticated-session expiry responses. */
export function isAuthenticationExpired(error: unknown) {
  const message = error instanceof UpstreamError && error.payload && typeof error.payload === "object" && !Array.isArray(error.payload)
    ? upstreamMessage(error.payload as JsonMap, error.message)
    : error instanceof Error ? error.message : String(error ?? "");
  return /40002|还没有登录|登录已超时|重新登录|登录失效|移动平台token校验不通过|token.*(?:不存在|失效|过期|not\s+exist|invalid|expired)|session.*(?:失效|过期|invalid|expired)/i.test(message);
}
// The app's global response resolver and endpoint call sites compare code to 0.
export function isSuccess(payload: JsonMap) { return Number(payload.code) === 0; }

/** The SMS gateway can return a success code while declining delivery. */
export function isSmsAccepted(payload: JsonMap) {
  if (!isSuccess(payload)) return false;
  const message = upstreamMessage(payload, "");
  return !/(过于频繁|稍后再试|发送失败|验证码.*频繁)/i.test(message);
}

export function loginCredential(data: unknown) {
  if (!data || typeof data !== "object") return "";
  const value = data as JsonMap;
  // goPhoneLogin reads data["sessionId"] and passes that exact value to
  // UserManager.loginSuccess. A response may also contain a different token,
  // but it is not the credential used by the app's authenticated requests.
  return typeof value.sessionId === "string"
    ? value.sessionId
    : typeof value.token === "string" ? value.token : "";
}

function walk(value: unknown, visit: (item: JsonMap) => void) {
  if (Array.isArray(value)) return value.forEach((item) => walk(item, visit));
  if (!value || typeof value !== "object") return;
  const item = value as JsonMap; visit(item); Object.values(item).forEach((child) => walk(child, visit));
}

export function communityIds(payload: unknown): number[] {
  const found = new Set<number>();
  walk(payload, (item) => { const id = Number(item.communityId); if (Number.isSafeInteger(id) && id > 0) found.add(id); });
  return [...found];
}

function passwordModels() { return new Set(providerBundle().access.passwordModels || []); }
export type Door = { doorControlId: number; communityId: number; name: string; communityName?: string; communityCode?: string; mac?: string; deviceModel?: string; passwordSupported?: boolean; providerFeatured?: boolean; providerOrder?: number };

type DoorSortCategory = "gate" | "building" | "custom";
type DoorSortState = {
  common: number[];
  gate: number[];
  building: number[];
  custom: number[];
  categories: Map<number, DoorSortCategory>;
  gateDoorColor: number;
  buildingDoorColor: number;
  customDoorColor: number;
};

function safeDoorIds(value: unknown) {
  const ids: number[] = [];
  walk(value, (item) => {
    const id = Number(item.doorControlId ?? item.doorId);
    if (Number.isSafeInteger(id) && id > 0 && !ids.includes(id)) ids.push(id);
  });
  return ids;
}

function doorUseforCategory(value: unknown): DoorSortCategory | undefined {
  if (value === "大门") return "gate";
  if (value === "单元门或楼栋门") return "building";
  if (value === "其它") return "custom";
  return undefined;
}

/** Recover the provider's door-sort state from the configured complete list. */
export function doorSortState(payload: unknown): DoorSortState {
  let source: JsonMap | null = null;
  walk(payload, (item) => {
    if (!source && ("commonlyUsedDoor" in item || "gateDoorList" in item || "buildingDoorList" in item || "customDoorList" in item)) source = item;
  });
  if (!source) throw new UpstreamError("门禁分类数据缺失，请刷新后重试");
  const record = source as JsonMap;
  const gate = safeDoorIds(record.gateDoorList);
  const building = safeDoorIds(record.buildingDoorList);
  const custom = safeDoorIds(record.customDoorList);
  const common = safeDoorIds(record.commonlyUsedDoor);
  const categories = new Map<number, DoorSortCategory>();
  gate.forEach((id) => categories.set(id, "gate"));
  building.forEach((id) => categories.set(id, "building"));
  custom.forEach((id) => categories.set(id, "custom"));
  walk(record.commonlyUsedDoor, (item) => {
    const id = Number(item.doorControlId ?? item.doorId);
    const category = doorUseforCategory(item.doorControlUsefor);
    if (Number.isSafeInteger(id) && id > 0 && category) categories.set(id, category);
  });
  const color = (key: string) => Number.isInteger(Number(record[key])) ? Number(record[key]) : -1;
  return { common, gate, building, custom, categories, gateDoorColor: color("gateDoorColor"), buildingDoorColor: color("buildingDoorColor"), customDoorColor: color("customDoorColor") };
}

/** Build the exact body used by the provider's homepage key editor. */
export function doorSortBody(payload: unknown, communityId: number, doorControlId: number, selected: boolean): JsonMap {
  if (!Number.isSafeInteger(communityId) || communityId <= 0 || !Number.isSafeInteger(doorControlId) || doorControlId <= 0) throw new UpstreamError("门禁参数无效");
  const state = doorSortState(payload);
  const category = state.categories.get(doorControlId);
  if (!category) throw new UpstreamError("无法识别该门禁的官方分类");
  const without = (ids: number[]) => ids.filter((id) => id !== doorControlId);
  const common = without(state.common);
  const groups = { gate: without(state.gate), building: without(state.building), custom: without(state.custom) };
  if (selected) common.push(doorControlId);
  else groups[category].push(doorControlId);
  return {
    list: [{ commondoorControlIds: common, gatedoorControlIds: groups.gate, buildingDoorList: groups.building, customDoorList: groups.custom }],
    method: "doorSort",
    commId: communityId,
    gateDoorColor: state.gateDoorColor,
    buildingDoorColor: state.buildingDoorColor,
    customDoorColor: state.customDoorColor,
  };
}

export function communityCodes(payload: unknown): Map<number, string> {
  const found = new Map<number, string>();
  walk(payload, (item) => {
    const id = Number(item.communityId);
    const code = item.communityCode;
    if (Number.isSafeInteger(id) && id > 0 && (typeof code === "string" || typeof code === "number")) found.set(id, String(code));
  });
  return found;
}
export function communityNames(payload: unknown): Map<number, string> {
  const found = new Map<number, string>();
  walk(payload, (item) => {
    const id = Number(item.communityId);
    const name = item.communityName ?? item.commName;
    if (Number.isSafeInteger(id) && id > 0 && typeof name === "string" && name.trim()) found.set(id, name.trim());
  });
  return found;
}
export function normalizeDoors(payload: unknown, fallbackCommunityId: number, communityCode?: string, fallbackCommunityName?: string): Door[] {
  const found = new Map<string, Door>();
  walk(payload, (item) => {
    const doorControlId = Number(item.doorControlId ?? item.doorId);
    const communityId = Number(item.communityId ?? fallbackCommunityId);
    if (!Number.isSafeInteger(doorControlId) || doorControlId <= 0 || !Number.isSafeInteger(communityId) || communityId <= 0) return;
    const name = String(item.customDoorControlName ?? item.customName ?? item.doorControlName ?? item.doorName ?? item.name ?? item.unitName ?? item.buildingName ?? `门禁 ${doorControlId}`);
    const deviceModel = typeof item.deviceModel === "string" ? item.deviceModel : undefined;
    const communityName = typeof item.communityName === "string" && item.communityName.trim() ? item.communityName.trim() : fallbackCommunityName;
    const mac = typeof item.mac === "string" ? item.mac : typeof item.macAddress === "string" ? item.macAddress : undefined;
    found.set(`${communityId}:${doorControlId}`, {
      doorControlId, communityId, name,
      ...(communityName ? { communityName } : {}),
      ...(communityCode ? { communityCode } : {}),
      ...(mac ? { mac } : {}),
      ...(deviceModel ? { deviceModel, passwordSupported: passwordModels().has(deviceModel) } : {}),
    });
  });
  return [...found.values()];
}

/** Generate a provider-compatible time-bucketed access code. */
export function doorPassword(mac: string, communityCode: string, now = Date.now()) {
  if (!mac || !communityCode) throw new UpstreamError("该门禁缺少密码计算参数");
  const timeBucket = Math.floor(now / 600_000) * 600_000;
  const digits = createHash("md5").update(`${mac}${timeBucket}${communityCode}`).digest("hex").replace(/[^0-9]/g, "").trim();
  if (digits.length < 4) throw new UpstreamError("开门密码计算失败");
  return { password: digits.slice(-4), validUntil: new Date(timeBucket + 600_000).toISOString() };
}

export function supportsDoorPassword(deviceModel?: string) { return Boolean(deviceModel && passwordModels().has(deviceModel)); }

export function dedupeDoors(doors: Door[]) {
  const found = new Map<string, Door>();
  for (const door of doors) found.set(`${door.communityId}:${door.doorControlId}`, door);
  return [...found.values()];
}

export function openDoorBody(doorControlId: number, communityId: number) {
  if (!Number.isSafeInteger(doorControlId) || doorControlId <= 0 || !Number.isSafeInteger(communityId) || communityId <= 0) {
    throw new UpstreamError("门禁参数无效");
  }
  return { appChannel: 1, doorControlId, communityId };
}

export function serializeUpstreamCookies(context: ProviderRequestContext) {
  return JSON.stringify(context.cookies);
}

export function parseUpstreamCookies(value: string): ProviderRequestContext {
  if (!value) return { cookies: {} };
  try {
    const parsed = JSON.parse(value) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return { cookies: {} };
    const cookies: Record<string, string> = {};
    for (const [name, cookieValue] of Object.entries(parsed)) {
      if (/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(name) && typeof cookieValue === "string" && !/[\r\n;]/.test(cookieValue)) cookies[name] = cookieValue;
    }
    return { cookies };
  } catch { return { cookies: {} }; }
}
