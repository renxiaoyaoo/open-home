export function verifyDoorSelection(doors: Array<{ communityId: number; doorControlId: number; providerFeatured?: boolean }>, communityId: number, doorControlId: number, selected: boolean) {
  const target = doors.find((door) => door.communityId === communityId && door.doorControlId === doorControlId);
  if (!target || Boolean(target.providerFeatured) !== selected) throw new Error("厂商未确认常用门禁变更，请重试");
}
