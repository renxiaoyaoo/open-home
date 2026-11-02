import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

process.env.OPENHOME_PROVIDER_BUNDLE = JSON.stringify({ schemaVersion: 1, access: {
  baseUrls: { mobile: "https://mobile.provider.example/api/", app: "https://app.provider.example/", gateway: "https://gateway.provider.example/" },
  credentials: { appId: "test-app", appSecret: "test-secret", encryptionKey: "FBC213C4C7BEEBD2AA4EDBF0F681C41B", signingKey: "test-signing-key" },
  client: { version: "5.3.0", channel: "test", vendor: "test", versionCode: "1", platform: "0" },
  routes: { login: "account/login", profile: "account/profile", communities: "items/groups", homeItems: "items/home", allItems: "items/all", sortItems: "items/sort", operate: "items/operate", sms: "account/sms" },
  passwordModels: ["model-with-code"],
}, device: {
  baseUrl: "https://device.provider.example", credentials: { appId: "test", appKey: "test", iotKey: "test", hmacKey: "test", deviceId: "test" },
  client: { version: "1", secretVersion: "1", platformId: "1", clientType: "1", language: "en", source: "test", module: "test" },
  routes: { sms: "/account/sms", login: "/account/login", refresh: "/account/refresh", homes: "/homes", devices: "/devices", templateMap: "/templates/map", templateGet: "/templates/get", properties: "/properties/{deviceId}", action: "/actions/{action}/{deviceId}" },
  properties: { program: "program", power: "power", parameters: { temperature_level: { property: "temperature" }, dry_level: { property: "dryness" }, dry_temp: { property: "sanitize" }, crease_resist_old: { property: "crease", type: "boolean" }, dry_time_new: { property: "time" } } }, actions: { start: "start", pause: "pause", schedule: "schedule", cancelSchedule: "cancel" },
} });
process.env.OPENHOME_SESSION_ENCRYPTION_KEY = "00".repeat(32);
const { OpenDeviceProvider } = await import("../lib/opendevice-provider.ts");
const { isProviderBundle } = await import("../lib/provider-bundle.ts");
const { createDoorHandle, readDoorHandle } = await import("../lib/door-handle.ts");
const { UpstreamError, absorbSetCookies, appendRawSessionId, communityCodes, communityIds, communityNames, cookieHeader, dedupeDoors, doorPassword, doorSortBody, encryptMobile, isAuthenticationExpired, isSmsAccepted, isSuccess, loginCredential, normalizeDoors, openDoorBody, parseUpstreamCookies, providerPost, providerUrl, serializeUpstreamCookies, signHeaders, signMobileBody, supportsDoorPassword } = await import("../lib/provider.ts");
const { publicDoor } = await import("../lib/public-door.ts");
const { personalDisplayName } = await import("../lib/account-name.ts");

test("rejects incomplete provider bundles before a feature uses them", () => {
  const valid = JSON.parse(process.env.OPENHOME_PROVIDER_BUNDLE || "null");
  assert.equal(isProviderBundle(valid), true);
  const incomplete = structuredClone(valid);
  delete incomplete.device.actions.cancelSchedule;
  assert.equal(isProviderBundle(incomplete), false);
});

test("carries a door target in an opaque encrypted handle without persistence", () => {
  const handle = createDoorHandle("account-1", { communityId: 12, doorControlId: 34, name: "East", communityCode: "private-code", mac: "001122334455", passwordSupported: true });
  assert.equal(handle.includes("account-1"), false);
  assert.equal(handle.includes("001122334455"), false);
  assert.deepEqual(readDoorHandle(handle), { accountId: "account-1", communityId: 12, doorControlId: 34, communityCode: "private-code", mac: "001122334455", passwordSupported: true });
  assert.throws(() => readDoorHandle(`${handle.slice(0, -1)}${handle.endsWith("A") ? "B" : "A"}`));
});

test("routes configured provider APIs", () => {
  assert.equal(providerUrl("gateway", "account/sms").href, "https://gateway.provider.example/account/sms");
  assert.equal(providerUrl("mobile", "account/login").href, "https://mobile.provider.example/api/account/login");
});

test("maps only model-verified dryer parameters into one property update", async () => {
  const originalFetch = globalThis.fetch;
  let captured: RequestInit | undefined;
  globalThis.fetch = async (_input, init) => {
    captured = init;
    return new Response(JSON.stringify({ code: 0, data: {} }), { status: 200, headers: { "content-type": "application/json" } });
  };
  try {
    await new OpenDeviceProvider({ uid: "user", accessToken: "token", deviceId: "client" }).configureProgram("dryer", 43, { temperature_level: 2, dry_level: 3, dry_temp: 1, crease_resist_old: 1 });
  } finally { globalThis.fetch = originalFetch; }
  assert.deepEqual(JSON.parse(String(captured?.body)), { program: 43, temperature: 2, dryness: 3, sanitize: 1, crease: true });
  assert.throws(() => new OpenDeviceProvider().configureProgram("dryer", 43, { dry_level: 99 }));
});

test("refreshes an expired appliance session and retries the original request once", async () => {
  const originalFetch = globalThis.fetch;
  const calls: Array<{ url: string; headers: Record<string, string>; body: Record<string, unknown> }> = [];
  globalThis.fetch = async (input, init) => {
    calls.push({ url: String(input), headers: init?.headers as Record<string, string>, body: JSON.parse(String(init?.body || "{}")) });
    if (calls.length === 1) return Response.json({ code: 40002, msg: "token expired" });
    if (calls.length === 2) return Response.json({ code: 0, data: { accessToken: "fresh-token", expired: 99 } });
    return Response.json({ code: 0, data: { homeList: [] } });
  };
  const session = { uid: "user", accessToken: "old-token", deviceId: "client", tokenPwd: "refresh-secret", accessTokenExpiresAt: undefined as number | undefined };
  try { await new OpenDeviceProvider(session).listHomes(); } finally { globalThis.fetch = originalFetch; }
  assert.equal(calls.length, 3);
  assert.match(calls[1].url, /\/account\/refresh$/);
  assert.equal(calls[1].headers.userId, "user");
  assert.equal(calls[1].headers.accessToken, undefined);
  assert.equal(calls[1].headers.uid, undefined);
  assert.deepEqual(calls[1].body, { timestamp: calls[1].body.timestamp, data: { tokenPwd: "refresh-secret", rule: 1, platform: 2, iotAppId: "test", deviceId: "client" } });
  assert.equal(calls[2].headers.accessToken, "fresh-token");
  assert.equal(session.accessToken, "fresh-token");
  assert.equal(session.accessTokenExpiresAt, 99);
});

test("refreshes an appliance session when the provider rejects the token password", async () => {
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  let homes = 0;
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input); const body = JSON.parse(String(init?.body || "{}")); calls.push({ url, body });
    if (url.endsWith("/homes")) return Response.json(homes++ === 0 ? { code: 65012, msg: "token invalid" } : { code: 0, data: [] });
    return Response.json({ code: 0, data: { accessToken: "new-token", expired: 123 } });
  }) as typeof fetch;
  const session = { uid: "user", accessToken: "old-token", deviceId: "client", tokenPwd: "refresh-secret" };
  const provider = new OpenDeviceProvider(session);
  assert.deepEqual(await provider.listHomes(), []);
  assert.equal(session.accessToken, "new-token");
  assert.equal(calls.length, 3);
});

test("matches the provider app's literal sessionId URL concatenation", () => {
  const url = providerUrl("mobile", "account/profile");
  assert.equal(appendRawSessionId(url, "abc:0123456789abcdef"), "https://mobile.provider.example/api/account/profile?sessionId=abc:0123456789abcdef");
  assert.throws(() => appendRawSessionId(url, "unsafe&tail"));
});

test("keeps provider routes outside product code", () => {
  assert.equal(providerUrl("mobile", "account/profile").toString(), "https://mobile.provider.example/api/account/profile");
  assert.equal(providerUrl("mobile", "items/groups").toString(), "https://mobile.provider.example/api/items/groups");
});

test("emits the provider app JSON wire contract for authenticated body requests", async () => {
  const originalFetch = globalThis.fetch;
  let captured: { input: URL | RequestInfo; init?: RequestInit } | undefined;
  globalThis.fetch = async (input, init) => {
    captured = { input, init };
    return new Response(JSON.stringify({ code: 0, data: [] }), { status: 200, headers: { "content-type": "application/json" } });
  };
  try {
    await providerPost("mobile", "items/groups", { method: "communityInfo" }, {
      sessionId: "session:0123456789abcdef", signingToken: "session:0123456789abcdef", openId: "device-id", signing: "mobile-body", encoding: "json",
    });
  } finally { globalThis.fetch = originalFetch; }
  assert.ok(captured);
  const url = new URL(String(captured.input));
  assert.equal(url.searchParams.get("sessionId"), "session:0123456789abcdef");
  assert.match(url.toString(), /sessionId=session:0123456789abcdef/);
  assert.equal((captured.init?.headers as Record<string, string>)["content-type"], "application/json; charset=utf-8");
  assert.equal((captured.init?.headers as Record<string, string>).openId, "device-id");
  const fields = JSON.parse(String(captured.init?.body));
  assert.equal(fields.method, "communityInfo");
  assert.equal(fields.token, undefined);
  assert.match(String(fields.nonce), /^\d{5}$/);
  assert.match(String(fields.timestamp), /^\d{13}$/);
  assert.equal(fields.version, "5.3.0");
  const signing = { method: fields.method, token: "session:0123456789abcdef", timestamp: fields.timestamp, version: fields.version, nonce: fields.nonce };
  const canonical = Object.keys(signing).sort().map((key) => `${key}=${String(signing[key as keyof typeof signing])}`).join("&");
  assert.equal(fields.sign, createHash("md5").update(`${canonical}&key=test-signing-key`).digest("hex").toUpperCase());
});

test("emits login as JSON request body without an empty sessionId", async () => {
  const originalFetch = globalThis.fetch;
  let captured: { input: URL | RequestInfo; init?: RequestInit } | undefined;
  globalThis.fetch = async (input, init) => {
    captured = { input, init };
    return new Response(JSON.stringify({ code: 0, data: { sessionId: "session" } }), { status: 200, headers: { "content-type": "application/json" } });
  };
  try {
    await providerPost("mobile", "account/login", { mobile: "ciphertext", smsCode: "123456", appChannel: 1 }, {
      openId: "device-id", signing: "mobile-body", encoding: "json",
    });
  } finally { globalThis.fetch = originalFetch; }
  assert.ok(captured);
  const url = new URL(String(captured.input));
  assert.equal(url.searchParams.has("sessionId"), false);
  assert.equal((captured.init?.headers as Record<string, string>)["content-type"], "application/json; charset=utf-8");
  const fields = JSON.parse(String(captured.init?.body));
  assert.deepEqual({ mobile: fields.mobile, smsCode: fields.smsCode, appChannel: fields.appChannel }, {
    mobile: "ciphertext", smsCode: "123456", appChannel: 1,
  });
  assert.equal(fields.token, undefined);
  assert.match(String(fields.sign), /^[A-F0-9]{32}$/);
});

test("emits open-door fields only in the URL and sends no request body", async () => {
  const originalFetch = globalThis.fetch;
  let captured: { input: URL | RequestInfo; init?: RequestInit } | undefined;
  globalThis.fetch = async (input, init) => {
    captured = { input, init };
    return new Response(JSON.stringify({ code: 0 }), { status: 200, headers: { "content-type": "application/json" } });
  };
  try {
    await providerPost("mobile", "items/operate", openDoorBody(12, 8), {
      sessionId: "session", signingToken: "session", openId: "device-id", signing: "mobile-body", encoding: "query",
    });
  } finally { globalThis.fetch = originalFetch; }
  assert.ok(captured);
  const url = new URL(String(captured.input));
  assert.equal(url.searchParams.get("appChannel"), "1");
  assert.equal(url.searchParams.get("doorControlId"), "12");
  assert.equal(url.searchParams.get("communityId"), "8");
  assert.equal(url.searchParams.get("sessionId"), "session");
  assert.match(url.searchParams.get("nonce") || "", /^\d{5}$/);
  assert.match(url.searchParams.get("sign") || "", /^[A-F0-9]{32}$/);
  assert.match(url.search, /^\?sessionId=session&appChannel=1&doorControlId=12&communityId=8&/);
  assert.equal(captured.init?.body, undefined);
});

test("documents the provider app login credential field", () => {
  assert.equal(loginCredential({ token: "other-token", sessionId: "app-session" }), "app-session");
  assert.equal(loginCredential({ token: "fallback-token" }), "fallback-token");
});

test("retains login response cookies for authenticated requests", () => {
  const context = { cookies: {} };
  absorbSetCookies(context, [
    "SESSION=first; Path=/; HttpOnly",
    "route=node-a; Path=/, affinity=edge; Path=/; Secure",
  ]);
  assert.equal(cookieHeader(context), "SESSION=first; route=node-a; affinity=edge");
  absorbSetCookies(context, ["SESSION=second; Path=/; HttpOnly"]);
  assert.equal(cookieHeader(context), "SESSION=second; route=node-a; affinity=edge");
});

test("rejects absolute and root-relative upstream paths", () => {
  assert.throws(() => providerUrl("mobile", "https://example.com/steal"));
  assert.throws(() => providerUrl("mobile", "/other"));
});

test("signed requests include all gateway-required fields", () => {
  const headers = signHeaders({ mobile: "13800000000" });
  assert.match(headers.nonce, /^\d{4}$/);
  assert.match(headers.timestamp, /^\d{13}$/);
  assert.equal(headers.version, "v2");
  assert.match(headers.sign, /^[A-F0-9]{32}$/);
});

test("does not report rate-limited SMS requests as delivered", () => {
  assert.equal(isSmsAccepted({ code: 0, message: "success" }), true);
  assert.equal(isSmsAccepted({ code: 0, message: "短信发送过于频繁，请稍后再试。" }), false);
  assert.equal(isSmsAccepted({ code: 500, message: "success" }), false);
});

test("matches the provider app business-success rule exactly", () => {
  assert.equal(isSuccess({ code: 0 }), true);
  assert.equal(isSuccess({ code: "0" }), true);
  assert.equal(isSuccess({ code: 1 }), false);
  assert.equal(isSuccess({ code: 200 }), false);
});

test("recognizes provider session expiry without classifying ordinary failures as authentication", () => {
  assert.equal(isAuthenticationExpired(new Error("您还没有登录，或者登录已超时，请重新登录！")), true);
  assert.equal(isAuthenticationExpired(new UpstreamError("request failed", { code: 1, message: "登录失效" })), true);
  assert.equal(isAuthenticationExpired(new Error("OpenDevice provider: 40002 移动平台Token校验不通过 [user token not exist]")), true);
  assert.equal(isAuthenticationExpired(new Error("OpenLock provider: 40002 user token not exist")), true);
  assert.equal(isAuthenticationExpired(new Error("门禁查询失败")), false);
  assert.equal(isAuthenticationExpired(new Error("OpenLock provider: 500 request failed")), false);
});

test("round-trips only safe upstream cookie-jar entries", () => {
  const encoded = serializeUpstreamCookies({ cookies: { SESSION: "abc123", route: "node-a" } });
  assert.deepEqual(parseUpstreamCookies(encoded), { cookies: { SESSION: "abc123", route: "node-a" } });
  assert.deepEqual(parseUpstreamCookies('{"bad name":"x","ok":"line\\nfeed","safe":"yes"}'), { cookies: { safe: "yes" } });
  assert.deepEqual(parseUpstreamCookies("not-json"), { cookies: {} });
});

test("mobile requests carry the required five-digit nonce and body signature", () => {
  const body = signMobileBody(
    { mobile: "ciphertext", smsCode: "123456", appChannel: 2 },
    { nonce: "01234", timestamp: 1761111111111, version: "5.3.0" },
  );
  assert.deepEqual(body, {
    mobile: "ciphertext",
    smsCode: "123456",
    appChannel: 2,
    timestamp: 1761111111111,
    version: "5.3.0",
    nonce: "01234",
    sign: createHash("md5").update("appChannel=2&mobile=ciphertext&nonce=01234&smsCode=123456&timestamp=1761111111111&version=5.3.0&key=test-signing-key").digest("hex").toUpperCase(),
  });
});

test("authenticated mobile signatures use but do not transmit the session token", () => {
  const body = signMobileBody({}, { nonce: "54321", timestamp: 1761111111111, version: "5.3.0", token: "session" });
  assert.equal(body.token, undefined);
  assert.equal(body.sign, createHash("md5").update("nonce=54321&timestamp=1761111111111&token=session&version=5.3.0&key=test-signing-key").digest("hex").toUpperCase());
});

test("doorSort keeps list on the wire but excludes it from the official signature", () => {
  const list = [{ commondoorControlIds: [1], gatedoorControlIds: [2], buildingDoorList: [], customDoorList: [] }];
  const body = signMobileBody(
    { list, method: "doorSort", commId: 8, gateDoorColor: -1, buildingDoorColor: -1, customDoorColor: -1 },
    { nonce: "12345", timestamp: 1761111111111, version: "5.3.0", token: "session", exclude: ["list"] },
  );
  assert.deepEqual(body.list, list);
  assert.equal(body.sign, createHash("md5").update("buildingDoorColor=-1&commId=8&customDoorColor=-1&gateDoorColor=-1&method=doorSort&nonce=12345&timestamp=1761111111111&token=session&version=5.3.0&key=test-signing-key").digest("hex").toUpperCase());
});

test("rebuilds the provider doorSort groups when a common door is added or removed", () => {
  const payload = {
    gateDoorList: [{ doorControlId: 10 }],
    buildingDoorList: [{ doorControlId: 20 }],
    customDoorList: [{ doorControlId: 30 }],
    commonlyUsedDoor: { first: { doorControlId: 40, doorControlUsefor: "大门" } },
    gateDoorColor: 1,
    buildingDoorColor: 2,
    customDoorColor: 3,
  };
  assert.deepEqual(doorSortBody(payload, 8, 20, true), {
    list: [{ commondoorControlIds: [40, 20], gatedoorControlIds: [10], buildingDoorList: [], customDoorList: [30] }],
    method: "doorSort", commId: 8, gateDoorColor: 1, buildingDoorColor: 2, customDoorColor: 3,
  });
  assert.deepEqual(doorSortBody(payload, 8, 40, false), {
    list: [{ commondoorControlIds: [], gatedoorControlIds: [10, 40], buildingDoorList: [20], customDoorList: [30] }],
    method: "doorSort", commId: 8, gateDoorColor: 1, buildingDoorColor: 2, customDoorColor: 3,
  });
});

test("encrypts a mobile number with AES-128-ECB PKCS#7", () => {
  assert.equal(encryptMobile("13800138000"), "38C1CCB03057298251BF91A0E6EA1BF3");
});

test("extracts unique community ids from nested responses", () => {
  assert.deepEqual(communityIds({ data: [{ communityId: 8 }, { child: { communityId: "9" } }, { communityId: 8 }] }), [8, 9]);
});

test("normalizes and deduplicates only real door records", () => {
  const first = normalizeDoors({ list: [{ id: 99, name: "不是门禁" }, { doorControlId: 12, customDoorControlName: "自定义东门", doorControlName: "东门", communityId: 8 }] }, 8);
  assert.equal(first[0]?.name, "自定义东门");
  const second = normalizeDoors([{ doorId: "12", doorName: "东门重复" }, { doorControlId: 13, name: "车库" }], 8);
  assert.deepEqual(dedupeDoors([...first, ...second]), [
    { doorControlId: 12, communityId: 8, name: "东门重复" },
    { doorControlId: 13, communityId: 8, name: "车库" },
  ]);
});

test("extracts community codes and preserves password-capable door metadata", () => {
  assert.deepEqual([...communityCodes({ data: [{ communityId: 8, communityCode: "CQ001" }] })], [[8, "CQ001"]]);
  assert.deepEqual([...communityNames({ data: [{ communityId: 8, communityName: "测试小区" }] })], [[8, "测试小区"]]);
  assert.deepEqual(normalizeDoors([{ doorControlId: 12, macAddress: "AA:BB", deviceModel: "model-with-code" }], 8, "CQ001", "测试小区")[0], {
    doorControlId: 12, communityId: 8, name: "门禁 12", communityName: "测试小区", communityCode: "CQ001", mac: "AA:BB", deviceModel: "model-with-code", passwordSupported: true,
  });
});

test("reproduces the provider app four-digit ten-minute door password", () => {
  const result = doorPassword("AA:BB:CC:DD:EE:FF", "CQ001", Date.UTC(2026, 9, 23, 4, 7, 59));
  const bucket = Math.floor(Date.UTC(2026, 9, 23, 4, 7, 59) / 600000) * 600000;
  const expected = createHash("md5").update(`AA:BB:CC:DD:EE:FF${bucket}CQ001`).digest("hex").replace(/[^0-9]/g, "").slice(-4);
  assert.equal(result.password, expected);
  assert.equal(result.validUntil, new Date(bucket + 600000).toISOString());
  assert.equal(supportsDoorPassword("model-with-code"), true);
  assert.equal(supportsDoorPassword("unknown"), false);
});

test("builds the exact open-door payload and rejects invalid ids", () => {
  assert.deepEqual(openDoorBody(12, 8), { appChannel: 1, doorControlId: 12, communityId: 8 });
  assert.throws(() => openDoorBody(0, 8));
  assert.throws(() => openDoorBody(12, Number.NaN));
});

test("projects an opaque public door without account or upstream identifiers", () => {
  const value = publicDoor({ publicId: "00000000-0000-4000-8000-000000000001", name: "东门", communityName: "测试小区", passwordSupported: true, providerFeatured: true, selected: true, refreshedAt: 1 });
  assert.deepEqual(value, { id: "00000000-0000-4000-8000-000000000001", name: "东门", communityName: "测试小区", passwordSupported: true, providerFeatured: true, selected: true, refreshedAt: 1 });
  assert.deepEqual(Object.keys(value || {}).sort(), ["communityName", "id", "name", "passwordSupported", "providerFeatured", "refreshedAt", "selected"]);
});

test("extracts a bounded account username from personal info", () => {
  assert.equal(personalDisplayName({ data: { userInfo: { nickName: "  小明  " } } }), "小明");
  assert.equal(personalDisplayName({ data: { unknown: true } }), null);
});
