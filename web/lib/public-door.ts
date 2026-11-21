export type PublicDoor = {
  id: string;
  handle: string;
  name: string;
  communityName: string | null;
  passwordSupported: boolean;
  selected: boolean;
  refreshedAt: number;
};

export function publicDoor(row: {
  id: string;
  handle: string;
  name: string;
  communityName: string | null;
  passwordSupported: boolean;
  selected: boolean;
  refreshedAt: number;
}): PublicDoor {
  return { id: row.id, handle: row.handle, name: row.name, communityName: row.communityName, passwordSupported: row.passwordSupported, selected: row.selected, refreshedAt: row.refreshedAt };
}
