import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { normalizeDetailedVehicleEnergy, normalizeVehicleEnergy, normalizeVehicleSummary, type VehicleEnergy, type VehicleSummary } from "./openauto.ts";
import { autoRoute, providerBundle } from "./provider-bundle.ts";
import { decryptEnvelope, encryptEnvelope } from "./openauto-codec.js";

export type OpenAutoSession = { userId: string; superId?: string; signToken: string; encryToken: string; displayName?: string };
export type OpenAutoSnapshot = { summary: VehicleSummary; energy: VehicleEnergy };
type Json = Record<string, unknown>;

export class OpenAutoUpstreamError extends Error {
  constructor(readonly code: string, message: string) { super(message); this.name = "OpenAutoUpstreamError"; }
}

function md5(value: string) { return createHash("md5").update(value, "utf8").digest("hex").toUpperCase(); }
function sha1Mixed(value: string) { return [...createHash("sha1").update(value, "utf8").digest()].map((byte, index) => { const hex = byte.toString(16); return index % 2 ? hex.toLowerCase() : hex.toUpperCase(); }).join(""); }
function aesEncrypt(value: Json, key: string) { const cipher = createCipheriv("aes-128-cbc", Buffer.from(key, "hex"), Buffer.alloc(16)); return Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]).toString("hex").toUpperCase(); }
function aesDecrypt(value: string, key: string) { const decipher = createDecipheriv("aes-128-cbc", Buffer.from(key, "hex"), Buffer.alloc(16)); return JSON.parse(Buffer.concat([decipher.update(Buffer.from(value, "hex")), decipher.final()]).toString("utf8")) as Json; }
function sign(fields: Json, password: string) { const value = Object.keys(fields).sort().map((key) => `${key}=${String(fields[key])}`).join("&"); return sha1Mixed(`${value}&password=${password}`); }
function random() { return randomBytes(16).toString("hex").toUpperCase(); }

export class DirectOpenAutoProvider {
  private readonly config = providerBundle().auto;
  private readonly session?: OpenAutoSession;
  constructor(session?: OpenAutoSession) { this.session = session; if (!this.config) throw new Error("OpenAuto provider is not configured"); }
  private client(name: string, fallback = "") { return this.config!.client[name] || fallback; }
  private deviceFields(value: Json) {
    Object.assign(value, { ostype: this.client("ostype", "and"), imei: this.client("imei"), mac: this.client("mac"), model: this.client("model"), sdk: this.client("sdk"), serviceTime: String(Date.now()), mod: this.client("mod") });
    value.checkcode = createHash("sha256").update(JSON.stringify(value), "utf8").digest("hex");
    return value;
  }
  private inner(now = Date.now()) { return { deviceName: this.client("deviceName"), deviceType: this.client("deviceType", "0"), imeiMD5: this.client("imeiMD5"), mobileBrand: this.client("mobileBrand"), mobileModel: this.client("mobileModel"), networkOperator: this.client("networkOperator"), networkType: this.client("networkType", "wifi"), osType: this.client("osType", "Android"), osVersion: this.client("osVersion"), random: random(), softType: this.client("softType", "0"), timeStamp: String(now), version: this.client("version") }; }
  private async post(route: string, body: Json) {
    const response = await fetch(`${this.config!.baseUrl}${route}`, { method: "POST", headers: { "content-type": "application/json; charset=UTF-8", "accept-encoding": "identity", "user-agent": this.client("userAgent", "okhttp/4.12.0"), version: this.client("version"), platform: this.client("platform", "ANDROID"), BrandFlag: this.client("brandFlag") }, body: JSON.stringify({ request: encryptEnvelope(JSON.stringify(body)) }), cache: "no-store" });
    if (!response.ok) throw new Error(`OpenAuto request failed (${response.status})`);
    const wrapped = await response.json() as { response?: string };
    if (!wrapped.response) throw new Error("OpenAuto response is invalid");
    return JSON.parse(decryptEnvelope(wrapped.response)) as Json;
  }
  private tokenRequest(inner: Json) {
    if (!this.session) throw new Error("Account is not signed in");
    const reqTimestamp = String(Date.now()); const contentKey = md5(this.session.encryToken); const password = md5(this.session.signToken); const identifier = this.session.superId || this.session.userId; const targetBrand = this.client("targetBrand"); const appChannel = this.client("appChannel"); const vehicleBrand = this.client("vehicleBrand", targetBrand); const imeiMD5 = this.client("imeiMD5");
    const fields = { ...inner, appChannel, identifier, identifierType: 1, imeiMD5, objective: inner.vin || "", reqTimestamp, targetBrand, vehicleBrand };
    return { request: this.deviceFields({ appChannel, encryData: aesEncrypt(inner, contentKey), identifier, identifierType: 1, imeiMD5, objective: inner.vin || "", outModelTypes: null, reqTimestamp, sign: sign(fields, password), softType: null, targetBrand, vehicleBrand, version: null }), contentKey };
  }
  async passwordLogin(phone: string, password: string): Promise<OpenAutoSession> {
    if (!/^1\d{10}$/.test(phone) || !password) throw new Error("手机号或密码无效");
    const now = Date.now(); const reqTimestamp = String(now); const loginInner: Json = { appInnerVersion: this.client("version"), appVersion: this.client("appVersion"), bluetoothMac: this.client("bluetoothMac"), city: this.client("city"), configVersion: this.client("configVersion"), deviceType: this.client("deviceType", "0"), devicename: this.client("deviceName"), imeiMD5: this.client("imeiMD5"), isAuto: this.client("isAuto", "0"), latitude: this.client("latitude"), longitude: this.client("longitude"), mobileBrand: this.client("mobileBrand"), mobileModel: this.client("mobileModel"), networkOperator: this.client("networkOperator"), networkType: this.client("networkType", "wifi"), osType: this.client("osType", "Android"), osVersion: this.client("osVersion"), random: random(), softType: this.client("softType", "0"), timeStamp: reqTimestamp };
    const appChannel = this.client("appChannel"); const targetBrand = this.client("targetBrand"); const imeiMD5 = this.client("imeiMD5"); const key = md5(md5(password)); const fields = { ...loginInner, appChannel, identifier: phone, loginType: 0, reqTimestamp, targetBrand };
    const response = await this.post(autoRoute("login"), { appChannel, encryData: aesEncrypt(loginInner, key), identifier: phone, imeiMD5, isAuto: this.client("isAuto", "0"), loginType: 0, reqTimestamp, sign: sign(fields, md5(password)), targetBrand });
    if (String(response.code) !== "0") throw new Error(String(response.message || "账号登录失败"));
    const decoded = aesDecrypt(String(response.respondData || ""), key); const token = (decoded.token || {}) as Json; const relations = (token.superBindRelationDtoMap || {}) as Record<string, Json>; const superId = String(token.superId || ""); const userId = String(relations[targetBrand]?.userId || superId); const signToken = String(token.signToken || ""); const encryToken = String(token.encryToken || token.encryptToken || "");
    if (!userId || !signToken || !encryToken) throw new Error("登录响应缺少会话信息");
    return { userId, superId: superId || undefined, signToken, encryToken, displayName: String(decoded.nickName || "OpenAuto 账号") };
  }
  async vehicles() {
    const inner = { appUiName: "", ...this.inner() }; const built = this.tokenRequest(inner); const response = await this.post(autoRoute("vehicles"), built.request); if (String(response.code) !== "0") throw new OpenAutoUpstreamError(String(response.code ?? "unknown"), String(response.message || "车辆加载失败")); const decoded = aesDecrypt(String(response.respondData || ""), built.contentKey); const list = Array.isArray(decoded) ? decoded : Array.isArray(decoded.diLinkAutoInfoList) ? decoded.diLinkAutoInfoList : []; return (list as Json[]).filter((item) => item.vin).map((item) => ({ id: String(item.vin), name: String(item.autoName || item.modelName || item.carTypeName || "车辆") }));
  }
  private async rawSummary(vehicleId: string) {
    const inner = { ...this.inner(), energyType: this.client("energyType", "0"), tboxVersion: this.client("tboxVersion", "3"), vin: vehicleId }; const built = this.tokenRequest(inner); const response = await this.post(autoRoute("latestCondition"), built.request); if (String(response.code) !== "0") throw new Error(String(response.message || "车辆状态加载失败")); return aesDecrypt(String(response.respondData || ""), built.contentKey);
  }
  private async energyRequest(route: "recentEnergy" | "historicalEnergy", vehicleId: string, vehicle: Json, extra: Json = {}) {
    const inner = { ...this.inner(), vin: vehicleId, autoType: String(vehicle.autoType || this.client("autoType")), tboxVersion: String(vehicle.tboxVersion || this.client("tboxVersion", "3")), ...extra };
    const built = this.tokenRequest(inner); const response = await this.post(autoRoute(route), built.request);
    if (String(response.code) !== "0") throw new Error(String(response.message || "能耗数据加载失败"));
    return aesDecrypt(String(response.respondData || ""), built.contentKey);
  }
  async summary(vehicleId: string): Promise<OpenAutoSnapshot> {
    const raw = await this.rawSummary(vehicleId); const summary = normalizeVehicleSummary(raw, vehicleId);
    try {
      const [recent, historical] = await Promise.all([this.energyRequest("recentEnergy", vehicleId, raw, { type: "NEAREST_KM" }), this.energyRequest("historicalEnergy", vehicleId, raw)]);
      return { summary, energy: normalizeDetailedVehicleEnergy(recent, historical, summary.odometerKm) };
    } catch {
      return { summary, energy: normalizeVehicleEnergy(raw) };
    }
  }
}
