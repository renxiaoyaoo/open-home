export function verifyDoorSelection(doors: Array<{ id: string; selected: boolean }>, scope: string[], expected: string[]) {
  const scoped = new Set(scope);
  const actual = new Set(doors.filter((door) => scoped.has(door.id) && door.selected).map((door) => door.id));
  const desired = new Set(expected);
  const returned = new Set(doors.map((door) => door.id));
  if (scope.some((id) => !returned.has(id)) || desired.size !== actual.size || [...desired].some((id) => !actual.has(id))) throw new Error("厂商未确认常用门禁变更，请刷新查看实际状态");
}
