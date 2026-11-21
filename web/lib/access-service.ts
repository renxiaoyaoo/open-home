import { listActiveAccountIds, loadCentralSession, persistCentralSession } from "./central";
import { createDoorHandle, createDoorId, readDoorHandle } from "./door-handle";
import { verifyDoorSelection } from "./door-selection";
import { centralDoors } from "./provider-service";
import { doorPassword, doorSortBody, isAuthenticationExpired, isSuccess, openDoorBody, providerPost, upstreamMessage } from "./provider";
import { accessRoute } from "./provider-bundle.ts";
import { publicDoor } from "./public-door";

type OpenResult = { ok: boolean; message: string; replayed?: boolean };
const openRequests = new Map<string, { expiresAt: number; promise: Promise<OpenResult> }>();

/** Query every account and project provider-owned resources without persisting them. */
export async function refreshPublicDoors() {
  const accountIds = await listActiveAccountIds();
  const results = await Promise.allSettled(accountIds.map(async (accountId) => ({ accountId, doors: await centralDoors(accountId) })));
  const rejected = results.filter((result): result is PromiseRejectedResult => result.status === "rejected");
  const expired = rejected.filter((result) => isAuthenticationExpired(result.reason));
  const refreshedAt = Date.now();
  const doors = results.flatMap((result) => result.status === "fulfilled" ? result.value.doors.map((door) => ({ value: publicDoor({
    id: createDoorId(result.value.accountId, door), handle: createDoorHandle(result.value.accountId, door), name: door.name, communityName: door.communityName ?? null,
    passwordSupported: Boolean(door.passwordSupported), providerFeatured: Boolean(door.providerFeatured), pinned: Boolean(door.providerPinned), selected: Boolean(door.providerFeatured), refreshedAt,
  }), providerOrder: door.providerOrder ?? Number.MAX_SAFE_INTEGER })) : [])
    .sort((left, right) => Number(right.value.selected) - Number(left.value.selected) || left.providerOrder - right.providerOrder || left.value.name.localeCompare(right.value.name, "zh-CN"))
    .map((item) => item.value);
  return { doors, accountCount: accountIds.length, failedAccountCount: rejected.length, expiredAccountCount: expired.length };
}
async function performOpen(handle: string): Promise<OpenResult> {
  const door = readDoorHandle(handle);
  const session = await loadCentralSession(door.accountId);
  const payload = await providerPost("mobile", accessRoute("operate"), openDoorBody(door.doorControlId, door.communityId), { sessionId: session.sessionId, signingToken: session.signingToken, openId: session.openId, signing: "mobile-body", encoding: "query", context: session.context });
  await persistCentralSession(door.accountId, session);
  const ok = isSuccess(payload);
  return { ok, message: upstreamMessage(payload, ok ? "开门请求成功" : "开门失败") };
}

export async function openPublicDoor(handle: string, idempotencyKey: string) {
  if (!idempotencyKey) return performOpen(handle);
  const now = Date.now();
  for (const [key, value] of openRequests) if (value.expiresAt <= now) openRequests.delete(key);
  const key = `${handle}:${idempotencyKey}`;
  const previous = openRequests.get(key);
  if (previous) return { ...await previous.promise, replayed: true };
  const promise = performOpen(handle);
  openRequests.set(key, { expiresAt: now + 30_000, promise });
  try { return await promise; } catch (error) { openRequests.delete(key); throw error; }
}

export async function publicDoorPassword(handle: string) {
  const door = readDoorHandle(handle);
  if (!door.passwordSupported) throw new Error("该设备不支持密码开门");
  return doorPassword(door.mac || "", door.communityCode || "");
}

export async function setProviderDoorSelected(handle: string, selected: boolean) {
  const door = readDoorHandle(handle);
  const session = await loadCentralSession(door.accountId);
  const options = { sessionId: session.sessionId, signingToken: session.signingToken, openId: session.openId, signing: "mobile-body" as const, context: session.context };
  const all = await providerPost("mobile", accessRoute("allItems"), { communityId: door.communityId }, { ...options, encoding: "multipart" });
  if (!isSuccess(all)) throw new Error(upstreamMessage(all, "门禁查询失败"));
  const body = doorSortBody(all.data, door.communityId, door.doorControlId, selected);
  const saved = await providerPost("mobile", accessRoute("sortItems"), body, { ...options, encoding: "json", signingExclude: ["list"] });
  if (!isSuccess(saved)) throw new Error(upstreamMessage(saved, "常用门禁保存失败"));
  await persistCentralSession(door.accountId, session);
  const verified = await centralDoors(door.accountId);
  verifyDoorSelection(verified, door.communityId, door.doorControlId, selected);
  return refreshPublicDoors();
}
