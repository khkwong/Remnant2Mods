print("[ZZTestMod] Loaded and running (idle - no active diagnostic).\n")

-- Research scratchpad only. Feature code lives in MoreLoadoutSlots/Scripts/main.lua.
--
-- Currently idle. Past diagnostics are recoverable from git history:
--   - LoadoutComponent Slots/NumRecords structure dump
--   - RegisterHook self:get() safety test (PASSED - always unwrap with self:get(), never
--     touch the raw RemoteUnrealParam wrapper)
--   - Three-path input logger (mapped F/Space/RMB/LMB to their dispatch paths and the
--     E_TooltipContextAction enum byte values)
--   - First-launch NotifyOnNewObject quirk diagnostic (obsolete: fixed by the UE4SS
--     experimental-latest upgrade)
--   - Multicast delegate stage-1 test (PASSED under experimental UE4SS: reading
--     tile.OnClicked returns a MulticastDelegateProperty userdata with
--     Add/Remove/Clear/Broadcast - the 3.0.1 pcall-piercing abort is gone; API is
--     delegate:Add(targetUObject, FName("FunctionName")))
