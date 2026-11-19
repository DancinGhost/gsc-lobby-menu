/*
 * T6 Multiplayer - custom lobby menu entry file.
 *
 * Game-specific config and hooks only. The engine lives in
 * src/common/menu_core.gsc; scripts/build.sh joins both into
 * build/t6/mp/lobbymenu_t6_mp.gsc.
 *
 * Controls:
 *   Open         : ADS + Melee
 *   Up / Down    : D-Pad Up / Down   (Action Slot 1 / 2)
 *   Adjust value : D-Pad Left / Right (Action Slot 3 / 4)
 *   Select       : Use
 *   Back / Close : Melee
 */

#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

init()
{
    level.menuTitle = "^5Custom Lobby ^7Menu (T6)";
    level.menuDirectionIsPolled = true;
    level.menuGravityDvar = "bg_gravity"; // T6 has no g_gravity

    mmCoreInit();
}

game_onPlayerConnect()
{
}

game_readDirection()
{
    if (self actionSlotOneButtonPressed())
        return "up";
    if (self actionSlotTwoButtonPressed())
        return "down";
    if (self actionSlotThreeButtonPressed())
        return "left";
    if (self actionSlotFourButtonPressed())
        return "right";
    return undefined;
}

// cg_thirdPerson is cheat-protected on T6; the stock scripts use this instead.
game_setThirdPerson(enabled)
{
    if (enabled)
        self setClientThirdPerson(1);
    else
        self setClientThirdPerson(0);
}

game_addWeaponOptions(menuId)
{
    self mmAddOption(menuId, "Give DSR-50", ::mmGiveWeapon, "dsr50_mp");
    self mmAddOption(menuId, "Give Ballista", ::mmGiveWeapon, "ballista_mp");
    self mmAddOption(menuId, "Give MSMC", ::mmGiveWeapon, "msmc_mp");
    self mmAddOption(menuId, "Give AN-94", ::mmGiveWeapon, "an94_mp");
    self mmAddOption(menuId, "Give SCAR-H", ::mmGiveWeapon, "scar_mp");
}

// The stock bot helper also picks a team and class and runs the bot AI.
game_spawnBot()
{
    return maps\mp\bots\_bot::spawn_bot("autoassign");
}
