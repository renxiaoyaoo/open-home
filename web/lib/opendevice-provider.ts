import { createHmac, randomBytes } from "node:crypto";
import { DRYER_PROGRAM_IDS, DRYER_PROGRAMS } from "./dryer-programs.ts";
import { deviceRoute, providerBundle } from "./provider-bundle.ts";

export type OpenDeviceSession = { uid: string; accessToken: string; deviceId: string; displayName?: string; tokenPwd?: string; accessTokenExpiresAt?: number; tokenPwdExpiresAt?: number };
export type RefreshedSession = Pick<OpenDeviceSession, "accessToken" | "accessTokenExpiresAt" | "tokenPwd" | "tokenPwdExpiresAt">;
export type OpenDeviceRefreshCoordinator = (staleAccessToken: string | undefined, refresh: () => Promise<RefreshedSession>) => Promise<RefreshedSession>;
const refreshFlights = new Map<string, Promise<RefreshedSession>>();
function stamp(now = new Date()) { return now.toISOString().replace(/[-:T]/g, "").slice(0, 14); }

export class OpenDeviceProvider {
  private readonly config = providerBundle().device;
  private readonly url = this.config.baseUrl;
  private readonly appId = this.config.credentials.appId;
  private readonly appKey = this.config.credentials.appKey;
  private readonly iotKey = this.config.credentials.iotKey;
  private readonly hmacKey = this.config.credentials.hmacKey;
  readonly deviceId: string;
  private uid?: string;
  private accessToken?: string;
  private readonly session?: OpenDeviceSession;
  private readonly refreshCoordinator?: OpenDeviceRefreshCoordinator;

  constructor(session?: OpenDeviceSession, refreshCoordinator?: OpenDeviceRefreshCoordinator) { this.session = session; this.refreshCoordinator = refreshCoordinator; this.deviceId = session?.deviceId || this.config.credentials.deviceId; this.uid = session?.uid; this.accessToken = session?.accessToken; }
  private general(extra: Record<string, unknown> = {}) { const client = this.config.client; return { src: this.appId, format: "2", stamp: stamp(), platformId: client.platformId, deviceId: this.deviceId, reqId: randomBytes(16).toString("hex"), uid: this.uid, clientType: client.clientType, appId: this.appId, language: client.language, ...extra }; }
  private async request(alias: string, options: { method?: string; data?: unknown; query?: string; headers?: Record<string, string>; refresh?: boolean; authenticated?: boolean } = {}): Promise<unknown> {
    const method = options.method || "POST"; const body = options.data === undefined ? "" : JSON.stringify(options.data); const nonce = String(Math.floor(Date.now() / 1000));
    const headers: Record<string, string> = { "content-type": "application/json; charset=utf-8", version: this.config.client.version, secretVersion: this.config.client.secretVersion, random: nonce, sign: createHmac("sha256", this.hmacKey).update(`${this.iotKey}${body}${nonce}`).digest("hex"), ...options.headers };
    if (options.authenticated !== false) { if (this.uid) headers.uid = this.uid; if (this.accessToken) headers.accessToken = this.accessToken; }
    const response = await fetch(`${this.url}${alias}${options.query || ""}`, { method, headers, body: method === "GET" ? undefined : body, signal: AbortSignal.timeout(12_000) });
    const payload = await response.json().catch(() => ({ code: response.status, msg: "invalid response" })) as { code?: string | number; msg?: string; data?: unknown };
    if (!response.ok || String(payload.code) !== "0") {
      if (options.refresh !== false && ["40002", "65012"].includes(String(payload.code)) && this.session?.tokenPwd) {
        await this.refreshAccessToken();
        return this.request(alias, { ...options, refresh: false });
      }
      throw new Error(`OpenLiving provider: ${payload.code ?? response.status} ${payload.msg || "request failed"}`);
    }
    return payload.data;
  }
  private async refreshAccessToken() {
    if (!this.uid || !this.session?.tokenPwd) throw new Error("OpenLiving session cannot be refreshed");
    if (this.refreshCoordinator) {
      const refreshed = await this.refreshCoordinator(this.accessToken, () => this.performAccessTokenRefresh());
      this.accessToken = refreshed.accessToken;
      Object.assign(this.session, refreshed);
      return;
    }
    const key = `${this.uid}:${this.session.tokenPwd}`;
    let flight = refreshFlights.get(key);
    if (!flight) {
      flight = this.performAccessTokenRefresh();
      refreshFlights.set(key, flight);
      void flight.finally(() => refreshFlights.delete(key)).catch(() => undefined);
    }
    const refreshed = await flight;
    this.accessToken = refreshed.accessToken;
    Object.assign(this.session, refreshed);
  }
  private async performAccessTokenRefresh(): Promise<RefreshedSession> {
    if (!this.uid || !this.session?.tokenPwd) throw new Error("OpenLiving session cannot be refreshed");
    const result = await this.request(deviceRoute("refresh"), {
      data: { timestamp: stamp(), data: { tokenPwd: this.session.tokenPwd, rule: 1, platform: 2, iotAppId: this.appId, deviceId: this.deviceId } },
      headers: { userId: this.uid },
      refresh: false,
      authenticated: false,
    }) as { accessToken?: string; expired?: number; tokenPwdInfo?: { tokenPwd?: string; expiredDate?: number }; mdata?: { accessToken?: string; expired?: number; tokenPwdInfo?: { tokenPwd?: string; expiredDate?: number } } };
    const accessToken = result.accessToken || result.mdata?.accessToken;
    const tokenInfo = result.tokenPwdInfo || result.mdata?.tokenPwdInfo;
    if (!accessToken) throw new Error("OpenLiving session refresh did not return a token");
    const accessExpiry = result.expired ?? result.mdata?.expired;
    return {
      accessToken,
      accessTokenExpiresAt: Number.isFinite(Number(accessExpiry)) ? Number(accessExpiry) : this.session.accessTokenExpiresAt,
      tokenPwd: tokenInfo?.tokenPwd || this.session.tokenPwd,
      tokenPwdExpiresAt: Number.isFinite(Number(tokenInfo?.expiredDate)) ? Number(tokenInfo?.expiredDate) : this.session.tokenPwdExpiresAt,
    };
  }
  requestSms(mobile: string) { return this.request(deviceRoute("sms"), { data: { data: { deviceId: this.deviceId }, iotData: { type: 9, mobile, iotAppId: this.appId }, timestamp: stamp() } }); }
  async smsLogin(mobile: string, smsCode: string) {
    const result = await this.request(deviceRoute("login"), { data: { data: { appKey: this.appKey, appVersion: this.config.client.version, deviceId: this.deviceId, deviceName: "OpenHome", osVersion: "Cloudflare", platform: 2 }, iotData: { mobile, smsCode, iotAppId: this.appId, appVersion: this.config.client.version, deviceId: this.deviceId, loginType: 0 }, timestamp: stamp() } }) as { iotUserId?: string; userInfo?: { uid?: string; userId?: string; nickName?: string; nickname?: string; name?: string }; mdata?: { accessToken?: string; expired?: number; tokenPwdInfo?: { tokenPwd?: string; expiredDate?: number }; userInfo?: { uid?: string; nickName?: string; nickname?: string } }; tokenPwdInfo?: { tokenPwd?: string; expiredDate?: number } };
    const uid = result.userInfo?.uid || result.userInfo?.userId || result.iotUserId || result.mdata?.userInfo?.uid; const accessToken = result.mdata?.accessToken;
    const displayName = result.userInfo?.nickName || result.userInfo?.nickname || result.userInfo?.name || result.mdata?.userInfo?.nickName || result.mdata?.userInfo?.nickname || `${mobile.slice(0, 3)}****${mobile.slice(-4)}`;
    const tokenInfo = result.mdata?.tokenPwdInfo || result.tokenPwdInfo;
    if (!uid || !accessToken) throw new Error("OpenLiving login response did not contain a session");
    return { uid: String(uid), accessToken: String(accessToken), deviceId: this.deviceId, displayName, tokenPwd: tokenInfo?.tokenPwd, accessTokenExpiresAt: result.mdata?.expired, tokenPwdExpiresAt: tokenInfo?.expiredDate };
  }
  listHomes() { return this.request(deviceRoute("homes"), { data: this.general() }); }
  listDevices(homeId: string) { return this.request(deviceRoute("devices"), { data: this.general({ homegroupId: homeId }) }); }
  async capabilities(homeId: string, applianceCode: string) {
    const mapping = await this.request(deviceRoute("templateMap"), { data: this.general({ homeGroupId: homeId, applianceCodes: [applianceCode], screenVersion: this.config.client.version, protocolVersion: 0, platform: "app", needOldTemplate: 1 }) }) as Array<{ currentUiTemplateId?: number | string; currentUiJsId?: number | string }>;
    const item = Array.isArray(mapping) ? mapping[0] : undefined;
    if (!item) throw new Error("OpenLiving template mapping is unavailable");
    await this.request(deviceRoute("templateGet"), { data: this.general({ uiTemplateIds: item.currentUiTemplateId ? [Number(item.currentUiTemplateId)] : null, uiJsIds: item.currentUiJsId ? [Number(item.currentUiJsId)] : null, platform: "app" }) });
    return { programs: DRYER_PROGRAMS };
  }
  async status(deviceId: string) {
    const raw = await this.thing("GET", deviceRoute("properties", { deviceId }));
    const source = raw as { properties?: Array<{ code?: string; propertyCode?: string; value: unknown }>; data?: { properties?: Array<{ code?: string; propertyCode?: string; value: unknown }> } };
    const list = source?.properties || source?.data?.properties;
    const values = Array.isArray(list) ? Object.fromEntries(list.map((item) => [item.code || item.propertyCode || "", item.value])) : raw as Record<string, unknown>;
    const parameters = Object.fromEntries(Object.entries(this.config.properties.parameters || {}).map(([key, mapping]) => {
      const value = values[mapping.property];
      return [key, mapping.type === "boolean" ? (value === true ? 1 : 0) : value];
    }));
    return Array.isArray(list) ? { ...source, openHomeParameters: parameters } : { ...values, openHomeParameters: parameters };
  }
  program(deviceId: string, programId: number) { if (!DRYER_PROGRAM_IDS.has(programId)) throw new Error("Unsupported dryer program"); return this.thing("PUT", deviceRoute("properties", { deviceId }), { [this.config.properties.program]: programId }); }
  configureProgram(deviceId: string, programId: number, parameters: Record<string, number>) {
    const program = DRYER_PROGRAMS.find((item) => item.value === programId);
    if (!program) throw new Error("Unsupported dryer program");
    const allowed = new Map((program.parameters || []).map((parameter) => [parameter.property, new Set(parameter.values.map((option) => option.value))]));
    const body: Record<string, number | boolean> = { [this.config.properties.program]: programId };
    for (const [key, value] of Object.entries(parameters)) {
      const values = allowed.get(key as keyof typeof this.config.properties.parameters);
      const mapping = this.config.properties.parameters?.[key as keyof NonNullable<typeof this.config.properties.parameters>];
      if (!values?.has(value) || !mapping) throw new Error("Unsupported dryer parameter");
      body[mapping.property] = mapping.type === "boolean" ? value === 1 : value;
    }
    return this.thing("PUT", deviceRoute("properties", { deviceId }), body);
  }
  power(deviceId: string, power: boolean) { return this.thing("PUT", deviceRoute("properties", { deviceId }), { [this.config.properties.power]: power }); }
  action(deviceId: string, action: keyof ProviderBundleActions, data: unknown) { const target = this.config.actions[action]; if (!target) throw new Error("Unsupported dryer action"); return this.thing("POST", deviceRoute("action", { action: target, deviceId }), data); }
  private thing(method: string, alias: string, data?: unknown) { return this.request(alias, { method, data, query: `?requestId=${randomBytes(16).toString("hex")}&sync=true`, headers: { caller: this.appId, "call-source": this.config.client.source, "call-module": this.config.client.module } }); }
}

type ProviderBundleActions = ReturnType<typeof providerBundle>["device"]["actions"];
