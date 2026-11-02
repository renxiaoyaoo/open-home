import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

const bundle = { schemaVersion: 1,
  access: { baseUrls: { mobile: "https://a.example", app: "https://a.example", gateway: "https://a.example" }, credentials: { appId: "id", appSecret: "secret", encryptionKey: "key", signingKey: "sign" }, client: { version: "1", channel: "test", vendor: "test", versionCode: "1", platform: "0" }, routes: { login: "login", profile: "profile", communities: "communities", homeItems: "home", allItems: "all", sortItems: "sort", operate: "operate", sms: "sms" }, passwordModels: [] },
  device: { baseUrl: "https://d.example", credentials: { appId: "id", appKey: "key", iotKey: "iot", hmacKey: "hmac", deviceId: "device" }, client: { version: "1", secretVersion: "1", platformId: "1", clientType: "1", language: "en", source: "test", module: "test" }, routes: { sms: "/sms", login: "/login", refresh: "/refresh", homes: "/homes", devices: "/devices", templateMap: "/map", templateGet: "/get", properties: "/properties", action: "/action" }, properties: { program: "program", power: "power" }, actions: { start: "start", pause: "pause", schedule: "schedule", cancelSchedule: "cancel" } },
} as Record<string, unknown>;
(bundle as { lock?: unknown }).lock = {
  baseUrl: "https://lock.provider.example", identityCipher: "private-identity", client: { appVersion: "1", clientType: "test" },
  routes: { loginToken: "/login/token", login: "/login/password", devices: "/devices", detail: "/detail", securityLogs: "/logs/security", operationLogs: "/logs/operation", temporaryPasswordCount: "/password/count", temporaryPasswordCreate: "/password/create", users: "/users", thumbnail: "/media/sign" },
  media: { baseUrl: "https://media.provider.example", route: "/events", alarmThumbnailTemplate: "/alarms/{pictureId}.jpg", successPath: "result", successValue: "ok", auth: { route: "/session", appKey: "test-app", appSecret: "test-secret", openId: "test-user", action: "session-action", signatureExclude: ["Action"], tokenPath: "payload.token", expiryPath: "payload.expires" }, eventRequest: { credential: "{accessToken}", product: "{productId}", device: "{deviceName}", from: "{startTime}", to: "{endTime}", context: "{context}" }, thumbnailRequest: { credential: "{accessToken}", action: "private-action", device: "{deviceId}", paths: "{thumbnails}" }, videoSignRequest: { credential: "{accessToken}", action: "sign-video", video: "{video}", expires: "{videoExpiresAt}" } },
  fields: { deviceId: "id", deviceName: "name", detail: "status", wifiName: "wifi", wifiSignal: "signal", battery: "battery", cameraBattery: "cameraBattery", batteryUpdatedAt: "updated", profileName: "nickname", logItems: "items", logTime: "time", logContent: "text", logPicture: "picture", temporaryPasswordCount: "remaining", mediaProductId: "product", mediaDeviceName: "mediaName", mediaEvents: "payload.events", mediaEventId: "eventId", mediaEventTime: "created", mediaEventEndTime: "ended", mediaThumbnail: "thumbnail", mediaVideo: "payload.video", mediaContext: "payload.context", mediaListOver: "payload.done", signedThumbnails: "signed", signedThumbnailUrl: "url", signedVideoUrl: "Response.SignedVideoURL" },
};
process.env.OPENHOME_PROVIDER_BUNDLE = JSON.stringify(bundle);
const { OpenLockProvider } = await import("../lib/openlock-provider.ts");

test("logs in with the configured private identity and password digest", async () => {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    calls.push({ url: String(input), init });
    if (String(input).includes("/session")) return Response.json({ payload: { token: "media-token", expires: Math.floor(Date.now() / 1000) + 3600 } });
    const data = calls.length === 1 ? ["challenge"] : [{ token: "session-token", nickname: "Home" }]; return Response.json({ status: 1, success: true, data });
  };
  try { const session = await new OpenLockProvider().passwordLogin("13800138000", "secret"); assert.equal(session.token, "session-token"); assert.equal(session.displayName, "Home"); assert.equal(session.mediaToken, "media-token"); assert.ok((session.mediaExpiresAt || 0) > Date.now() / 1000); }
  finally { globalThis.fetch = original; }
  assert.equal(new URL(calls[0].url).searchParams.get("encryptUserPhone"), "private-identity");
  const form = new URLSearchParams(String(calls[1].init?.body));
  assert.equal(form.get("loginToken"), "challenge");
  assert.equal(form.get("passWord2"), createHash("md5").update("secret").digest("hex"));
  assert.equal(form.get("encryptUserPhone"), "private-identity");
});

test("keeps the primary lock login when optional media authentication is unavailable", async () => {
  const original = globalThis.fetch; let request = 0;
  globalThis.fetch = async (input) => {
    request += 1;
    if (String(input).includes("/session")) return new Response("unavailable", { status: 503 });
    return Response.json({ status: 1, success: true, data: request === 1 ? ["challenge"] : [{ token: "session-token", nickname: "Home" }] });
  };
  try {
    const session = await new OpenLockProvider().passwordLogin("13800138000", "secret");
    assert.equal(session.token, "session-token");
    assert.equal(session.mediaToken, undefined);
  } finally { globalThis.fetch = original; }
});

test("builds media requests from private templates and returns signed captures", async () => {
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const url = String(input); const body = init?.body ? JSON.parse(String(init.body)) as Record<string, unknown> : {};
    calls.push({ url, body });
    if (url.includes("/session")) return Response.json({ payload: { token: "fresh-media-token", expires: Math.floor(Date.now() / 1000) + 3600 } });
    if (url.includes("/events") && body.action === "sign-video") return Response.json({ Response: { SignedVideoURL: "http://videos.example/signed.m3u8" } });
    if (url.includes("/events")) return body.context
      ? Response.json({ result: "ok", payload: { done: true, events: [{ eventId: "second", created: 12, thumbnail: "b" }] } })
      : Response.json({ result: "ok", payload: { context: "next", done: false, video: "https://videos.example/first.m3u8", events: [{ eventId: "first", created: "1970-01-01T00:00:10Z", ended: 18, thumbnail: "a" }] } });
    if (url.includes("/media/sign")) return Response.json({ status: 1, success: true, data: [{ signed: [{ url: Array.isArray(body.paths) && body.paths[0] === "a" ? "https://images.example/a" : "https://images.example/b" }] }] });
    return Response.json({ status: 1, success: true, data: [{ status: { product: "product-1", mediaName: "device-1", mediaId: "id-1" } }] });
  };
  try {
    const session = { token: "session" }; const provider = new OpenLockProvider(session); const first = await provider.captures("7"); const second = await provider.captures("7", first.nextCursor);
    assert.deepEqual(first.items, [{ id: "first-10-0", time: 10, type: "first", image: "https://images.example/a", video: "https://videos.example/signed.m3u8" }]);
    assert.ok(first.nextCursor);
    assert.deepEqual(second, { items: [{ id: "second-12-0", time: 12, type: "second", image: "https://images.example/b", video: undefined }], nextCursor: undefined });
    assert.equal(provider.sessionState()?.mediaToken, "fresh-media-token");
  } finally { globalThis.fetch = original; }
  assert.equal(calls[2].body.product, "product-1");
  assert.equal(calls[2].body.credential, "fresh-media-token");
  assert.ok(Number(calls[2].body.from) <= Math.floor(Date.now() / 1000) - 7 * 24 * 60 * 60 + 2);
  assert.equal(calls[3].body.device, "7");
  assert.deepEqual(calls[3].body.paths, ["a"]);
  assert.equal(calls[4].body.action, "sign-video");
  assert.match(String(calls[4].body.video), /endtime_epoch=18/);
  assert.equal(calls[6].body.context, "next");
  assert.equal(calls[7].body.credential, "fresh-media-token");
  assert.deepEqual(calls[7].body.paths, ["b"]);
});

test("normalizes device status, records, and temporary password capacity", async () => {
  const original = globalThis.fetch; const requested: string[] = [];
  globalThis.fetch = async (input) => {
    requested.push(String(input));
    const path = new URL(String(input)).pathname;
    if (path === "/media/sign") return Response.json({ status: 1, success: true, data: [{ signed: [{ url: "https://signed.example/alarm.jpg" }] }] });
    const data = path === "/devices" ? [{ id: "7", name: "Front" }]
      : path === "/detail" ? [{ status: { name: "Front", wifi: "Home", signal: "good", battery: "80", cameraBattery: "70", updated: "today" } }]
      : path === "/password/count" ? [{ remaining: 4 }]
      : [{ items: [{ time: "now", text: "opened", picture: "1234567890" }] }];
    return Response.json({ status: 1, success: true, data });
  };
  try {
    const provider = new OpenLockProvider({ token: "session", mediaToken: "media", mediaExpiresAt: Math.floor(Date.now() / 1000) + 3600 });
    assert.deepEqual(await provider.devices(), [{ id: "7", name: "Front" }]);
    assert.deepEqual(await provider.detail("7"), { name: "Front", wifiName: "Home", wifiSignal: "good", battery: "80", cameraBattery: "70", batteryUpdatedAt: "today" });
    assert.deepEqual(await provider.lockDynamics("7"), { items: [{ time: "now", content: "opened", image: "https://signed.example/alarm.jpg" }], nextCursor: "2" });
    assert.equal(new URL(requested.findLast((url) => url.includes("/logs/security"))!).searchParams.get("type"), "1");
    assert.deepEqual(await provider.securityLogs("7"), { items: [{ time: "now", content: "opened", image: "https://signed.example/alarm.jpg" }], nextCursor: "2" });
    assert.equal(new URL(requested.findLast((url) => url.includes("/logs/security"))!).searchParams.get("type"), "2");
    assert.deepEqual(await provider.temporaryPasswordCount("7"), { remaining: 4 });
  } finally { globalThis.fetch = original; }
});

test("creates an eight-digit temporary password with the observed query contract", async () => {
  const original = globalThis.fetch; let requested = "";
  globalThis.fetch = async (input) => { requested = String(input); return Response.json({ success: true, data: [{ password: "12345678", expiredSecond: 900 }] }); };
  try {
    const before = Date.now(); const result = await new OpenLockProvider({ token: "session" }).createTemporaryPassword("7");
    assert.equal(result.password, "12345678"); assert.ok(Date.parse(result.expiresAt) >= before + 15 * 60 * 1000);
  } finally { globalThis.fetch = original; }
  const url = new URL(requested); assert.equal(url.searchParams.get("lockId"), "7"); assert.equal(url.searchParams.get("passwordEncrypt"), "false");
});
