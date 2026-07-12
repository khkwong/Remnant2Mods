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
-- HAZARD (resolved, but the rule still matters): RegisterHook's "self" parameter is a
-- RemoteUnrealParam wrapper, NOT a plain UObject. Touching it directly crashes: a method
-- call (self:GetFullName()) silently returned nil, and a plain property access
-- (self.LoadoutList) hard-crashed the game with no catchable error. The documented accessor
-- self:get() unwraps it to the real UObject and was safety-tested in ZZTestMod (3 runs, all
-- reads fine afterward). Rule: inside any RegisterHook callback, ALWAYS self:get() first,
-- never touch the raw wrapper.

-- The most recently constructed Loadouts panel. Screen reopens construct a fresh panel each
-- time, so the tile-click hooks below must always act on the CURRENT panel, never a closured
-- stale one (a stale closure was the original cause of the reopen bug).
local currentPanel = nil

-- Full names of every tile widget this mod has created, so the tile-click hooks can tell our
-- tiles apart from the game's own (whose clicks already work via the panel's own delegate
-- subscriptions - reacting to those too would double-trigger their dialogs).
local ourTileFullNames = {}

-- Wire up save/load for OUR tiles. Background (see docs/remnant2-modding-research.md
-- 3.4o/3.4p): a tile's right/left click handlers just broadcast multicast delegates; the
-- panel subscribes its OnLoadoutSlotSaved/OnLoadoutClicked handlers (which own the actual
-- confirmation dialogs and save/load calls) to each tile IT creates. UE4SS Lua cannot bind
-- multicast delegates (unsupported property type in this build), so instead we post-hook the
-- tile class's click handlers - which DO fire on our tiles, since WidgetBlueprintLibrary
-- .Create applied the tile-internal button bindings - and forward the event to the panel's
-- handler ourselves, exactly as the missing delegate subscription would have.
local tileHooksRegistered = false

local function registerTileInteractionHooks()
  if tileHooksRegistered then
    return
  end

  -- Reads the tile's own equipped-state indicator (the EquippedIconBox overlay, whose
  -- visibility the tile's RefreshEquipped keeps in sync by calling the LoadoutComponent's
  -- native IsLoadoutEquipped). Reading the icon avoids calling that native function
  -- ourselves - its parameter signature is unknown, and guess-calling native functions has
  -- crashed the game before (the FText incident).
  local function isTileEquipped(tile)
    local ok, visible = pcall(function() return tile.EquippedIconBox:IsVisible() end)
    return ok and visible == true
  end

  local function forwardTileEventToPanel(selfParam, panelHandlerName, actionLabel, blockedWhenEquipped)
    local getOk, tile = pcall(function() return selfParam:get() end)
    if not getOk or not tile or not tile:IsValid() then
      return
    end

    local nameOk, fullName = pcall(function() return tile:GetFullName() end)
    if not nameOk or not fullName or not ourTileFullNames[fullName] then
      return -- one of the game's own tiles; its clicks already reach the panel natively
    end

    if blockedWhenEquipped and isTileEquipped(tile) then
      print(string.format(
        "[MoreLoadoutSlots] %s on this mod's extra tile suppressed - its loadout is currently equipped, and the game disables this action on the equipped loadout (matching vanilla tile behavior).\n",
        actionLabel
      ))
      return
    end

    if not currentPanel or not currentPanel:IsValid() then
      print(string.format(
        "[MoreLoadoutSlots] %s detected on one of this mod's extra tiles, but no valid Loadouts panel reference is available to forward it to - ignoring.\n",
        actionLabel
      ))
      return
    end

    local idxOk, idx = pcall(function() return tile.Index end)
    if not idxOk or type(idx) ~= "number" then
      print(string.format(
        "[MoreLoadoutSlots] %s detected on one of this mod's extra tiles, but its Index could not be read - ignoring.\n",
        actionLabel
      ))
      return
    end

    print(string.format(
      "[MoreLoadoutSlots] %s on this mod's extra tile (Index=%d) - forwarding to the panel's %s handler (the game's own tiles get this via a delegate subscription UE4SS can't replicate).\n",
      actionLabel, idx, panelHandlerName
    ))
    ExecuteInGameThread(function()
      local callOk, callErr = pcall(function()
        currentPanel[panelHandlerName](currentPanel, idx)
      end)
      if not callOk then
        print(string.format(
          "[MoreLoadoutSlots] FAILED to call the panel's %s handler: %s\n",
          panelHandlerName, tostring(callErr)
        ))
      end
    end)
  end

  -- Right-click = save. The tile's internal button's OnMouseRightClick is bound (via the
  -- class's ComponentDelegateBinding) to this handler. Suppressed when the tile's loadout is
  -- currently equipped - vanilla tiles disable overwrite-save on the equipped loadout, and
  -- that check lives inside the vanilla tile's own handler (pre-broadcast), so a raw event
  -- forward would bypass it.
  local rmbOk = pcall(function()
    RegisterHook(
      "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C:BndEvt__Widget_Loadout_Button_K2Node_ComponentBoundEvent_0_OnFocusMouseEventDelegate__DelegateSignature",
      function(self)
        forwardTileEventToPanel(self, "OnLoadoutSlotSaved", "Right-click (save)", true)
      end
    )
  end)

  -- Left-click = load, same mechanism via the button's OnClicked.
  local lmbOk = pcall(function()
    RegisterHook(
      "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C:BndEvt__Widget_Loadout_Button_K2Node_ComponentBoundEvent_2_OnAdvButtonClickedEvent__DelegateSignature",
      function(self)
        forwardTileEventToPanel(self, "OnLoadoutClicked", "Left-click (load)", false)
      end
    )
  end)

  -- Keyboard context-actions (F = delete, Space = equip) never touch the mouse bound events -
  -- they dispatch through the tooltip framework's OnInputAction(ButtonWidget, InputAction)
  -- instead. Enum byte values mapped via a scripted in-game test (see
  -- docs/remnant2-modding-research.md): 1 = equip (Space), 3 = delete (F). Same forwarding
  -- rationale: the vanilla tile's OnInputAction broadcasts delegates only panel-created tiles
  -- have subscribers for.
  local INPUT_ACTION_EQUIP = 1
  local INPUT_ACTION_DELETE = 3

  local keyOk = pcall(function()
    RegisterHook(
      "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C:OnInputAction",
      function(self, ButtonWidgetParam, InputActionParam)
        local actionOk, action = pcall(function() return InputActionParam:get() end)
        if not actionOk then
          return
        end
        if action == INPUT_ACTION_EQUIP then
          forwardTileEventToPanel(self, "OnLoadoutClicked", "Space (equip)", false)
        elseif action == INPUT_ACTION_DELETE then
          forwardTileEventToPanel(self, "OnLoadoutSlotDeleted", "F (delete)", false)
        end
      end
    )
  end)

  if rmbOk and lmbOk and keyOk then
    tileHooksRegistered = true
    print("[MoreLoadoutSlots] Tile interaction forwarding hooks registered: right-click (save), left-click (load), Space (equip), F (delete).\n")
  else
    print(string.format(
      "[MoreLoadoutSlots] FAILED to register tile interaction forwarding hooks (right-click ok: %s, left-click ok: %s, keyboard ok: %s) - will retry next time the Loadouts screen opens.\n",
      tostring(rmbOk), tostring(lmbOk), tostring(keyOk)
    ))
  end
end

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

      -- Construct the tile the same way the game's own panel Refresh does: via
      -- WidgetBlueprintLibrary.Create, the native function behind the Blueprint "Create Widget"
      -- node. The earlier StaticConstructObject approach produced a tile that rendered and
      -- showed tooltips but ignored all clicks - the tile class's FModel JSON dump revealed a
      -- ComponentDelegateBinding wiring Button.OnMouseRightClick (save), Button.OnClicked
      -- (load), and mouse enter/leave to the tile's handlers, and those dynamic delegate
      -- bindings are only applied during UUserWidget::Initialize(), which CreateWidget runs
      -- and raw StaticConstructObject skips (Initialize isn't a reflected UFunction, so it
      -- can't be called from Lua after the fact).
      local wblOk, wbl = pcall(function()
        return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
      end)
      if not wblOk or not wbl or not wbl:IsValid() then
        print("[MoreLoadoutSlots] FAILED to find the engine's WidgetBlueprintLibrary (needed to create widgets through the normal UMG lifecycle) - cannot add an extra loadout slot this session. Error: " .. tostring(wbl) .. "\n")
        return
      end

      local playerController = FindFirstOf("PlayerController")

      local constructOk, newTile = pcall(function()
        return wbl:Create(panel, tileClass, playerController)
      end)
      if not constructOk or not newTile or not newTile:IsValid() then
        print("[MoreLoadoutSlots] FAILED to create a new Widget_Loadout_C tile widget via WidgetBlueprintLibrary.Create - cannot add an extra loadout slot this session. Error: " .. tostring(newTile) .. "\n")
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

      -- Register this tile so the click-forwarding hooks can recognize it, and make sure
      -- those hooks exist (registered lazily here because the Widget_Loadout_C class is
      -- guaranteed loaded at this point, which isn't true at mod startup).
      pcall(function() ourTileFullNames[newTile:GetFullName()] = true end)
      registerTileInteractionHooks()

      -- KNOWN LIMITATION, do not reattempt naively: the tile's clicks broadcast multicast
      -- delegates (OnClicked/OnLoadoutSaved/OnLoadoutSlotDeleted) that the PANEL subscribes to
      -- for tiles it creates itself - the save/load confirmation dialogs live in the panel's
      -- handlers, not the tile. Binding those delegates from Lua is NOT possible in the
      -- installed UE4SS build: merely reading newTile.OnClicked raises
      -- "[handle_unreal_property_value] ... Property type 'MulticastInlineDelegateProperty'
      -- not supported", and that error aborts the entire enclosing callback DESPITE pcall
      -- (the tile never got added at all). See docs/remnant2-modding-research.md 3.4o/3.4p
      -- for the researched workaround options.

      pcall(function() newTile:Refresh() end)

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
  currentPanel = panel
  addExtraLoadoutTile(panel)
end)
