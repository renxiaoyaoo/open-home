import assert from "node:assert/strict";
import test from "node:test";
import { cloudflareRoutes, publicAPIURL } from "../../deploy/cloudflare/prepare-config.mjs";

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

test("derives the native API URL from the private deployment hostname", () => {
  assert.equal(publicAPIURL({ OPENHOME_CF_API_DOMAIN: "api.home.example" }), "https://api.home.example/api/v1");
  assert.equal(publicAPIURL({ OPENHOME_PUBLIC_API_URL: "https://native.example/custom/" }), "https://native.example/custom");
  assert.throws(() => publicAPIURL({ OPENHOME_PUBLIC_API_URL: "http://native.example/api/v1" }), /must be an HTTPS URL/);
});
