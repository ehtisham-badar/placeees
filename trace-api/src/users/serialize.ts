export interface UserRow {
  id: string;
  handle: string | null;
  homeZone: unknown;
  bannedAt: Date | null;
  createdAt: Date;
}

export function serializeUser(u: UserRow) {
  return {
    id: u.id,
    handle: u.handle,
    hasHomeZone: u.homeZone != null,
    createdAt: u.createdAt,
  };
}
