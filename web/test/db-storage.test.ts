import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import test from "node:test";

test("center storage contains provider sessions and client device identities", async () => {
  const directory = mkdtempSync(resolve(tmpdir(), "open-home-db-"));
  process.env.OPENHOME_DATABASE_PATH = resolve(directory, "open-home.sqlite");
  process.env.OPENHOME_SESSION_ENCRYPTION_KEY = "11".repeat(32);
  try {
    const { getDb } = await import("../db/index.ts");
    const { loadProviderSession, publicAccounts, refreshProviderSession, saveProviderSession } = await import("../lib/central.ts");
    const db = await getDb();
    const rows = await db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all<{ name: string }>();
    assert.deepEqual(rows.results.map((row) => row.name), ["accounts", "activation_codes", "client_devices", "live_activities", "provider_leases", "sessions"]);
    await saveProviderSession("opendevice", "od-test", "13800138000", "Appliance", { accessToken: "device-token" });
    await saveProviderSession("openlock", "ol-test", "13800138000", "Lock", { token: "lock-token" });
    assert.deepEqual((await loadProviderSession<{ accessToken: string }>("opendevice")).session, { accessToken: "device-token" });
    assert.deepEqual((await loadProviderSession<{ token: string }>("openlock")).session, { token: "lock-token" });
    assert.deepEqual((await publicAccounts("opendevice")).map(({ id, provider }) => ({ id, provider })), [{ id: "od-test", provider: "opendevice" }]);
    let refreshes = 0;
    const refresh = async () => { refreshes += 1; await new Promise((resolve) => setTimeout(resolve, 10)); return { accessToken: "fresh-token" }; };
    const sessions = await Promise.all([
      refreshProviderSession("opendevice", "od-test", "device-token", refresh),
      refreshProviderSession("opendevice", "od-test", "device-token", refresh),
    ]);
    assert.equal(refreshes, 1);
    assert.deepEqual(sessions, [{ accessToken: "fresh-token" }, { accessToken: "fresh-token" }]);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("consumes a human-readable activation once and authenticates the issued device", async () => {
  const { activateClient, authenticateDevice, createActivation, listDevices, revokeDevice } = await import("../lib/client-auth.ts");
  const issued = await createActivation("https://home.example/api/v1", 10);
  assert.match(issued.activationCode, /^[23456789A-HJ-NP-Z]{4}-[23456789A-HJ-NP-Z]{4}$/);
  assert.equal(issued.publicAPIURL, "https://home.example/api/v1");
  const activationURL = new URL(issued.activationURL);
  assert.equal(activationURL.protocol, "openhome:");
  assert.equal(activationURL.searchParams.get("server"), issued.publicAPIURL);
  assert.equal(activationURL.searchParams.get("code"), issued.activationCode);
  assert.match(issued.activationQRCode, /^data:image\/gif;base64,/);
  const device = await activateClient(issued.activationCode.toLowerCase(), "Test iPhone");
  const authenticated = await authenticateDevice(new Request("https://home.example/api/v1/doors", { headers: { authorization: `Bearer ${device.deviceToken}` } }));
  assert.equal(authenticated.deviceID, device.deviceID);
  assert.equal(authenticated.deviceName, "Test iPhone");
  assert.equal(typeof authenticated.createdAt, "number");
  assert.deepEqual((await listDevices()).map(({ id, name }) => ({ id, name })), [{ id: device.deviceID, name: "Test iPhone" }]);
  const { liveActivityTargets, registerLiveActivity, unregisterLiveActivity } = await import("../lib/live-activities.ts");
  const token = "ab".repeat(32);
  await registerLiveActivity(device.deviceID, { activityId: "activity-1", provider: "living", resourceId: "dryer-1", pushToken: token, environment: "sandbox" });
  assert.deepEqual(await liveActivityTargets("living", "dryer-1"), [{ activityId: "activity-1", pushToken: token, environment: "sandbox", lastStateHash: null }]);
  await registerLiveActivity(device.deviceID, { activityId: "activity-2", provider: "living", resourceId: "dryer-1", pushToken: "cd".repeat(32), environment: "sandbox" });
  assert.deepEqual((await liveActivityTargets("living", "dryer-1")).map(({ activityId }) => activityId), ["activity-2"]);
  const { publishLiveActivity } = await import("../lib/live-activity-push.ts");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const configuration = { keyId: "ABC123DEFG", teamId: "DEF123GHIJ", bundleId: "org.example.openhome", privateKey: privateKey.export({ format: "pem", type: "pkcs8" }).toString() };
  let deliveries = 0;
  const transport = { async send() { deliveries += 1; return { status: 200 }; } };
  const state = { title: "Dryer", state: "Running", detail: "Bedding" };
  assert.equal((await publishLiveActivity("living", "dryer-1", state, "update", configuration, transport))[0].status, 200);
  assert.equal((await publishLiveActivity("living", "dryer-1", state, "update", configuration, transport))[0].skipped, true);
  assert.equal(deliveries, 1);
  await unregisterLiveActivity(device.deviceID, "activity-2");
  assert.deepEqual(await liveActivityTargets("living", "dryer-1"), []);
  const { refreshLiveActivities } = await import("../lib/live-activity-refresh.ts");
  assert.deepEqual(await refreshLiveActivities(), []);
  await revokeDevice(device.deviceID);
  assert.deepEqual(await listDevices(), []);
  await assert.rejects(() => authenticateDevice(new Request("https://home.example/api/v1/doors", { headers: { authorization: `Bearer ${device.deviceToken}` } })), /authorization failed/);
  await assert.rejects(() => activateClient(issued.activationCode, "Second iPhone"), /invalid or expired/);
});
