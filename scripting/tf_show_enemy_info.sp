#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools_functions>

#include <tf2_stocks>

#pragma newdecls required

#include <stocksoup/log_server>
#include <stocksoup/tf/annotations>

#define ANNOTATION_OFFS 0x66EFAA00

#define PLUGIN_VERSION "0.0.0"
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
int g_iCurrentTargetHealth[MAXPLAYERS + 1];
int g_bAnnotationVisible[MAXPLAYERS + 1];
int g_nTicksNotAimed[MAXPLAYERS + 1];

Handle g_OnAimTarget;

public void OnPluginStart() {
	g_OnAimTarget = CreateGlobalForward("TFEnemyInfo_OnAimTarget", ET_Hook, Param_Cell,
			Param_Cell, Param_CellByRef);
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
	g_bAnnotationVisible[client] = false;
	g_iCurrentTarget[client] = INVALID_ENT_REFERENCE;
	g_nTicksNotAimed[client] = 0;
}

public void OnAnnotationPost(int client) {
	if (IsFakeClient(client)) {
		return;
	}
	
	if (GetGameTickCount() % 2 != 0) {
		return;
	}
	
	int iTarget = GetClientAimTarget(client);
	if (iTarget == -1 || !ShouldAnnotateTarget(client, iTarget)) {
		if (g_bAnnotationVisible[client] && g_nTicksNotAimed[client]++ > 10) {
			PrintCenterText(client, "");
			ClearAnnotationData(client);
		}
		
		int lastTarget = EntRefToEntIndex(g_iCurrentTarget[client]);
		if (IsValidEntity(lastTarget) && !IsPlayerAlive(lastTarget)) {
			PrintCenterText(client, "%N: DEAD", lastTarget);
		}
		return;
	}
	
	int targetRef = EntIndexToEntRef(iTarget);
	int targetHealth = GetClientHealth(iTarget);
	
	if (targetRef == g_iCurrentTarget[client]
			&& targetHealth == g_iCurrentTargetHealth[client]) {
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
	
	g_iCurrentTarget[client] = EntIndexToEntRef(iTarget);
	
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
	
	/*TFAnnotationEvent annotation = new TFAnnotationEvent();
	if (annotation) {
		annotation.VisibilityBits = 1 << client;
		annotation.SetText(buffer);
		annotation.ID = 0x66EFAA00 + client;
		annotation.Lifetime = 999.0;
		annotation.FollowEntity = iTarget;
		
		annotation.Fire();
	}*/
	g_bAnnotationVisible[client] = true;
	g_iCurrentTargetHealth[client] = targetHealth;
}

bool ShouldAnnotateTarget(int client, int target) {
	return GetClientTeam(client) != GetClientTeam(target)
			&& !TF2_IsPlayerInCondition(client, TFCond_Cloaked);
}
