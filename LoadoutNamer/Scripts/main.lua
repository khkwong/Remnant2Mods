print("[LoadoutNamer] Loaded and running.\n")

-- Mod #2: custom names for loadout slots.
--   Hover a loadout tile and press F2 -> a text box opens in the tile's title row.
--   Type the new name, then Enter or F2 commits; Escape cancels. Names persist in
--   loadout_names.txt next to this mod (one "recordIndex<TAB>name" line per slot) and
--   are re-applied every time the Loadouts panel is constructed. The hover tooltip's
--   title also shows the (full, untruncated) name; long names show truncated on the
--   tile itself.
--
-- Everything here composes building blocks proven in ZZTestMod probe rounds 1-2
-- (research doc 3.4y/3.4z): LabelOverride FText writes survive the game's own
-- refreshes; EditableTextBox injection + Text reads work; RegisterKeyBind fires in
-- menu context; the OnMouseEnter bound-event hook gives hover identity.

local PANEL_CLASS = "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_LoadoutsPanel.Widget_LoadoutsPanel_C"
local MOUSE_ENTER_FN = "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_Loadout.Widget_Loadout_C:BndEvt__Widget_Loadout_Button_K2Node_ComponentBoundEvent_4_OnAdvButtonClickedEvent__DelegateSignature"

-- Record 10 is the game's reserved last-gear-state auto-save (research doc 3.4w); it
-- renders as the hoverable "Last Gear State" tile on the character screen (3.4z).
local RESERVED_RECORD_INDEX = 10

-- Longest name a slot can keep (storage cap). The full name shows in the hover
-- tooltip's title, which is much wider than the tile.
local MAX_NAME_LENGTH = 32

-- The tile label (GFGRemnantCracked font, size 12, rendered uppercase) runs off the
-- tile's right edge somewhere past ~18 characters - there's no wrapping or ellipsis -
-- so names longer than this are shown truncated on the tile (full name in the tooltip).
local TILE_LABEL_MAX = 18

-- The hover tooltip (Widget_LoadoutTooltip dump): its title is an ItemLabel TextBlock
-- whose text is the static string "Loadout" (dump line ~2186) - the game never varies
-- it, so writing it per-hover is safe and writing the literal back restores default.
local TOOLTIP_CLASS_NAME = "Widget_LoadoutTooltip_C"
local TOOLTIP_DEFAULT_TITLE = "Loadout"

-- MoreLoadoutSlots builds the panel out to 20 tiles; waiting for that count sequences
-- our apply-names pass after its label pass with no explicit coordination (3.4y).
-- If that mod is ever disabled, the 8-tile vanilla panel would time the poll out - the
-- fallback below then applies names to however many tiles exist.
local EXPECTED_TILES = 20

-- ============================== name store ==============================

-- The game's io working directory is the game exe dir; which relative prefix reaches
-- this (symlinked) mod folder depends on the UE4SS layout, so probe candidates once.
local NAMES_FILE_CANDIDATES = {
  "ue4ss/Mods/LoadoutNamer/loadout_names.txt",
  "Mods/LoadoutNamer/loadout_names.txt",
}

local namesFilePath = nil
local names = {} -- [recordIndex] = custom name

local function resolveNamesFilePath()
  for _, path in ipairs(NAMES_FILE_CANDIDATES) do
    local f = io.open(path, "r")
    if f then
      f:close()
      return path
    end
  end
  for _, path in ipairs(NAMES_FILE_CANDIDATES) do
    local f = io.open(path, "a") -- creates an empty file where writable
    if f then
      f:close()
      return path
    end
  end
  return nil
end

local function loadNames()
  namesFilePath = resolveNamesFilePath()
  if not namesFilePath then
    print("[LoadoutNamer] WARNING: no writable names-file location found (tried: " .. table.concat(NAMES_FILE_CANDIDATES, ", ") .. ") - renames will work but WILL NOT persist across sessions.\n")
    return
  end
  local count = 0
  local f = io.open(namesFilePath, "r")
  if f then
    for line in f:lines() do
      local idx, name = line:match("^(%d+)\t(.+)$")
      if idx and name then
        -- Enforce the length cap on pre-existing entries too (older saves may predate it).
        names[tonumber(idx)] = name:sub(1, MAX_NAME_LENGTH):match("^(.-)%s*$")
        count = count + 1
      end
    end
    f:close()
  end
  print(string.format("[LoadoutNamer] Names file: %s (%d saved names loaded).\n", namesFilePath, count))
end

local function saveNames()
  if not namesFilePath then
    return
  end
  local f, err = io.open(namesFilePath, "w")
  if not f then
    print("[LoadoutNamer] FAILED to write the names file: " .. tostring(err) .. "\n")
    return
  end
  for idx, name in pairs(names) do
    f:write(string.format("%d\t%s\n", idx, name))
  end
  f:close()
end

loadNames()

-- ============================== labels ==============================

-- What a slot shows with no custom name. Records 0-9 derive "Loadout {Index+1}"
-- natively, so an empty override lets the tile regenerate it; records 11+ carry the
-- "Loadout N" override MoreLoadoutSlots pins on them (label number == record index
-- past the reserved record), so removing a custom name must restore that, not blank.
local function defaultLabelFor(recordIndex)
  if recordIndex > RESERVED_RECORD_INDEX then
    return string.format("Loadout %d", recordIndex)
  end
  return ""
end

-- Game thread only.
local function writeLabel(tile, text)
  local ok, err = pcall(function()
    tile.LabelOverride = FText(text)
    tile:Refresh()
  end)
  if not ok then
    print("[LoadoutNamer] FAILED to write a tile label: " .. tostring(err) .. "\n")
  end
  return ok
end

-- What the tile itself displays for a custom name: truncated with a ".." marker when
-- it would run off the tile. The stored name stays full-length for the tooltip.
local function tileTextFor(name)
  if #name > TILE_LABEL_MAX then
    return name:sub(1, TILE_LABEL_MAX - 2) .. ".."
  end
  return name
end

-- Game thread only. Puts the slot's correct at-rest label on the tile.
local function applyRestingLabel(tile, recordIndex)
  local name = names[recordIndex]
  writeLabel(tile, name and tileTextFor(name) or defaultLabelFor(recordIndex))
end

-- ============================== apply pass ==============================

local function applySavedNames(panel)
  local attempts = 0
  local MAX_ATTEMPTS = 80 -- ~4s; also filters the two benign no-LoadoutList panel instances

  LoopAsync(50, function()
    attempts = attempts + 1

    local countOk, count = pcall(function() return panel.LoadoutList:GetChildrenCount() end)
    local haveList = countOk and count and count > 0

    if not haveList or count < EXPECTED_TILES then
      if attempts < MAX_ATTEMPTS then
        return false
      end
      if not haveList then
        return true -- benign non-UI panel instance; nothing to do
      end
      -- Fewer tiles than expected (MoreLoadoutSlots disabled?) - apply to what exists.
    end

    ExecuteInGameThread(function()
      local applied = 0
      for i = 0, count - 1 do
        local ok = pcall(function()
          local tile = panel.LoadoutList:GetChildAt(i)
          local idx = tile.Index
          if names[idx] then
            if writeLabel(tile, tileTextFor(names[idx])) then
              applied = applied + 1
            end
          end
        end)
        if not ok then
          print(string.format("[LoadoutNamer] Could not read tile %d during the apply-names pass - skipping it.\n", i))
        end
      end
      if applied > 0 then
        print(string.format("[LoadoutNamer] Applied %d saved names to the Loadouts panel.\n", applied))
      end
    end)

    return true
  end)
end

-- ============================== tooltip title ==============================

-- Write the hovered slot's name (or the "Loadout" default) into the tooltip's title.
-- The tooltip widget is created/shown by the game some time after mouse-enter, so a
-- short poll finds it and keeps rewriting for ~1s to land after the game's own setup.
-- A generation counter cancels stale polls when the hover moves on.
local tooltipGen = 0

local function scheduleTooltipTitle(recordIndex)
  tooltipGen = tooltipGen + 1
  local gen = tooltipGen
  local title = names[recordIndex] or TOOLTIP_DEFAULT_TITLE
  local attempts = 0
  local logged = false

  LoopAsync(50, function()
    if gen ~= tooltipGen then
      return true -- a newer hover superseded this poll
    end
    attempts = attempts + 1

    pcall(function()
      local tooltips = FindAllOf(TOOLTIP_CLASS_NAME)
      if tooltips then
        for _, tt in ipairs(tooltips) do
          -- Skip the class-default object: writing its template would leak the
          -- title into every future tooltip instance.
          if tt:IsValid() and not tt:GetFullName():find("Default__") then
            ExecuteInGameThread(function()
              pcall(function() tt.ItemLabel:SetText(FText(title)) end)
            end)
            if not logged then
              logged = true
              print(string.format("[LoadoutNamer] Tooltip title set for record %d ('%s').\n", recordIndex, title))
            end
          end
        end
      end
    end)

    return attempts >= 20 -- ~1s of coverage
  end)
end

-- ============================== tab hotkey suppression ==============================

-- The in-game menu's T/I/M keys switch tabs even while the rename box has keyboard
-- focus, and UE4SS can't consume input. But the game gates each switch on the tab
-- button's own visibility (ZZTestMod probe: FocusTraits/FocusInventory/FocusMap still
-- fire with the buttons hidden, then early-out on an IsVisible check). So: hide those
-- tab buttons for the duration of an edit. Hidden (ESlateVisibility 2) - not Collapsed -
-- keeps their layout space, so the tab bar doesn't reflow; the labels just fade out.
-- The game resets tab visibility itself when the menu reopens, so a leaked Hidden
-- state (screen closed mid-edit) self-heals.
local TAB_HOTKEY_PROPS = { "TraitTab", "InventoryTab", "MapTab" }
local hiddenTabs = {}

-- Game thread only.
local function suppressTabHotkeys()
  local menu = nil
  pcall(function()
    local all = FindAllOf("Widget_InGameMenu_C")
    if all then
      for _, m in ipairs(all) do
        if m:IsValid() and not m:GetFullName():find("Default__") then
          menu = m
        end
      end
    end
  end)
  if not menu then
    return
  end
  for _, prop in ipairs(TAB_HOTKEY_PROPS) do
    pcall(function()
      local tab = menu[prop]
      -- Only touch tabs the game is currently showing, so restore can't force-show
      -- a tab the game itself hides in this context.
      if tab and tab:IsValid() and tab:IsVisible() then
        tab:SetVisibility(2) -- Hidden: blocks the hotkey, keeps layout space
        table.insert(hiddenTabs, tab)
      end
    end)
  end
end

-- Game thread only.
local function restoreTabHotkeys()
  for _, tab in ipairs(hiddenTabs) do
    pcall(function()
      if tab:IsValid() then
        tab:SetVisibility(0) -- Visible
      end
    end)
  end
  hiddenTabs = {}
end

-- ============================== rename session ==============================

local hoveredTile = nil -- last tile the mouse entered (kept on leave - forgiving F2 timing)
local editBox = nil     -- live EditableTextBox while a rename is in progress
local editTile = nil
local editIndex = nil
local hoverHookRegistered = false

-- Track which tile the mouse is over. Registered lazily on first panel construction so
-- Widget_Loadout_C is guaranteed loaded. Hazards respected: self:get() only (H3), read
-- cached properties only, no native calls in the hook body (H8).
local function registerHoverHook()
  if hoverHookRegistered then
    return
  end
  local ok, err = pcall(function()
    RegisterHook(MOUSE_ENTER_FN, function(self)
      local getOk, tile = pcall(function() return self:get() end)
      if getOk and tile and tile:IsValid() then
        hoveredTile = tile
        -- Reflected property read only in the hook body (H8); the tooltip work
        -- itself runs later on the async poll + game thread.
        local idxOk, idx = pcall(function() return tile.Index end)
        if idxOk and type(idx) == "number" then
          scheduleTooltipTitle(idx)
        end
      end
    end)
  end)
  if ok then
    hoverHookRegistered = true
    print("[LoadoutNamer] Hover tracking registered - hover a loadout tile and press F2 to rename it.\n")
  else
    print("[LoadoutNamer] FAILED to register hover tracking (renaming unavailable): " .. tostring(err) .. "\n")
  end
end

local function beginRename(tile, recordIndex)
  ExecuteInGameThread(function()
    local ok, err = pcall(function()
      -- Parent the box into the VERTICAL box holding the tile's text rows (reached via
      -- the Archetype subtitle, a named variable like Label). In a VerticalBox the box
      -- gets its own full-width row below the subtitle; appending it to the title row
      -- (a HorizontalBox) instead left it squished against the tile's right edge - the
      -- blanked Label still reserves its MinDesiredWidth=130 there.
      local column = tile.Archetype:GetParent()
      if not column or not column:IsValid() then
        error("could not reach the tile's text column")
      end

      local box = StaticConstructObject(StaticFindObject("/Script/UMG.EditableTextBox"), tile.WidgetTree)
      if not box or not box:IsValid() then
        error("failed to construct the EditableTextBox")
      end
      -- Raw write is fine here: MinimumDesiredWidth feeds desired-size computation each
      -- frame, and a failed/ignored write just means a narrower box.
      pcall(function() box.MinimumDesiredWidth = 130.0 end)
      column:AddChild(box)

      -- Blank the tile's label for the duration of the edit so it's obvious which name
      -- is being replaced (the old text comes back on cancel).
      writeLabel(tile, " ")

      -- Blank the archetype subtitle too - the box sits right on top of it. Must happen
      -- AFTER writeLabel's Refresh (Refresh re-derives the subtitle), and must use the
      -- real SetText setter, not a raw Text write (H4: raw writes on visual properties
      -- don't invalidate Slate). Restore is automatic: every exit from the edit calls
      -- Refresh again via applyRestingLabel. Non-fatal if it fails - just overlap.
      pcall(function() tile.Archetype:SetText(FText(" ")) end)

      editBox = box
      editTile = tile
      editIndex = recordIndex

      -- Typing T/I/M must not yank the menu to another tab mid-edit.
      suppressTabHotkeys()
    end)
    if ok then
      print(string.format("[LoadoutNamer] Renaming slot (record %d) - click the box, type the new name, then Enter/F2 to commit or Escape to cancel. Committing an empty name removes the custom name.\n", recordIndex))
    else
      print("[LoadoutNamer] FAILED to open the rename box: " .. tostring(err) .. "\n")
    end
  end)
end

local function endRename(commit)
  ExecuteInGameThread(function()
    local box, tile, idx = editBox, editTile, editIndex
    editBox, editTile, editIndex = nil, nil, nil

    restoreTabHotkeys()

    local text = ""
    pcall(function() text = box.Text:ToString() end)

    pcall(function()
      local parent = box:GetParent()
      if parent and parent:IsValid() then
        parent:RemoveChild(box)
      end
    end)

    if not tile or not tile:IsValid() then
      return -- screen closed mid-edit; the next apply pass restores labels anyway
    end

    if not commit then
      applyRestingLabel(tile, idx)
      print("[LoadoutNamer] Rename cancelled.\n")
      return
    end

    -- Trim and strip characters that would corrupt the tab-separated store.
    text = text:gsub("[\t\r\n]", ""):match("^%s*(.-)%s*$")

    if #text > MAX_NAME_LENGTH then
      print(string.format("[LoadoutNamer] Name truncated to %d characters (the storage cap; the tile shows the first %d with '..', the tooltip shows the rest).\n", MAX_NAME_LENGTH, TILE_LABEL_MAX))
      text = text:sub(1, MAX_NAME_LENGTH):match("^(.-)%s*$")
    end

    if text == "" then
      names[idx] = nil
      saveNames()
      applyRestingLabel(tile, idx)
      print(string.format("[LoadoutNamer] Custom name removed from record %d - back to its default label.\n", idx))
    else
      names[idx] = text
      saveNames()
      applyRestingLabel(tile, idx)
      print(string.format("[LoadoutNamer] Record %d named '%s' (saved).\n", idx, text))
    end

    -- If the tooltip is on screen right now (mouse is still over the tile), bring its
    -- title in line with the new name immediately.
    scheduleTooltipTitle(idx)
  end)
end

local function editSessionActive()
  if not editBox then
    return false
  end
  local ok, alive = pcall(function() return editBox:IsValid() end)
  if ok and alive then
    return true
  end
  editBox, editTile, editIndex = nil, nil, nil -- box died with the screen
  ExecuteInGameThread(restoreTabHotkeys) -- belt-and-braces; menu reopen resets these anyway
  return false
end

-- ============================== keybinds ==============================

RegisterKeyBind(Key.F2, function()
  if editSessionActive() then
    endRename(true)
    return
  end

  if not hoveredTile then
    return
  end
  local aliveOk, alive = pcall(function() return hoveredTile:IsValid() end)
  if not aliveOk or not alive then
    hoveredTile = nil
    return
  end

  local idxOk, idx = pcall(function() return hoveredTile.Index end)
  if not idxOk or type(idx) ~= "number" then
    print("[LoadoutNamer] F2: could not read the hovered tile's record index - ignoring.\n")
    return
  end
  if idx == RESERVED_RECORD_INDEX then
    print("[LoadoutNamer] F2: that's the game's Last Gear State auto-save slot - it can't be renamed.\n")
    return
  end

  beginRename(hoveredTile, idx)
end)

RegisterKeyBind(Key.RETURN, function()
  if editSessionActive() then
    endRename(true)
  end
end)

RegisterKeyBind(Key.ESCAPE, function()
  if editSessionActive() then
    endRename(false)
  end
end)

-- ============================== wiring ==============================

NotifyOnNewObject(PANEL_CLASS, function(panel)
  registerHoverHook()
  applySavedNames(panel)
end)
