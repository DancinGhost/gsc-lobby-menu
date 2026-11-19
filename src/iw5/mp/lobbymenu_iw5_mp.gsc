/*
 * IW5 Multiplayer - custom lobby menu entry file.
 *
 * Game-specific config and hooks only. The engine lives in
 * src/common/menu_core.gsc; scripts/build.sh joins both into
 * build/iw5/mp/lobbymenu_iw5_mp.gsc.
 *
 * Controls:
 *   Open         : ADS + Melee
 *   Up / Down    : +actionslot 1 / 2 (D-Pad Up / Down)
 *   Adjust value : +actionslot 3 / 4 (D-Pad Left / Right)
 *   Select       : Use
 *   Back / Close : Melee
 */

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

init()
{
    level.menuTitle = "^5Custom Lobby ^7Menu (IW5)";
    level.menuDirectionIsPolled = false;
    level.menuGravityDvar = "g_gravity";

    mmCoreInit();
}

// IW5 has no actionSlot*ButtonPressed(), so the D-pad is bound to notifies.
// Bind once per connection: registering again would send each notify twice.
game_onPlayerConnect()
{
    self notifyOnPlayerCommand("mm_dir_up", "+actionslot 1");
    self notifyOnPlayerCommand("mm_dir_down", "+actionslot 2");
    self notifyOnPlayerCommand("mm_dir_left", "+actionslot 3");
    self notifyOnPlayerCommand("mm_dir_right", "+actionslot 4");
    self.menu["dirPending"] = undefined;
    self thread iw5WatchDirection("mm_dir_up", "up");
    self thread iw5WatchDirection("mm_dir_down", "down");
    self thread iw5WatchDirection("mm_dir_left", "left");
    self thread iw5WatchDirection("mm_dir_right", "right");
}

// Raw waittill per direction instead of waittill_any_return(), because IW5's
// stock waittill_any_return() runs self endon("death") and would die on first death.
iw5WatchDirection(notifyName, dir)
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        self waittill(notifyName);
        if (self.menu["isOpen"])
            self.menu["dirPending"] = dir;
    }
}

game_readDirection()
{
    dir = self.menu["dirPending"];
    self.menu["dirPending"] = undefined;
    return dir;
}

// Stock IW5 resets cg_thirdPerson on spawn; the core re-applies this after respawn.
game_setThirdPerson(enabled)
{
    if (enabled)
        self setClientDvar("cg_thirdPerson", "1");
    else
        self setClientDvar("cg_thirdPerson", "0");
}

game_addWeaponOptions(menuId)
{
    self mmAddOption(menuId, "Give MSR", ::mmGiveWeapon, "iw5_msr_mp");
    self mmAddOption(menuId, "Give L118A", ::mmGiveWeapon, "iw5_l96a1_mp");
    self mmAddOption(menuId, "Give ACR 6.8", ::mmGiveWeapon, "iw5_acr_mp");
    self mmAddOption(menuId, "Give MP7", ::mmGiveWeapon, "iw5_mp7_mp");
    self mmAddOption(menuId, "Give Desert Eagle", ::mmGiveWeapon, "iw5_deserteagle_mp");
}

game_spawnBot()
{
    bot = addTestClient();
    if (!isDefined(bot))
        return false;

    bot.pers["isBot"] = true;
    bot thread iw5BotJoin();
    return true;
}

// Test clients don't pick a team or class on their own; auto-assign a team,
// then select a default class.
iw5BotJoin()
{
    self endon("disconnect");

    while (!isDefined(self.pers["team"]))
        wait 0.05;

    self notify("menuresponse", game["menu_team"], "autoassign");
    wait 0.5;

    classes = getArrayKeys(level.classmap);
    for (i = 0; i < classes.size; i++)
    {
        if (!isSubStr(classes[i], "custom"))
        {
            self notify("menuresponse", "changeclass", classes[i]);
            return;
        }
    }
}
