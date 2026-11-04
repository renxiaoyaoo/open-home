CREATE TABLE `activation_codes` (
	`id` text PRIMARY KEY NOT NULL,
	`secret_hash` text NOT NULL,
	`expires_at` integer NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `activation_codes_secret_hash_unique` ON `activation_codes` (`secret_hash`);--> statement-breakpoint
CREATE TABLE `client_devices` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`token_hash` text NOT NULL,
	`created_at` integer NOT NULL,
	`last_seen_at` integer NOT NULL,
	`revoked_at` integer
);
--> statement-breakpoint
CREATE UNIQUE INDEX `client_devices_token_hash_unique` ON `client_devices` (`token_hash`);