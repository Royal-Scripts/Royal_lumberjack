CREATE TABLE IF NOT EXISTS `royal_lumberjack_trees` (
    `id` int(11) NOT NULL,
    `state` varchar(50) DEFAULT 'standing',
    `endTime` bigint(20) DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `royal_lumberjack_leaderboard` (
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) DEFAULT NULL,
    `wood_collected` int(11) DEFAULT 0,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
