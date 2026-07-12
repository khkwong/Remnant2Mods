print("[ZZTestMod] Loaded - ACTIVE PROBES for LoadoutNamer: P1 (vanilla-tile LabelOverride persistence) + P2 (EditableTextBox injection).\n")

-- Research scratchpad only. Feature code lives in MoreLoadoutSlots/Scripts/main.lua.
--
-- ACTIVE: LoadoutNamer probes P1 + P2 (see dev-docs/LOADOUT_NAMER_START.md section 7).
--   P1: writes LabelOverride on the FIRST VANILLA tile (child 0, "Loadout 1") then calls
--       Refresh. In-game test: does "P1 CUSTOM NAME" show, and does it SURVIVE saving/
--       equipping that slot (which re-runs the game's own Refresh/UpdateArchetypeText)?
--   P2: constructs a raw /Script/UMG.EditableTextBox (same StaticConstructObject recipe as
--       mod #1's ScrollBox) and adds it to the bottom of LoadoutList. In-game test: does it
--       render, take focus, accept typing? A 500ms poll prints the box's Text property to
--       the log whenever it changes, proving we can read what was typed.
--
-- Past diagnostics are recoverable from git history:
--   - LoadoutComponent Slots/NumRecords structure dump
--   - RegisterHook self:get() safety test (PASSED - always unwrap with self:get())
--   - Three-path input logger (F/Space/RMB/LMB dispatch paths + E_TooltipContextAction bytes)
--   - First-launch NotifyOnNewObject quirk diagnostic (obsolete: fixed by UE4SS upgrade)
--   - Multicast delegate stage-1 test (PASSED: delegate:Add(uobject, FName("Handler")))

local PANEL_CLASS = "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_LoadoutsPanel.Widget_LoadoutsPanel_C"
local EXPECTED_TILES = 20 -- wait for MoreLoadoutSlots to finish its tile pass before probing

NotifyOnNewObject(PANEL_CLASS, function(panel)
  local attempts = 0
  local MAX_ATTEMPTS = 80 -- ~4s; also filters the two benign panel instances that never get a LoadoutList

  LoopAsync(50, function()
    attempts = attempts + 1

    local countOk, count = pcall(function() return panel.LoadoutList:GetChildrenCount() end)
    if not countOk or not count or count < EXPECTED_TILES then
      if attempts >= MAX_ATTEMPTS then
        print("[ZZTestMod] Timed out waiting for the 20-tile LoadoutList (benign for the two no-UI panel instances) - skipping probes for this panel.\n")
        return true
      end
      return false
    end

    ExecuteInGameThread(function()
      -- ---- P1: custom label on a VANILLA tile ----
      local p1Ok, p1Err = pcall(function()
        local tile = panel.LoadoutList:GetChildAt(0) -- "Loadout 1", record index 0
        tile.LabelOverride = FText("P1 CUSTOM NAME")
        tile:Refresh()
      end)
      if p1Ok then
        print("[ZZTestMod] P1: wrote LabelOverride='P1 CUSTOM NAME' on vanilla tile 0 and called Refresh. Check: does the first tile show it? Then SAVE/EQUIP slot 1 - does the name survive?\n")
      else
        print("[ZZTestMod] P1 FAILED: " .. tostring(p1Err) .. "\n")
      end

      -- ---- P2: inject an engine EditableTextBox ----
      local p2Ok, p2Err = pcall(function()
        local cls = StaticFindObject("/Script/UMG.EditableTextBox")
        if not cls or not cls:IsValid() then
          error("EditableTextBox class not found")
        end
        local box = StaticConstructObject(cls, panel.WidgetTree)
        if not box or not box:IsValid() then
          error("StaticConstructObject returned invalid object")
        end
        panel.LoadoutList:AddChild(box)

        -- Poll the box's Text property so the log proves we can read typed input.
        local lastText = nil
        LoopAsync(500, function()
          local aliveOk, alive = pcall(function() return box:IsValid() end)
          if not aliveOk or not alive then
            print("[ZZTestMod] P2: text box no longer valid (screen closed) - stopping the text poll.\n")
            return true
          end
          local readOk, txt = pcall(function() return box.Text:ToString() end)
          if readOk and txt ~= lastText then
            lastText = txt
            print("[ZZTestMod] P2: EditableTextBox text is now: '" .. tostring(txt) .. "'\n")
          end
          return false
        end)
      end)
      if p2Ok then
        print("[ZZTestMod] P2: EditableTextBox constructed and added below the tiles. Check: does a text box render at the bottom of the (scrollable) list? Can you click into it and type? Watch the log for text-change lines.\n")
      else
        print("[ZZTestMod] P2 FAILED: " .. tostring(p2Err) .. "\n")
      end
    end)

    return true
  end)
end)
