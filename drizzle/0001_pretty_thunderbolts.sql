CREATE TABLE `match_replays` (
	`id` int AUTO_INCREMENT NOT NULL,
	`userId` int NOT NULL,
	`fileName` varchar(255) NOT NULL,
	`fileKey` varchar(512) NOT NULL,
	`fileUrl` text NOT NULL,
	`fileSizeBytes` bigint NOT NULL DEFAULT 0,
	`mimeType` varchar(128) NOT NULL DEFAULT 'application/json',
	`durationSeconds` float NOT NULL DEFAULT 0,
	`result` enum('win','loss','draw') NOT NULL,
	`playerKiRemaining` float NOT NULL DEFAULT 0,
	`enemyKiRemaining` float NOT NULL DEFAULT 0,
	`createdAt` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `match_replays_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `player_configs` (
	`id` int AUTO_INCREMENT NOT NULL,
	`userId` int NOT NULL,
	`fileKey` varchar(512),
	`fileUrl` text,
	`gestureThreshold` float NOT NULL DEFAULT 0.15,
	`slowMotionFactor` float NOT NULL DEFAULT 0.3,
	`kiRegenRate` float NOT NULL DEFAULT 5,
	`hapticFeedback` enum('off','light','strong') NOT NULL DEFAULT 'light',
	`updatedAt` timestamp NOT NULL DEFAULT (now()) ON UPDATE CURRENT_TIMESTAMP,
	CONSTRAINT `player_configs_id` PRIMARY KEY(`id`),
	CONSTRAINT `player_configs_userId_unique` UNIQUE(`userId`)
);
--> statement-breakpoint
CREATE TABLE `player_stats` (
	`id` int AUTO_INCREMENT NOT NULL,
	`userId` int NOT NULL,
	`totalMatches` int NOT NULL DEFAULT 0,
	`wins` int NOT NULL DEFAULT 0,
	`losses` int NOT NULL DEFAULT 0,
	`totalKiUsed` float NOT NULL DEFAULT 0,
	`totalDamageDealt` float NOT NULL DEFAULT 0,
	`totalDamageBlocked` float NOT NULL DEFAULT 0,
	`createdAt` timestamp NOT NULL DEFAULT (now()),
	`updatedAt` timestamp NOT NULL DEFAULT (now()) ON UPDATE CURRENT_TIMESTAMP,
	CONSTRAINT `player_stats_id` PRIMARY KEY(`id`)
);
