print("[ZZTestMod] Loaded and running.\n")

-- Research scratchpad only. Feature code lives in MoreLoadoutSlots/Scripts/main.lua.
--
-- CURRENT TEST: why does NotifyOnNewObject only fire after one hot-reload per play session?
--
-- Theory: NotifyOnNewObject resolves its class-path argument to the actual UClass object AT
-- REGISTRATION TIME. At mod startup (game just launched, main menu, no world), the
-- Widget_LoadoutsPanel_C Blueprint class isn't loaded yet, so the registration binds to
-- nothing and silently never matches. A hot-reload done later in the session re-registers
-- everything at a time when the class IS loaded, which is why the one-throwaway-hot-reload
-- workaround has been needed.
--
-- This diagnostic tests the theory AND the fix in one run:
--   1. Logs whether the panel class is loaded (StaticFindObject succeeds) at mod startup,
--      at player spawn (ClientRestart), and every 2 seconds after that.
--   2. The moment the class becomes loaded, registers a LATE NotifyOnNewObject for it.
--   3. On the session's first Loadouts-screen open (NO hot-reload beforehand!):
--      - if only the LATE registration fires (this mod prints, MoreLoadoutSlots doesn't),
--        the theory is confirmed and delayed registration is the fix;
--      - if both fire, the quirk is something else entirely (timing, not class resolution).
--
-- TEST PROCEDURE: full game relaunch, do NOT hot-reload at any point, load into the
-- character, wait a few seconds, open the Loadouts screen. Send the whole log.

local PANEL_CLASS_PATH = "/Game/UI2/UI_Widgets/UI_Game/UI_Game_Character/Widget_LoadoutsPanel.Widget_LoadoutsPanel_C"

local function panelClassStatus()
  local ok, cls = pcall(function() return StaticFindObject(PANEL_CLASS_PATH) end)
  if ok and cls and cls:IsValid() then
    return true, "LOADED"
  end
  return false, "not loaded yet"
end

local _, startupStatus = panelClassStatus()
print(string.format("[ZZTestMod] Panel class (Widget_LoadoutsPanel_C) at mod startup: %s\n", startupStatus))

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
  local _, status = panelClassStatus()
  print(string.format("[ZZTestMod] Panel class at player spawn (ClientRestart): %s\n", status))
end)

local lateHookRegistered = false
local pollCount = 0
local MAX_POLLS = 150 -- 5 minutes at 2s per poll, then give up

LoopAsync(2000, function()
  pollCount = pollCount + 1

  local loaded, status = panelClassStatus()
  if not loaded then
    -- Only log every 5th miss to keep the log readable while still showing the timeline.
    if pollCount % 5 == 0 then
      print(string.format("[ZZTestMod] Panel class still %s (%d seconds since startup).\n", status, pollCount * 2))
    end
    return pollCount >= MAX_POLLS -- true stops the loop (give-up case)
  end

  if not lateHookRegistered then
    lateHookRegistered = true
    print(string.format("[ZZTestMod] Panel class became LOADED (~%d seconds after startup) - registering the LATE NotifyOnNewObject now.\n", pollCount * 2))
    local ok, err = pcall(function()
      NotifyOnNewObject(PANEL_CLASS_PATH, function(panel)
        print("[ZZTestMod] LATE-registered NotifyOnNewObject FIRED for a new Loadouts panel instance. (If MoreLoadoutSlots' startup-registered callback did NOT also fire for this same screen-open, the registration-time class-resolution theory is confirmed.)\n")
      end)
    end)
    if not ok then
      print("[ZZTestMod] FAILED to register the late NotifyOnNewObject: " .. tostring(err) .. "\n")
    end
  end
  return true -- class found and late hook handled; stop polling
end)
