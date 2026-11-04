import assert from "node:assert/strict";
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
    const { loadProviderSession, publicAccounts, saveProviderSession } = await import("../lib/central.ts");
    const db = await getDb();
    const rows = await db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all<{ name: string }>();
    assert.deepEqual(rows.results.map((row) => row.name), ["accounts", "activation_codes", "client_devices", "sessions"]);
    await saveProviderSession("opendevice", "od-test", "13800138000", "Appliance", { accessToken: "device-token" });
    await saveProviderSession("openlock", "ol-test", "13800138000", "Lock", { token: "lock-token" });
    assert.deepEqual((await loadProviderSession<{ accessToken: string }>("opendevice")).session, { accessToken: "device-token" });
    assert.deepEqual((await loadProviderSession<{ token: string }>("openlock")).session, { token: "lock-token" });
    assert.deepEqual((await publicAccounts("opendevice")).map(({ id, provider }) => ({ id, provider })), [{ id: "od-test", provider: "opendevice" }]);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("consumes a self-contained activation once and authenticates the issued device", async () => {
  const { activateClient, authenticateDevice, createActivation } = await import("../lib/client-auth.ts");
  const issued = await createActivation("https://home.example/api/v1", 10);
  assert.match(issued.activationCode, /^oh1\./);
  const encoded = issued.activationCode.slice(4).replace(/-/g, "+").replace(/_/g, "/");
  const payload = JSON.parse(Buffer.from(encoded, "base64").toString("utf8")) as { baseURL: string; code: string };
  assert.equal(payload.baseURL, "https://home.example/api/v1");
  const device = await activateClient(payload.code, "Test iPhone");
  const authenticated = await authenticateDevice(new Request("https://home.example/api/v1/doors", { headers: { authorization: `Bearer ${device.deviceToken}` } }));
  assert.equal(authenticated.deviceID, device.deviceID);
  await assert.rejects(() => activateClient(payload.code, "Second iPhone"), /invalid or expired/);
});
