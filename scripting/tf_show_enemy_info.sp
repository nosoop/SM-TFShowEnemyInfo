#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools_functions>

#include <tf2_stocks>

#pragma newdecls required

#include <stocksoup/tf/annotations>

#define ANNOTATION_OFFS 0x66EFAA00

#define PLUGIN_VERSION "1.0.1"
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
int g_bAnnotationVisible[MAXPLAYERS + 1];

float g_flHoverExpiryTime[MAXPLAYERS + 1];

Handle g_OnAimTarget;

ConVar g_OverlayDuration;

public void OnPluginStart() {
	g_OnAimTarget = CreateGlobalForward("TFEnemyInfo_OnAimTarget", ET_Hook, Param_Cell,
			Param_Cell, Param_CellByRef);
	
	g_OverlayDuration = CreateConVar("sm_showenemyinfo_overlay_duration", "1.0",
			"Duration that the info will be displayed for, in seconds.", _,
			true, 0.0);
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
	SDKHook(client, SDKHook_PostThinkPost, OnAnnotationPost);
	
	ClearAnnotationData(client);
}

void ClearAnnotationData(int client) {
	g_flHoverExpiryTime[client] = 0.0;
	g_bAnnotationVisible[client] = false;
	g_iCurrentTarget[client] = INVALID_ENT_REFERENCE;
}

public void OnAnnotationPost(int client) {
	if (IsFakeClient(client)) {
		return;
	}
	
	if (GetGameTickCount() % 2 != 0) {
		return;
	}
	
	int iTarget = GetClientAimTarget(client);
	if (iTarget != -1) {
		g_iCurrentTarget[client] = GetClientSerial(iTarget);
		g_flHoverExpiryTime[client] = GetGameTime() + g_OverlayDuration.FloatValue;
	} else if (GetGameTime() > g_flHoverExpiryTime[client]) {
		PrintCenterText(client, "");
		ClearAnnotationData(client);
		return;
	}
	
	iTarget = GetClientFromSerial(g_iCurrentTarget[client]);
	if (!IsValidEntity(iTarget)) {
		PrintCenterText(client, "");
		ClearAnnotationData(client);
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
		Format(buffer, sizeof(buffer), "%s: %d", buffer, targetHealth);
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
	
	PrintCenterText(client, "%s", buffer);
	
	g_bAnnotationVisible[client] = true;
}

bool ShouldAnnotateTarget(int client, int target) {
	return GetClientTeam(client) != GetClientTeam(target)
			&& !TF2_IsPlayerInCondition(client, TFCond_Cloaked);
}

/**
 * Updates parity data and checks if the new values are different.
 * 
 * @return True if the data has been updated and the info indicator needs to be redrawn.
 */
bool UpdateClientDisplayParity(int client, int target) {
	// we'll just return true for now, if TF2 annotations work out we'll handle it accordingly
	#pragma unused client, target
	return true;
}
