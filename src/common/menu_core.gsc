/*
 * Shared custom lobby menu engine (T6 MP / IW5 MP).
 *
 * This file is never loaded on its own. scripts/build.sh (or build.ps1) appends
 * it to each game's entry file (src/<game>/mp/lobbymenu_<game>_mp.gsc), which
 * supplies the #include lines, init(), and the game hooks below.
 *
 * Game hooks every entry file must define:
 *   game_onPlayerConnect()          per-player setup at connect (command binds, ...)
 *   game_readDirection()            "up" / "down" / "left" / "right" or undefined
 *   game_setGodMode(enabled)        game-specific invulnerability toggle on self
 *   game_setThirdPerson(enabled)
 *   game_setSuperJump(enabled)      game-specific lobby super jump toggle
 *   game_addWeaponOptions(menuId)   adds weapon entries via mmAddOption()
 *   game_getWeaponsList()           returns array of all weapons held by self
 *   game_spawnBot()                 returns true if a bot was added
 *   game_setupEspWaypoint()         turns self (a client hud elem) into a world
 *                                   waypoint (setWaypoint args differ per game)
 *
 * Level config the entry file sets in init() before calling mmCoreInit():
 *   level.menuTitle
 *   level.menuDirectionIsPolled     true if game_readDirection() reports held
 *                                   buttons (polled), false if it reports
 *                                   one-shot press events
 *   level.menuGravityDvar           world gravity dvar for this game
 *   level.menuExtraTrackedDvars     (optional) array of extra game-specific dvars
 *                                   to back up and restore (e.g. jump_height)
 *
 * Access levels: 0 = None, 1 = VIP, 2 = Admin, 3 = Host / Owner.
 * Persistent access: the "mm_admins" dvar holds "guid:level,guid:level". Grants
 * made in-game are written back to it, and server owners can preset it in
 * their server config (level 3 there gives full access on dedicated servers).
 */

/* =========================
 *  INIT
 * ========================= */

mmCoreInit()
{
    level.menuMaxVisible = 8;

    level.menuLayout = spawnStruct();
    level.menuLayout.x = 220;
    level.menuLayout.y = -90;
    level.menuLayout.width = 210;
    level.menuLayout.rowHeight = 20;
    level.menuLayout.headerHeight = 28;
    level.menuLayout.bgColor = (0.05, 0.06, 0.09);
    level.menuLayout.headerColor = (0.12, 0.48, 0.85);
    level.menuLayout.scrollerColor = (0.18, 0.58, 0.96);
    level.menuLayout.footerColor = (0.75, 0.8, 0.88);
    level.menuFooterText = "^7[D-Pad] Move / Adjust | [Use] Select | [Melee] Back";

    // Every dvar the menu can change. Originals are backed up in mm_orig_* dvars
    // and restored here (covers map changes and fast restarts) and at game end.
    level.menuTrackedDvars = [];
    level.menuTrackedDvars[0] = "bg_fallDamageMinHeight";
    level.menuTrackedDvars[1] = "bg_fallDamageMaxHeight";
    level.menuTrackedDvars[2] = level.menuGravityDvar;
    if (isDefined(level.menuExtraTrackedDvars))
    {
        for (i = 0; i < level.menuExtraTrackedDvars.size; i++)
            level.menuTrackedDvars[level.menuTrackedDvars.size] = level.menuExtraTrackedDvars[i];
    }
    mmRestoreAllDvars();

    if (!isDefined(level.menuEspMaxMarkers))
        level.menuEspMaxMarkers = 12;

    level.menuServerToggles = [];
    level.menuServerToggles["superjump"] = false;

    level.menuGravityDefault = getDvarInt(level.menuGravityDvar);
    if (level.menuGravityDefault <= 0)
        level.menuGravityDefault = 800;

    level.menuServerValues = [];
    level.menuServerValues["gravity"] = level.menuGravityDefault;

    // Aimbot target bones, cycled by "Aim Target" in Combat Options.
    level.menuAimBones = [];
    level.menuAimBones[0] = "j_head";
    level.menuAimBones[1] = "j_neck";
    level.menuAimBones[2] = "j_spineupper";
    level.menuAimBoneLabels = [];
    level.menuAimBoneLabels[0] = "Head";
    level.menuAimBoneLabels[1] = "Neck";
    level.menuAimBoneLabels[2] = "Chest";

    mmRegisterToggles();
    mmInitStringTracking();

    level thread mmOnPlayerConnect();
    level thread mmWatchGameEnd();
}

mmRegisterToggles()
{
    level.menuToggleDefs = [];
    mmRegisterToggle("god", "God Mode", ::mmGodOn, ::mmGodOff, true);
    mmRegisterToggle("ammo", "Infinite Ammo", ::mmAmmoOn, ::mmAmmoOff, false);
    mmRegisterToggle("ufo", "UFO / Noclip", ::mmUfoOn, ::mmUfoOff, false);
    mmRegisterToggle("speed", "Speed Boost", ::mmSpeedOn, ::mmSpeedOff, true);
    mmRegisterToggle("thirdperson", "Third Person", ::mmThirdPersonOn, ::mmThirdPersonOff, true);

    // Combat. The aimbot and ESP threads survive death, so no reapply is needed.
    mmRegisterToggle("aimbot", "Aimbot", ::mmAimbotOn, ::mmAimbotOff, false);
    mmRegisterToggle("aim_noads", "Aim Without ADS", ::mmNoop, ::mmNoop, false);
    mmRegisterToggle("aim_walls", "Aim Through Walls", ::mmNoop, ::mmNoop, false);
    mmRegisterToggle("esp", "Wallhack / ESP", ::mmEspOn, ::mmEspOff, false);
}

// For toggles that are only settings read by another feature's loop.
mmNoop()
{
}

// reapplyOnSpawn: call onFunc again after respawn (for effects the game resets on spawn).
mmRegisterToggle(key, label, onFunc, offFunc, reapplyOnSpawn)
{
    def = spawnStruct();
    def.key = key;
    def.label = label;
    def.onFunc = onFunc;
    def.offFunc = offFunc;
    def.reapplyOnSpawn = reapplyOnSpawn;
    level.menuToggleDefs[key] = def;
}

/* =========================
 *  PLAYER LIFECYCLE
 * ========================= */

mmOnPlayerConnect()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("connected", player);
        player mmInitPlayer();
        player game_onPlayerConnect();
        player thread mmOnPlayerSpawned();
        player thread mmWatchDeath();
        player thread mmInputLoop();
        player thread mmOnPlayerDisconnect();
    }
}

mmInitPlayer()
{
    self.menu = [];
    self.menu["isOpen"] = false;
    self.menu["current"] = "main";
    self.menu["cursor"] = [];
    self.menu["scroll"] = [];
    self.menu["ui"] = [];
    self.menu["held"] = [];
    self.menu["held"]["use"] = false;
    self.menu["held"]["melee"] = false;
    self.menu["dirLast"] = "none";
    self.menu["dirTicks"] = 0;
    self.menu["weaponBlocks"] = [];
    self.menu["weaponsBlocked"] = false;
    self.menu["frozen"] = false;
    self.menu["welcomed"] = false;

    self.menu["toggles"] = [];
    keys = getArrayKeys(level.menuToggleDefs);
    for (i = 0; i < keys.size; i++)
        self.menu["toggles"][keys[i]] = false;

    self.menu["values"] = [];
    self.menu["values"]["speed"] = 1.75;
    self.menu["values"]["ufospeed"] = 45;
    self.menu["values"]["aimfov"] = 90;
    self.menu["values"]["aimbone"] = 0;

    // ESP markers keyed by the enemy's entity number (as a string).
    self.menu["esp"] = [];

    guid = self getGuid();
    if (isDefined(guid))
        self.menu["guid"] = "" + guid;
    else
        self.menu["guid"] = "";

    if (self isHost())
        self.menu["access"] = 3;
    else
        self.menu["access"] = self mmLoadSavedAccess();
}

mmOnPlayerSpawned()
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        self waittill("spawned_player");

        if (!self.menu["welcomed"] && self.menu["access"] > 0)
        {
            self.menu["welcomed"] = true;
            self mmPrintWelcome();
        }

        // Wait until stock spawned_player listeners finish so health/speed/view
        // settings aren't immediately overwritten on the spawn frame.
        waittillframeend;
        if (!isAlive(self))
            continue;

        self mmReapplyToggles();

        if (self.menu["frozen"])
            self freezeControls(true);
    }
}

mmWatchDeath()
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        self waittill("death");

        self.menu["pendingWeapon"] = undefined;

        if (self.menu["isOpen"])
            self mmCloseMenu();

        if (self.menu["toggles"]["ufo"])
            self mmSetToggle("ufo", false, true);
    }
}

mmOnPlayerDisconnect()
{
    self waittill("disconnect");

    if (isDefined(self.ufoOrigin))
        self.ufoOrigin delete();

    self mmDestroyHud();
    self mmEspClear();
}

mmWatchGameEnd()
{
    level waittill("game_ended");

    players = level.players;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isDefined(p) || !isDefined(p.menu))
            continue;

        if (p.menu["isOpen"])
            p mmCloseMenu();

        if (p.menu["toggles"]["ufo"])
            p mmSetToggle("ufo", false, true);

        // The ESP loop ends with the game; don't leave frozen markers on screen.
        p mmEspClear();
    }

    if (level.menuServerToggles["superjump"])
    {
        level.menuServerToggles["superjump"] = false;
        game_setSuperJump(false);
    }

    mmRestoreAllDvars();
}

mmPrintWelcome()
{
    self iprintln("^5[LobbyMenu] ^7Access: ^2" + mmAccessLabel(self.menu["access"]) + "^7. Press ^3ADS + Melee ^7to open the menu.");
}

/* =========================
 *  INPUT
 * ========================= */

mmInputLoop()
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        wait 0.05;

        ads = self adsButtonPressed();
        meleePressed = self mmButtonEdge("melee", self meleeButtonPressed());
        usePressed = self mmButtonEdge("use", self useButtonPressed());
        dir = self mmPollDirection();

        if (!self.menu["isOpen"])
        {
            if (ads && meleePressed && self.menu["access"] > 0 && isAlive(self) && !self.menu["frozen"] && (!isDefined(self.sessionstate) || self.sessionstate == "playing"))
                self mmOpenMenu();
            continue;
        }

        if (!isAlive(self) || self.menu["frozen"] || self.menu["access"] <= 0 || (isDefined(self.sessionstate) && self.sessionstate != "playing"))
        {
            self mmCloseMenu();
            continue;
        }

        if (isDefined(dir))
        {
            if (dir == "up")
                self mmMoveCursor(-1);
            else if (dir == "down")
                self mmMoveCursor(1);
            else if (dir == "left")
                self mmAdjustValue(-1);
            else if (dir == "right")
                self mmAdjustValue(1);
        }
        else if (usePressed)
        {
            self mmSelectCurrentOption();
        }
        else if (meleePressed)
        {
            self mmGoBack();
        }
    }
}

// True only on the frame a button goes from released to pressed, so holding
// Melee after opening the menu does not immediately close it again.
mmButtonEdge(name, pressed)
{
    wasHeld = self.menu["held"][name];
    self.menu["held"][name] = pressed;
    return (pressed && !wasHeld);
}

// Polled games: fire on press, then auto-repeat while held (after ~0.3s, every 0.1s).
// Event games: game_readDirection() already returns one-shot presses.
mmPollDirection()
{
    dir = self game_readDirection();

    if (!level.menuDirectionIsPolled)
        return dir;

    if (!isDefined(dir))
    {
        self.menu["dirLast"] = "none";
        return undefined;
    }

    if (dir != self.menu["dirLast"])
    {
        self.menu["dirLast"] = dir;
        self.menu["dirTicks"] = 0;
        return dir;
    }

    self.menu["dirTicks"] = self.menu["dirTicks"] + 1;
    if (self.menu["dirTicks"] >= 6 && (self.menu["dirTicks"] % 2) == 0)
        return dir;

    return undefined;
}

// Weapons and offhands stay disabled while any reason ("menu", "ufo") is active,
// so menu buttons don't knife / reload / throw and UFO controls don't fire.
mmBlockWeapons(reason, enabled)
{
    if (enabled)
        self.menu["weaponBlocks"][reason] = true;
    else
        self.menu["weaponBlocks"][reason] = undefined;

    blocked = (getArrayKeys(self.menu["weaponBlocks"]).size > 0);
    if (blocked == self.menu["weaponsBlocked"])
        return;

    self.menu["weaponsBlocked"] = blocked;
    if (blocked)
    {
        self disableWeapons();
        self disableOffhandWeapons();
    }
    else
    {
        self enableWeapons();
        self enableOffhandWeapons();
        if (isDefined(self.menu["pendingWeapon"]))
        {
            weapon = self.menu["pendingWeapon"];
            self.menu["pendingWeapon"] = undefined;
            if (self hasWeapon(weapon))
                self switchToWeapon(weapon);
        }
    }
}

/* =========================
 *  NAVIGATION
 * ========================= */

mmOpenMenu()
{
    self.menu["isOpen"] = true;
    self mmBlockWeapons("menu", true);
    self mmCreateHud();
    self mmGoTo("main", true);
}

mmCloseMenu()
{
    self.menu["isOpen"] = false;
    self.menu["selectedPlayer"] = undefined;
    self mmDestroyHud();
    self mmBlockWeapons("menu", false);
}

// Rebuilds menus (so access level, player list and labels are current) and shows menuId.
mmGoTo(menuId, resetCursor)
{
    self mmBuildMenus();

    if (!isDefined(self.menu["menus"][menuId]))
    {
        if (menuId == "player_actions")
        {
            self iprintln("^1That player is no longer available.");
            menuId = "players";
        }

        if (!isDefined(self.menu["menus"][menuId]))
            menuId = "main";
    }

    self.menu["current"] = menuId;
    self.menu["navigated"] = true;

    if (resetCursor)
    {
        self.menu["cursor"][menuId] = 0;
        self.menu["scroll"][menuId] = 0;
    }

    self mmClampCursor();
    self mmRender();
}

mmRefresh()
{
    if (self.menu["isOpen"])
        self mmGoTo(self.menu["current"], false);
}

mmOpenSubmenu(menuId)
{
    self mmGoTo(menuId, true);
}

mmOpenPlayerActions(target)
{
    if (!isDefined(target) || !isDefined(target.menu))
    {
        self iprintln("^1Player is no longer connected.");
        return;
    }

    self.menu["selectedPlayer"] = target;
    self mmGoTo("player_actions", true);
}

// Going back keeps the parent's remembered cursor position.
mmGoBack()
{
    menu = self.menu["menus"][self.menu["current"]];

    if (!isDefined(menu) || menu.parent == "none")
    {
        self mmCloseMenu();
        return;
    }

    if (self.menu["current"] == "player_actions")
        self.menu["selectedPlayer"] = undefined;

    self mmGoTo(menu.parent, false);
}

mmMoveCursor(delta)
{
    id = self.menu["current"];
    menu = self.menu["menus"][id];
    if (!isDefined(menu) || menu.items.size == 0)
        return;

    curs = self.menu["cursor"][id] + delta;
    if (curs < 0)
        curs = menu.items.size - 1;
    else if (curs >= menu.items.size)
        curs = 0;

    self.menu["cursor"][id] = curs;
    self mmClampCursor();
    self mmRender();
}

// Keeps cursor and scroll valid after the item list changes size (e.g. players leave).
mmClampCursor()
{
    id = self.menu["current"];
    menu = self.menu["menus"][id];
    count = menu.items.size;
    maxVis = level.menuMaxVisible;

    curs = self.menu["cursor"][id];
    if (curs >= count)
        curs = count - 1;
    if (curs < 0)
        curs = 0;

    scroll = self.menu["scroll"][id];
    if (curs < scroll)
        scroll = curs;
    if (curs >= scroll + maxVis)
        scroll = curs - maxVis + 1;

    maxScroll = count - maxVis;
    if (maxScroll < 0)
        maxScroll = 0;
    if (scroll > maxScroll)
        scroll = maxScroll;
    if (scroll < 0)
        scroll = 0;

    self.menu["cursor"][id] = curs;
    self.menu["scroll"][id] = scroll;
}

mmCurrentOption()
{
    id = self.menu["current"];
    menu = self.menu["menus"][id];
    if (!isDefined(menu) || menu.items.size == 0)
        return undefined;

    return menu.items[self.menu["cursor"][id]];
}

mmSelectCurrentOption()
{
    opt = self mmCurrentOption();
    if (!isDefined(opt) || opt.type == "value" || !isDefined(opt.func))
        return;

    self.menu["navigated"] = false;

    if (isDefined(opt.arg2))
        self [[opt.func]](opt.arg1, opt.arg2);
    else if (isDefined(opt.arg1))
        self [[opt.func]](opt.arg1);
    else
        self [[opt.func]]();

    // Labels (toggle states, access tags, player list) may have changed.
    // Skip when the action already navigated via mmGoTo() to avoid double-rendering.
    if (!self.menu["navigated"])
        self mmRefresh();
}

mmAdjustValue(direction)
{
    opt = self mmCurrentOption();
    if (!isDefined(opt) || opt.type != "value")
        return;

    oldVal = self mmGetOptionValue(opt);
    value = oldVal + (opt.step * direction);
    if (opt.isServer && opt.valueKey == "gravity")
    {
        defVal = level.menuGravityDefault;
        if ((oldVal < defVal && value > defVal) || (oldVal > defVal && value < defVal))
            value = defVal;
    }
    if (value < opt.minVal)
        value = opt.minVal;
    if (value > opt.maxVal)
        value = opt.maxVal;

    if (opt.isServer)
        level.menuServerValues[opt.valueKey] = value;
    else
        self.menu["values"][opt.valueKey] = value;

    if (isDefined(opt.onChange))
        self [[opt.onChange]](value);

    self mmRender();
}

/* =========================
 *  MENU DEFINITION
 * ========================= */

mmBuildMenus()
{
    self.menu["menus"] = [];
    access = self.menu["access"];

    self mmAddMenu("main", level.menuTitle, "none");
    self mmAddOption("main", "Self Options", ::mmOpenSubmenu, "self");
    self mmAddOption("main", "Combat Options", ::mmOpenSubmenu, "combat");
    self mmAddOption("main", "Weapon Loadouts", ::mmOpenSubmenu, "weapons");
    if (access >= 2)
    {
        self mmAddOption("main", "Lobby Settings", ::mmOpenSubmenu, "lobby");
        self mmAddOption("main", "Player Manager", ::mmOpenSubmenu, "players");
    }

    self mmAddMenu("self", "Self Options", "main");
    self mmAddToggleOption("self", "god");
    self mmAddToggleOption("self", "ammo");
    self mmAddToggleOption("self", "ufo");
    self mmAddToggleOption("self", "speed");
    self mmAddToggleOption("self", "thirdperson");
    self mmAddValueOption("self", "Speed Multiplier", "speed", 1.0, 3.0, 0.25, false, ::mmApplySpeedValue);
    self mmAddValueOption("self", "UFO Speed", "ufospeed", 15, 150, 15, false, undefined);
    self mmAddOption("self", "Suicide", ::mmSuicide);

    self mmAddMenu("combat", "Combat Options", "main");
    self mmAddToggleOption("combat", "aimbot");
    self mmAddOption("combat", "Aim Target: ^3" + level.menuAimBoneLabels[self.menu["values"]["aimbone"]], ::mmCycleAimBone);
    self mmAddValueOption("combat", "Aim FOV", "aimfov", 15, 360, 15, false, undefined);
    self mmAddToggleOption("combat", "aim_noads");
    self mmAddToggleOption("combat", "aim_walls");
    self mmAddToggleOption("combat", "esp");

    self mmAddMenu("weapons", "Weapon Loadouts", "main");
    self game_addWeaponOptions("weapons");
    self mmAddOption("weapons", "Refill All Ammo", ::mmRefillAmmo);
    self mmAddOption("weapons", "Take All Weapons", ::mmTakeAllWeapons);

    if (access < 2)
        return;

    self mmAddMenu("lobby", "Lobby Settings", "main");
    self mmAddServerToggleOption("lobby", "Super Jump", "superjump", ::mmToggleSuperJump);
    self mmAddValueOption("lobby", "Gravity", "gravity", 100, 1000, 50, true, ::mmApplyGravity);
    self mmAddOption("lobby", "Spawn Bot", ::mmSpawnBot);
    self mmAddOption("lobby", "Kick All Bots", ::mmKickAllBots);
    self mmAddOption("lobby", "Fast Restart Map", ::mmFastRestart);

    self mmAddMenu("players", "Player Manager", "main");
    players = level.players;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!isDefined(p) || !isDefined(p.menu) || p == self || isDefined(p.menu["kicked"]))
            continue;

        self mmAddOption("players", p.name + " ^7[" + mmAccessLabel(p.menu["access"]) + "]", ::mmOpenPlayerActions, p);
    }

    target = self.menu["selectedPlayer"];
    if (isDefined(target) && isDefined(target.menu) && !isDefined(target.menu["kicked"]))
        self mmBuildPlayerActions(target);
}

mmBuildPlayerActions(target)
{
    self mmAddMenu("player_actions", target.name, "players");

    if (self mmCanManage(target))
    {
        for (lvl = 1; lvl < self.menu["access"]; lvl++)
        {
            if (target.menu["access"] != lvl)
                self mmAddOption("player_actions", "Set " + mmAccessLabel(lvl), ::mmSetTargetAccess, target, lvl);
        }

        if (target.menu["access"] > 0)
            self mmAddOption("player_actions", "Revoke Access", ::mmSetTargetAccess, target, 0);

        self mmAddOption("player_actions", "Freeze Controls" + mmOnOffTag(target.menu["frozen"]), ::mmToggleTargetFreeze, target);
        self mmAddOption("player_actions", "Kill Player", ::mmKillTarget, target);
        self mmAddOption("player_actions", "Kick Player", ::mmKickTarget, target);
        self mmAddOption("player_actions", "Bring Player To Me", ::mmBringTarget, target);
    }

    self mmAddOption("player_actions", "Teleport To Player", ::mmTeleportToTarget, target);
}

mmAddMenu(id, title, parent)
{
    menu = spawnStruct();
    menu.id = id;
    menu.title = title;
    menu.parent = parent;
    menu.items = [];
    self.menu["menus"][id] = menu;

    if (!isDefined(self.menu["cursor"][id]))
        self.menu["cursor"][id] = 0;
    if (!isDefined(self.menu["scroll"][id]))
        self.menu["scroll"][id] = 0;
}

mmNewOption(menuId, label)
{
    opt = spawnStruct();
    opt.label = label;
    opt.type = "action";
    opt.isServer = false;

    items = self.menu["menus"][menuId].items;
    items[items.size] = opt;
    self.menu["menus"][menuId].items = items;
    return opt;
}

mmAddOption(menuId, label, func, arg1, arg2)
{
    opt = self mmNewOption(menuId, label);
    opt.func = func;
    opt.arg1 = arg1;
    opt.arg2 = arg2;
}

mmAddToggleOption(menuId, key)
{
    def = level.menuToggleDefs[key];
    opt = self mmNewOption(menuId, def.label);
    opt.type = "toggle";
    opt.toggleKey = key;
    opt.func = ::mmToggle;
    opt.arg1 = key;
}

mmAddServerToggleOption(menuId, label, key, func)
{
    opt = self mmNewOption(menuId, label);
    opt.type = "toggle";
    opt.toggleKey = key;
    opt.isServer = true;
    opt.func = func;
}

// Left / right changes the value by step within [minVal, maxVal] and calls onChange(value).
mmAddValueOption(menuId, label, key, minVal, maxVal, step, isServer, onChange)
{
    opt = self mmNewOption(menuId, label);
    opt.type = "value";
    opt.valueKey = key;
    opt.minVal = minVal;
    opt.maxVal = maxVal;
    opt.step = step;
    opt.isServer = isServer;
    opt.onChange = onChange;
}

mmGetOptionValue(opt)
{
    if (opt.isServer)
        return level.menuServerValues[opt.valueKey];
    return self.menu["values"][opt.valueKey];
}

mmFormatOption(opt)
{
    if (opt.type == "toggle")
    {
        state = false;
        if (opt.isServer)
            state = level.menuServerToggles[opt.toggleKey];
        else
            state = self.menu["toggles"][opt.toggleKey];
        return opt.label + mmOnOffTag(state);
    }

    if (opt.type == "value")
    {
        value = self mmGetOptionValue(opt);
        return opt.label + ": ^3< " + value + " >";
    }

    return opt.label;
}

/* =========================
 *  HUD
 * ========================= */

mmRowY(index)
{
    return level.menuLayout.y + level.menuLayout.headerHeight + (index * level.menuLayout.rowHeight);
}

mmCreateHud()
{
    self mmDestroyHud();

    layout = level.menuLayout;
    bodyH = (level.menuMaxVisible * layout.rowHeight) + 16;

    bg = self createIcon("white", layout.width, bodyH);
    bg setPoint("CENTER", "CENTER", layout.x, layout.y + (bodyH / 2) + (layout.headerHeight / 2));
    bg.color = layout.bgColor;
    bg.alpha = 0.78;
    bg.sort = 1;
    bg.hideWhenInMenu = true;
    self.menu["ui"]["bg"] = bg;

    header = self createIcon("white", layout.width, layout.headerHeight);
    header setPoint("CENTER", "CENTER", layout.x, layout.y);
    header.color = layout.headerColor;
    header.alpha = 0.92;
    header.sort = 2;
    header.hideWhenInMenu = true;
    self.menu["ui"]["header"] = header;

    scroller = self createIcon("white", layout.width - 6, layout.rowHeight);
    scroller setPoint("CENTER", "CENTER", layout.x, mmRowY(0));
    scroller.color = layout.scrollerColor;
    scroller.alpha = 0.72;
    scroller.sort = 2;
    scroller.hideWhenInMenu = true;
    self.menu["ui"]["scroller"] = scroller;

    title = self createFontString("objective", 1.45);
    title setPoint("CENTER", "CENTER", layout.x, layout.y);
    title.sort = 3;
    title.hideWhenInMenu = true;
    self.menu["ui"]["title"] = title;

    footer = self createFontString("default", 1.0);
    footer setPoint("CENTER", "CENTER", layout.x, layout.y + bodyH + 22);
    footer.color = layout.footerColor;
    footer.sort = 3;
    footer.hideWhenInMenu = true;
    self.menu["ui"]["footer"] = footer;

    // Rows are allocated once; scrolling only changes their text.
    self.menu["ui"]["rows"] = [];
    for (i = 0; i < level.menuMaxVisible; i++)
    {
        row = self createFontString("objective", 1.2);
        row setPoint("LEFT", "CENTER", layout.x - (layout.width / 2) + 10, mmRowY(i));
        row.sort = 4;
        row.hideWhenInMenu = true;
        self.menu["ui"]["rows"][i] = row;
    }
}

mmRender()
{
    if (!self.menu["isOpen"] || !isDefined(self.menu["ui"]["rows"]))
        return;

    id = self.menu["current"];
    menu = self.menu["menus"][id];
    if (!isDefined(menu))
        return;

    mmSetText(self.menu["ui"]["title"], menu.title);
    mmSetText(self.menu["ui"]["footer"], level.menuFooterText);

    scroll = self.menu["scroll"][id];
    rows = self.menu["ui"]["rows"];
    for (i = 0; i < rows.size; i++)
    {
        idx = scroll + i;
        if (idx < menu.items.size)
        {
            mmSetText(rows[i], self mmFormatOption(menu.items[idx]));
            rows[i].alpha = 1;
        }
        else
        {
            rows[i].alpha = 0;
        }
    }

    scroller = self.menu["ui"]["scroller"];
    if (menu.items.size == 0)
    {
        scroller.alpha = 0;
    }
    else
    {
        scroller.alpha = 0.72;
        scroller setPoint("CENTER", "CENTER", level.menuLayout.x, mmRowY(self.menu["cursor"][id] - scroll));
    }
}

mmDestroyHud()
{
    if (!isDefined(self.menu) || !isDefined(self.menu["ui"]))
        return;

    // destroyElem() (not destroy()) also unregisters the element from
    // level.uiParent.children, which _hud_util's create* functions added it to.
    keys = getArrayKeys(self.menu["ui"]);
    for (i = 0; i < keys.size; i++)
    {
        k = keys[i];
        if (k == "rows")
            continue;
        if (isDefined(self.menu["ui"][k]))
            self.menu["ui"][k] destroyElem();
    }

    if (isDefined(self.menu["ui"]["rows"]))
    {
        rows = self.menu["ui"]["rows"];
        for (i = 0; i < rows.size; i++)
        {
            if (isDefined(rows[i]))
                rows[i] destroyElem();
        }
    }

    self.menu["ui"] = [];
}

/* =========================
 *  STRING / CONFIGSTRING TRACKING
 *
 *  Every distinct setText() string takes a configstring slot until the map
 *  ends. Labels with player names keep adding new ones on a busy server, so we
 *  count distinct strings and, past the limit, free every string created after
 *  a hidden anchor element, then redraw open menus. This is the usual GSC
 *  "overflow fix". It can also blank game HUD text created after the anchor
 *  until the game sets it again. Set level.menuOverflowFix = false in init()
 *  to disable it, or level.menuStringLimit to change the threshold.
 * ========================= */

mmInitStringTracking()
{
    level.menuStrings = [];
    level.menuStringCount = 0;
    level.menuStringFlushing = false;

    if (!isDefined(level.menuStringLimit))
        level.menuStringLimit = 50;

    level.menuNextFlush = level.menuStringLimit;

    if (!isDefined(level.menuOverflowFix))
        level.menuOverflowFix = true;
}

// Created lazily on first menu text write rather than in init(), so
// _hud_util::init() (level.uiParent / level.fontHeight) is guaranteed ready
// and startup/prematch HUD strings stay ahead of the anchor.
mmEnsureStringAnchor()
{
    if (!level.menuOverflowFix || isDefined(level.menuStringAnchor))
        return;

    level.menuStringAnchor = createServerFontString("default", 1.0);
    level.menuStringAnchor setText("mm_overflow_anchor");
    level.menuStringAnchor.alpha = 0;
}

// Skips unchanged text so re-renders don't resend strings.
mmSetText(elem, text)
{
    if (!isDefined(elem))
        return;
    if (isDefined(elem.mmText) && elem.mmText == text)
        return;

    mmEnsureStringAnchor();

    elem.mmText = text;
    elem setText(text);

    if (text == "" || isDefined(level.menuStrings[text]))
        return;

    level.menuStrings[text] = true;
    level.menuStringCount++;

    if (level.menuOverflowFix && !level.menuStringFlushing && level.menuStringCount >= level.menuNextFlush)
        level thread mmFlushStrings();
}

mmFlushStrings()
{
    level endon("game_ended");

    level.menuStringFlushing = true;
    waittillframeend;

    if (isDefined(level.menuStringAnchor))
        level.menuStringAnchor clearAllTextAfterHudElem();
    level.menuStrings = [];
    level.menuStringCount = 0;

    players = level.players;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (isDefined(p) && isDefined(p.menu) && p.menu["isOpen"])
            p mmRedrawText();
    }

    // If simultaneous open menus alone met the threshold, leave headroom before
    // the next flush instead of flushing on every subsequent text write.
    if (level.menuStringCount >= level.menuStringLimit)
        level.menuNextFlush = level.menuStringCount + 10;
    else
        level.menuNextFlush = level.menuStringLimit;

    level.menuStringFlushing = false;
}

mmRedrawText()
{
    keys = getArrayKeys(self.menu["ui"]);
    for (i = 0; i < keys.size; i++)
    {
        if (keys[i] != "rows" && isDefined(self.menu["ui"][keys[i]]))
            self.menu["ui"][keys[i]].mmText = undefined;
    }

    if (isDefined(self.menu["ui"]["rows"]))
    {
        rows = self.menu["ui"]["rows"];
        for (i = 0; i < rows.size; i++)
        {
            if (isDefined(rows[i]))
                rows[i].mmText = undefined;
        }
    }

    self mmRender();
}

/* =========================
 *  PLAYER TOGGLES
 * ========================= */

mmToggle(key)
{
    self mmSetToggle(key, !self.menu["toggles"][key], false);
}

mmSetToggle(key, state, silent)
{
    if (self.menu["toggles"][key] == state)
        return;

    def = level.menuToggleDefs[key];
    self.menu["toggles"][key] = state;

    if (state)
        self [[def.onFunc]]();
    else
        self [[def.offFunc]]();

    if (!silent)
        self iprintln(def.label + ": " + mmOnOff(state));
}

mmReapplyToggles()
{
    keys = getArrayKeys(level.menuToggleDefs);
    for (i = 0; i < keys.size; i++)
    {
        def = level.menuToggleDefs[keys[i]];
        if (def.reapplyOnSpawn && self.menu["toggles"][keys[i]])
            self [[def.onFunc]]();
    }
}

mmResetToggles()
{
    keys = getArrayKeys(level.menuToggleDefs);
    for (i = 0; i < keys.size; i++)
        self mmSetToggle(keys[i], false, true);
}

mmGodOn()
{
    self game_setGodMode(true);
}

mmGodOff()
{
    self game_setGodMode(false);
}

mmAmmoOn()
{
    self notify("mm_stop_ammo");
    self thread mmInfiniteAmmoLoop();
}

mmAmmoOff()
{
    self notify("mm_stop_ammo");
}

mmInfiniteAmmoLoop()
{
    self endon("disconnect");
    self endon("mm_stop_ammo");
    level endon("game_ended");

    for (;;)
    {
        if (isAlive(self))
        {
            weapon = self getCurrentWeapon();
            if (isDefined(weapon) && weapon != "" && weapon != "none")
            {
                clip = weaponClipSize(weapon);
                if (clip > 0)
                    self setWeaponAmmoClip(weapon, clip);
                self giveMaxAmmo(weapon);
            }
        }
        wait 0.1;
    }
}

mmSpeedOn()
{
    self notify("mm_stop_speed");
    self setMoveSpeedScale(self.menu["values"]["speed"]);
    self thread mmSpeedWatchWeaponChange();
}

mmSpeedOff()
{
    self notify("mm_stop_speed");
    self setMoveSpeedScale(1.0);
}

// Stock weapon scripts recalculate moveSpeedScale on weapon_change; reapply
// our boost after they finish so switching weapons doesn't silently clear it.
mmSpeedWatchWeaponChange()
{
    self endon("disconnect");
    self endon("mm_stop_speed");
    level endon("game_ended");

    for (;;)
    {
        self waittill("weapon_change");
        waittillframeend;
        if (isAlive(self) && self.menu["toggles"]["speed"])
            self setMoveSpeedScale(self.menu["values"]["speed"]);
    }
}

mmApplySpeedValue(value)
{
    if (self.menu["toggles"]["speed"])
        self setMoveSpeedScale(value);
}

mmThirdPersonOn()
{
    self game_setThirdPerson(true);
}

mmThirdPersonOff()
{
    self game_setThirdPerson(false);
}

mmUfoOn()
{
    self notify("mm_stop_ufo");
    self thread mmUfoLoop();
}

mmUfoOff()
{
    self notify("mm_stop_ufo");
    self unlink();

    if (isDefined(self.ufoOrigin))
        self.ufoOrigin delete();
    self.ufoOrigin = undefined;

    self mmBlockWeapons("ufo", false);
}

mmUfoLoop()
{
    self endon("disconnect");
    self endon("mm_stop_ufo");
    level endon("game_ended");

    if (isDefined(self.ufoOrigin))
        self.ufoOrigin delete();

    self.ufoOrigin = spawn("script_origin", self.origin);
    self playerLinkTo(self.ufoOrigin);
    self mmBlockWeapons("ufo", true);
    self iprintln("^3Attack^7: forward | ^3ADS^7: back | ^3Lethal^7: up | ^3Tactical^7: down");

    for (;;)
    {
        wait 0.05;

        if (!isAlive(self) || self.menu["isOpen"] || self.menu["frozen"] || (isDefined(self.sessionstate) && self.sessionstate != "playing"))
            continue;

        speed = self.menu["values"]["ufospeed"];
        forward = anglesToForward(self getPlayerAngles());
        move = (0, 0, 0);

        if (self attackButtonPressed())
            move = move + (forward * speed);
        if (self adsButtonPressed())
            move = move - (forward * speed);
        if (self fragButtonPressed())
            move = move + (0, 0, speed);
        if (self secondaryOffhandButtonPressed())
            move = move - (0, 0, speed);

        self.ufoOrigin.origin = self.ufoOrigin.origin + move;
    }
}

mmSuicide()
{
    self mmCloseMenu();
    if (self.menu["toggles"]["god"])
        self game_setGodMode(false);
    self suicide();
}

/* =========================
 *  COMBAT
 * ========================= */

// Living opponent of self: other team in team modes, anyone else in FFA.
mmIsEnemy(p)
{
    if (!isDefined(p) || p == self || !isDefined(p.pers) || !isAlive(p))
        return false;
    if (isDefined(p.sessionstate) && p.sessionstate != "playing")
        return false;
    if (isDefined(self.pers) && isDefined(self.pers["team"]) && self.pers["team"] == "spectator")
        return false;
    if (isDefined(p.pers["team"]) && p.pers["team"] == "spectator")
        return false;
    if (!isDefined(level.teamBased) || !level.teamBased)
        return true;
    if (!isDefined(self.pers) || !isDefined(self.pers["team"]) || !isDefined(p.pers["team"]))
        return false;
    return (p.pers["team"] != self.pers["team"]);
}

// Safely resolves a target bone with a fallback offset if the tag is not ready.
mmGetTargetPos(player, bone, fallbackOffset)
{
    pos = player getTagOrigin(bone);
    if (isDefined(pos))
        return pos;
    if (isDefined(player.origin))
        return player.origin + (0, 0, fallbackOffset);
    return undefined;
}

mmAimbotOn()
{
    self notify("mm_stop_aimbot");
    self thread mmAimbotLoop();
}

mmAimbotOff()
{
    self notify("mm_stop_aimbot");
}

// Snaps the view to the best target while ADS is held (or always, with
// "Aim Without ADS"). Paused while the menu is open, frozen, in UFO mode, or dead.
mmAimbotLoop()
{
    self endon("disconnect");
    self endon("mm_stop_aimbot");
    level endon("game_ended");

    for (;;)
    {
        wait 0.05;

        if (!isAlive(self) || self.menu["isOpen"] || self.menu["toggles"]["ufo"] || self.menu["frozen"] || (isDefined(self.sessionstate) && self.sessionstate != "playing"))
            continue;
        if (!self.menu["toggles"]["aim_noads"] && !self adsButtonPressed())
            continue;

        eye = self getEye();
        aimPos = self mmFindAimTarget(eye);
        if (isDefined(aimPos))
            self setPlayerAngles(vectorToAngles(aimPos - eye));
    }
}

// Returns the aim bone position of the enemy closest to the crosshair (by
// angle) inside the FOV cone, or undefined. Skips enemies behind walls unless
// "Aim Through Walls" is on.
mmFindAimTarget(eye)
{
    forward = anglesToForward(self getPlayerAngles());
    bone = level.menuAimBones[self.menu["values"]["aimbone"]];
    throughWalls = self.menu["toggles"]["aim_walls"];

    bestPos = undefined;
    fov = self.menu["values"]["aimfov"];
    if (fov >= 360)
        bestDot = -2;
    else
        bestDot = cos(fov * 0.5);

    players = level.players;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (!self mmIsEnemy(p))
            continue;

        pos = mmGetTargetPos(p, bone, 50);
        if (!isDefined(pos) || distanceSquared(eye, pos) < 1)
            continue;

        dot = vectorDot(forward, vectorNormalize(pos - eye));
        if (dot < bestDot)
            continue;
        if (!throughWalls && !bulletTracePassed(eye, pos, false, self))
            continue;

        bestPos = pos;
        bestDot = dot;
    }

    return bestPos;
}

mmCycleAimBone()
{
    next = self.menu["values"]["aimbone"] + 1;
    if (next >= level.menuAimBones.size)
        next = 0;
    self.menu["values"]["aimbone"] = next;
}

mmEspOn()
{
    self notify("mm_stop_esp");
    self thread mmEspLoop();
}

mmEspOff()
{
    self notify("mm_stop_esp");
    self mmEspClear();
}

// One client-only waypoint per living enemy (capped at level.menuEspMaxMarkers
// to stay under the per-client HUD limit), drawn through walls and moved to the
// enemy's head every frame. Markers for enemies that died or left are freed.
mmEspLoop()
{
    self endon("disconnect");
    self endon("mm_stop_esp");
    level endon("game_ended");

    for (;;)
    {
        enemies = [];
        players = level.players;
        for (i = 0; i < players.size; i++)
        {
            p = players[i];
            if (self mmIsEnemy(p))
                enemies[enemies.size] = p;
        }

        // In large FFA lobbies, show markers for the closest living enemies so we
        // stay within the per-client HUD element budget.
        maxMarkers = level.menuEspMaxMarkers;
        if (enemies.size > maxMarkers && isDefined(self.origin))
        {
            for (i = 0; i < maxMarkers; i++)
            {
                bestIdx = i;
                bestDist = distanceSquared(self.origin, enemies[i].origin);
                for (j = i + 1; j < enemies.size; j++)
                {
                    d = distanceSquared(self.origin, enemies[j].origin);
                    if (d < bestDist)
                    {
                        bestDist = d;
                        bestIdx = j;
                    }
                }
                if (bestIdx != i)
                {
                    tmp = enemies[i];
                    enemies[i] = enemies[bestIdx];
                    enemies[bestIdx] = tmp;
                }
            }
        }

        limit = enemies.size;
        if (limit > maxMarkers)
            limit = maxMarkers;

        active = [];
        positions = [];
        for (i = 0; i < limit; i++)
        {
            p = enemies[i];
            head = mmGetTargetPos(p, "j_head", 60);
            if (!isDefined(head))
                continue;

            key = "" + p getEntityNumber();
            active[key] = true;
            positions[key] = head + (0, 0, 14);
        }

        // Destroy stale markers first so swapping enemies never spikes HUD elem count.
        keys = getArrayKeys(self.menu["esp"]);
        for (i = 0; i < keys.size; i++)
        {
            if (isDefined(active[keys[i]]))
                continue;
            if (isDefined(self.menu["esp"][keys[i]]))
                self.menu["esp"][keys[i]] destroy();
            self.menu["esp"][keys[i]] = undefined;
        }

        activeKeys = getArrayKeys(active);
        for (i = 0; i < activeKeys.size; i++)
        {
            key = activeKeys[i];
            marker = self.menu["esp"][key];
            if (!isDefined(marker))
            {
                marker = self mmCreateEspMarker();
                if (!isDefined(marker))
                    continue;
                self.menu["esp"][key] = marker;
            }

            pos = positions[key];
            marker.x = pos[0];
            marker.y = pos[1];
            marker.z = pos[2];
        }

        wait 0.05;
    }
}

// Raw newClientHudElem (not _hud_util), so it is freed with destroy().
mmCreateEspMarker()
{
    marker = newClientHudElem(self);
    if (!isDefined(marker))
        return undefined;

    marker.color = (1, 0.15, 0.15);
    marker.alpha = 0.85;
    marker.archived = false;
    marker.hideWhenInMenu = true;
    marker setShader("white", 6, 6);
    marker game_setupEspWaypoint();
    return marker;
}

mmEspClear()
{
    if (!isDefined(self.menu) || !isDefined(self.menu["esp"]))
        return;

    keys = getArrayKeys(self.menu["esp"]);
    for (i = 0; i < keys.size; i++)
    {
        if (isDefined(self.menu["esp"][keys[i]]))
            self.menu["esp"][keys[i]] destroy();
    }
    self.menu["esp"] = [];
}

/* =========================
 *  WEAPONS
 * ========================= */

mmGiveWeapon(weaponName)
{
    self giveWeapon(weaponName);
    self giveMaxAmmo(weaponName);
    if (self.menu["weaponsBlocked"])
        self.menu["pendingWeapon"] = weaponName;
    else
        self switchToWeapon(weaponName);
    self iprintln("Gave weapon: ^5" + weaponName);
}

mmRefillAmmo()
{
    weapons = self game_getWeaponsList();
    if (isDefined(weapons))
    {
        for (i = 0; i < weapons.size; i++)
        {
            weapon = weapons[i];
            if (!isDefined(weapon) || weapon == "" || weapon == "none")
                continue;
            clip = weaponClipSize(weapon);
            if (clip > 0)
                self setWeaponAmmoClip(weapon, clip);
            self giveMaxAmmo(weapon);
        }
    }
    self iprintln("All weapon ammo refilled.");
}

mmTakeAllWeapons()
{
    self.menu["pendingWeapon"] = undefined;
    self takeAllWeapons();
    self iprintln("Removed all weapons.");
}

/* =========================
 *  LOBBY
 * ========================= */

// Backs up the dvar's original value (once) before changing it.
// Values are prefixed with "v:" so an originally empty dvar is distinct from no backup.
mmOverrideDvar(dvar, value)
{
    backup = "mm_orig_" + dvar;
    if (getDvar(backup) == "")
        setDvar(backup, "v:" + getDvar(dvar));
    setDvar(dvar, value);
}

mmRestoreDvar(dvar)
{
    backup = "mm_orig_" + dvar;
    orig = getDvar(backup);
    if (orig == "")
        return;

    if (orig.size >= 2 && getSubStr(orig, 0, 2) == "v:")
    {
        if (orig.size > 2)
            orig = getSubStr(orig, 2, orig.size);
        else
            orig = "";
    }

    setDvar(dvar, orig);
    setDvar(backup, "");
}

mmRestoreAllDvars()
{
    for (i = 0; i < level.menuTrackedDvars.size; i++)
        mmRestoreDvar(level.menuTrackedDvars[i]);
}

mmBroadcast(msg)
{
    players = level.players;
    for (i = 0; i < players.size; i++)
    {
        if (isDefined(players[i]))
            players[i] iprintln(msg);
    }
}

mmToggleSuperJump()
{
    state = !level.menuServerToggles["superjump"];
    level.menuServerToggles["superjump"] = state;

    game_setSuperJump(state);

    mmBroadcast("Super Jump: " + mmOnOff(state));
}

mmApplyGravity(value)
{
    if (value == level.menuGravityDefault)
        mmRestoreDvar(level.menuGravityDvar);
    else
        mmOverrideDvar(level.menuGravityDvar, "" + value);
}

mmSpawnBot()
{
    ok = self game_spawnBot();
    if (isDefined(ok) && ok)
        self iprintln("Spawned a bot.");
    else
        self iprintln("^1Failed to spawn bot (lobby may be full).");
}

mmIsBot()
{
    return (isDefined(self.pers) && isDefined(self.pers["isBot"]) && self.pers["isBot"]);
}

mmKickAllBots()
{
    players = level.players;
    kicked = 0;
    for (i = 0; i < players.size; i++)
    {
        p = players[i];
        if (isDefined(p) && p mmIsBot() && (!isDefined(p.menu) || !isDefined(p.menu["kicked"])))
        {
            if (isDefined(p.menu))
                p.menu["kicked"] = true;
            kick(p getEntityNumber());
            kicked++;
        }
    }
    self iprintln("Kicked ^5" + kicked + " ^7bot(s).");
}

mmFastRestart()
{
    map_restart(false);
}

/* =========================
 *  ACCESS & PLAYER MANAGER
 * ========================= */

mmAccessLabel(levelVal)
{
    if (levelVal >= 3)
        return "Host";
    if (levelVal == 2)
        return "Admin";
    if (levelVal == 1)
        return "VIP";
    return "None";
}

mmOnOff(state)
{
    if (state)
        return "^2ON";
    return "^1OFF";
}

mmOnOffTag(state)
{
    if (state)
        return " ^2[ON]";
    return " ^1[OFF]";
}

// A player can only manage players strictly below their own level.
mmCanManage(target)
{
    if (!isDefined(target) || !isDefined(target.menu) || target == self)
        return false;
    if (target isHost())
        return false;
    return (self.menu["access"] > target.menu["access"]);
}

mmSetTargetAccess(target, newLevel)
{
    if (!self mmCanManage(target))
    {
        self iprintln("^1You can only manage players below your access level.");
        return;
    }

    if (newLevel >= self.menu["access"])
    {
        self iprintln("^1You can only grant access below your own.");
        return;
    }

    target mmApplyAccess(newLevel);

    if (newLevel == 0)
        self iprintln("Revoked access from ^5" + target.name);
    else
        self iprintln("Set ^5" + target.name + " ^7to ^2" + mmAccessLabel(newLevel));
}

mmApplyAccess(newLevel)
{
    oldLevel = self.menu["access"];
    if (oldLevel == newLevel)
        return;

    self.menu["access"] = newLevel;
    self mmSaveAccess();

    // Demoted players may be looking at pages they can no longer use.
    if (newLevel < oldLevel && self.menu["isOpen"])
        self mmCloseMenu();

    if (newLevel == 0)
    {
        self mmResetToggles();
        self iprintln("^1Your menu access was revoked.");
        return;
    }

    if (oldLevel == 0)
    {
        self.menu["welcomed"] = true;
        self mmPrintWelcome();
    }
    else
    {
        self iprintln("^2Menu access set to: ^5" + mmAccessLabel(newLevel));
    }
}

mmLoadSavedAccess()
{
    if (self mmIsBot())
        return 0;

    guid = self.menu["guid"];
    if (guid == "" || guid == "0")
        return 0;

    entries = strTok(getDvar("mm_admins"), ", ");
    for (i = 0; i < entries.size; i++)
    {
        parts = strTok(entries[i], ":");
        if (parts.size == 2 && parts[0] == guid)
        {
            lvl = int(parts[1]);
            if (lvl < 0)
                lvl = 0;
            if (lvl > 3)
                lvl = 3;
            return lvl;
        }
    }

    return 0;
}

mmSaveAccess()
{
    guid = self.menu["guid"];
    if (guid == "" || guid == "0" || self mmIsBot())
        return;

    entries = strTok(getDvar("mm_admins"), ", ");
    out = "";
    for (i = 0; i < entries.size; i++)
    {
        parts = strTok(entries[i], ":");
        if (parts.size == 2 && parts[0] == guid)
            continue;
        out = mmJoin(out, entries[i]);
    }

    if (self.menu["access"] > 0)
        out = mmJoin(out, guid + ":" + self.menu["access"]);

    setDvar("mm_admins", out);
}

mmJoin(list, entry)
{
    if (list == "")
        return entry;
    return list + "," + entry;
}

// Moves a player, or their UFO anchor if they are flying.
mmMovePlayer(position)
{
    if (isDefined(self.ufoOrigin))
        self.ufoOrigin.origin = position;
    else
        self setOrigin(position);
}

mmToggleTargetFreeze(target)
{
    if (!self mmCanManage(target))
        return;

    state = !target.menu["frozen"];
    target.menu["frozen"] = state;

    if (state)
    {
        if (target.menu["isOpen"])
            target mmCloseMenu();
        if (target.menu["toggles"]["ufo"])
            target mmSetToggle("ufo", false, true);
    }

    target freezeControls(state);

    if (state)
        target iprintln("^1You have been frozen by an admin.");
    else
        target iprintln("^2You have been unfrozen.");
    self iprintln("Freeze ^5" + target.name + "^7: " + mmOnOff(state));
}

mmKillTarget(target)
{
    if (!self mmCanManage(target))
        return;

    if (!isAlive(target))
    {
        self iprintln("^1" + target.name + " is not alive.");
        return;
    }

    if (target.menu["toggles"]["god"])
        target game_setGodMode(false);
    target suicide();
    self iprintln("Killed ^5" + target.name);
}

mmKickTarget(target)
{
    if (!self mmCanManage(target))
        return;

    name = target.name;
    target.menu["kicked"] = true;
    self.menu["selectedPlayer"] = undefined;
    kick(target getEntityNumber());
    self iprintln("Kicked ^5" + name);
    self mmGoTo("players", false);
}

mmTeleportToTarget(target)
{
    if (!isDefined(target) || !isAlive(target) || !isAlive(self))
    {
        self iprintln("^1Both players must be alive to teleport.");
        return;
    }

    self mmMovePlayer(target.origin + (0, 0, 10));
    self iprintln("Teleported to ^5" + target.name);
}

mmBringTarget(target)
{
    if (!self mmCanManage(target))
        return;

    if (!isAlive(target) || !isAlive(self))
    {
        self iprintln("^1Both players must be alive to teleport.");
        return;
    }

    target mmMovePlayer(self.origin + (0, 0, 10));
    self iprintln("Brought ^5" + target.name + " ^7to your position.");
}
