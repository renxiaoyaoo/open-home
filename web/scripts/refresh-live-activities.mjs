import { createHmac } from "node:crypto";

const keySource = process.env.OPENHOME_SESSION_ENCRYPTION_KEY || "";
const key = /^[0-9a-f]{64}$/i.test(keySource) ? Buffer.from(keySource, "hex") : Buffer.from(keySource, "base64");
if (key.length !== 32) throw new Error("Set OPENHOME_SESSION_ENCRYPTION_KEY to the deployment's recoverable key");
const publicAPIURL = new URL(process.env.OPENHOME_PUBLIC_API_URL || "");
const administratorToken = createHmac("sha256", key).update("admin:activation-issuer").digest("hex");
const response = await fetch(new URL("live-activities/refresh", `${publicAPIURL.toString().replace(/\/$/, "")}/`), { method: "POST", headers: { authorization: `Bearer ${administratorToken}` } });
const payload = await response.json();
if (!response.ok || !payload.ok) throw new Error(payload.message || `Live Activity service returned ${response.status}`);
const resources = Array.isArray(payload.data) ? payload.data : [];
process.stdout.write(`${JSON.stringify({ resources: resources.length, failures: resources.filter((item) => !item.ok).length })}\n`);
