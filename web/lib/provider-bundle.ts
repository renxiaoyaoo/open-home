type AccessRoute = "login" | "profile" | "communities" | "homeItems" | "allItems" | "sortItems" | "operate" | "sms";
type DeviceRoute = "sms" | "login" | "refresh" | "homes" | "devices" | "templateMap" | "templateGet" | "properties" | "action";
type LockRoute = "loginToken" | "login" | "devices" | "detail" | "securityLogs" | "operationLogs" | "temporaryPasswordCount" | "temporaryPasswordCreate" | "users" | "thumbnail";
type AutoRoute = "login" | "vehicles" | "latestCondition" | "recentEnergy" | "historicalEnergy" | "climateStatus" | "location";

export type ProviderBundle = {
  schemaVersion: 1;
  access: {
    baseUrls: Record<"mobile" | "app" | "gateway", string>;
    credentials: { appId: string; appSecret: string; encryptionKey: string; signingKey: string };
    client: { version: string; channel: string; vendor: string; versionCode: string; platform: string };
    routes: Record<AccessRoute, string>;
    passwordModels: string[];
  };
  device: {
    baseUrl: string;
    credentials: { appId: string; appKey: string; iotKey: string; hmacKey: string; deviceId: string };
    client: { version: string; secretVersion: string; platformId: string; clientType: string; language: string; source: string; module: string };
    routes: Record<DeviceRoute, string>;
    properties: {
      program: string;
      power: string;
      parameters?: Partial<Record<"temperature_level" | "dry_level" | "dry_temp" | "crease_resist_old" | "dry_time_new", { property: string; type?: "boolean" }>>;
    };
    actions: Record<"start" | "pause" | "schedule" | "cancelSchedule", string>;
  };
  lock?: {
    baseUrl: string;
    identityCipher: string;
    client: Record<string, string>;
    routes: Record<LockRoute, string>;
    media: {
      baseUrl: string; route: string; eventRequest: Record<string, unknown>; thumbnailRequest: Record<string, unknown>; videoSignRequest?: Record<string, unknown>; successPath: string; successValue: string;
      alarmThumbnailTemplate: string;
      auth?: { route: string; appKey: string; appSecret: string; openId: string; action: string; signatureExclude: string[]; tokenPath: string; expiryPath: string };
    };
    fields: {
      deviceId: string; deviceName: string; detail: string; wifiName: string; wifiSignal: string;
      battery: string; cameraBattery: string; batteryUpdatedAt: string; profileName: string;
      logItems: string; logDate?: string; logTime: string; logContent: string; logPicture?: string; temporaryPasswordCount: string;
      mediaProductId: string; mediaDeviceName: string; mediaEvents: string;
      mediaEventId: string; mediaEventTime: string; mediaEventEndTime?: string; mediaEventType?: string; mediaThumbnail: string; mediaVideo?: string; mediaContext?: string; mediaListOver?: string; signedThumbnails: string; signedThumbnailUrl: string; signedVideoUrl?: string;
    };
  };
  auto?: {
    baseUrl: string;
    client: Record<string, string>;
    routes: Record<Exclude<AutoRoute, "location">, string> & Partial<Record<"location", string>>;
    locationResolver?: { baseUrl: string; key: string };
    codec: {
      tables: Record<string, string>;
      outerEncryptKey: string;
      outerDecryptKey: string;
      innerEncryptKey: string;
      innerDecryptKey: string;
      outerEncryptIv: string;
      outerDecryptIv: string;
      innerEncryptIv: string;
    };
  };
};

let source = "";
let cached: ProviderBundle | undefined;

function hasStrings(value: unknown, keys: readonly string[]) {
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return keys.every((key) => typeof record[key] === "string" && record[key] !== "");
}

export function isProviderBundle(value: unknown): value is ProviderBundle {
  if (!value || typeof value !== "object") return false;
  const bundle = value as Partial<ProviderBundle>;
  const access = bundle.access; const device = bundle.device; const lock = bundle.lock; const auto = bundle.auto;
  if (bundle.schemaVersion !== 1 || !access || !device) return false;
  if (!hasStrings(access.baseUrls, ["mobile", "app", "gateway"]) || !hasStrings(access.credentials, ["appId", "appSecret", "encryptionKey", "signingKey"]) || !hasStrings(access.client, ["version", "channel", "vendor", "versionCode", "platform"]) || !hasStrings(access.routes, ["login", "profile", "communities", "homeItems", "allItems", "sortItems", "operate", "sms"]) || !Array.isArray(access.passwordModels)) return false;
  if (!hasStrings(device, ["baseUrl"]) || !hasStrings(device.credentials, ["appId", "appKey", "iotKey", "hmacKey", "deviceId"]) || !hasStrings(device.client, ["version", "secretVersion", "platformId", "clientType", "language", "source", "module"]) || !hasStrings(device.routes, ["sms", "login", "refresh", "homes", "devices", "templateMap", "templateGet", "properties", "action"]) || !hasStrings(device.properties, ["program", "power"]) || !hasStrings(device.actions, ["start", "pause", "schedule", "cancelSchedule"])) return false;
  if (lock && (!hasStrings(lock, ["baseUrl", "identityCipher"]) || !hasStrings(lock.routes, ["loginToken", "login", "devices", "detail", "securityLogs", "operationLogs", "temporaryPasswordCount", "temporaryPasswordCreate", "users", "thumbnail"]) || !hasStrings(lock.media, ["baseUrl", "route", "successPath", "successValue", "alarmThumbnailTemplate"]) || !lock.media.alarmThumbnailTemplate.startsWith("/") || lock.media.alarmThumbnailTemplate.includes("://") || !lock.media.alarmThumbnailTemplate.includes("{pictureId}") || !hasStrings(lock.fields, ["deviceId", "deviceName", "detail", "wifiName", "wifiSignal", "battery", "cameraBattery", "batteryUpdatedAt", "profileName", "logItems", "logTime", "logContent", "temporaryPasswordCount", "mediaProductId", "mediaDeviceName", "mediaEvents", "mediaEventId", "mediaEventTime", "mediaThumbnail", "signedThumbnails", "signedThumbnailUrl"]))) return false;
  if (auto && (!hasStrings(auto, ["baseUrl"]) || !hasStrings(auto.routes, ["login", "vehicles", "latestCondition", "recentEnergy", "historicalEnergy", "climateStatus"]) || (auto.locationResolver && !hasStrings(auto.locationResolver, ["baseUrl", "key"])) || !hasStrings(auto.codec, ["outerEncryptKey", "outerDecryptKey", "innerEncryptKey", "innerDecryptKey", "outerEncryptIv", "outerDecryptIv", "innerEncryptIv"]) || !auto.codec.tables || typeof auto.codec.tables !== "object")) return false;
  return true;
}

export function providerBundle(): ProviderBundle {
  const partCount = Number.parseInt(process.env.OPENHOME_PROVIDER_BUNDLE_PART_COUNT || "0", 10);
  const value = partCount > 0 && partCount <= 32
    ? Array.from({ length: partCount }, (_, index) => process.env[`OPENHOME_PROVIDER_BUNDLE_PART_${index}`] || "").join("")
    : process.env.OPENHOME_PROVIDER_BUNDLE?.trim() || "";
  if (!value) throw new Error("Provider bundle is not configured");
  if (value === source && cached) return cached;
  let parsed: unknown;
  try { parsed = JSON.parse(value); } catch { throw new Error("Provider bundle is invalid"); }
  if (!isProviderBundle(parsed)) {
    throw new Error("Provider bundle schema is unsupported");
  }
  const bundle = parsed;
  source = value; cached = bundle; return bundle;
}

export function accessRoute(name: AccessRoute) {
  const route = providerBundle().access.routes[name];
  if (!route || route.startsWith("/") || route.includes("://")) throw new Error(`Provider route is invalid: ${name}`);
  return route;
}

export function deviceRoute(name: DeviceRoute, values: Record<string, string> = {}) {
  let route = providerBundle().device.routes[name];
  if (!route || route.includes("://")) throw new Error(`Provider route is invalid: ${name}`);
  for (const [key, value] of Object.entries(values)) route = route.replaceAll(`{${key}}`, encodeURIComponent(value));
  if (/\{[^}]+\}/.test(route)) throw new Error(`Provider route parameters are incomplete: ${name}`);
  return route;
}

export function lockRoute(name: LockRoute) {
  const route = providerBundle().lock?.routes[name];
  if (!route || !route.startsWith("/") || route.includes("://")) throw new Error(`Provider route is invalid: ${name}`);
  return route;
}

export function autoRoute(name: AutoRoute) {
  const route = providerBundle().auto?.routes[name];
  if (!route || !route.startsWith("/") || route.includes("://")) throw new Error(`Provider route is invalid: ${name}`);
  return route;
}
