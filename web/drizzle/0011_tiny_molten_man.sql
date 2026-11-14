ALTER TABLE `client_devices` ADD `instance_hash` text;--> statement-breakpoint
CREATE UNIQUE INDEX `client_devices_instance_hash_unique` ON `client_devices` (`instance_hash`);