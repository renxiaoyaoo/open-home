import { loadCentralSession, persistCentralSession, saveCentralSession, type CentralSession } from "./central.ts";
import { communityCodes, communityIds, communityNames, dedupeDoors, deviceId, doorSortState, encryptMobile, isSuccess, loginCredential, normalizeDoors, providerPost, upstreamMessage } from "./provider.ts";
import { accessRoute } from "./provider-bundle.ts";
import { personalDisplayName } from "./account-name.ts";

export async function centralLogin(accountId: string, mobile: string, smsCode: string) {
  const openId = deviceId(); const context = { cookies: {} };
  const login = await providerPost("mobile", accessRoute("login"), { mobile: encryptMobile(mobile), smsCode, appChannel: 1 }, { openId, signing: "mobile-body", encoding: "json", context });
  const credential = loginCredential(login.data);
  if (!isSuccess(login) || !credential) throw new Error(upstreamMessage(login, "登录失败"));
  const personal = await providerPost("mobile", accessRoute("profile"), { method: "personalInfo" }, { sessionId: credential, signingToken: credential, openId, signing: "mobile-body", encoding: "json", context });
  if (!isSuccess(personal)) throw new Error(upstreamMessage(personal, "登录初始化失败"));
  const session: CentralSession = { sessionId: credential, signingToken: credential, openId, context };
  await saveCentralSession(accountId, mobile, personalDisplayName(personal.data), session);
}
export async function centralDoors(accountId: string) {
  const session = await loadCentralSession(accountId);
  const options = { sessionId: session.sessionId, signingToken: session.signingToken, openId: session.openId, signing: "mobile-body" as const, context: session.context };
  const communities = await providerPost("mobile", accessRoute("communities"), { method: "communityInfo" }, { ...options, encoding: "json" });
  if (!isSuccess(communities)) throw new Error(upstreamMessage(communities, "小区查询失败"));
  const codes = communityCodes(communities.data); const names = communityNames(communities.data); const doors = [];
  for (const communityId of communityIds(communities.data).slice(0, 20)) {
    const home = await providerPost("mobile", accessRoute("homeItems"), { communityId }, { ...options, encoding: "multipart" });
    if (!isSuccess(home)) throw new Error(upstreamMessage(home, "常用门禁查询失败"));
    const featured = normalizeDoors(home.data, communityId, codes.get(communityId), names.get(communityId));
    const featuredIds = new Set(featured.map((door) => `${door.communityId}:${door.doorControlId}`));
    const featuredOrder = new Map(featured.map((door, index) => [`${door.communityId}:${door.doorControlId}`, index]));
    const all = await providerPost("mobile", accessRoute("allItems"), { communityId }, { ...options, encoding: "multipart" });
    if (!isSuccess(all)) throw new Error(upstreamMessage(all, "门禁查询失败"));
    const sortState = doorSortState(all.data);
    doors.push(...normalizeDoors(all.data, communityId, codes.get(communityId), names.get(communityId)).map((door) => ({
      ...door,
      providerFeatured: featuredIds.has(`${door.communityId}:${door.doorControlId}`),
      providerPinned: sortState.common.includes(door.doorControlId) && sortState.categories.get(door.doorControlId) === "building",
      providerOrder: featuredOrder.get(`${door.communityId}:${door.doorControlId}`),
    })));
  }
  const result = dedupeDoors(doors); await persistCentralSession(accountId, session); return result;
}
