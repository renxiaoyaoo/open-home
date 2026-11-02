import { loadCentralSession, persistCentralSession, saveCentralSession, type CentralSession } from "./central";
import { communityCodes, communityIds, communityNames, dedupeDoors, deviceId, encryptMobile, isSuccess, loginCredential, normalizeDoors, providerPost, upstreamMessage } from "./provider";
import { accessRoute } from "./provider-bundle.ts";
import { personalDisplayName } from "./account-name";

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
    let home: Awaited<ReturnType<typeof providerPost>> | null = null;
    try {
      home = await providerPost("mobile", accessRoute("homeItems"), { communityId }, { ...options, encoding: "multipart" });
    } catch {
      // The complete list remains usable when the home-list request is unavailable.
    }
    const featured = home && isSuccess(home) ? normalizeDoors(home.data, communityId, codes.get(communityId), names.get(communityId)) : [];
    const featuredIds = new Set(featured.map((door) => `${door.communityId}:${door.doorControlId}`));
    const featuredOrder = new Map(featured.map((door, index) => [`${door.communityId}:${door.doorControlId}`, index]));
    let all: Awaited<ReturnType<typeof providerPost>> | null = null;
    try {
      all = await providerPost("mobile", accessRoute("allItems"), { communityId }, { ...options, encoding: "multipart" });
    } catch {
      // Fall through to the already verified home-list endpoint below.
    }
    if (all && isSuccess(all)) {
      doors.push(...normalizeDoors(all.data, communityId, codes.get(communityId), names.get(communityId)).map((door) => ({
        ...door,
        providerFeatured: featuredIds.has(`${door.communityId}:${door.doorControlId}`),
        providerOrder: featuredOrder.get(`${door.communityId}:${door.doorControlId}`),
      })));
      continue;
    }

    // Older provider deployments may not expose the complete-list endpoint.
    // Preserve the previously verified home-list behavior instead of erasing
    // the account's cached doors when that happens.
    if (!home || !isSuccess(home)) throw new Error(upstreamMessage(home || {}, "门禁查询失败"));
    doors.push(...featured.map((door, index) => ({ ...door, providerFeatured: true, providerOrder: index })));
  }
  const result = dedupeDoors(doors); await persistCentralSession(accountId, session); return result;
}
