print("[ZZTestMod] Loaded - probing TraitsComponent (F9 in-game to run).\n")

-- Research scratchpad only. Feature code lives in MoreLoadoutSlots/,
-- LoadoutNamer/, EquipmentSearch/, and InventoryTracker/ (each
-- <Mod>/Scripts/main.lua).
--
-- ACTIVE PROBE (2026-07-28): InventoryTracker traits support - confirming how
-- to read which traits the player owns/has leveled. CXX header dump
-- (GunfireRuntime.hpp) already answered the shape without touching the game:
--   - UTraitsComponent (ActorComponent) has TArray<FTraitInfo> Traits - this
--     looks like the actual owned-trait list (parallel to
--     RemnantPlayerInventoryComponent.Items for rings/amulets/etc).
--   - FTraitInfo has: TraitBP (TSubclassOf<UTrait>, the class ref to compare
--     against MASTER_LIST classPath, same GetFullName() pattern already
--     proven for items), Level (int32, 0-10 allocated points), bNewTrait,
--     plus SlotIndex/InstanceData/Transient/LevelMods/MaxLevelMods (probably
--     not needed).
--   - UTraitsComponent also has TArray<TSubclassOf<UTrait>> AvailableTraits -
--     unclear yet whether this is "all traits that exist" (not useful, we
--     have that from the wiki+FModel already) or something narrower. This
--     probe logs both array lengths so we can tell them apart empirically.
--   - Both Traits and AvailableTraits are plain properties (no function
--     call needed) - same safety class as LoadoutComponent.Slots and
--     RemnantPlayerInventoryComponent.Items, both already proven safe to
--     read directly. Not calling HasTrait/GetTraitLevel/GetAvailableTraits
--     for this probe on purpose - stay on the safest rung first.
--
-- What this probe does: on F9, finds the live TraitsComponent for the
-- player pawn (FindAllOf + GetOuter match, same pattern as
-- findOwnedInventoryComponent in InventoryTracker/Scripts/main.lua), logs
-- TraitPoints/MaxTraitPoints, the length of AvailableTraits vs Traits, then
-- every entry in Traits (TraitBP's /Game/... class path + Level).
--
-- IF THIS WORKS: readOwnedClassPaths-style logic for traits reads
-- Traits[i].TraitBP:GetFullName() + Traits[i].Level directly, no function
-- calls, no crash risk beyond generic pcall-wrapped property access already
-- proven throughout this project.

RegisterKeyBind(Key.F9, function()
    ExecuteInGameThread(function()
        local pawn = FindFirstOf("Character_Master_Player_C")
        if not pawn then
            print("[ZZTestMod] F9: no player pawn found.\n")
            return
        end

        local all = FindAllOf("TraitsComponent")
        if not all then
            print("[ZZTestMod] F9: FindAllOf('TraitsComponent') returned nothing.\n")
            return
        end
        print(string.format("[ZZTestMod] F9: %d TraitsComponent instance(s) found.\n", #all))

        local comp = nil
        for _, c in ipairs(all) do
            local okOuter, owner = pcall(function() return c:GetOuter() end)
            if okOuter and owner then
                local okSame, same = pcall(function() return owner:GetFullName() == pawn:GetFullName() end)
                if okSame and same then
                    comp = c
                    break
                end
            end
        end

        if not comp then
            print("[ZZTestMod] F9: no TraitsComponent matched to the player pawn via GetOuter - logging all instances' owners instead.\n")
            for i, c in ipairs(all) do
                local okOuter, owner = pcall(function() return c:GetOuter() end)
                local ownerName = (okOuter and owner and select(2, pcall(function() return owner:GetFullName() end))) or "?"
                print(string.format("[ZZTestMod]   instance %d owner: %s\n", i, tostring(ownerName)))
            end
            return
        end

        local okPoints, points = pcall(function() return comp.TraitPoints end)
        local okMax, maxPoints = pcall(function() return comp.MaxTraitPoints end)
        print(string.format("[ZZTestMod] F9: TraitPoints=%s MaxTraitPoints=%s\n",
            okPoints and tostring(points) or "?", okMax and tostring(maxPoints) or "?"))

        local okAvail, avail = pcall(function() return comp.AvailableTraits end)
        if okAvail and avail then
            local okLen, len = pcall(function() return #avail end)
            print(string.format("[ZZTestMod] F9: AvailableTraits length=%s\n", okLen and tostring(len) or "?"))
        else
            print("[ZZTestMod] F9: AvailableTraits unreadable.\n")
        end

        local okTraits, traits = pcall(function() return comp.Traits end)
        if not okTraits or traits == nil then
            print("[ZZTestMod] F9: comp.Traits unreadable.\n")
            return
        end
        local okLen, len = pcall(function() return #traits end)
        if not okLen then
            print("[ZZTestMod] F9: #traits unreadable.\n")
            return
        end
        print(string.format("[ZZTestMod] F9: Traits length=%d\n", len))

        for i = 1, len do
            local okEntry, entry = pcall(function() return traits[i] end)
            if okEntry and entry ~= nil then
                local unwrapped = entry
                if type(entry) == "userdata" then
                    local okGet, inner = pcall(function() return entry:get() end)
                    if okGet and inner ~= nil then unwrapped = inner end
                end
                local okLevel, level = pcall(function() return unwrapped.Level end)
                local okBP, traitBP = pcall(function() return unwrapped.TraitBP end)
                local pathStr = "?"
                if okBP and traitBP ~= nil then
                    local okPath, path = pcall(function() return traitBP:GetFullName() end)
                    if okPath and path then pathStr = path end
                end
                print(string.format("[ZZTestMod]   [%d] Level=%s TraitBP=%s\n",
                    i, okLevel and tostring(level) or "?", pathStr))
            else
                print(string.format("[ZZTestMod]   [%d] entry unreadable.\n", i))
            end
        end
    end)
end)

print("[ZZTestMod] Ready - press F9 in-game to dump TraitsComponent state.\n")
