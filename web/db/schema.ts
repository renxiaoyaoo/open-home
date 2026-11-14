import { integer, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

export const gateAccounts = sqliteTable("accounts", {
  id: text("id").primaryKey(),
  provider: text("provider").notNull().default("opengate"),
  mobileFingerprint: text("mobile_fingerprint"),
  mobileMask: text("mobile_mask").notNull(),
  displayName: text("display_name"),
  status: text("status").notNull().default("pending"),
  createdAt: integer("created_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
}, (table) => [uniqueIndex("accounts_provider_mobile_fingerprint").on(table.provider, table.mobileFingerprint)]);

export const gateSessions = sqliteTable("sessions", {
  accountId: text("account_id").primaryKey().references(() => gateAccounts.id, { onDelete: "cascade" }),
  encryptedState: text("encrypted_state").notNull(),
  verifiedAt: integer("verified_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
});

export const providerLeases = sqliteTable("provider_leases", {
  accountId: text("account_id").primaryKey().references(() => gateAccounts.id, { onDelete: "cascade" }),
  owner: text("owner").notNull(),
  expiresAt: integer("expires_at").notNull(),
});

export const activationCodes = sqliteTable("activation_codes", {
  id: text("id").primaryKey(),
  secretHash: text("secret_hash").notNull().unique(),
  expiresAt: integer("expires_at").notNull(),
  createdAt: integer("created_at").notNull(),
});

export const clientDevices = sqliteTable("client_devices", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  instanceHash: text("instance_hash").unique(),
  tokenHash: text("token_hash").notNull().unique(),
  createdAt: integer("created_at").notNull(),
  lastSeenAt: integer("last_seen_at").notNull(),
  revokedAt: integer("revoked_at"),
});

export const liveActivities = sqliteTable("live_activities", {
  activityId: text("activity_id").primaryKey(),
  deviceId: text("device_id").notNull().references(() => clientDevices.id, { onDelete: "cascade" }),
  provider: text("provider").notNull(),
  resourceId: text("resource_id").notNull(),
  pushToken: text("push_token").notNull(),
  environment: text("environment").notNull(),
  lastStateHash: text("last_state_hash"),
  lastPushedAt: integer("last_pushed_at"),
  createdAt: integer("created_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
}, (table) => [uniqueIndex("live_activities_device_resource").on(table.deviceId, table.provider, table.resourceId)]);
