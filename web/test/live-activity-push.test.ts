import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import test from "node:test";
import { APNsProviderTokenCache, apnsConfiguration, apnsLiveActivityRequest, createAPNsProviderToken, FetchLiveActivityPushTransport, liveActivityPayload } from "../lib/live-activity-push.ts";

test("creates an Apple ES256 provider token with the required claims", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const token = createAPNsProviderToken({ keyId: "ABC123DEFG", teamId: "DEF123GHIJ", privateKey: privateKey.export({ format: "pem", type: "pkcs8" }).toString() }, 1_700_000_000);
  const [header, claims, signature] = token.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url").toString()), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(JSON.parse(Buffer.from(claims, "base64url").toString()), { iss: "DEF123GHIJ", iat: 1_700_000_000 });
  assert.equal(verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url")), true);
});

test("builds the default-Codable ActivityKit state and APNs request", () => {
  const now = new Date("2026-11-04T10:00:00Z");
  const expectedEnd = new Date("2026-11-04T12:07:00Z");
  const payload = liveActivityPayload({ title: "Dryer", state: "Running", detail: "Bedding", expectedEnd }, "update", now);
  assert.deepEqual(payload, { aps: { timestamp: 1_793_786_400, event: "update", "content-state": { title: "Dryer", state: "Running", detail: "Bedding", progress: null, expectedEnd: 815_486_820 }, "stale-date": 1_793_794_020 } });
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const request = apnsLiveActivityRequest({ keyId: "ABC123DEFG", teamId: "DEF123GHIJ", bundleId: "org.example.openhome", privateKey: privateKey.export({ format: "pem", type: "pkcs8" }).toString() }, "sandbox", "ab".repeat(32), { title: "Car", state: "Driving" }, "update", 10, now);
  assert.equal(request.url, `https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
  assert.equal(request.headers["apns-topic"], "org.example.openhome.push-type.liveactivity");
  assert.equal(request.headers["apns-push-type"], "liveactivity");
  assert.equal(request.headers["apns-priority"], "10");
});

test("loads APNs secrets without exposing them and delegates delivery to a transport", async () => {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const pem = privateKey.export({ format: "pem", type: "pkcs8" }).toString();
  const configuration = apnsConfiguration({ OPENHOME_APNS_KEY_ID: "ABC123DEFG", OPENHOME_APPLE_TEAM_ID: "DEF123GHIJ", OPENHOME_IOS_BUNDLE_ID: "org.example.openhome", OPENHOME_APNS_PRIVATE_KEY_BASE64: Buffer.from(pem).toString("base64") });
  assert.equal(configuration.privateKey, pem);
  let observed: { url: string; init?: RequestInit } | undefined;
  const transport = new FetchLiveActivityPushTransport(async (url, init) => { observed = { url: String(url), init }; return Response.json({}, { status: 200 }); });
  const result = await transport.send(apnsLiveActivityRequest(configuration, "production", "ab".repeat(32), { title: "Car", state: "Driving" }));
  assert.deepEqual(result, { status: 200, reason: undefined });
  assert.match(observed?.url || "", /^https:\/\/api\.push\.apple\.com\/3\/device\//);
  assert.equal((observed?.init?.headers as Record<string, string>)["apns-push-type"], "liveactivity");
});

test("reuses an APNs provider token and refreshes it before Apple expires it", () => {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const configuration = { keyId: "ABC123DEFG", teamId: "DEF123GHIJ", privateKey: privateKey.export({ format: "pem", type: "pkcs8" }).toString() };
  const cache = new APNsProviderTokenCache();
  const first = cache.token(configuration, 1_700_000_000);
  assert.equal(cache.token(configuration, 1_700_000_000 + 20 * 60), first);
  assert.notEqual(cache.token(configuration, 1_700_000_000 + 50 * 60), first);
});
