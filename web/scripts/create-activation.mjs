import { createHmac } from "node:crypto";

const keySource = process.env.OPENHOME_SESSION_ENCRYPTION_KEY || "";
const key = /^[0-9a-f]{64}$/i.test(keySource) ? Buffer.from(keySource, "hex") : Buffer.from(keySource, "base64");
if (key.length !== 32) throw new Error("Set OPENHOME_SESSION_ENCRYPTION_KEY to the deployment's recoverable key");
const publicAPIURL = new URL(process.env.OPENHOME_PUBLIC_API_URL || "");
if (publicAPIURL.protocol !== "https:" && !(publicAPIURL.protocol === "http:" && ["localhost", "127.0.0.1"].includes(publicAPIURL.hostname))) throw new Error("OPENHOME_PUBLIC_API_URL must use HTTPS");
const administratorToken = createHmac("sha256", key).update("admin:activation-issuer").digest("hex");
const response = await fetch(new URL("client/activation-codes", `${publicAPIURL.toString().replace(/\/$/, "")}/`), {
  method: "POST",
  headers: { authorization: `Bearer ${administratorToken}`, "content-type": "application/json" },
  body: JSON.stringify({ publicAPIURL: publicAPIURL.toString().replace(/\/$/, ""), lifetimeMinutes: 10 }),
});
const payload = await response.json();
if (!response.ok || !payload.ok) throw new Error(payload.message || `Activation service returned ${response.status}`);
process.stdout.write(`${payload.data.activationCode}\n`);
