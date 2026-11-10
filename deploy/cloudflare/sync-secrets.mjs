import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const envFile = process.argv[2];
const wranglerConfig = process.argv[3] || "wrangler.production.jsonc";
const webRoot = resolve(import.meta.dirname, "../../web");
const wrangler = resolve(webRoot, "node_modules/.bin/wrangler");
const config = resolve(webRoot, wranglerConfig);
const values = new Map(Object.entries(process.env).filter(([, value]) => typeof value === "string"));
if (envFile) {
  for (const line of readFileSync(envFile, "utf8").split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator > 0) values.set(line.slice(0, separator), line.slice(separator + 1));
  }
}

const url = new URL(values.get("OPENHOME_PROVIDER_BUNDLE_URL") || "");
if (url.protocol !== "https:") throw new Error("Provider bundle URL must use HTTPS");
const token = values.get("OPENHOME_PROVIDER_BUNDLE_TOKEN");
if (!token) throw new Error("Missing required deployment value: OPENHOME_PROVIDER_BUNDLE_TOKEN");
const response = await fetch(url, { headers: { authorization: `Bearer ${token}` }, redirect: "error", signal: AbortSignal.timeout(15_000) });
if (!response.ok) throw new Error(`Provider bundle service returned ${response.status}`);
const source = await response.text();
if (Buffer.byteLength(source) > 131_072) throw new Error("Provider bundle is too large");
let bundle;
try { bundle = JSON.parse(source); } catch { throw new Error("Provider bundle is not JSON"); }
if (bundle?.schemaVersion !== 1 || !bundle.access || !bundle.device) throw new Error("Provider bundle schema is unsupported");

const sessionKey = values.get("OPENHOME_SESSION_ENCRYPTION_KEY");
if (!sessionKey) throw new Error("Missing required secret: OPENHOME_SESSION_ENCRYPTION_KEY");
const parts = source.match(/[\s\S]{1,4400}/g) || [];
const secrets = [["OPENHOME_PROVIDER_BUNDLE_PART_COUNT", String(parts.length)], ...parts.map((value, index) => [`OPENHOME_PROVIDER_BUNDLE_PART_${index}`, value]), ["OPENHOME_SESSION_ENCRYPTION_KEY", sessionKey]];
const apnsNames = ["OPENHOME_APNS_KEY_ID", "OPENHOME_APPLE_TEAM_ID", "OPENHOME_IOS_BUNDLE_ID", "OPENHOME_APNS_PRIVATE_KEY_BASE64"];
const apnsValues = apnsNames.map((name) => values.get(name) || "");
if (apnsValues.some(Boolean) && !apnsValues.every(Boolean)) throw new Error("ActivityKit remote updates require all APNs deployment values");
if (apnsValues.every(Boolean)) secrets.push(...apnsNames.map((name, index) => [name, apnsValues[index]]));
for (const [name, value] of secrets) {
  const result = spawnSync(wrangler, ["secret", "put", name, "--config", config], { input: `${value}\n`, encoding: "utf8" });
  if (result.status !== 0) { process.stderr.write(result.stderr || `Failed to sync ${name}\n`); process.exit(result.status || 1); }
  console.log(`Synced ${name}`);
}
