print("[ZZTestMod] Loaded and running.\n")

-- Research scratchpad only. This mod does NOT contain the "add extra loadout slot" feature -
-- that logic now lives in MoreLoadoutSlots/Scripts/main.lua as its own standalone mod. This
-- file stays focused on live inspection/diagnostics for whatever's currently being
-- investigated, and gets rewritten between research sessions rather than accumulating
-- unrelated feature logic.

-- Diagnostic: on every player spawn, dump the live LoadoutComponent's Slots array - reads
-- NumRecords (how many saved loadout records the backing data supports) and cross-checks it
-- against LoadoutComponent:GetMaxRecordsForTemplate(Template) (a UFunction on the same
-- component that the Loadouts screen's tile-count logic actually calls - confirmed via
-- Widget_LoadoutsPanel_C's Refresh function - rather than reading NumRecords directly).
-- Patches NumRecords to 20 mid-dump to confirm GetMaxRecordsForTemplate reflects live writes.
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, NewPawn)
  print("[ZZTestMod] Player spawned (ClientRestart fired).\n")

  ExecuteInGameThread(function()
    local components = FindAllOf("LoadoutComponent")
    if not components then
      print("[ZZTestMod] No live LoadoutComponent instances found yet (character may not be fully spawned).\n")
      return
    end

    print(string.format(
      "[ZZTestMod] Found %d live LoadoutComponent instance(s) - Remnant 2 characters commonly have 2 simultaneously (cause not fully root-caused; see docs/remnant2-modding-research.md).\n",
      #components
    ))

    for i, comp in ipairs(components) do
      if comp:IsValid() then
        print(string.format("[ZZTestMod] LoadoutComponent #%d: %s\n", i, comp:GetFullName()))

        local ok, slots = pcall(function() return comp.Slots end)
        if not ok or not slots then
          print("[ZZTestMod]   Could not read this component's Slots array.\n")
        else
          for j = 1, #slots do
            local slot = slots[j]
            local numRecords = "?"
            local templateName = "?"
            pcall(function() numRecords = tostring(slot.NumRecords) end)
            pcall(function() templateName = slot.Template:IsValid() and slot.Template:GetFullName() or "invalid" end)
            print(string.format(
              "[ZZTestMod]   Slot %d: NumRecords (raw data field, how many loadout records this template's backing storage supports) = %s, Template = %s\n",
              j, numRecords, templateName
            ))

            local maxOk1, maxResult1 = pcall(function()
              return comp:GetMaxRecordsForTemplate(slot.Template)
            end)
            if maxOk1 then
              print(string.format(
                "[ZZTestMod]   Slot %d: GetMaxRecordsForTemplate() BEFORE patching NumRecords = %s (this is the function the Loadouts screen's tile-count logic actually calls, not the raw field above)\n",
                j, tostring(maxResult1)
              ))
            else
              print(string.format("[ZZTestMod]   Slot %d: FAILED to call GetMaxRecordsForTemplate - %s\n", j, tostring(maxResult1)))
            end

            local patchOk, patchErr = pcall(function() slot.NumRecords = 20 end)
            if patchOk then
              print(string.format("[ZZTestMod]   Slot %d: patched the raw NumRecords field to 20.\n", j))
            else
              print(string.format("[ZZTestMod]   Slot %d: FAILED to patch NumRecords - %s\n", j, tostring(patchErr)))
            end

            local maxOk2, maxResult2 = pcall(function()
              return comp:GetMaxRecordsForTemplate(slot.Template)
            end)
            if maxOk2 then
              print(string.format(
                "[ZZTestMod]   Slot %d: GetMaxRecordsForTemplate() AFTER patching NumRecords = %s (should now read 20 if the function directly proxies the field)\n",
                j, tostring(maxResult2)
              ))
            else
              print(string.format("[ZZTestMod]   Slot %d: FAILED to call GetMaxRecordsForTemplate (after patch) - %s\n", j, tostring(maxResult2)))
            end
          end
        end
      end
    end
  end)
end)
