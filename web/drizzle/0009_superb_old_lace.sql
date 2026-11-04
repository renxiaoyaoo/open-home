CREATE TABLE `live_activities` (
	`activity_id` text PRIMARY KEY NOT NULL,
	`device_id` text NOT NULL,
	`provider` text NOT NULL,
	`resource_id` text NOT NULL,
	`push_token` text NOT NULL,
	`environment` text NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`device_id`) REFERENCES `client_devices`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `live_activities_device_resource` ON `live_activities` (`device_id`,`provider`,`resource_id`);