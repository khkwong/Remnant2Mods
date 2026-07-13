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

-- The tile label's font asset, from dev-data/Widget_Loadout.json (~3574-3580). Loaded
-- whenever the character screen is up, so StaticFindObject finds it when we need it.
-- StaticFindObject needs the FULL object path (Package.ObjectName) - the bare package
-- path fails with "GetPackageNameFromLongName: Name wasn't long" (2026-07-13 log).
local EDIT_FONT_PATH = "/Game/UI/Fonts/GFGRemnantCracked_Font.GFGRemnantCracked_Font"

-- The game's reusable key-glyph widget (dev-data/Widget_KeyIcon.json): Background image
-- + KeyText TextBlock. Used for the tooltip's "F2 Rename" prompt.
local KEYICON_CLASS_PATH = "/Game/UI/UI_Widgets/Widget_KeyIcon.Widget_KeyIcon_C"

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

-- ============================== tooltip rename prompt ==============================

-- Adds an "F2 Rename" entry to the tooltip's action-button footer. The footer widget
-- (Widget_Tooltip_Actions_C, a named variable on the tooltip) has an ExtraActionList
-- HorizontalBox that exists precisely for extra entries, so this is the game's own
-- extension point - we append a real Widget_KeyIcon (the game's key-glyph widget,
-- created through WidgetBlueprintLibrary.Create so it initializes like the game's own)
-- plus a TextBlock label styled like the tile text.
-- One prompt per live tooltip instance: more than one tooltip can be alive at once
-- (hovering tile B while tile A's tooltip still exists), so track by the instance's
-- ExtraActionList full name. A single global reference here caused an alternating
-- recreate loop that stacked duplicate prompts (2026-07-13 test).
local promptsByExtra = {} -- [ExtraActionList full name] = { icon = ..., label = ... }

-- Game thread only. Idempotent - called on every tooltip-poll tick.
local function ensureRenamePrompt(tooltip, recordIndex)
  local ok, err = pcall(function()
    local actions = tooltip.Widget_Tooltip_Actions
    if not actions or not actions:IsValid() then
      return
    end
    local extra = actions.ExtraActionList
    if not extra or not extra:IsValid() then
      return
    end

    -- Already installed in THIS tooltip instance? Validate the stored widgets are
    -- alive AND still parented here (an object name can be recycled by a new
    -- instance after the old one is garbage-collected).
    local extraName = extra:GetFullName()
    local entry = promptsByExtra[extraName]
    local present = false
    pcall(function()
      if entry and entry.icon:IsValid() and entry.label:IsValid() then
        local parent = entry.icon:GetParent()
        present = parent and parent:IsValid() and parent:GetFullName() == extraName
      end
    end)

    if not present then
      local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
      local keyIconClass = StaticFindObject(KEYICON_CLASS_PATH)
      if not (wbl and wbl:IsValid() and keyIconClass and keyIconClass:IsValid()) then
        return
      end
      -- Owning player must come from an owned widget, never FindFirstOf (multiplayer
      -- rule, research doc 3.4z).
      local player = tooltip:GetOwningPlayer()
      if not player or not player:IsValid() then
        return
      end

      local keyIcon = wbl:Create(tooltip, keyIconClass, player)
      if not keyIcon or not keyIcon:IsValid() then
        print("[LoadoutNamer] Could not create the KeyIcon widget for the tooltip's Rename prompt.\n")
        return
      end

      local label = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tooltip.WidgetTree)
      if not label or not label:IsValid() then
        return
      end
      -- Match the tile text's look (font write-back: reading the struct hands a
      -- detached copy, so mutate then assign back - same lesson as the edit box style).
      -- Creation-time only, so the error logs below can't spam.
      local fOk, fErr = pcall(function()
        local f = label.Font
        f.Size = 10.0 -- before the font lookup, so a lookup failure can't abort the size
        local font = StaticFindObject(EDIT_FONT_PATH)
        if font and font:IsValid() then
          f.FontObject = font
        end
        label.Font = f
      end)
      if not fOk then
        print("[LoadoutNamer] Rename-prompt label font styling failed: " .. tostring(fErr) .. "\n")
      end
      local cOk, cErr = pcall(function()
        local c = label.ColorAndOpacity
        c.SpecifiedColor.R = 0.7
        c.SpecifiedColor.G = 0.7
        c.SpecifiedColor.B = 0.7
        c.SpecifiedColor.A = 1.0
        pcall(function() c.ColorUseRule = 0 end)
        label.ColorAndOpacity = c
      end)
      if not cOk then
        print("[LoadoutNamer] Rename-prompt label color styling failed: " .. tostring(cErr) .. "\n")
      end

      extra:AddChild(keyIcon)
      extra:AddChild(label)
      -- Center the label vertically in the action row like the game's own prompt
      -- labels (2 = VAlign_Center). The slot only exists after AddChild.
      pcall(function() label.Slot:SetVerticalAlignment(2) end)
      entry = { icon = keyIcon, label = label }
      promptsByExtra[extraName] = entry
      print("[LoadoutNamer] 'F2 Rename' prompt added to the loadout tooltip's action row.\n")
    end

    -- Re-assert the texts every tick: the KeyIcon's own Construct may derive KeyText
    -- from its (unset) InputActionName after we first write it, and SetText is cheap.
    pcall(function() entry.icon.KeyText:SetText(FText("F2")) end)
    pcall(function() entry.label:SetText(FText("Rename")) end)

    -- The reserved Last Gear State record can't be renamed - hide the prompt there.
    local vis = (recordIndex == RESERVED_RECORD_INDEX) and 1 or 0 -- 1 = Collapsed
    pcall(function() entry.icon:SetVisibility(vis) end)
    pcall(function() entry.label:SetVisibility(vis) end)
  end)
  if not ok then
    print("[LoadoutNamer] Rename-prompt injection failed: " .. tostring(err) .. "\n")
  end
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
              ensureRenamePrompt(tt, recordIndex)
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

-- ============================== edit box styling ==============================

-- Target look, from dev-data/Widget_Loadout.json (~3565-3581): the tile label is
-- EDIT_FONT_PATH size 12, color 0.7/0.7/0.7.

-- Sets R/G/B/A on an FSlateColor's SpecifiedColor, and pins ColorUseRule to
-- UseColor_Specified (0) - if the rule was set to inherit, the specified color
-- would be ignored no matter what we write into it.
local function setSlateColor(slateColor, r, g, b, a)
  slateColor.SpecifiedColor.R = r
  slateColor.SpecifiedColor.G = g
  slateColor.SpecifiedColor.B = b
  slateColor.SpecifiedColor.A = a
  pcall(function() slateColor.ColorUseRule = 0 end)
end

-- Best-effort restyle toward the game's look. WidgetStyle struct writes are the
-- riskiest op class (research doc 3.4), so: every path is read-probed before it is
-- written (a failed read = that layout doesn't exist on this engine version = skip,
-- never guess), each group has its own pcall, and any failure just leaves that part
-- of the box at the engine default. Must run BEFORE the box enters the widget tree
-- so Slate builds with these values.
local function styleEditBox(box)
  local fontApplied, fgApplied, bgApplied, writtenBack = false, false, false, false

  pcall(function()
    -- Read-modify-WRITE-BACK: reading a struct property may hand back a detached
    -- copy (first attempt's nested writes changed nothing visually), so after
    -- mutating we assign the whole struct back to the property below.
    local style = box.WidgetStyle

    -- Font: probed at both known layouts - TextStyle.Font (newer style structs) and
    -- Font directly on the style (what this game's build actually exposes; the
    -- TextStyle path read-fails here, confirmed via the styling log 2026-07-13).
    -- Size 10 (the Archetype subtitle's size) rather than the label's 12: the box has
    -- fixed width, and the smaller size keeps more of a long name visible while typing.
    pcall(function()
      local fontStruct = nil
      -- Both known layouts read-fail on this build; log each path's actual error
      -- once so the real field name can be identified instead of guessed (H6).
      local candidates = {
        { "TextStyle.Font", function() return style.TextStyle.Font end },
        { "Font",           function() return style.Font end },
      }
      for _, cand in ipairs(candidates) do
        local ok, resultOrErr = pcall(cand[2])
        if ok and resultOrErr then
          fontStruct = resultOrErr
          break
        else
          print(string.format("[LoadoutNamer] Font path '%s': %s\n", cand[1], tostring(resultOrErr)))
        end
      end
      if fontStruct then
        -- Each write logged separately: the path READS fine but the writes were
        -- failing silently inside the enclosing pcall (2026-07-13 log).
        local sizeOk, sizeErr = pcall(function() fontStruct.Size = 10.0 end)
        if not sizeOk then
          print("[LoadoutNamer] Font Size write failed: " .. tostring(sizeErr) .. "\n")
        end
        local fobOk, fobErr = pcall(function()
          local font = StaticFindObject(EDIT_FONT_PATH)
          if font and font:IsValid() then
            fontStruct.FontObject = font
          end
        end)
        if not fobOk then
          print("[LoadoutNamer] FontObject write failed: " .. tostring(fobErr) .. "\n")
        end
        -- Write the font struct back up the chain in case reading it detached a copy
        -- (colors didn't need this, but they're one level shallower).
        pcall(function() style.TextStyle.Font = fontStruct end)
        fontApplied = sizeOk or fobOk
      end
    end)

    -- Typed text color: ashen gray, brighter than the label's 0.7 so it stands out
    -- against the near-black box fill (user-tuned).
    pcall(function()
      local _ = style.ForegroundColor.SpecifiedColor.R
      setSlateColor(style.ForegroundColor, 0.85, 0.85, 0.85, 1.0)
      pcall(function() setSlateColor(style.FocusedForegroundColor, 0.85, 0.85, 0.85, 1.0) end)
      fgApplied = true
    end)

    -- Background: tint the engine's white rounded-box brush dark and translucent so
    -- the box reads as part of the tile in all three interaction states.
    pcall(function()
      local _ = style.BackgroundImageNormal.TintColor.SpecifiedColor.R
      setSlateColor(style.BackgroundImageNormal.TintColor, 0.02, 0.02, 0.02, 0.85)
      pcall(function() setSlateColor(style.BackgroundImageHovered.TintColor, 0.04, 0.04, 0.04, 0.9) end)
      pcall(function() setSlateColor(style.BackgroundImageFocused.TintColor, 0.04, 0.04, 0.04, 0.9) end)
      bgApplied = true
    end)

    box.WidgetStyle = style -- write the mutated struct back onto the widget
    writtenBack = true
  end)

  print(string.format("[LoadoutNamer] Edit box styling: font=%s, text-color=%s, background=%s, write-back=%s.\n",
    fontApplied and "ok" or "skipped", fgApplied and "ok" or "skipped", bgApplied and "ok" or "skipped",
    writtenBack and "ok" or "FAILED"))
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
      -- Parent the box into the TITLE row (the HorizontalBox holding the Label), so the
      -- edit happens visually where the name lives. The blanked Label would normally
      -- squish the box by reserving its MinDesiredWidth=130 in that row, so zero it for
      -- the duration of the edit (plain-float property write; endRename restores it).
      local row = tile.Label:GetParent()
      if not row or not row:IsValid() then
        error("could not reach the tile's title row")
      end

      local box = StaticConstructObject(StaticFindObject("/Script/UMG.EditableTextBox"), tile.WidgetTree)
      if not box or not box:IsValid() then
        error("failed to construct the EditableTextBox")
      end
      -- Raw write is fine here: MinimumDesiredWidth feeds desired-size computation each
      -- frame, and a failed/ignored write just means a narrower box.
      pcall(function() box.MinimumDesiredWidth = 130.0 end)
      styleEditBox(box) -- before AddChild: Slate builds the box with these values

      -- Blank the tile's label and stop it reserving width, THEN add the box - it
      -- takes the label's place in the title row. The subtitle stays visible below.
      -- MinDesiredWidth is a LAYOUT property: the real SetMinDesiredWidth setter is
      -- mandatory, a raw write doesn't invalidate Slate layout (H4 - the raw write
      -- indeed changed nothing, 2026-07-13 test).
      writeLabel(tile, " ")
      pcall(function() tile.Label:SetMinDesiredWidth(0.0) end)
      row:AddChild(box)

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

    -- Give the label its reserved title-row width back (zeroed for the edit).
    -- Real setter, not a raw write - layout property (H4).
    pcall(function() tile.Label:SetMinDesiredWidth(130.0) end)

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
