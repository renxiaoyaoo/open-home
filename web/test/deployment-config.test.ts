import assert from "node:assert/strict";
import test from "node:test";
import { cloudflareRoutes } from "../../deploy/cloudflare/prepare-config.mjs";

test("routes the Web and native API hostnames to one portable Worker", () => {
  assert.deepEqual(cloudflareRoutes({
    OPENHOME_CF_CUSTOM_DOMAIN: "home.example",
    OPENHOME_CF_API_DOMAIN: "api.home.example",
  }), [
    { pattern: "home.example", custom_domain: true },
    { pattern: "api.home.example", custom_domain: true },
  ]);
  assert.throws(() => cloudflareRoutes({
    OPENHOME_CF_CUSTOM_DOMAIN: "home.example",
    OPENHOME_CF_API_DOMAIN: "HOME.EXAMPLE",
  }), /must be different/);
});
