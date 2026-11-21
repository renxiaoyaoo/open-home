import { listActiveAccountIds, loadCentralSession, persistCentralSession } from "./central.ts";
import { accessRoute } from "./provider-bundle.ts";
import { communityIds, doorSortState, isSuccess, normalizeDoors, providerPost } from "./provider.ts";

export async function probeGateRules(mode: "inspect" | "below-minimum" | "remove-one") {
  const accounts = await listActiveAccountIds();
  if (accounts.length !== 1) throw new Error("Probe requires exactly one active gate account");
  const session = await loadCentralSession(accounts[0]);
  const options = { sessionId: session.sessionId, signingToken: session.signingToken, openId: session.openId, signing: "mobile-body" as const, context: session.context, encoding: "multipart" as const };
  const communities = await providerPost("mobile", accessRoute("communities"), { method: "communityInfo" }, { ...options, encoding: "json" });
  if (!isSuccess(communities)) throw new Error("Community read failed");
  const ids = communityIds(communities.data);
  if (ids.length !== 1) throw new Error("Probe requires exactly one community");
  const communityId = ids[0];
  const record = (value: unknown) => value as Record<string, unknown>;
  const read = async () => {
    const home = await providerPost("mobile", accessRoute("homeItems"), { communityId }, options);
    const all = await providerPost("mobile", accessRoute("allItems"), { communityId }, options);
    if (!isSuccess(home) || !isSuccess(all)) throw new Error("Probe read failed");
    return { home: record(home.data), all: record(all.data), groups: doorSortState(all.data) };
  };
  const original = await read();
  const keys = (value: unknown) => normalizeDoors(value, communityId).map((door) => door.doorControlId);
  const originalUser = keys(original.all.userDoorDTOS);
  const homeUser = keys(original.home.userDoorDTOS);
  const automatic = original.groups.common;
  const same = (left: number[], right: number[]) => left.length === right.length && left.every((id, index) => id === right[index]);
  if (!same(originalUser, homeUser)) throw new Error("Home and complete-list selections differ before probe");
  const summarize = (value: typeof original) => ({ userCount: keys(value.all.userDoorDTOS).length, homeCount: keys(value.home).length, automaticCount: value.groups.common.length, gateCount: value.groups.gate.length, buildingCount: value.groups.building.length, customCount: value.groups.custom.length });
  if (mode === "inspect") return { before: summarize(original), homeMatchesCompleteSelection: true, automaticOverlapsBuilding: automatic.filter((id) => original.groups.building.includes(id)).length };
  if (originalUser.length < 3) throw new Error("Insufficient initial selection for this probe");
  const desired = mode === "below-minimum" ? originalUser.slice(0, 1) : originalUser.slice(1);
  const body = (common: number[]) => ({ list: [{ commondoorControlIds: common, gatedoorControlIds: original.groups.gate, buildingDoorList: original.groups.building, customDoorList: original.groups.custom }], method: "doorSort", commId: communityId, gateDoorColor: original.groups.gateDoorColor, buildingDoorColor: original.groups.buildingDoorColor, customDoorColor: original.groups.customDoorColor });
  let changed = false;
  try {
    changed = true;
    const saved = await providerPost("mobile", accessRoute("sortItems"), body(desired), { ...options, encoding: "json", signingExclude: ["list"] });
    const observed = await read();
    return { mode, before: summarize(original), requestedUserCount: desired.length, businessSuccess: isSuccess(saved), after: summarize(observed), requestedMembershipMatched: same(keys(observed.all.userDoorDTOS), desired), addedCount: keys(observed.all.userDoorDTOS).filter((id) => !desired.includes(id)).length, automaticMembershipUnchanged: same(observed.groups.common, automatic), restoredExactly: true };
  } finally {
    if (changed) {
      await new Promise((resolve) => setTimeout(resolve, 10_000));
      const restored = await providerPost("mobile", accessRoute("sortItems"), body(originalUser), { ...options, encoding: "json", signingExclude: ["list"] });
      const final = await read();
      const restoredExactly = isSuccess(restored) && same(keys(final.all.userDoorDTOS), originalUser) && same(keys(final.home.userDoorDTOS), homeUser) && same(final.groups.common, automatic) && same(final.groups.gate, original.groups.gate) && same(final.groups.building, original.groups.building) && same(final.groups.custom, original.groups.custom);
      console.info("gate-rule-probe-restoration", { restoredExactly });
      if (!restoredExactly) throw new Error("Probe restoration did not match original grouped state; stop further writes");
    }
    await persistCentralSession(accounts[0], session);
  }
}
