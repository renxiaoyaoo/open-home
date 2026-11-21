import type { Door } from "./provider.ts";
import { openSession, sealSession, stableOpaqueId } from "./session-crypto.ts";

export type DoorHandle = Pick<Door, "communityId" | "doorControlId" | "communityCode" | "mac" | "deviceModel" | "passwordSupported"> & { accountId: string };

export function createDoorHandle(accountId: string, door: Door) {
  return sealSession({ accountId, communityId: door.communityId, doorControlId: door.doorControlId, communityCode: door.communityCode, mac: door.mac, deviceModel: door.deviceModel, passwordSupported: door.passwordSupported } satisfies DoorHandle);
}

export function createDoorId(accountId: string, door: Pick<Door, "communityId" | "doorControlId">) {
  return stableOpaqueId("door", [accountId, door.communityId, door.doorControlId]);
}

export function readDoorHandle(value: string): DoorHandle {
  if (!/^v1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value) || value.length > 1024) throw new Error("Invalid door ID");
  const door = openSession<DoorHandle>(value);
  if (!/^[a-z0-9][a-z0-9_-]{0,47}$/i.test(door.accountId) || !Number.isSafeInteger(door.communityId) || !Number.isSafeInteger(door.doorControlId)) throw new Error("Invalid door ID");
  return door;
}
