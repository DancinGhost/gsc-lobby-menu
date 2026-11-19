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

game_setGodMode(enabled)
{
    if (enabled)
        self enableInvulnerability();
    else
        self disableInvulnerability();
}

// cg_thirdPerson is cheat-protected on T6; the stock scripts use this instead.
game_setThirdPerson(enabled)
{
    if (enabled)
        self setClientThirdPerson(1);
    else
        self setClientThirdPerson(0);
}

// T6 MP has no jump_height dvar, so boost upward velocity on takeoff and
// raise the fall damage thresholds while Super Jump is active.
game_setSuperJump(enabled)
{
    level notify("mm_stop_t6_superjump");

    if (enabled)
    {
        mmOverrideDvar("bg_fallDamageMinHeight", "9998");
        mmOverrideDvar("bg_fallDamageMaxHeight", "9999");
        level thread t6SuperJumpLoop();
    }
    else
    {
        mmRestoreDvar("bg_fallDamageMinHeight");
        mmRestoreDvar("bg_fallDamageMaxHeight");
    }
}

t6SuperJumpLoop()
{
    level endon("game_ended");
    level endon("mm_stop_t6_superjump");

    for (;;)
    {
        players = level.players;
        for (i = 0; i < players.size; i++)
        {
            p = players[i];
            if (!isDefined(p) || !isAlive(p))
                continue;
            if (isDefined(p.menu) && (p.menu["toggles"]["ufo"] || p.menu["frozen"]))
                continue;

            if (!isDefined(p.mmCanSuperJump))
                p.mmCanSuperJump = true;
            if (!isDefined(p.mmJumpCooldown))
                p.mmJumpCooldown = 0;

            if (p.mmJumpCooldown > 0)
                p.mmJumpCooldown--;

            onGround = p isOnGround();
            pressingJump = p jumpButtonPressed();

            if (onGround && p.mmJumpCooldown == 0 && !pressingJump)
                p.mmCanSuperJump = true;

            if (p.mmCanSuperJump && pressingJump)
            {
                vel = p getVelocity();
                p setVelocity((vel[0], vel[1], 560));
                p.mmCanSuperJump = false;
                p.mmJumpCooldown = 5;
            }
        }
        wait 0.05;
    }
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

// T6: setWaypoint(constantSize, offscreenMaterial). The offscreen material
// keeps a marker at the screen edge when the enemy is out of view.
game_setupEspWaypoint()
{
    self setWaypoint(true, "white");
}
