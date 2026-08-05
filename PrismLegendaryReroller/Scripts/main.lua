print("[PrismLegendaryReroller] Loaded and running.\n")

-- Mod #5: cleansing a Prism's legendary (Mythic) bonus no longer costs a relevel.
--
-- Vanilla behavior: a maxed (level 51) Prism with a rolled legendary bonus can be
-- "cleansed" to reroll just that bonus. This calls APrismStone::ServerFlushSegment
-- on the Mythic segment's index, which removes that one segment and leaves every
-- other rolled stat segment untouched - but the Prism's level (a value COMPUTED
-- from segment content, not a stored field) drops from 51 to 50 as a side effect,
-- forcing a full relevel grind just to be allowed to roll again. (This is distinct
-- from the separate "cleanse the whole Prism" action, ServerFlushPrismStone, which
-- resets everything to 0 - untouched by this mod, on purpose.)
--
-- Fix: hook ServerFlushSegment. If the Prism was at level 51 right before the call
-- (the only way a Mythic segment can exist to flush in the first place - proven
-- signal, see docs/remnant2-modding-research.md), grant back exactly the experience
-- needed to reach 51 again via the game's own AddExperience() (the same function
-- combat kills/feeding use - "prefer the game's own machinery" per CLAUDE.md), once
-- the flush has actually applied. This makes the Prism immediately eligible to roll
-- again (CanRoll flips true) without an artificial relevel.
--
-- Proven building blocks (ZZTestMod probe, 2026-08-04):
-- - Hook path: "/Script/Remnant.PrismStone:ServerFlushSegment" (native /Script/ path
--   -> single-callback form is a PRE-hook, fires before the real flush runs).
-- - Registered at TOP LEVEL, not nested inside a ClientRestart hook: APrismStone is
--   a native engine class, its UFunctions are already resident at script-load time.
--   (Nesting inside ClientRestart was tried first and never fired on a hot-reload,
--   since that event already happened earlier in the play session and hot-reload
--   doesn't respawn the character.)
-- - Calling a native no-arg getter (GetPrismStoneLevel()) SYNCHRONOUSLY inside the
--   hook body, after self:get(), is safe - confirmed crash-free and correct (read
--   51 right before a flush that would drop it to 50). This was a novel operation
--   for this project (every prior hook only read wrapped param values or plain
--   properties in the hook body; further native calls were always deferred via
--   ExecuteInGameThread) - now proven safe for this specific read.
-- - GetExperienceRequiredForLevel(51) + AddExperience() (both APrismStone functions)
--   reliably relevel a Prism and flip CanRoll back to true - confirmed with a real
--   in-game legendary reroll (F11 test step, ZZTestMod).

local function relevelToFullAfterMythicFlush(prismObj)
  local okLevel, level = pcall(function() return prismObj:GetPrismStoneLevel() end)
  if not okLevel then
    print(string.format("[PrismLegendaryReroller] post-flush GetPrismStoneLevel() FAILED: %s\n", tostring(level)))
    return
  end
  if level >= 51 then
    return
  end

  local okReq, required = pcall(function() return prismObj:GetExperienceRequiredForLevel(51) end)
  if not okReq then
    print(string.format("[PrismLegendaryReroller] GetExperienceRequiredForLevel(51) FAILED: %s\n", tostring(required)))
    return
  end

  local okAdd, addErr = pcall(function() prismObj:AddExperience(required) end)
  if not okAdd then
    print(string.format("[PrismLegendaryReroller] AddExperience(%s) FAILED: %s\n", tostring(required), tostring(addErr)))
    return
  end

  print(string.format("[PrismLegendaryReroller] Legendary cleanse detected - restored level 51 (AddExperience %s).\n", tostring(required)))
end

local hookOk, hookErr = pcall(function()
  RegisterHook("/Script/Remnant.PrismStone:ServerFlushSegment", function(selfParam, SegmentIndexParam, NumRefundLevelsParam)
    local okSelf, prismObj = pcall(function() return selfParam:get() end)
    if not okSelf then
      print(string.format("[PrismLegendaryReroller] self:get() FAILED: %s\n", tostring(prismObj)))
      return
    end

    -- Pre-flush level is the reliable signal: a Mythic segment can only exist on a
    -- level-51 Prism, so this can only be true for a legendary-bonus cleanse, never
    -- a regular segment reroll (which happens at any level, with the vanilla level
    -- cost paid through NumRefundLevels instead).
    local okPreLevel, preLevel = pcall(function() return prismObj:GetPrismStoneLevel() end)
    if not okPreLevel then
      print(string.format("[PrismLegendaryReroller] pre-flush GetPrismStoneLevel() FAILED: %s\n", tostring(preLevel)))
      return
    end
    if preLevel ~= 51 then
      return
    end

    ExecuteInGameThread(function()
      relevelToFullAfterMythicFlush(prismObj)
    end)
  end)
end)

if not hookOk then
  print(string.format("[PrismLegendaryReroller] WARNING: failed to register hook on ServerFlushSegment: %s\n", tostring(hookErr)))
else
  print("[PrismLegendaryReroller] Ready - legendary Prism cleanses will no longer drop you to level 50.\n")
end
