print("[EquipmentSearch] Loaded and running.\n")

-- EquipmentSearch: adds a working text search to the inventory item grids
-- (rings, amulets, armor, relics, weapons - plus the materials/quest/usable
-- lists, which use the same widget class).
--
-- The game ships a hidden, half-finished search filter widget
-- (Widget_InventorySearchFilter inside Widget_InventoryList). Its bar and text
-- box render fine once unhidden, but its filtering pipeline is dead (keyword
-- DataTable shipped empty) and every vanilla grid-rebuild entry point
-- early-outs when nothing changed, so the matching AND the hiding are ours:
-- on query change we walk the grid's card children and SetVisibility per
-- match. Matching text per ItemID comes from each card's Get_InspectInfo
-- (Label/SubLabel/FlavorText plus the Stats/Mods effect arrays), cached per
-- session. Full findings: docs/remnant2-modding-research.md 3.6b.

local LIST_CLASS_PATH = "/Game/UI/UI_Inventory/Widget_InventoryList.Widget_InventoryList_C"
local FILTER_CLASS = "/Game/UI/UI_Inventory/Widget_InventorySearchFilter.Widget_InventorySearchFilter_C"

local TEXTCHANGED_FUNC_PATH = FILTER_CLASS
    .. ":BndEvt__Widget_InventorySearchFilter_SearchFilterText_K2Node_ComponentBoundEvent_1_OnEditableTextBoxChangedEvent__DelegateSignature"
-- the X button clears the box WITHOUT firing OnTextChanged (traced), so its
-- clicked event needs its own hook
local XBUTTON_FUNC_PATH = FILTER_CLASS
    .. ":BndEvt__Widget_InventorySearchFilter_Button_246_K2Node_ComponentBoundEvent_3_OnButtonClickedEvent__DelegateSignature"
-- the game's own grid passes; post-hooked to re-apply our filter after
-- vanilla rebuilds ('Update Inventory List' covers equip/pickup refreshes,
-- 'Build Inventory List' covers popup reopen / tab construction)
local LIST_UPDATE_FUNC_PATH = LIST_CLASS_PATH .. ":Update Inventory List"
local LIST_BUILD_FUNC_PATH  = LIST_CLASS_PATH .. ":Build Inventory List"

local VISIBLE   = 0  -- ESlateVisibility::Visible
local COLLAPSED = 1  -- ESlateVisibility::Collapsed

-- Every live list gets its own entry: several instances coexist (equipment
-- screen + the materials/quest/usable lists on the Inventory tab), and a
-- single "current list" variable caused text changes on one list to stomp the
-- filter state of another. Keyed by list full name; pruned when invalid.
-- entry = { list = <widget>, box = <text box>, query = <lowercased string> }
local trackedLists = {}

-- ItemID -> lowercased searchable text. Session-lifetime, built lazily from
-- each list's own grid children (NOT the global card pool - stale pooled
-- cards from destroyed screens misreport and poisoned the cache once).
-- Known staleness: an upgraded item keeps its old cached "+N" label until
-- relaunch; name/description words still match, so acceptable.
local itemTextCache = {}

-- original visibility of cards we've hidden, keyed by card full name, so a
-- loosened query restores exactly what was there before
local hiddenCardVis = {}

-- Effect text ships with rich-text markup (<stat>7%</>, <span color=...>) and
-- embedded newlines that break phrase matching ("grey health" failed when a
-- tag or line break sat between the words). Strip tags, collapse whitespace
-- (incl. UTF-8 non-breaking spaces), lowercase. Applied to cached text and
-- queries alike so both sides normalize identically.
local function normalizeText(s)
    s = string.lower(s or "")
    s = string.gsub(s, "<[^>]*>", " ")
    s = string.gsub(s, "\194\160", " ") -- U+00A0 no-break space
    s = string.gsub(s, "%s+", " ")
    return s
end

-- The Stats/Mods arrays hold native structs; their entries arrive in Lua as
-- LocalUnrealParam wrappers (probed) that need :get() before field access.
-- Field names are resolved once at load via reflection: InspectInfo's array
-- properties -> inner struct -> its Text/Str-typed fields.
local statTextFields = {} -- e.g. { "Label", "Value" } - filled at load

local function resolveStatTextFields()
    local ok, err = pcall(function()
        local infoStruct = StaticFindObject("/Script/GunfireRuntime.InspectInfo")
        if not infoStruct or not infoStruct:IsValid() then
            print("[EquipmentSearch] InspectInfo struct not found for reflection\n")
            return
        end
        local seen = {}
        infoStruct:ForEachProperty(function(prop)
            local okProp = pcall(function()
                local full = prop:GetFullName() -- "ArrayProperty /Script/...:Stats"
                local propName = string.match(full, ":(%w+)$")
                if propName ~= "Stats" and propName ~= "Mods" then return end
                local inner = prop:GetInner()
                if not inner then return end
                local innerStruct = inner:GetStruct()
                if not innerStruct or not innerStruct:IsValid() then return end
                print("[EquipmentSearch] " .. propName .. " entry struct: "
                    .. innerStruct:GetFullName() .. "\n")
                innerStruct:ForEachProperty(function(fieldProp)
                    pcall(function()
                        local ffull = fieldProp:GetFullName()
                        print("[EquipmentSearch]   field: " .. ffull .. "\n")
                        local ftype, fname = string.match(ffull, "^(%w+) .*:(%w+)$")
                        -- FlavorText excluded by user decision: lore quotes are
                        -- not gameplay text and caused surprising matches.
                        -- NOTE: InspectMod.Label is where ring effect text
                        -- actually lives (removing it emptied all 213 caches);
                        -- Description is unused on rings.
                        if (ftype == "TextProperty" or ftype == "StrProperty")
                           and fname and fname ~= "FlavorText" and not seen[fname] then
                            seen[fname] = true
                            statTextFields[#statTextFields + 1] = fname
                        end
                    end)
                end)
            end)
        end)
        print("[EquipmentSearch] stat text fields: "
            .. table.concat(statTextFields, ", ") .. "\n")
    end)
    if not ok then
        print("[EquipmentSearch] stat field reflection FAILED: " .. tostring(err) .. "\n")
    end
end
resolveStatTextFields()

-- One-time reflection of the native Item:GetInspectInfo (the call the item
-- tooltip uses to build the COMPLETE inspect info - trigger-style rings like
-- Disaster Converter get their effect text only through this path).
do
    local ok, err = pcall(function()
        local fn = StaticFindObject("/Script/GunfireRuntime.Item:GetInspectInfo")
        if not fn or not fn:IsValid() then
            print("[EquipmentSearch] Item:GetInspectInfo not found via reflection\n")
            return
        end
        print("[EquipmentSearch] Item:GetInspectInfo params:\n")
        fn:ForEachProperty(function(prop)
            pcall(function()
                print("[EquipmentSearch]   " .. prop:GetFullName() .. "\n")
            end)
        end)
    end)
    if not ok then
        print("[EquipmentSearch] GetInspectInfo reflection error: " .. tostring(err) .. "\n")
    end
end

-- One-time reflection of the InventoryItem struct (what the card's
-- Get_InventoryItem returns) - looking for the field holding the item's BP
-- class, whose default object is the receiver for Item:GetInspectInfo.
do
    local ok, err = pcall(function()
        local s = StaticFindObject("/Script/GunfireRuntime.InventoryItem")
        if not s or not s:IsValid() then
            print("[EquipmentSearch] InventoryItem struct not found via reflection\n")
            return
        end
        print("[EquipmentSearch] InventoryItem fields:\n")
        s:ForEachProperty(function(prop)
            pcall(function()
                print("[EquipmentSearch]   " .. prop:GetFullName() .. "\n")
            end)
        end)
    end)
    if not ok then
        print("[EquipmentSearch] InventoryItem reflection error: " .. tostring(err) .. "\n")
    end
end

-- one-time diagnostic of what InspectObject actually points at (trim later)
local dumpedInspectObject = false
local dumpedInventoryItem = false
local dumpedFallbackActor = false

-- ItemIDs whose cached text is name-only (no effect text found anywhere);
-- '!?' in the search box lists them
local nameOnlyItems = {}

-- the native-call fallback self-disables after this many errors
local fallbackErrors = 0

-- Pull display strings out of a Stats/Mods array. Out-param arrays arrive as
-- Lua tables of LocalUnrealParam-wrapped structs; arrays read off a returned
-- struct arrive as TArray userdata (# and [i] indexing).
local function extractTexts(arr, parts)
    local entries = {}
    if type(arr) == "table" then
        for _, e in pairs(arr) do entries[#entries + 1] = e end
    elseif type(arr) == "userdata" then
        pcall(function()
            for i = 1, #arr do entries[#entries + 1] = arr[i] end
        end)
    else
        return
    end
    for _, entry in ipairs(entries) do
        pcall(function()
            local unwrapped = entry
            if type(entry) == "userdata" then
                local okGet, inner = pcall(function() return entry:get() end)
                if okGet and inner ~= nil then unwrapped = inner end
            end
            local gotText = false
            for _, field in ipairs(statTextFields) do
                pcall(function()
                    local v = unwrapped[field]
                    if v ~= nil then
                        local okStr, s = pcall(function() return v:ToString() end)
                        if okStr and type(s) == "string" and s ~= "" then
                            parts[#parts + 1] = s
                            if field == "Description" then gotText = true end
                        end
                    end
                end)
            end
            -- trigger-style effects (Disaster Converter etc.) ship an empty
            -- Description; their text lives on the referenced perk object
            if not gotText then
                pcall(function()
                    local obj = unwrapped.InspectObject
                    if obj == nil or not obj:IsValid() then return end
                    if not dumpedInspectObject then
                        dumpedInspectObject = true
                        print("[EquipmentSearch] DIAG InspectObject: "
                            .. obj:GetFullName() .. "\n")
                    end
                    for _, field in ipairs({ "Description", "Label", "TooltipText" }) do
                        pcall(function()
                            local v = obj[field]
                            if v ~= nil then
                                local okStr, s = pcall(function() return v:ToString() end)
                                if okStr and type(s) == "string" and s ~= "" then
                                    parts[#parts + 1] = s
                                end
                            end
                        end)
                    end
                end)
            end
        end)
    end
end

-- Build cache entries for grid cards whose ItemID we haven't seen yet.
-- Game thread only: Get_InspectInfo is a BlueprintPure BP call with a struct
-- out param (UE4SS spreads the struct's fields into the passed table - probed).
local function ensureItemTextCache(list)
    if not list or not list:IsValid() then return end
    local added = 0
    local firstErr = nil
    local okGrid, gridErr = pcall(function()
        local grid = list.InventoryGrid
        if not grid or not grid:IsValid() then return end
        local n = grid:GetChildrenCount()
        for i = 0, n - 1 do
            local okCard, cardErr = pcall(function()
                local card = grid:GetChildAt(i)
                if not card or not card:IsValid() then return end
                local id = card.ItemID
                if not id or id == 0 or itemTextCache[id] then return end

                local info = {}
                card:Get_InspectInfo(info)
                -- InspectInfo.Description (lore paragraph) and FlavorText
                -- (quoted lore) intentionally excluded: not gameplay text
                -- (user decision) - the search covers name, type, and the
                -- effect text from the Stats/Mods arrays
                local parts = {}
                for _, field in ipairs({ "Label", "SubLabel" }) do
                    local v = info[field]
                    if v ~= nil then
                        local okStr, str = pcall(function() return v:ToString() end)
                        if okStr and str then parts[#parts + 1] = str end
                    end
                end
                -- the gameplay-effect text ("Increases Melee damage...") lives
                -- in the Mods array's Label field, not on InspectInfo itself
                extractTexts(info.Stats, parts)
                extractTexts(info.Mods, parts)

                -- "no effect text" means: nothing beyond Label/SubLabel except
                -- name echoes (Momentum Driver's mod Label repeats the item
                -- name - a plain part count misses it)
                local labelNorm = normalizeText(parts[1] or "")
                local hasEffect = false
                for i = 3, #parts do
                    local p = normalizeText(parts[i])
                    p = string.match(p, "^%s*(.-)%s*$")
                    if p ~= "" and p ~= labelNorm then hasEffect = true end
                end

                -- fallback for trigger-style items (30 rings, listed by '!?'):
                -- their effect text is GENERATED at display time by each
                -- ring's ModifyInspectInfo override (FText::Format - see
                -- Ring_OfferingStone.json ~318), not stored anywhere readable.
                -- Calling ModifyInspectInfo from the cache loop hard-crashed
                -- the game (2026-07-14); the call is DISABLED here until the
                -- ZZTestMod single-item probe (F4) finds a safe calling
                -- convention. Until then these 30 match by name only.
                if false and not hasEffect and fallbackErrors < 3 then
                    local okFb, fbErr = pcall(function()
                        local inv = {}
                        card:Get_InventoryItem(inv)
                        local bp = inv.ItemBP
                        pcall(function() bp = bp:get() end)
                        if bp == nil or not bp:IsValid() then return end

                        -- the class's default object is the callable Item
                        local cdo = nil
                        pcall(function() cdo = bp:GetCDO() end)
                        if cdo == nil or not cdo:IsValid() then
                            -- fallback: build the Default__ object path from
                            -- the class full name
                            local full = bp:GetFullName()
                            local path = string.match(full, "%s(.+)$") or full
                            local pkg, cls = string.match(path, "^(.*)%.([^%.]+)$")
                            if pkg and cls then
                                cdo = StaticFindObject(pkg .. ".Default__" .. cls)
                            end
                        end
                        if cdo == nil or not cdo:IsValid() then
                            print("[EquipmentSearch] fallback: no CDO for "
                                .. tostring(bp:GetFullName()) .. "\n")
                            return
                        end

                        local instance = inv.InstanceData
                        pcall(function() instance = instance:get() end)

                        -- Actor=nil returned Mods len=0 (Offering Stone dump):
                        -- no effect text. Trigger-effect text is presumably
                        -- computed against the owning actor, so pass the
                        -- player character (the instance data's outer).
                        local actor = nil
                        pcall(function()
                            local outer = instance:GetOuter()
                            if outer and outer:IsValid() then actor = outer end
                        end)
                        if actor == nil then
                            pcall(function()
                                local pawn = FindFirstOf("Character_Master_Player_C")
                                if pawn and pawn:IsValid() then actor = pawn end
                            end)
                        end
                        if not dumpedFallbackActor and actor ~= nil then
                            dumpedFallbackActor = true
                            print("[EquipmentSearch] DIAG fallback Actor: "
                                .. actor:GetFullName() .. "\n")
                        end

                        -- The effect text is GENERATED, not stored: trigger
                        -- rings override ModifyInspectInfo(Actor, InInstance-
                        -- Data, Info ref, HideBaseStats out) and build the
                        -- sentence with FText::Format (Ring_OfferingStone.json
                        -- ~318). Call it on the CDO with an empty Info: lore
                        -- comes from the base item data we are NOT passing in,
                        -- so whatever lands in Info is pure effect text.
                        local infoOut = {}
                        local hbsOut = {}
                        cdo:ModifyInspectInfo(actor, instance, infoOut, hbsOut)
                        if not dumpedInventoryItem then
                            dumpedInventoryItem = true
                            print(string.format(
                                "[EquipmentSearch] DIAG ModifyInspectInfo ItemID=%d via %s returned:\n",
                                id, cdo:GetFullName()))
                            for k, v in pairs(infoOut) do
                                local val = v
                                pcall(function() val = v:get() end)
                                local desc = tostring(val)
                                pcall(function() desc = val:ToString() end)
                                pcall(function() desc = val:GetFullName() end)
                                pcall(function() desc = desc .. " (len=" .. #val .. ")" end)
                                print(string.format("[EquipmentSearch]   .%s = %s\n",
                                    tostring(k), desc))
                            end
                        end
                        pcall(function()
                            local d = infoOut.Description
                            pcall(function() d = d:get() end)
                            if d ~= nil then
                                local okStr, s = pcall(function() return d:ToString() end)
                                if okStr and s and s ~= "" then parts[#parts + 1] = s end
                            end
                        end)
                        extractTexts(infoOut.Stats, parts)
                        extractTexts(infoOut.Mods, parts)
                    end)
                    if not okFb then
                        fallbackErrors = fallbackErrors + 1
                        print("[EquipmentSearch] item-object fallback error ("
                            .. fallbackErrors .. "/3): " .. tostring(fbErr) .. "\n")
                    end
                end

                -- anything still name-only here won't match description
                -- searches - '!?' lists these (the known-limitation set).
                -- Recheck: the fallback may have appended parts above.
                if not hasEffect then
                    for i = 3, #parts do
                        local p = normalizeText(parts[i])
                        p = string.match(p, "^%s*(.-)%s*$")
                        if p ~= "" and p ~= labelNorm then hasEffect = true end
                    end
                end
                nameOnlyItems[id] = (not hasEffect) or nil
                itemTextCache[id] = normalizeText(table.concat(parts, " "))
                added = added + 1
            end)
            -- per-card pcall: one bad card must not abort the whole cache pass
            if not okCard and not firstErr then firstErr = tostring(cardErr) end
        end
    end)
    if not okGrid then firstErr = firstErr or tostring(gridErr) end
    if added > 0 then
        print(string.format("[EquipmentSearch] cached search text for %d new item(s)\n", added))
    end
    if firstErr then
        print("[EquipmentSearch] cache pass error (first): " .. firstErr .. "\n")
    end
end

-- Walk one list's grid children and toggle visibility per match. Game thread
-- only. Collapsed reflows the WrapBox so matches flow together; restoring
-- uses each card's own recorded pre-hide visibility.
local function applyFilter(entry, verbose)
    local list, query = entry.list, entry.query
    if not list or not list:IsValid() then return end
    local shown, hidden = 0, 0
    local okApply, applyErr = pcall(function()
        local grid = list.InventoryGrid
        if not grid or not grid:IsValid() then return end
        local n = grid:GetChildrenCount()
        for i = 0, n - 1 do
            pcall(function()
                local card = grid:GetChildAt(i)
                if not card or not card:IsValid() then return end
                local id = card.ItemID
                if not id then return end -- not an item card; leave alone

                local text = itemTextCache[id]
                local matches = query == ""
                    or (text ~= nil and string.find(text, query, 1, true) ~= nil)
                local key = card:GetFullName()

                if matches then
                    if hiddenCardVis[key] ~= nil then
                        card:SetVisibility(hiddenCardVis[key])
                        hiddenCardVis[key] = nil
                    end
                    shown = shown + 1
                    -- diagnostic (trim later): what text did the first few
                    -- matches match on?
                    if verbose and query ~= "" and shown <= 3 then
                        print(string.format("[EquipmentSearch]   match ItemID=%d text='%s'\n",
                            id, string.sub(text or "<nil>", 1, 120)))
                    end
                else
                    if hiddenCardVis[key] == nil then
                        hiddenCardVis[key] = card.Visibility
                    end
                    card:SetVisibility(COLLAPSED)
                    hidden = hidden + 1
                end
            end)
        end
    end)
    if not okApply then
        print("[EquipmentSearch] applyFilter error: " .. tostring(applyErr) .. "\n")
        return
    end
    if verbose then
        print(string.format("[EquipmentSearch] filter applied: %d shown, %d hidden\n",
            shown, hidden)) -- test aid, trim later
    end
end

-- Sync every tracked list against its own text box. Runs on the game thread
-- only (never from inside a hook body directly - H8). Prunes dead entries.
local function refreshAllLists(forceApply)
    for key, entry in pairs(trackedLists) do
        local ok, err = pcall(function()
            if not entry.list:IsValid() or not entry.box:IsValid() then
                trackedLists[key] = nil
                return
            end
            local query = normalizeText(entry.box.Text:ToString())
            query = string.match(query, "^%s*(.-)%s*$") -- trim edges
            -- debug commands (trim before release): '!<word>' dumps the FULL
            -- cached text of every item containing <word>; '!!' clears the
            -- cache so the next keystroke rebuilds it fresh; '!?' lists every
            -- item whose cache is name-only (won't match description search)
            if string.sub(query, 1, 1) == "!" then
                local needle = string.sub(query, 2)
                if needle == "!" then
                    itemTextCache = {}
                    nameOnlyItems = {}
                    print("[EquipmentSearch] item text cache cleared\n")
                    needle = ""
                elseif needle == "?" then
                    local count = 0
                    for id in pairs(nameOnlyItems) do
                        count = count + 1
                        print(string.format("[EquipmentSearch] NAME-ONLY ItemID=%d: %s\n",
                            id, tostring(itemTextCache[id])))
                    end
                    print(string.format("[EquipmentSearch] %d name-only item(s) total\n", count))
                    needle = ""
                end
                if #needle >= 2 then
                    for id, text in pairs(itemTextCache) do
                        if string.find(text, needle, 1, true) then
                            print(string.format("[EquipmentSearch] DUMP ItemID=%d:\n%s\n---\n",
                                id, text))
                        end
                    end
                end
                query = "" -- show the full grid while debugging
            end
            if query ~= entry.query then
                entry.query = query
                print("[EquipmentSearch] query: '" .. query .. "'\n") -- test aid
                ensureItemTextCache(entry.list)
                applyFilter(entry, true)
            elseif forceApply and query ~= "" then
                -- silent pass: watchdog / vanilla-rebuild re-apply
                ensureItemTextCache(entry.list)
                applyFilter(entry, false)
            end
        end)
        if not ok then
            print("[EquipmentSearch] refresh error: " .. tostring(err) .. "\n")
            trackedLists[key] = nil
        end
    end
end

-- Un-hide the search bar on one freshly-constructed list instance.
-- Two hiding layers (research doc 3.6b): the filter child itself (inert
-- CanSeeSearchBar binding evaluates a few times during construction) and the
-- SearchFilterText box (Collapsed at the asset level). The combo box is
-- vanilla-functional but redundant with the W-filters screen - collapse it.
local function showSearchBar(list)
    local filter = list.Widget_InventorySearchFilter
    if not filter or not filter:IsValid() then
        return false, "filter child not valid"
    end
    local box = filter.SearchFilterText
    if not box or not box:IsValid() then
        return false, "SearchFilterText not valid"
    end

    filter:SetVisibility(VISIBLE)
    box:SetVisibility(VISIBLE)

    local okCombo, comboErr = pcall(function()
        local combo = filter.ComboBoxKey_58
        if combo and combo:IsValid() then combo:SetVisibility(COLLAPSED) end
    end)
    if not okCombo then
        -- cosmetic only - log and carry on
        print("[EquipmentSearch] combo collapse failed: " .. tostring(comboErr) .. "\n")
    end
    return true, box
end

-- Hooks on /Game/ classes can only be registered once the Blueprint is loaded
-- (fails with 'no UFunction found' at mod start on a fresh launch - research
-- doc 3.6b), so registration is deferred to the first successful capture.
local hooksRegistered = false
local function registerHooksOnce()
    if hooksRegistered then return end

    local ok, err = pcall(function()
        -- fires per keystroke (proven). Hook bodies defer to the game thread;
        -- no native calls in hook context. Which box changed doesn't matter -
        -- the sync pass reads every tracked list's own box.
        RegisterHook(TEXTCHANGED_FUNC_PATH, function()
            ExecuteInGameThread(function() refreshAllLists(false) end)
        end)

        -- X button: box is now empty; the sync pass restores that list's grid
        RegisterHook(XBUTTON_FUNC_PATH, function()
            ExecuteInGameThread(function() refreshAllLists(false) end)
        end)

        -- re-apply after the game's own grid passes (tab switch, equip,
        -- pickup, popup reopen). Build repopulates cards asynchronously, so
        -- re-apply again after a short delay - an immediate pass alone left
        -- reopened popups unfiltered.
        local function reapplyAfterVanillaPass()
            ExecuteInGameThread(function() refreshAllLists(true) end)
            LoopAsync(150, function()
                ExecuteInGameThread(function() refreshAllLists(true) end)
                return true -- one-shot
            end)
        end
        RegisterHook(LIST_UPDATE_FUNC_PATH, function() end, reapplyAfterVanillaPass)
        RegisterHook(LIST_BUILD_FUNC_PATH,  function() end, reapplyAfterVanillaPass)

        -- watchdog: the game has rebuild paths that bypass Update/Build (the
        -- equip -> popup-reopen flow reset the grid to unfiltered). Instead of
        -- chasing every entry point, silently re-apply active filters on a
        -- short interval; a full pass measured ~2ms, so this is cheap.
        LoopAsync(300, function()
            local anyActive = false
            for _, entry in pairs(trackedLists) do
                if entry.query ~= "" then anyActive = true break end
            end
            if anyActive then
                ExecuteInGameThread(function() refreshAllLists(true) end)
            end
            return false -- keep running for the mod's lifetime
        end)
    end)

    if ok then
        hooksRegistered = true
        print("[EquipmentSearch] hooks registered (TextChanged, X button, Update/Build passes).\n")
    else
        print("[EquipmentSearch] hook registration FAILED: " .. tostring(err) .. "\n")
    end
end

-- Widget capture skeleton (proven in MoreLoadoutSlots/LoadoutNamer): notify on
-- construction, poll until children are initialized, then do widget work on
-- the game thread. The visibility gate binding fires a few times during
-- construction, so we apply once the filter child reports valid; the binding
-- is inert afterwards and our write sticks.
NotifyOnNewObject(LIST_CLASS_PATH, function(list)
    local attempts = 0
    local MAX_ATTEMPTS = 40 -- ~2s at 50ms per attempt

    LoopAsync(50, function()
        attempts = attempts + 1

        -- cheap readiness check: keep polling until the filter child and its
        -- text box are initialized
        local ready = false
        local okCheck = pcall(function()
            if list:IsValid() then
                local filter = list.Widget_InventorySearchFilter
                if filter and filter:IsValid() then
                    local box = filter.SearchFilterText
                    ready = box and box:IsValid()
                end
            end
        end)

        if not okCheck or not ready then
            if attempts >= MAX_ATTEMPTS then
                print("[EquipmentSearch] Gave up waiting for the search filter child "
                    .. "to initialize (" .. attempts .. " polls) - bar not enabled "
                    .. "for this screen.\n")
                return true -- stop looping
            end
            return false -- keep polling
        end

        -- children ready - do the widget work on the game thread
        ExecuteInGameThread(function()
            local ok, err = pcall(function()
                local shown, boxOrWhy = showSearchBar(list)
                if shown then
                    trackedLists[list:GetFullName()] = {
                        list = list, box = boxOrWhy, query = "",
                    }
                    registerHooksOnce()
                    print("[EquipmentSearch] Search bar enabled on "
                        .. list:GetFullName() .. "\n")
                    -- the CanSeeSearchBar binding still evaluates a few times
                    -- during construction and could stomp an early write - one
                    -- delayed re-apply covers that window (it's inert after)
                    LoopAsync(500, function()
                        ExecuteInGameThread(function()
                            pcall(function()
                                if list:IsValid() then showSearchBar(list) end
                            end)
                        end)
                        return true -- one-shot
                    end)
                else
                    print("[EquipmentSearch] Search bar NOT enabled: "
                        .. tostring(boxOrWhy) .. "\n")
                end
            end)
            if not ok then
                print("[EquipmentSearch] showSearchBar error: " .. tostring(err) .. "\n")
            end
        end)
        return true -- stop looping
    end)
end)
