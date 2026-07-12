print("[ZZTestMod] Loaded and running.\n")

-- Research scratchpad only. Feature code lives in MoreLoadoutSlots/Scripts/main.lua.
--
-- CURRENT TEST: map every input on a loadout tile (F / Space / right-click / left-click) to
-- the code path(s) it triggers. Three candidate paths are logged with distinct labels:
--   PATH A: OnInputAction(ButtonWidget, InputAction enum byte) - tooltip context-action dispatch
--   PATH B: the tile Button's OnMouseRightClick bound event (BndEvt_0)
--   PATH C: the tile Button's OnClicked bound event (BndEvt_2)
-- (MoreLoadoutSlots' own forwarding prints will also appear for the mod-added tile - that's
-- extra signal, not noise.)
--
-- TEST SCRIPT to run in-game, one input at a time, cancelling any dialog that appears:
--   On ONE vanilla tile with a saved, NOT-equipped loadout: press F ... Space ... RMB ... LMB
--   Then the same four inputs, same order, on the mod-added 9th tile.
-- Report which input you pressed in what order (the timestamps + this order = full mapping).

local function describeTile(selfParam)
  local ok, tile = pcall(function() return selfParam:get() end)
  if not ok or not tile or not tile:IsValid() then
    return "(tile could not be unwrapped/validated)"
  end
  local idx = "?"
  pcall(function() idx = tostring(tile.Index) end)
  local equipped = "?"
  pcall(function() equipped = tostring(tile.EquippedIconBox:IsVisible()) end)
  return string.format("tile Index=%s, equipped-icon visible=%s", idx, equipped)
end

local hooks = {
  {
    label = "PATH A: OnInputAction",
    path = "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C:OnInputAction",
    callback = function(self, ButtonWidgetParam, InputActionParam)
      local actionValue = "?"
      pcall(function() actionValue = tostring(InputActionParam:get()) end)
      print(string.format("[ZZTestMod] PATH A: OnInputAction, InputAction enum byte = %s, %s\n", actionValue, describeTile(self)))
    end,
  },
  {
    label = "PATH B: Button.OnMouseRightClick bound event (BndEvt_0)",
    path = "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C:BndEvt__Widget_Loadout_Button_K2Node_ComponentBoundEvent_0_OnFocusMouseEventDelegate__DelegateSignature",
    callback = function(self)
      print(string.format("[ZZTestMod] PATH B: Button.OnMouseRightClick bound event, %s\n", describeTile(self)))
    end,
  },
  {
    label = "PATH C: Button.OnClicked bound event (BndEvt_2)",
    path = "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C:BndEvt__Widget_Loadout_Button_K2Node_ComponentBoundEvent_2_OnAdvButtonClickedEvent__DelegateSignature",
    callback = function(self)
      print(string.format("[ZZTestMod] PATH C: Button.OnClicked bound event, %s\n", describeTile(self)))
    end,
  },
}

for _, h in ipairs(hooks) do
  local ok, err = pcall(function() RegisterHook(h.path, h.callback) end)
  if ok then
    print(string.format("[ZZTestMod] Logger hook registered: %s\n", h.label))
  else
    print(string.format("[ZZTestMod] FAILED to register logger hook (%s) - Widget_Loadout_C may not be loaded yet; open the Loadouts screen once, then hot-reload. Error: %s\n", h.label, tostring(err)))
  end
end
