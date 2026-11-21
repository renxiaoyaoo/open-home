import { listActiveAccountIds, loadCentralSession, persistCentralSession } from "./central.ts";
import { createDoorHandle, createDoorId, readDoorHandle } from "./door-handle.ts";
import { centralDoors } from "./provider-service.ts";
import { doorPassword, doorSortBody, isAuthenticationExpired, isSuccess, normalizeDoors, openDoorBody, providerPost, upstreamMessage } from "./provider.ts";
import { accessRoute } from "./provider-bundle.ts";
import { publicDoor } from "./public-door.ts";

type OpenResult = { ok: boolean; message: string; replayed?: boolean };
const openRequests = new Map<string, { expiresAt: number; promise: Promise<OpenResult> }>();

/** Query every account and project provider-owned resources without persisting them. */
export async function refreshPublicDoors() {
  const accountIds = await listActiveAccountIds();
  const results = await Promise.allSettled(accountIds.map(async (accountId) => ({ accountId, doors: await centralDoors(accountId) })));
  const rejected = results.filter((result): result is PromiseRejectedResult => result.status === "rejected");
  const expired = rejected.filter((result) => isAuthenticationExpired(result.reason));
  if (accountIds.length > 0 && rejected.length === results.length) throw rejected[0].reason;
  const refreshedAt = Date.now();
  const doors = results.flatMap((result) => result.status === "fulfilled" ? result.value.doors.map((door) => ({ value: publicDoor({
    id: createDoorId(result.value.accountId, door), handle: createDoorHandle(result.value.accountId, door), name: door.name, communityName: door.communityName ?? null,
    passwordSupported: Boolean(door.passwordSupported), selected: Boolean(door.selected), refreshedAt,
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
  const home = await providerPost("mobile", accessRoute("homeItems"), { communityId: door.communityId }, { ...options, encoding: "multipart" });
  if (!isSuccess(home)) throw new Error(upstreamMessage(home, "常用门禁查询失败"));
  const all = await providerPost("mobile", accessRoute("allItems"), { communityId: door.communityId }, { ...options, encoding: "multipart" });
  if (!isSuccess(all)) throw new Error(upstreamMessage(all, "门禁查询失败"));
  const body = doorSortBody(all.data, home.data, door.communityId, door.doorControlId, selected);
  const targetId = createDoorId(door.accountId, door);
  const wasSelected = normalizeDoors(home.data, door.communityId).some((item) => item.doorControlId === door.doorControlId);
  if (wasSelected !== selected) {
    const saved = await providerPost("mobile", accessRoute("sortItems"), body, { ...options, encoding: "json", signingExclude: ["list"] });
    if (!isSuccess(saved)) throw new Error(upstreamMessage(saved, "常用门禁保存失败"));
  }
  await persistCentralSession(door.accountId, session);
  const verified = await refreshPublicDoors();
  const actual = verified.doors.find((item) => item.id === targetId);
  if (!actual) throw new Error("无法读取厂商保存后的门禁状态");
  const message = actual.selected === selected
    ? selected ? "已加入常用门禁" : "已移出常用门禁"
    : actual.selected ? "厂商仍将此门禁列为常用" : "厂商未将此门禁加入常用";
  return { ...verified, message };
}
