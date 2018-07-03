/**
 * Include description here.
 */

#if defined __tf_show_enemy_info_included
	#endinput
#endif

#define __tf_show_enemy_info_included

#define ENEMYINFO_HEALTH			(1 << 0)
#define ENEMYINFO_NAME				(1 << 1)
#define ENEMYINFO_UBERCHARGE		(1 << 2)

/**
 * Called when an update to a target is performed.
 * Flags can be temporarily modified here.
 */
forward Action TFEnemyInfo_OnAimTarget(int client, int target, int &flags);