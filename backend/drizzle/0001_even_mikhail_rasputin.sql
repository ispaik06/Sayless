ALTER TABLE `usage_events` ADD `provider` text;--> statement-breakpoint
ALTER TABLE `usage_events` ADD `model` text;--> statement-breakpoint
ALTER TABLE `usage_events` ADD `input_tokens` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `usage_events` ADD `output_tokens` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `usage_events` ADD `total_tokens` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `usage_events` ADD `latency_ms` integer;