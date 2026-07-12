print("[MoreLoadoutSlots] Loaded and running.\n")

-- Patch the LoadoutComponent's record capacity upward on spawn. Confirmed (research session,
-- see docs/remnant2-modding-research.md 3.4g) that GetMaxRecordsForTemplate directly proxies
-- this field - not currently load-bearing for the single extra tile below (the underlying
-- record storage already supports index 8 with the native default of NumRecords=11), but kept
-- here since going beyond 11 total slots eventually will need it.
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, NewPawn)
  print("[MoreLoadoutSlots] Player spawned - patching LoadoutComponent.Slots[].NumRecords to 20.\n")

  ExecuteInGameThread(function()
    local components = FindAllOf("LoadoutComponent")
    if not components then
      return
    end

    for i, comp in ipairs(components) do
      if comp:IsValid() then
        local ok, slots = pcall(function() return comp.Slots end)
        if ok and slots then
          for j = 1, #slots do
            pcall(function() slots[j].NumRecords = 20 end)
          end
        end
      end
    end
  end)
end)

-- Mod #1 extra-tile logic.
--
-- HAZARD, confirmed by a real native crash (not just a Lua error): RegisterHook's own "self"
-- parameter is NOT safe to touch at all in this context - not just for method calls
-- (self:GetFullName() returned nil rather than erroring), but even a plain PROPERTY ACCESS
-- (self.LoadoutList) crashed the game outright (log just stopped, same signature as the
-- FText crash documented in the research doc - a native crash, not something pcall can
-- catch). So RegisterHook-on-Refresh is never used here; never touch a hook's "self".
--
-- Fix: only ever use the "panel" object handed to us by NotifyOnNewObject, which has been
-- proven safe every time this session. The problem that motivated wanting a Refresh hook in
-- the first place was timing - panel.LoadoutList isn't valid yet at the exact moment
-- NotifyOnNewObject fires (construction time), so poll for it with LoopAsync instead of
-- relying on a hook to tell us when it's ready.
local tileNameCounter = 0

local function addExtraLoadoutTile(panel)
  local TARGET_TILE_COUNT = 9
  local attempts = 0
  local MAX_ATTEMPTS = 40 -- ~2 seconds at 50ms per attempt, safety cap

  LoopAsync(50, function()
    attempts = attempts + 1

    local listOk, list = pcall(function() return panel.LoadoutList end)
    if not listOk or not list or not list:IsValid() then
      if attempts >= MAX_ATTEMPTS then
        print("[MoreLoadoutSlots] Timed out after " .. attempts .. " polling attempts waiting for the Loadouts screen's tile container (LoadoutList) to finish initializing - giving up for this screen-open, no extra tile added.\n")
        return true -- stop looping
      end
      return false -- keep polling
    end

    -- LoadoutList is valid - safe to proceed. Do the actual work inside the game thread.
    ExecuteInGameThread(function()
      -- Idempotency guard: this whole function can run again on a screen reopen (a fresh
      -- NotifyOnNewObject firing for a newly-constructed panel instance). Skip if the target
      -- count is already met.
      local countOk, currentCount = pcall(function() return list:GetChildrenCount() end)
      if countOk and currentCount and currentCount >= TARGET_TILE_COUNT then
        print(string.format("[MoreLoadoutSlots] Loadouts screen already has %d tiles (target %d) - not adding another.\n", currentCount, TARGET_TILE_COUNT))
        return
      end

      local tileClassOk, tileClass = pcall(function()
        return StaticFindObject("/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C")
      end)
      if not tileClassOk or not tileClass or not tileClass:IsValid() then
        print("[MoreLoadoutSlots] FAILED to find the Widget_Loadout_C tile class - cannot add an extra loadout slot this session. Error: " .. tostring(tileClass) .. "\n")
        return
      end

      -- Unique name per construction - StaticConstructObject with a name already taken under
      -- the same Outer can fail/misbehave.
      tileNameCounter = tileNameCounter + 1
      local tileName = "MoreLoadoutSlotsTile_" .. tostring(tileNameCounter)

      local constructOk, newTile = pcall(function()
        return StaticConstructObject(tileClass, panel, tileName)
      end)
      if not constructOk or not newTile or not newTile:IsValid() then
        print("[MoreLoadoutSlots] FAILED to construct a new Widget_Loadout_C tile widget - cannot add an extra loadout slot this session. Error: " .. tostring(newTile) .. "\n")
        return
      end

      local templateOk, template = pcall(function()
        return StaticFindObject("/Game/_Core/Loadouts/Gear_Loadout.Gear_Loadout")
      end)
      if not templateOk or not template or not template:IsValid() then
        print("[MoreLoadoutSlots] FAILED to find the Gear_Loadout template asset - cannot configure the new tile. Error: " .. tostring(template) .. "\n")
        return
      end

      pcall(function() newTile.Index = 8 end)
      pcall(function() newTile.LoadoutTemplate = template end)

      pcall(function() newTile:Refresh() end)

      -- Experiment: right-click (save) currently does nothing on the tile, while the hover
      -- tooltip works fine. Theory: Construct() (the normal UMG lifecycle event, which
      -- StaticConstructObject skips - only CreateWidget triggers it automatically) sets up
      -- focusability/hit-testing needed for input routing, which the tooltip's pull-based
      -- query system doesn't need but OnInputAction dispatch might. Not yet confirmed.
      pcall(function() newTile:Construct() end)

      local addOk, addResult = pcall(function() return list:AddChild(newTile) end)
      if not addOk then
        print("[MoreLoadoutSlots] FAILED to add the new tile into the Loadouts screen's tile list - it was constructed and configured, but never became visible. Error: " .. tostring(addResult) .. "\n")
        return
      end

      -- SizeBox_0 (fixed HeightOverride=688, room for 8 tiles) isn't a bound variable on the
      -- panel, so reach it via LoadoutList's own Slot.Parent instead - confirmed from the JSON
      -- dump that SizeBoxSlot_0.Parent points back to SizeBox_0. 688 / 8 tiles = 86px/tile.
      -- Plain property write on HeightOverride has no visible effect - only the real
      -- SetHeightOverride function triggers a re-layout.
      local sizeBoxOk, sizeBox = pcall(function() return list.Slot.Parent end)
      if sizeBoxOk and sizeBox and sizeBox:IsValid() then
        pcall(function() sizeBox:SetHeightOverride(774.0) end)
      end

      print("[MoreLoadoutSlots] Added a 9th loadout slot tile (Index=8) to the Loadouts screen.\n")
    end)

    return true -- stop looping, we found a valid LoadoutList
  end)
end

NotifyOnNewObject("/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_LoadoutsPanel.Widget_LoadoutsPanel_C", function(panel)
  addExtraLoadoutTile(panel)
end)
