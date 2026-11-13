import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
const hostnamePattern = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i;

export function cloudflareRoutes(environment = process.env) {
  const domains = [environment.OPENHOME_CF_CUSTOM_DOMAIN, environment.OPENHOME_CF_API_DOMAIN].filter(Boolean);
  for (const domain of domains) {
    if (!hostnamePattern.test(domain)) throw new Error("Cloudflare custom domains must be hostnames");
  }
  if (new Set(domains.map((domain) => domain.toLowerCase())).size !== domains.length) throw new Error("Web and API domains must be different");
  return domains.map((pattern) => ({ pattern, custom_domain: true }));
}

export function prepareConfiguration(environment = process.env) {
  const databaseId = environment.OPENHOME_CF_DATABASE_ID;
  const databaseName = environment.OPENHOME_CF_DATABASE_NAME || "open-home";
  const apiEnabled = environment.OPENHOME_ACCESS_ENABLED === "1" ? "1" : "0";
  if (!databaseId) throw new Error("Set OPENHOME_CF_DATABASE_ID in the private deployment environment");
  const routes = cloudflareRoutes(environment);
  const routeConfiguration = routes.length ? `"routes": ${JSON.stringify(routes)},` : "";
  const template = readFileSync(resolve(root, "wrangler.template.jsonc"), "utf8");
  writeFileSync(
    resolve(root, "../../web/wrangler.production.jsonc"),
    template
      .replace("__DATABASE_ID__", databaseId)
      .replace("__DATABASE_NAME__", databaseName)
      .replace("__API_ENABLED__", apiEnabled)
      .replace("__ROUTES__", routeConfiguration),
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) prepareConfiguration();
