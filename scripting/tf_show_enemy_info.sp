#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools_functions>

#include <tf2_stocks>

#pragma newdecls required

#include <stocksoup/tf/annotations>

#define ANNOTATION_OFFS 0x66EFAA00

#define PLUGIN_VERSION "1.0.5"
public Plugin myinfo = {
	name = "[TF2] Show Enemy Info",
	author = "nosoop",
	description = "Displays enemy data.",
	version = PLUGIN_VERSION,
	url = "https://csrd.science/"
}

#define ENEMYINFO_HEALTH			(1 << 0)
#define ENEMYINFO_NAME				(1 << 1)
#define ENEMYINFO_UBERCHARGE		(1 << 2)

int g_iCurrentTarget[MAXPLAYERS + 1];
float g_flHoverExpiryTime[MAXPLAYERS + 1];
float g_flLastParityUpdate[MAXPLAYERS + 1];

Handle g_OnAimTarget;

ConVar g_OverlayDuration;

Handle g_HudSync;

public void OnPluginStart() {
	g_OnAimTarget = CreateGlobalForward("TFEnemyInfo_OnAimTarget", ET_Hook, Param_Cell,
			Param_Cell, Param_CellByRef);
	
	g_OverlayDuration = CreateConVar("sm_showenemyinfo_overlay_duration", "1.0",
			"Duration that the info will be displayed for, in seconds.", _,
			true, 0.0);
	
	g_HudSync = CreateHudSynchronizer();
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			HookAnnotationLogic(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	HookAnnotationLogic(client);
}

void HookAnnotationLogic(int client) {
	ClearAnnotationData(client);
}

public void OnGameFrame() {
	if (GetGameTickCount() % 2 != 0) {
		return;
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		
		if (IsFakeClient(i)) {
			// no point in sending HUD elements to bots. they don't have real eyes.
			continue;
		}
		
		OnAnnotationPost(i);
	}
}

void ClearAnnotationData(int client) {
	g_flHoverExpiryTime[client] = 0.0;
	g_flLastParityUpdate[client] = 0.0;
	g_iCurrentTarget[client] = INVALID_ENT_REFERENCE;
}

void OnAnnotationPost(int client) {
	int iTarget = UpdateCurrentHUDTarget(client);
	if (!iTarget && GetGameTime() > g_flHoverExpiryTime[client]) {
		if (!g_flHoverExpiryTime[client]) {
			ClearSyncHud(client, g_HudSync);
			ClearAnnotationData(client);
		}
		return;
	}
	
	if (!ShouldAnnotateTarget(client, iTarget)) {
		return;
	}
	
	int visflags;
	Call_StartForward(g_OnAimTarget);
	Call_PushCell(client);
	Call_PushCell(iTarget);
	Call_PushCellRef(visflags);
	Call_Finish();
	
	if (!visflags) {
		return;
	}
	
	// TODO store last state to only update when necessary
	if (!UpdateClientDisplayParity(client, iTarget)) {
		return;
	}
	g_flLastParityUpdate[client] = GetGameTime();
	
	int targetHealth = GetClientHealth(iTarget);
	
	char buffer[256];
	if (visflags & ENEMYINFO_NAME) {
		GetClientName(iTarget, buffer, sizeof(buffer));
	} else {
		strcopy(buffer, sizeof(buffer), "????");
	}
	
	if (visflags & ENEMYINFO_HEALTH) {
		char nameBuffer[64];
		strcopy(nameBuffer, sizeof(nameBuffer), buffer);
		Format(buffer, sizeof(buffer), "%s: %d", buffer, IsPlayerAlive(iTarget)? targetHealth : 0);
	}
	
	if (visflags & ENEMYINFO_UBERCHARGE) {
		int hSecondary = GetPlayerWeaponSlot(iTarget, 1);
		if (IsValidEntity(hSecondary) && HasEntProp(hSecondary, Prop_Send, "m_flChargeLevel")) {
			float flChargeLevel = GetEntPropFloat(hSecondary, Prop_Send,
					"m_flChargeLevel");
			
			char chargeBuffer[64];
			Format(chargeBuffer, sizeof(chargeBuffer), " (ubercharge: %d%%)",
					RoundToFloor(flChargeLevel * 100.0));
			StrCat(buffer, sizeof(buffer), chargeBuffer);
		}
	}
	
	int color;
	switch (TF2_GetClientTeam(iTarget)) {
		case TFTeam_Red: {
			color = 0xFF3E3E;
		}
		case TFTeam_Blue: {
			color = 0x9ACDFF;
		}
	}
	
	SetHudTextParams(-1.0, 0.35, 1.0, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF,
			255);
	ShowSyncHudText(client, g_HudSync, "%s", buffer);
}

/**
 * @return true if the given target should have their information rendered.
 */
bool ShouldAnnotateTarget(int client, int target) {
	return GetClientTeam(client) != GetClientTeam(target)
			&& !TF2_IsPlayerInCondition(client, TFCond_Cloaked);
}

/**
 * Updates parity data and checks if the new values are different.
 * 
 * @return true if the data has been updated and the info indicator needs to be redrawn.
 */
bool UpdateClientDisplayParity(int client, int target) {
	int pflLastDamageTime = GetEntSendPropOffs(target, "m_flMvMLastDamageTime", true) - 0x04;
	float flLastDamageTime = GetEntDataFloat(target, pflLastDamageTime);
	
	if (flLastDamageTime > g_flLastParityUpdate[client]) {
		return true;
	}
	
	if (GetGameTime() - g_flLastParityUpdate[client] > 0.5) {
		return true;
	}
	return false;
}

int UpdateCurrentHUDTarget(int client) {
	int iTarget = GetClientHUDAimTarget(client);
	if (iTarget != -1) {
		if (GetClientSerial(iTarget) != g_iCurrentTarget[client]) {
			// target changed; force parity update
			g_flLastParityUpdate[client] = 0.0;
		}
		
		// found target, update overlay expiry
		g_iCurrentTarget[client] = GetClientSerial(iTarget);
		g_flHoverExpiryTime[client] = GetGameTime() + g_OverlayDuration.FloatValue;
		return iTarget;
	}
	
	if (g_flHoverExpiryTime[client] > GetGameTime()) {
		return GetClientFromSerial(g_iCurrentTarget[client]);
	}
	return 0;
}

/**
 * Returns the index of the client being aimed at, or -1 if no client is available.
 */
int GetClientHUDAimTarget(int client) {
	// we should use TR_EnumerateEntities now...
	float vecEyeOrigin[3], vecEyeAngles[3];
	GetClientEyePosition(client, vecEyeOrigin);
	GetClientEyeAngles(client, vecEyeAngles);
	
	Handle trace = TR_TraceRayFilterEx(vecEyeOrigin, vecEyeAngles, MASK_SHOT_HULL,
			RayType_Infinite, FilterAimEntities, client);
	if (!TR_DidHit(trace)) {
		delete trace;
		return -1;
	}
	
	int entity = TR_GetEntityIndex(trace);
	delete trace;
	return (0 < entity <= MaxClients)? entity : -1;
}

bool FilterAimEntities(int entity, int mask, int client) {
	return (entity != client && 0 < entity && entity <= MaxClients);
}
