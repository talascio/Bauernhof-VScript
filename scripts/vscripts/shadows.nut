//rewrite by Braindawg
//original lua script by royal/washy/sntr

//allows referencing functions directly, better performance (FindByClassname instead of Entities.FindByClassname etc)
foreach (k, v in ::NetProps.getclass())
    if (k != "IsValid")
        ROOT[k] <- ::NetProps[k].bindenv(::NetProps);

foreach (k, v in ::Entities.getclass())
    if (k != "IsValid")
        ROOT[k] <- ::Entities[k].bindenv(::Entities);

local waveActive = false

local DoublePointsText = ""
local FireSaleText = ""
local InstakillText = ""

local DoublePointsDuration = 0
local FireSaleDuration = 0
local InstakillDuration = 0

local DumpsterCost = 950

//hack to display a model only to one player, used for glow effect on dumpsters
function ShowModelToPlayer(player, model = ["models/player/heavy.mdl", 0], pos = Vector(), ang = QAngle(), duration = 9999.0)
{
    PrecacheModel(model[0])
    local proxy_entity = CreateByClassname("obj_teleporter") // not using SpawnEntityFromTable as that creates spawning noises
    proxy_entity.SetAbsOrigin(pos)
    proxy_entity.SetAbsAngles(ang)
    DispatchSpawn(proxy_entity)

    proxy_entity.SetModel(model[0])
    proxy_entity.SetSkin(model[1])
    proxy_entity.AddEFlags(EFL_NO_THINK_FUNCTION) // EFL_NO_THINK_FUNCTION prevents the entity from disappearing
    proxy_entity.SetSolid(SOLID_NONE)

    SetPropBool(proxy_entity, "m_bPlacing", true)
    SetPropInt(proxy_entity, "m_fObjectFlags", 2) // sets "attachment" flag, prevents entity being snapped to player feet

    // m_hBuilder is the player who the entity will be networked to only
    SetPropEntity(proxy_entity, "m_hBuilder", player)
    EntFireByHandle(proxy_entity, "Kill", "", duration, player, player)
    return proxy_entity
}

//GAME EVENTS (replaces lua callbacks)
BHof <- {
    function OnGameEvent_player_spawn(params)
    {
		local player = GetPlayerFromUserID(params.userid)
        if (IsPlayerABot(player)) return
		player.ValidateScriptScope()
		local scope = player.GetScriptScope()
	
		//stuff we want to put in player scope
		local items = {
            deathCounts = 0,
            cooldownTime = 0
		}
		foreach (k,v in items) if (!(k in scope)) scope[k] <- v
    }
    function OnGameEvent_player_death(params)
    {
        local player = GetPlayerFromUserID(params.userid)
        
        player.GetScriptScope().deathCounts++
        
        AddThinkToEnt(player, null)
        
        if (GetPropString(player, "m_szNetname") == "Tank")
            EntFireByHandle(GetPlayerFromUserID(params.attacker), "SpeakResponseConcept", "TLK_MVM_TANK_DEAD", -1, null, null)

    }
    function OnGameEvent_mvm_begin_wave(params)
    {
        waveActive = true
    }
    function OnGameEvent_mvm_reset_stats(params)
    {

        waveActive = false
        DoublePointsText = ""
        FireSaleText = ""
        InstakillText = ""
        DoublePointsDuration = 0
        FireSaleDuration = 0
        InstakillDuration = 0
        DumpsterCost = 950
    }

    //cashforhits in lua
    function OnScriptHook_OnTakeDamage(params)
    {
        if (params.damage <= 0 || !IsPlayer(params.const_entity)) return
        local victim = params.const_entity, attacker = params.inflictor, type = params.damage_type
        local mult = (DoublePointsDuration > 0) ? 2 : 1

        if (type & 8) //DMG_BURN
            return true

        if (type & 1048576) //DMG_ACID (crits)
           damage = params.damage * 3
        
        if (InstakillDuration > 0 && GetPropString(victim, "m_szNetname") == "Zombie" && attacker.InCond(56))
            damage = victim.GetMaxHealth()

        //money
        if (type & 2 || type & 64 || type & 33554432) //in order: DMG_BULLET, DMG_BLAST, DMG_AIRBOAT (headshot)
            attacker.AddCurrency(65)
        else if (type & 134217728) //DMG_BLAST_SURFACE (melee)
            attacker.AddCurrency(140)
        else if (type & (135266304)) //melee | crit
            attacker.AddCurrency(90)
        else //misc
            attacker.AddCurrency(65)
    }
}
__CollectGameEventCallbacks(BHof)

function rejuvenatorHit(damage, activator, caller)
{
    local damageThreshold = 1

    if (damage < damageThreshold) return

    caller.AddCondEx(43, 5.0, activator)

    EntFireByHandle(caller, "RunScriptCode", "self.TakeDamage(9999, 0, !activator)", 5.0, activator, activator);
}

function chargerLogic()
{
    local charger = self
    if (GetPropInt(charger, "m_nButtons") & 2048 && GetPropFloat(charger, "m_flChargeMeter") > 94) //2048 = IN_ATTACK2
    {
        charger.ResetSequence("Charger_Charge")
    }
}

function comebackBonus(player, amount)
{
    ClientPrint(player, 3, format("You have received a %d comeback bonus.", amount))
    ClientPrint(player, 4, format("You have received a %d comeback bonus.", amount))
    player.AddCurrency(amount)
}

function revivelogic(player)
{
    if (player == null || GetPropInt(player, "m_lifeState") != 0) return
    function reanimate()
    {
        for (local reanimator; reanimator = FindByClassnameWithin(reanimator, "env_revive_marker", player.GetOrigin(), 150);)
        {
            local deadguy = reanimator.GetOwner()
            if (GetPropInt(deadguy, "m_lifeState") == 0) return //deadguy not dead
            deadguy.ForceRespawn()
            EmitSoundOn("MVM.PlayerRevived", deadguy)
            EntFireByHandle(deadguy, "SpeakResponseConcept", "TLK_RESURRECTED", -1, null, null)
            deadguy.SetOrigin(player.GetOrigin())
            deadguy.AddCondEx(51, 2.0, null);
            local stun = SpawnEntityFromTable("trigger_stun", {
                targetname = "__revivestun",
                stun_type = 1,
                stun_duration = 0.2,
                move_speed_reduction = 1.0,
                StartDisabled = 0,
                spawnflags = 1,
                "OnStunPlayer#1": "!self,Kill,,-1,-1"
            });
            EntFireByHandle(stun, "EndTouch", "", -1, player, player)
            player.AddCurrency(50)
        }
    }
}

local hudtime = 2
local hudcooldown = 0

//this isn't an actual hook, just keeping the name from lua
function OnGameTick()
{

}

function PlayerThink()
{
    ButtonThink(self)
}

__worldspawn.ValidateScriptScope()
__worldspawn.OnGameTick <- OnGameTick
AddThinkToEnt(__worldspawn, "OnGameTick")

//button pressing stuff
//highlight nearby important items
function ButtonThink(player)
{
	local scope = player.GetScriptScope();
	for (local button; button = FindInSphere(button, player.GetOrigin(), 150); )
	{
		//hint when we get close
		local glow;
		if (hudcooldown < Time())
		{
			if (!scope.hinted) EmitSoundOnClient("Hud.Hint", player)
			ShowHudHint(player, "Press%use_action_slot_item%", 2)

			local parent = button.GetMoveParent()
			if (parent == null) parent = FindInSphere(null, player.GetOrigin(), 150) //button isn't parented, find nearest prop_dynamic and glow that

			glow = ShowModelToPlayer(player, [parent.GetModelName(), parent.GetSkin()], parent.GetOrigin(), parent.GetAbsAngles(), 3.0);
			SetPropInt(glow, "m_nRenderMode", 1)
			glow.SetModelScale(glow.GetModelScale() + 0.01, -1)
            SetPropInt(entity, "m_clrRender", 0)
			SetPropBool(glow, "m_bGlowEnabled", true)
			hudcooldown = Time() + hudtime
			scope.hinted = true
			continue
		}
		if (player.IsUsingActionSlot() && scope.cooldownTime < Time())
		// if (InButton(player, IN_RELOAD) && scope.cooldowntime < Time())
		{
            if (button.GetClassname() == "entity_revive_marker")
                revivelogic(player)

            else if (startswith(button.GetName(), "vm_"))
			    usePerkMachine(player)

            else if (startswith(button.GetName(), "dumpsterbutton") && player.GetCurrency() > DumpsterCost)
                OpenDumpsterBox(player, button.GetName().slice(button.GetName().len() - 1, button.GetName().len()).tointeger())

            else if (startswith(button.GetName(), "tradeweapon"))
                DumpsterBoxTakeWeapon(player, button.GetName().slice(button.GetName().len() - 1, button.GetName().len()).tointeger())

			scope.hinted = false

			if (glow != null) glow.Kill()

			//manually set it here just in case
			SetPropBool(player, "m_bUsingActionSlot", false)

			//set cooldown time
			scope.cooldownTime = Time() + 1
		}
	}
	return -1;
}