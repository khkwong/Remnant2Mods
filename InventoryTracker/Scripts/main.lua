print("[InventoryTracker] Loaded and running.\n")

-- InventoryTracker: shows which unique equippable items the player currently
-- has vs. what's missing. Phase 1 scope: rings + amulets only (proof of
-- concept before generalizing to armor/weapons/mods/archetypes/mutators/
-- traits/consumables - see docs/remnant2-modding-research.md 3.10 for why
-- those categories need different logic).
--
-- CONFIRMED CEILING (research doc 3.10): the game has no persistent "ever
-- obtained" flag anywhere in native reflection. This mod can only ever
-- reflect CURRENT inventory contents - a sold/dismantled unique will show as
-- missing again. Known, accepted limitation, not a bug.
--
-- Ownership check: scan RemnantPlayerInventoryComponent.Items (a plain
-- TArray<FInventoryItem> property, read directly - no function call) for an
-- entry whose .ItemBP class path matches the master list entry. Deliberately
-- NOT calling HasItem() - it takes a TSoftClassPtr (a struct, not a raw
-- pointer) and crashed the game when called with a raw UClass value
-- (research doc 3.10 hazard). Property reads only, per the risk ladder.
--
-- MASTER LIST: all 328 wiki-listed rings/amulets (103/103 amulets, 225/225
-- rings), built 2026-07-27 from a full FModel export of every World_*
-- Trinkets folder - the initial export under pakchunk0 missed most base-game
-- content; re-exporting under pakchunk1 found World_Base/Fae/Jungle/
-- Labyrinth/Nerud/Root's real Items/Trinkets folders
-- (dev-data/Exports/Remnant2/Content/World_*/Items/Trinkets/...). Matched by
-- normalized name (folder name, falling back to the item file's own
-- basename) against remnant2.wiki.gg's List_of_rings/List_of_amulets, plus 7
-- manual name corrections (dev-data/match_items.ps1 $manualFixes) for items
-- whose dev-internal folder/file name differs from the shipped display name
-- - 5 of those (BrightSteelRing/PanMageSigil/StrongArmBand/DowngradedRing/
-- FocusedJewel) were user-confirmed in-game 2026-07-27 (owns all 5, wiki
-- search matched cleanly).
-- Class paths come from each item's own "Package" field (exact, patch-safe);
-- display names come from the wiki since the game has no static name string
-- anywhere in its data (names are built at runtime via ModifyInspectInfo).
--
-- KNOWN GAP: BlessedNecklace (World_Base amulet) has no wiki match at all -
-- not on remnant2.wiki.gg, unclear if it's a real obtainable item, cut
-- content, or listed under a name unrelated to its asset path. Excluded
-- rather than guessed at. Everything else in the wiki list is covered.
-- 302/323 owned came back on a long-playtime save with no false positives
-- spot-checked (user-verified 2026-07-27) - pipeline considered proven.
local MASTER_LIST = {
    { category = "Amulet", name = "Abrasive Whetstone", classPath = "/Game/World_Root/Items/Trinkets/Amulets/AbrasiveWhetstone/Amulet_AbrasiveWhetstone.Amulet_AbrasiveWhetstone_C" },
    { category = "Amulet", name = "Ankh of Power", classPath = "/Game/World_Root/Items/Trinkets/Amulets/AnkhOfPower/Amulet_AnkhOfPower.Amulet_AnkhOfPower_C" },
    { category = "Amulet", name = "Beads of the Valorous", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/BeadsOfTheValorous/Amulet_BeadsOfTheValorous.Amulet_BeadsOfTheValorous_C" },
    { category = "Amulet", name = "Birthright of the Lost", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/BirthrightOfTheLost/Amulet_BirthrightOfTheLost.Amulet_BirthrightOfTheLost_C" },
    { category = "Amulet", name = "Brazen Amalgam", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/BrazenAlloy/Amulet_BrazenAlloy.Amulet_BrazenAlloy_C" },
    { category = "Amulet", name = "Brewmaster's Cork", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/BrewmastersCork/Amulet_BrewmastersCork.Amulet_BrewmastersCork_C" },
    { category = "Amulet", name = "Broken Pocket Watch", classPath = "/Game/World_Root/Items/Trinkets/Amulets/BrokenPocketWatch/Amulet_BrokenPocketWatch.Amulet_BrokenPocketWatch_C" },
    { category = "Amulet", name = "Butcher's Fetish", classPath = "/Game/World_Base/Items/Trinkets/Amulets/ButchersFetish/Amulet_ButchersFetish.Amulet_ButchersFetish_C" },
    { category = "Amulet", name = "Canine Keepsake", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/CanineKeepsake/Amulet_CanineKeepsake.Amulet_CanineKeepsake_C" },
    { category = "Amulet", name = "Cervine Keepsake", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/CervineKeepsake/Amulet_CervineKeepsake.Amulet_CervineKeepsake_C" },
    { category = "Amulet", name = "Cessation Bulbel", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/CessationBulbel/Amulet_CessationBulbel.Amulet_CessationBulbel_C" },
    { category = "Amulet", name = "Chains of Amplification", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/ChainsOfAmplification/Amulet_ChainsOfAmplification.Amulet_ChainsOfAmplification_C" },
    { category = "Amulet", name = "Chef Medal", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/ChefMedal/Amulet_ChefMedal.Amulet_ChefMedal_C" },
    { category = "Amulet", name = "Cleansing Stone", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/CleansingStone/Amulet_CleansingStone.Amulet_CleansingStone_C" },
    { category = "Amulet", name = "Core Booster", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/CoreBooster/Amulet_CoreBooster.Amulet_CoreBooster_C" },
    { category = "Amulet", name = "Cost of Betrayal", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/Cost_Of_Betrayal/Amulet_CostOfBetrayal.Amulet_CostOfBetrayal_C" },
    { category = "Amulet", name = "Crisis Core", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/CrisisCore/Amulet_CrisisCore.Amulet_CrisisCore_C" },
    { category = "Amulet", name = "Daredevil's Charm", classPath = "/Game/World_Base/Items/Trinkets/Amulets/DaredevilsCharm/Amulet_DaredevilsCharm.Amulet_DaredevilsCharm_C" },
    { category = "Amulet", name = "Death's Embrace", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/DeathsEmbrace/Amulet_DeathsEmbrace.Amulet_DeathsEmbrace_C" },
    { category = "Amulet", name = "Death-Soaked Idol", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/DeathSoakedIdol/Amulet_DeathSoakedIdol.Amulet_DeathSoakedIdol_C" },
    { category = "Amulet", name = "Decayed Margin", classPath = "/Game/World_Root/Items/Trinkets/Amulets/DecayedMargin/Amulet_DecayedMargin.Amulet_DecayedMargin_C" },
    { category = "Amulet", name = "Detonation Trigger", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/DetonationTrigger/Amulet_DetonationTrigger.Amulet_DetonationTrigger_C" },
    { category = "Amulet", name = "Difference Engine", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/DifferenceEngine/Amulet_DifferenceEngine.Amulet_DifferenceEngine_C" },
    { category = "Amulet", name = "Downward Spiral", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/DownwardSpiral/Amulet_DownwardSpiral.Amulet_DownwardSpiral_C" },
    { category = "Amulet", name = "Echo Chamber", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/EchoChamber/Amulet_EchoChamber.Amulet_EchoChamber_C" },
    { category = "Amulet", name = "Echo of the Forest", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/EchoOfTheForest/Amulet_EchoOfTheForest.Amulet_EchoOfTheForest_C" },
    { category = "Amulet", name = "Effigy Pendant", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/EffigyPendant/Amulet_EffigyPendant.Amulet_EffigyPendant_C" },
    { category = "Amulet", name = "Effluvium Enhancer", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/EffluviumEnhancer/Amulet_EffluviumEnhancer.Amulet_EffluviumEnhancer_C" },
    { category = "Amulet", name = "Emergency Switch", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/EmergencySwitch/Amulet_EmergencySwitch.Amulet_EmergencySwitch_C" },
    { category = "Amulet", name = "Energized Neck Coil", classPath = "/Game/World_Labyrinth/Items/Trinkets/Amulets/EnergizedNeckCoil/Amulet_EnergizedNeckCoil.Amulet_EnergizedNeckCoil_C" },
    { category = "Amulet", name = "Energy Diverter", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/EnergyDiverter/Amulet_EnergyDiverter.Amulet_EnergyDiverter_C" },
    { category = "Amulet", name = "Escalation Protocol", classPath = "/Game/World_Root/Items/Trinkets/Amulets/EscalationProtocol/Amulet_EscalationProtocol.Amulet_EscalationProtocol_C" },
    { category = "Amulet", name = "Exhaust Valve", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/ExhaustValve/Amulet_ExhaustValve.Amulet_ExhaustValve_C" },
    { category = "Amulet", name = "Fragrant Thorn", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/FragrantThorn/Amulet_FragrantThorn.Amulet_FragrantThorn_C" },
    { category = "Amulet", name = "Full Moon Circlet", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/FullMoonCirclet/Amulet_FullMoonCirclet.Amulet_FullMoonCirclet_C" },
    { category = "Amulet", name = "Gift of Euphoria", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/GiftOfEuphoria/Amulet_GiftOfEuphoria.Amulet_GiftOfEuphoria_C" },
    { category = "Amulet", name = "Gift of Melancholy", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/GiftOfMelancholy/Amulet_GiftOfMelancholy.Amulet_GiftOfMelancholy_C" },
    { category = "Amulet", name = "Gift of the Unbound", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/GiftOfTheUnbound/Amulet_GiftOfTheUnbound.Amulet_GiftOfTheUnbound_C" },
    { category = "Amulet", name = "Golden Ribbon", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/GoldenRibbon/Amulet_GoldenRibbon.Amulet_GoldenRibbon_C" },
    { category = "Amulet", name = "Gunfire Security Lanyard", classPath = "/Game/World_Labyrinth/Items/Trinkets/Amulets/GunfireSecurityLanyard/Amulet_GunfireSecurityLanyard.Amulet_GunfireSecurityLanyard_C" },
    { category = "Amulet", name = "Gunslinger's Charm", classPath = "/Game/World_Base/Items/Trinkets/Amulets/GunslingersCharm/Amulet_GunslingersCharm.Amulet_GunslingersCharm_C" },
    { category = "Amulet", name = "Hallowed Egg", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/HallowedEgg/Amulet_HallowedEgg.Amulet_HallowedEgg_C" },
    { category = "Amulet", name = "Hangman's Noose", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/HangmansNoose/Amulet_HangmansNoose.Amulet_HangmansNoose_C" },
    { category = "Amulet", name = "Hyperconductor", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/Hyperconductor/Amulet_Hyperconductor.Amulet_Hyperconductor_C" },
    { category = "Amulet", name = "Index of the Scribe", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/IndexOfTheScribe/Amulet_IndexOfTheScribe.Amulet_IndexOfTheScribe_C" },
    { category = "Amulet", name = "Indignant Fetish", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/IndignantFetish/Amulet_IndignantFetish.Amulet_IndignantFetish_C" },
    { category = "Amulet", name = "Inert Overcharger", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/InertOvercharger/Amulet_InertOvercharger.Amulet_InertOvercharger_C" },
    { category = "Amulet", name = "Insipid Talon", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/InsipidTalon/Amulet_InsipidTalon.Amulet_InsipidTalon_C" },
    { category = "Amulet", name = "Insulation Driver", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/InsulationDriver/Amulet_InsulationDriver.Amulet_InsulationDriver_C" },
    { category = "Amulet", name = "Jester's Bell", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/JestersBell/Amulet_JestersBell.Amulet_JestersBell_C" },
    { category = "Amulet", name = "Kinetic Shield Exchanger", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/KineticShieldExchanger/Amulet_KineticShieldExchanger.Amulet_KineticShieldExchanger_C" },
    { category = "Amulet", name = "Kuri Kuri Charm", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/KuriKuriCharm/Amulet_KuriKuriCharm.Amulet_KuriKuriCharm_C" },
    { category = "Amulet", name = "Laemir Censer", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/LaemirCenser/Amulet_LaemirCenser.Amulet_LaemirCenser_C" },
    { category = "Amulet", name = "Legacy Protocol", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/LegacyProtocol/Amulet_LegacyProtocol.Amulet_LegacyProtocol_C" },
    { category = "Amulet", name = "Leto's Amulet", classPath = "/Game/World_Base/Items/Trinkets/Amulets/LetosAmulet/Amulet_LetosAmulet.Amulet_LetosAmulet_C" },
    { category = "Amulet", name = "Magnifying Glass", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/MagnifyingGlass/Amulet_MagnifyingGlass.Amulet_MagnifyingGlass_C" },
    { category = "Amulet", name = "Matriarch's Insignia", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/MatriarchsInsignia/Amulet_MatriarchsInsignia.Amulet_MatriarchsInsignia_C" },
    { category = "Amulet", name = "Moon Stone", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/MoonStone/Amulet_MoonStone.Amulet_MoonStone_C" },
    { category = "Amulet", name = "Navigator's Pendant", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/NavigatorsPendant/Amulet_NavigatorsPendant.Amulet_NavigatorsPendant_C" },
    { category = "Amulet", name = "Neckbone Necklace", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/NeckboneNecklace/Amulet_NeckboneNecklace.Amulet_NeckboneNecklace_C" },
    { category = "Amulet", name = "Necklace of Flowing Life", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/NecklaceOfFlowingLife/Amulet_NecklaceOfFlowingLife.Amulet_NecklaceOfFlowingLife_C" },
    { category = "Amulet", name = "Necklace of Supremacy", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/NecklaceOfSumpremacy/Amulet_NecklaceOfSupremacy.Amulet_NecklaceOfSupremacy_C" },
    { category = "Amulet", name = "Nightmare Spiral", classPath = "/Game/World_Base/Items/Trinkets/Amulets/NightmareSpiral/Amulet_NightmareSpiral.Amulet_NightmareSpiral_C" },
    { category = "Amulet", name = "Nightweaver's Grudge", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/NightweaversGrudge/Amulet_NightweaversGrudge.Amulet_NightweaversGrudge_C" },
    { category = "Amulet", name = "Nimue's Ribbon", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/NimuesRibbon/Amulet_NimuesRibbon.Amulet_NimuesRibbon_C" },
    { category = "Amulet", name = "One True King Sigil", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/OneTrueKingSigil/Amulet_OneTrueKingSigil.Amulet_OneTrueKingSigil_C" },
    { category = "Amulet", name = "One-Eyed Joker Idol", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/OneEyedJokerIdol/Amulet_OneEyedJokerIdol.Amulet_OneEyedJokerIdol_C" },
    { category = "Amulet", name = "Onyx Pendulum", classPath = "/Game/World_Base/Items/Trinkets/Amulets/OnyxPendulum/Amulet_OnyxPendulum.Amulet_OnyxPendulum_C" },
    { category = "Amulet", name = "Ornate Amulet", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/OrnateAmulet/Amulet_OrnateAmulet.Amulet_OrnateAmulet_C" },
    { category = "Amulet", name = "Participation Medal", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/ParticipationMedal/Amulet_ParticipationMedal.Amulet_ParticipationMedal_C" },
    { category = "Amulet", name = "Profane Soul Stone", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/ProfaneSoulStone/Amulet_ProfaneSoulStone.Amulet_ProfaneSoulStone_C" },
    { category = "Amulet", name = "Quantum Memory", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/QuantumMemory/Amulet_QuantumMemory.Amulet_QuantumMemory_C" },
    { category = "Amulet", name = "Range Finder", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/RangeFinder/Amulet_RangeFinder.Amulet_RangeFinder_C" },
    { category = "Amulet", name = "Ravager's Mark", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/RavagersMark/Amulet_RavagersMark.Amulet_RavagersMark_C" },
    { category = "Amulet", name = "Reaction Chain", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/ReactionChain/Amulet_ReactionChain.Amulet_ReactionChain_C" },
    { category = "Amulet", name = "Red Doe Sigil", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/RedDoeSigil/Amulet_RedDoeSigil.Amulet_RedDoeSigil_C" },
    { category = "Amulet", name = "Reed of the Vaunnt", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/ReedOfTheVaunnt/Amulet_ReedOfTheVaunnt.Amulet_ReedOfTheVaunnt_C" },
    { category = "Amulet", name = "Relay Device", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/RelayDevice/Amulet_RelayDevice.Amulet_RelayDevice_C" },
    { category = "Amulet", name = "Rusted Navigator's Pendant", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/RustedNavigatorsPendant/Amulet_RustedNavigatorsPendant.Amulet_RustedNavigatorsPendant_C" },
    { category = "Amulet", name = "Samoflange", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/Samoflange/Amulet_Samoflange.Amulet_Samoflange_C" },
    { category = "Amulet", name = "Scavenger's Bauble", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/ScavengersBauble/Amulet_ScavengersBauble.Amulet_ScavengersBauble_C" },
    { category = "Amulet", name = "Shaed Bloom Crystal", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/ShadeBloomFloret/Amulet_ShadeBloomCrystal.Amulet_ShadeBloomCrystal_C" },
    { category = "Amulet", name = "Shock Device", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/ConductivePadding/Amulet_ShockDevice.Amulet_ShockDevice_C" },
    { category = "Amulet", name = "Short Circuit", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/ShortCircuit/Amulet_ShortCircuit.Amulet_ShortCircuit_C" },
    { category = "Amulet", name = "Silver Ribbon", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/SilverRibbon/Amulet_SilverRibbon.Amulet_SilverRibbon_C" },
    { category = "Amulet", name = "Sinister Totem", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/SinisterTotem/Amulet_SinisterTotem.Amulet_SinisterTotem_C" },
    { category = "Amulet", name = "Soul Anchor", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/SoulAnchor/Amulet_SoulAnchor.Amulet_SoulAnchor_C" },
    { category = "Amulet", name = "Soul Stone", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/SoulStone/Amulet_SoulStone.Amulet_SoulStone_C" },
    { category = "Amulet", name = "Spirit Wisp Amulet", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/SpiritWispAmulet/Amulet_SpiritWispAmulet.Amulet_SpiritWispAmulet_C" },
    { category = "Amulet", name = "Stalker's Brand", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/StalkersBrand/Amulet_StalkersBrand.Amulet_StalkersBrand_C" },
    { category = "Amulet", name = "Stoneshaper's Chisel", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/StoneshapersChisel/Amulet_StoneshapersChisel.Amulet_StoneshapersChisel_C" },
    { category = "Amulet", name = "Talisman of the Sun", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/TalismanOfTheSun/Amulet_TalismanOfTheSun.Amulet_TalismanOfTheSun_C" },
    { category = "Amulet", name = "Timekeeper's Forfeit", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/TimekeepersForfeit/Amulet_TimekeepersForfeit.Amulet_TimekeepersForfeit_C" },
    { category = "Amulet", name = "Toxic Release Valve", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/ToxicReleaseValve/Amulet_ToxicReleaseValve.Amulet_ToxicReleaseValve_C" },
    { category = "Amulet", name = "Twisted Idol", classPath = "/Game/World_Base/Items/Trinkets/Amulets/TwistedIdol/Amulet_TwistedIdol.Amulet_TwistedIdol_C" },
    { category = "Amulet", name = "Vengeance Idol", classPath = "/Game/World_Jungle/Items/Trinkets/Amulets/VengeanceIdol/Amulet_VengeanceIdol.Amulet_VengeanceIdol_C" },
    { category = "Amulet", name = "Void Idol", classPath = "/Game/World_Nerud/Items/Trinkets/Amulets/VoidIdol/Amulet_VoidIdol.Amulet_VoidIdol_C" },
    { category = "Amulet", name = "Volatile Cartridge", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/VolatileCartridge/Amulet_VolatileCartridge.Amulet_VolatileCartridge_C" },
    { category = "Amulet", name = "Weightless Weight", classPath = "/Game/World_Fae/Items/Trinkets/Amulets/WeightlessWeight/Amulet_WeightlessWeight.Amulet_WeightlessWeight_C" },
    { category = "Amulet", name = "Whispering Marble", classPath = "/Game/World_DLC1/Items/Trinkets/Amulets/WhisperingMarble/Amulet_WhisperingMarble.Amulet_WhisperingMarble_C" },
    { category = "Amulet", name = "Worn Dog Tags", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/WornDogTags/Amulet_WornDogTags.Amulet_WornDogTags_C" },
    { category = "Amulet", name = "Zero Divide", classPath = "/Game/World_DLC2/Items/Trinkets/Amulets/ZeroDivide/Amulet_ZeroDivide.Amulet_ZeroDivide_C" },
    { category = "Amulet", name = "Zero Hour", classPath = "/Game/World_DLC3/Items/Trinkets/Amulets/ZeroHour/Amulet_ZeroHour.Amulet_ZeroHour_C" },
    { category = "Ring", name = "Acid Stone", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/PoisonStone/Ring_AcidStone.Ring_AcidStone_C" },
    { category = "Ring", name = "Ahanae Crystal", classPath = "/Game/World_Base/Items/Trinkets/Rings/PanMageSigil/Ring_PanMageSigil.Ring_PanMageSigil_C" },
    { category = "Ring", name = "Akari War Band", classPath = "/Game/World_Base/Items/Trinkets/Rings/AkariWarBand/Ring_AkariWarBand.Ring_AkariWarBand_C" },
    { category = "Ring", name = "Alchemy Stone", classPath = "/Game/World_Fae/Items/Trinkets/Rings/AlchemyStone/Ring_AlchemyStone.Ring_AlchemyStone_C" },
    { category = "Ring", name = "Alumni Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/AlumniRing/Ring_AlumniRing.Ring_AlumniRing_C" },
    { category = "Ring", name = "Amber Moonstone", classPath = "/Game/World_Base/Items/Trinkets/Rings/AmberMoonstone/Ring_AmberMoonstone.Ring_AmberMoonstone_C" },
    { category = "Ring", name = "Anastasija's Inspiration", classPath = "/Game/World_Root/Items/Trinkets/Rings/AnastasijasInspiration/Ring_AnastasijasInspiration.Ring_AnastasijasInspiration_C" },
    { category = "Ring", name = "Archer's Crest", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/ArchersCrest/Ring_ArchersCrest.Ring_ArchersCrest_C" },
    { category = "Ring", name = "Assassin's Seal", classPath = "/Game/World_Fae/Items/Trinkets/Rings/AssassinsSeal/Ring_AssassinsSeal.Ring_AssassinsSeal_C" },
    { category = "Ring", name = "A'Taerii Booster", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/AtaeriiBooster/Ring_ATaeriiBooster.Ring_ATaeriiBooster_C" },
    { category = "Ring", name = "Atonement Fold", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/AtonementFold/Ring_AtonementFold.Ring_AtonementFold_C" },
    { category = "Ring", name = "Band Band", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/BandBand/Ring_BandBand.Ring_BandBand_C" },
    { category = "Ring", name = "Band of Accord", classPath = "/Game/World_Base/Items/Trinkets/Rings/BandOfAccord/Ring_BandOfAccord.Ring_BandOfAccord_C" },
    { category = "Ring", name = "Band of the Fanatic", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/BandOfTheFanatic/Ring_BandOfTheFanatic.Ring_BandOfTheFanatic_C" },
    { category = "Ring", name = "Berserker's Crest", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/BerserkersCrest/Ring_BerserkersCrest.Ring_BerserkersCrest_C" },
    { category = "Ring", name = "Bisected Ring", classPath = "/Game/World_Labyrinth/Items/Trinkets/Rings/BisectedRing/Ring_BisectedRing.Ring_BisectedRing_C" },
    { category = "Ring", name = "Bitter Memento", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/BitterMemento/Ring_BitterMemento.Ring_BitterMemento_C" },
    { category = "Ring", name = "Black Cat Band", classPath = "/Game/World_Base/Items/Trinkets/Rings/BlackCatBand/Ring_BlackCatBand.Ring_BlackCatBand_C" },
    { category = "Ring", name = "Black Pawn Stamp", classPath = "/Game/World_Fae/Items/Trinkets/Rings/BlackPawnStamp/Ring_BlackPawnStamp.Ring_BlackPawnStamp_C" },
    { category = "Ring", name = "Black Spinel", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/BlackSpinel/Ring_BlackSpinel.Ring_BlackSpinel_C" },
    { category = "Ring", name = "Blackout Ring", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/BlackoutRing/Ring_BlackoutRing.Ring_BlackoutRing_C" },
    { category = "Ring", name = "Blasting Cap Ring", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/BlastingCapRing/Ring_BlastingCapRing.Ring_BlastingCapRing_C" },
    { category = "Ring", name = "Blessed Ring", classPath = "/Game/World_Base/Items/Trinkets/Rings/BlessedRing/Ring_BlessedRing.Ring_BlessedRing_C" },
    { category = "Ring", name = "Blood Jewel", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/BloodJewel/Ring_BloodJewel.Ring_BloodJewel_C" },
    { category = "Ring", name = "Blood Tinged Ring", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/BloodTingedRing/Ring_BloodTingedRing.Ring_BloodTingedRing_C" },
    { category = "Ring", name = "Bloodless King's Vow", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/BloodlessKingsVow/Ring_BloodlessKingsVow.Ring_BloodlessKingsVow_C" },
    { category = "Ring", name = "Booster Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/BoosterRing/Ring_BoosterRing.Ring_BoosterRing_C" },
    { category = "Ring", name = "Braided Thorns", classPath = "/Game/World_Base/Items/Trinkets/Rings/BraidedThorns/Ring_BraidedThorns.Ring_BraidedThorns_C" },
    { category = "Ring", name = "Brawler's Pride", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/BrawlersPride/Ring_BrawlersPride.Ring_BrawlersPride_C" },
    { category = "Ring", name = "Breach Accelerator", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/BreachAccelerator/Ring_BreachAccelerator.Ring_BreachAccelerator_C" },
    { category = "Ring", name = "Bridge Warden's Crest", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/BridgeWardensCrest/Ring_BridgeWardensCrest.Ring_BridgeWardensCrest_C" },
    { category = "Ring", name = "Burden of the Audacious", classPath = "/Game/World_Root/Items/Trinkets/Rings/BurdenOfTheAudacious/Ring_BurdenOfTheAudacious.Ring_BurdenOfTheAudacious_C" },
    { category = "Ring", name = "Burden of the Departed", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/BurdenOfTheDeparted/Ring_BurdenOfTheDeparted.Ring_BurdenOfTheDeparted_C" },
    { category = "Ring", name = "Burden of the Destroyer", classPath = "/Game/World_Root/Items/Trinkets/Rings/BurdenOfTheDestroyer/Ring_BurdenOfTheDestroyer.Ring_BurdenOfTheDestroyer_C" },
    { category = "Ring", name = "Burden of the Divine", classPath = "/Game/World_Fae/Items/Trinkets/Rings/BurdenOfTheDivine/Ring_BurdenOfTheDivine.Ring_BurdenOfTheDivine_C" },
    { category = "Ring", name = "Burden of the Excavator", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/BurdenOfTheExcavator/Ring_BurdenOfTheExcavator.Ring_BurdenOfTheExcavator_C" },
    { category = "Ring", name = "Burden of the Follower", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/BurdenOfTheFollower/Ring_BurdenOfTheFollower.Ring_BurdenOfTheFollower_C" },
    { category = "Ring", name = "Burden of the Gambler", classPath = "/Game/World_Base/Items/Trinkets/Rings/BurdenOfTheGambler/Ring_BurdenOfTheGambler.Ring_BurdenOfTheGambler_C" },
    { category = "Ring", name = "Burden of the Mariner", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/BurdenOfTheMariner/Ring_BurdenOfTheMariner.Ring_BurdenOfTheMariner_C" },
    { category = "Ring", name = "Burden of the Mason", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/BurdenOfTheMason/Ring_BurdenOfTheMason.Ring_BurdenOfTheMason_C" },
    { category = "Ring", name = "Burden of the Mesmer", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/BurdenOfTheMesmer/Ring_BurdenOfTheMesmer.Ring_BurdenOfTheMesmer_C" },
    { category = "Ring", name = "Burden of the Protector", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/BurdenOfTheProtector/Ring_BurdenOfTheProtector.Ring_BurdenOfTheProtector_C" },
    { category = "Ring", name = "Burden Of The Rebel", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/BurdenoftheRebel/Ring_BurdenOfTheRebel.Ring_BurdenOfTheRebel_C" },
    { category = "Ring", name = "Burden of the Sciolist", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/BurdenOfTheSciolist/Ring_BurdenOfTheSciolist.Ring_BurdenOfTheSciolist_C" },
    { category = "Ring", name = "Burden of the Stargazer", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/BurdenOfTheStargazer/Ring_BurdenOfTheStargazer.Ring_BurdenOfTheStargazer_C" },
    { category = "Ring", name = "Burden of the Warlock", classPath = "/Game/World_Fae/Items/Trinkets/Rings/BurdenOfTheWarlock/Ring_BurdenOfTheWarlock.Ring_BurdenOfTheWarlock_C" },
    { category = "Ring", name = "Bypass Primer", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/BypassPrimer/Ring_BypassPrimer.Ring_BypassPrimer_C" },
    { category = "Ring", name = "Captain's Insignia", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/CaptainsInsignia/Ring_CaptainsInsignia.Ring_CaptainsInsignia_C" },
    { category = "Ring", name = "Cataloger's Jewel", classPath = "/Game/World_Fae/Items/Trinkets/Rings/CatalogersJewel/Ring_CatalogersJewel.Ring_CatalogersJewel_C" },
    { category = "Ring", name = "Celerity Stone", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/CelerityStone/Ring_CelerityStone.Ring_CelerityStone_C" },
    { category = "Ring", name = "Clear Halo", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/ClearHalo/Ring_ClearHalo.Ring_ClearHalo_C" },
    { category = "Ring", name = "Closed Loop", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/ClosedLoop/Ring_ClosedLoop.Ring_ClosedLoop_C" },
    { category = "Ring", name = "Combat Shield Generator", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/CombatShieldGenerator/Ring_CombatShieldGenerator.Ring_CombatShieldGenerator_C" },
    { category = "Ring", name = "Compulsion Loop", classPath = "/Game/World_Base/Items/Trinkets/Rings/CompulsionLoop/Ring_CompulsionLoop.Ring_CompulsionLoop_C" },
    { category = "Ring", name = "Conjurer's Circle", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/ConjurersCircle/Ring_ConjurersCircle.Ring_ConjurersCircle_C" },
    { category = "Ring", name = "Conservation Seal", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/ConservationSeal/Ring_ConservationSeal.Ring_ConservationSeal_C" },
    { category = "Ring", name = "Constant Variable Ring", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/ConstantVariableRing/Ring_ConstantVariableRing.Ring_ConstantVariableRing_C" },
    { category = "Ring", name = "Crimson Dreamstone", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/CrimsonDreamstone/Ring_CrimsonDreamstone.Ring_CrimsonDreamstone_C" },
    { category = "Ring", name = "Custodian's Bastion", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/CustodiansBastion/Ring_CustodiansBastion.Ring_CustodiansBastion_C" },
    { category = "Ring", name = "Dark Sea Armada Crest", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/DarkSeaArmadaCrest/Ring_DarkSeaArmadaCrest.Ring_DarkSeaArmadaCrest_C" },
    { category = "Ring", name = "Dead King's Memento", classPath = "/Game/World_Root/Items/Trinkets/Rings/DeadKingsMemento/Ring_DeadKingsMemento.Ring_DeadKingsMemento_C" },
    { category = "Ring", name = "Deceiver's Band", classPath = "/Game/World_Base/Items/Trinkets/Rings/DeceiversBand/Ring_DeceiversBand.Ring_DeceiversBand_C" },
    { category = "Ring", name = "Deep Pocket Ring", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/DeepPocketRing/Ring_DeepPocketRing.Ring_DeepPocketRing_C" },
    { category = "Ring", name = "Defensive Action Loop", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/DefensiveActionLoop/Ring_DefensiveActionLoop.Ring_DefensiveActionLoop_C" },
    { category = "Ring", name = "Demolition Coil", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/DemolitionCoil/Ring_DemolitionCoil.Ring_DemolitionCoil_C" },
    { category = "Ring", name = "Dense Silicon Ring", classPath = "/Game/World_Labyrinth/Items/Trinkets/Rings/DenseSiliconRing/Ring_DenseSiliconRing.Ring_DenseSiliconRing_C" },
    { category = "Ring", name = "Detonating Cord", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/DetonatingCord/Ring_DetonatingCord.Ring_DetonatingCord_C" },
    { category = "Ring", name = "Devoured Loop", classPath = "/Game/World_Base/Items/Trinkets/Rings/DevouringLoop/Ring_DevouringLoop.Ring_DevouringLoop_C" },
    { category = "Ring", name = "Digested Hog Lure", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/DigestedHogLure/Ring_DigestedHogLure.Ring_DigestedHogLure_C" },
    { category = "Ring", name = "Disaster Converter", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/DisasterConverter/Ring_DisasterConverter.Ring_DisasterConverter_C" },
    { category = "Ring", name = "Drakestone Pearl", classPath = "/Game/World_Fae/Items/Trinkets/Rings/DrakestonePearl/Ring_DrakestonePearl.Ring_DrakestonePearl_C" },
    { category = "Ring", name = "Dran Memento", classPath = "/Game/World_Fae/Items/Trinkets/Rings/DranMemento/Ring_DranMemento.Ring_DranMemento_C" },
    { category = "Ring", name = "Dran Scavenger Ring", classPath = "/Game/World_Base/Items/Trinkets/Rings/DranScavengerSigil/Ring_DranScavengerSigil.Ring_DranScavengerSigil_C" },
    { category = "Ring", name = "Dread Font", classPath = "/Game/World_Fae/Items/Trinkets/Rings/DreadFont/Ring_DreadFont.Ring_DreadFont_C" },
    { category = "Ring", name = "Dried Clay Ring", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/DriedClayRing/Ring_DriedClayRing.Ring_DriedClayRing_C" },
    { category = "Ring", name = "Drzyr Sniper Sigil", classPath = "/Game/World_Base/Items/Trinkets/Rings/DrzyrSniperSigil/Ring_DrzyrSniperSigil.Ring_DrzyrSniperSigil_C" },
    { category = "Ring", name = "Dull Steel Ring", classPath = "/Game/World_Base/Items/Trinkets/Rings/BrightSteelRing/Ring_BrightSteelRing.Ring_BrightSteelRing_C" },
    { category = "Ring", name = "Dying Ember", classPath = "/Game/World_Root/Items/Trinkets/Rings/DyingEmber/Ring_DyingEmber.Ring_DyingEmber_C" },
    { category = "Ring", name = "Elevated Ring", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/ElevatedRing/Ring_ElevatedRing.Ring_ElevatedRing_C" },
    { category = "Ring", name = "Embrace of Sha'Hala", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/DowngradedRing/Ring_DowngradedRing.Ring_DowngradedRing_C" },
    { category = "Ring", name = "Empowering Loop", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/EmpoweringLoop/Ring_EmpoweringLoop.Ring_EmpoweringLoop_C" },
    { category = "Ring", name = "Encrypted Ring", classPath = "/Game/World_Labyrinth/Items/Trinkets/Rings/EncryptedLoop/Ring_EncryptedLoop.Ring_EncryptedLoop_C" },
    { category = "Ring", name = "Endaira's Endless Loop", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/EndairasEndlessLoop/Ring_EndairasEndlessLoop.Ring_EndairasEndlessLoop_C" },
    { category = "Ring", name = "Excess Coil", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/ExcessCoil/Ring_ExcessCoil.Ring_ExcessCoil_C" },
    { category = "Ring", name = "Fae Bruiser Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FaeBruiserRing/Ring_FaeBruiserRing.Ring_FaeBruiserRing_C" },
    { category = "Ring", name = "Fae Hunter Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FaeHunterRing/Ring_FaeHunterRing.Ring_FaeHunterRing_C" },
    { category = "Ring", name = "Fae Protector Signet", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FaeProtectorSignet/Ring_FaeProtectorSignet.Ring_FaeProtectorSignet_C" },
    { category = "Ring", name = "Fae Shaman Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/DranShamanRing/Ring_FaeShamanRing.Ring_FaeShamanRing_C" },
    { category = "Ring", name = "Fae Warrior Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FaeWarriorRing/Ring_FaeWarriorRing.Ring_FaeWarriorRing_C" },
    { category = "Ring", name = "Faelin's Sigil", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FaelinsSigil/Ring_FaelinsSigil.Ring_FaelinsSigil_C" },
    { category = "Ring", name = "Faerin's Sigil", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FaerinsSigil/Ring_FaerinsSigil.Ring_FaerinsSigil_C" },
    { category = "Ring", name = "Feastmaster's Signet", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FeastmastersSignet/Ring_FeastmastersSignet.Ring_FeastmastersSignet_C" },
    { category = "Ring", name = "Feathery Binding", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/FeatheryBinding/Ring_FeatheryBinding.Ring_FeatheryBinding_C" },
    { category = "Ring", name = "Feedback Loop", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/FeedbackLoop/Ring_FeedbackLoop.Ring_FeedbackLoop_C" },
    { category = "Ring", name = "Feeding Tube", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/FeedingTube/Ring_FeedingTube.Ring_FeedingTube_C" },
    { category = "Ring", name = "Fire Stone", classPath = "/Game/World_Fae/Items/Trinkets/Rings/FireStone/Ring_FireStone.Ring_FireStone_C" },
    { category = "Ring", name = "Floodlit Diamond", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/FloodlitDiamond/Ring_FloodlitDiamond.Ring_FloodlitDiamond_C" },
    { category = "Ring", name = "Flyweight's Sting", classPath = "/Game/World_Root/Items/Trinkets/Rings/FlyweightsSting/Ring_FlyweightsSting.Ring_FlyweightsSting_C" },
    { category = "Ring", name = "Focusing Shard", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/FocusedJewel/Ring_FocusedJewel.Ring_FocusedJewel_C" },
    { category = "Ring", name = "Force Multiplier", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/ForceMultiplier/Ring_ForceMultiplier.Ring_ForceMultiplier_C" },
    { category = "Ring", name = "Frivolous Band", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/FrivolousBand/Ring_FrivolousBand.Ring_FrivolousBand_C" },
    { category = "Ring", name = "Galvanized Resupply Band", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/GalvanizedResupplyBand/Ring_GalvanizedResupplyBand.Ring_GalvanizedResupplyBand_C" },
    { category = "Ring", name = "Game Master's Pride", classPath = "/Game/World_Fae/Items/Trinkets/Rings/GameMastersPride/Ring_GameMastersPride.Ring_GameMastersPride_C" },
    { category = "Ring", name = "Generating Band", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/GeneratingBand/Ring_GeneratingBand.Ring_GeneratingBand_C" },
    { category = "Ring", name = "Grounding Stone", classPath = "/Game/World_Fae/Items/Trinkets/Rings/GroundingStone/Ring_GroundingStone.Ring_GroundingStone_C" },
    { category = "Ring", name = "Guardian's Ring", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/GuardiansRing/Ring_GuardiansRing.Ring_GuardiansRing_C" },
    { category = "Ring", name = "Gul Signet", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/GulSignet/Ring_GulSignet.Ring_GulSignet_C" },
    { category = "Ring", name = "Gunslinger's Ring", classPath = "/Game/World_Base/Items/Trinkets/Rings/GunslingersRing/Ring_GunslingersRing.Ring_GunslingersRing_C" },
    { category = "Ring", name = "Hardcore Metal Band", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/HardcoreMetalBand/Ring_HardcoreMetalBand.Ring_HardcoreMetalBand_C" },
    { category = "Ring", name = "Hardened Coil", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/HardenedCoil/Ring_HardenedCoil.Ring_HardenedCoil_C" },
    { category = "Ring", name = "Haymaker's Ring", classPath = "/Game/World_Root/Items/Trinkets/Rings/HaymakersRing/Ring_HaymakersRing.Ring_HaymakersRing_C" },
    { category = "Ring", name = "Heart Of The Wolf", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/HeartOfTheWolf/Ring_HeartOfTheWolf.Ring_HeartOfTheWolf_C" },
    { category = "Ring", name = "Hex Ward", classPath = "/Game/World_Fae/Items/Trinkets/Rings/HexWard/Ring_HexWard.Ring_HexWard_C" },
    { category = "Ring", name = "Impact Augment", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/ImpactAugment/Ring_ImpactAugment.Ring_ImpactAugment_C" },
    { category = "Ring", name = "Infinity Pocket", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/InfinityPocket/Ring_InfinityPocket.Ring_InfinityPocket_C" },
    { category = "Ring", name = "Jewel of the Beholden", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/JewelOfTheBeholden/Ring_JewelOfTheBeholden.Ring_JewelOfTheBeholden_C" },
    { category = "Ring", name = "Kinetic Cycle Stone", classPath = "/Game/World_Root/Items/Trinkets/Rings/KineticCycleStone/Ring_KineticCycleStone.Ring_KineticCycleStone_C" },
    { category = "Ring", name = "Kolket Eyelet", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/KolketEyelet/Ring_KolketEyelet.Ring_KolketEyelet_C" },
    { category = "Ring", name = "Leaking Gemstone", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/LeakingGemstone/Ring_LeakingGemstone.Ring_LeakingGemstone_C" },
    { category = "Ring", name = "Lighthouse Keeper's Ring", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/LightHouseKeepersRing/Ring_LightHouseKeepersRing.Ring_LightHouseKeepersRing_C" },
    { category = "Ring", name = "Lithic Signet", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/LithicSignet/Ring_LithicSignet.Ring_LithicSignet_C" },
    { category = "Ring", name = "Lodestone Ring", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/LodestoneRing/Ring_LodestoneRing.Ring_LodestoneRing_C" },
    { category = "Ring", name = "Low Yield Recovery Ring", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/LowYieldRecoveryRing/Ring_LowYieldRecoveryRing.Ring_LowYieldRecoveryRing_C" },
    { category = "Ring", name = "Mark of the Destroyer", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/MarkOfTheDestroyer/Ring_MarkOfTheDestroyer.Ring_MarkOfTheDestroyer_C" },
    { category = "Ring", name = "Matriarch's Ring", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/MatriarchsRing/Ring_MatriarchsRing.Ring_MatriarchsRing_C" },
    { category = "Ring", name = "Mechanic's Cog", classPath = "/Game/World_Root/Items/Trinkets/Rings/MechanicsCog/Ring_MechanicsCog.Ring_MechanicsCog_C" },
    { category = "Ring", name = "Metal Driver", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/MetalDriver/Ring_MetalDriver.Ring_MetalDriver_C" },
    { category = "Ring", name = "Meteorite Shard Ring", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/MeteoriteShardRing/Ring_MeteoriteShardRing.Ring_MeteoriteShardRing_C" },
    { category = "Ring", name = "Microcompressor", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/Microcompressor/Ring_Microcompressor.Ring_Microcompressor_C" },
    { category = "Ring", name = "Momentum Driver", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/MomentumDriver/Ring_MomentumDriver.Ring_MomentumDriver_C" },
    { category = "Ring", name = "Mortal Coil", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/MortalCoil/Ring_MortalCoil.Ring_MortalCoil_C" },
    { category = "Ring", name = "Nanofiber Strand", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/NanoFiberStrand/Ring_NanoFiberStrand.Ring_NanoFiberStrand_C" },
    { category = "Ring", name = "Nightmare Sigil", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/NightmareSigil/Ring_NightmareSigil.Ring_NightmareSigil_C" },
    { category = "Ring", name = "Offering Stone", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/Offering_Stone/Ring_OfferingStone.Ring_OfferingStone_C" },
    { category = "Ring", name = "Outcast Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/OutcastRing/Ring_OutcastRing.Ring_OutcastRing_C" },
    { category = "Ring", name = "Painless Obsidian", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/PainlessObsidian/Ring_PainlessObsidian.Ring_PainlessObsidian_C" },
    { category = "Ring", name = "Pan War Band", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/PanWarBand/Ring_PanWarBand.Ring_PanWarBand_C" },
    { category = "Ring", name = "Point Focus Ring", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/PointFocusRing/Ring_PointFocusRing.Ring_PointFocusRing_C" },
    { category = "Ring", name = "Power Complex", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/PowerComplex/Ring_PowerComplex.Ring_PowerComplex_C" },
    { category = "Ring", name = "Power Saver", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/PowerSaver/Ring_PowerSaver.Ring_PowerSaver_C" },
    { category = "Ring", name = "Probability Cord", classPath = "/Game/World_Root/Items/Trinkets/Rings/ProbabilityCord/Ring_ProbabilityCord.Ring_ProbabilityCord_C" },
    { category = "Ring", name = "Propulsion Loop", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/PropulsionLoop/Ring_PropulsionLoop.Ring_PropulsionLoop_C" },
    { category = "Ring", name = "Provisioner Ring", classPath = "/Game/World_Base/Items/Trinkets/Rings/02_OnHold/ProvisionerRing/Ring_ProvisionerRing.Ring_ProvisionerRing_C" },
    { category = "Ring", name = "Rally Band", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/RallyBand/Ring_RallyBand.Ring_RallyBand_C" },
    { category = "Ring", name = "Ravager's Bargain", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/RavagersBargain/Ring_RavagersBargain.Ring_RavagersBargain_C" },
    { category = "Ring", name = "Reaping Stone", classPath = "/Game/World_Root/Items/Trinkets/Rings/ReapingStone/Ring_ReapingStone.Ring_ReapingStone_C" },
    { category = "Ring", name = "Red Ring of Death", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/RedRingofDeath/Ring_RedRingOfDeath.Ring_RedRingOfDeath_C" },
    { category = "Ring", name = "Rerouting Cable", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/ReroutingCable/Ring_ReroutingCable.Ring_ReroutingCable_C" },
    { category = "Ring", name = "Reserve Boosting Gem", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/ReserveBoostingGem/Ring_ReserveBoostingGem.Ring_ReserveBoostingGem_C" },
    { category = "Ring", name = "Restriction Cord", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/RestrictionCord/Ring_RestrictionCord.Ring_RestrictionCord_C" },
    { category = "Ring", name = "Ring of Ashes", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/RingOfAshes/Ring_RingOfAshes.Ring_RingOfAshes_C" },
    { category = "Ring", name = "Ring Of Bones", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/RingOfBones/Ring_RingOfBones.Ring_RingOfBones_C" },
    { category = "Ring", name = "Ring of Crisis", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/RingOfCrisis/Ring_RingOfCrisis.Ring_RingOfCrisis_C" },
    { category = "Ring", name = "Ring of Deflection", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/RingOfDeflection/Ring_RingOfDeflection.Ring_RingOfDeflection_C" },
    { category = "Ring", name = "Ring of Diversion", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/RingOfDiversion/Ring_RingOfDiversion.Ring_RingOfDiversion_C" },
    { category = "Ring", name = "Ring of Flawed Beauty", classPath = "/Game/World_Root/Items/Trinkets/Rings/RingOfFlawedBeauty/Ring_RingOfFlawedBeauty.Ring_RingOfFlawedBeauty_C" },
    { category = "Ring", name = "Ring of Grace", classPath = "/Game/World_Fae/Items/Trinkets/Rings/RingOfGrace/Ring_RingOfGrace.Ring_RingOfGrace_C" },
    { category = "Ring", name = "Ring of Infinite Damage", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/RingOfInfiniteDamage/Ring_RingOfInfiniteDamage.Ring_RingOfInfiniteDamage_C" },
    { category = "Ring", name = "Ring of Omens", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/RingOfOmens/Ring_RingOfOmens.Ring_RingOfOmens_C" },
    { category = "Ring", name = "Ring Of Ordnance", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/RingOfOrdnance/Ring_RingOfOrdnance.Ring_RingOfOrdnance_C" },
    { category = "Ring", name = "Ring Of Phantom Pain", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/RingOfPhantomPain/Ring_PhantomPain.Ring_PhantomPain_C" },
    { category = "Ring", name = "Ring of Restocking", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/RingOfRestocking/Ring_RingOfRestocking.Ring_RingOfRestocking_C" },
    { category = "Ring", name = "Ring of Retribution", classPath = "/Game/World_Fae/Items/Trinkets/Rings/RingOfRetribution/Ring_RingOfRetribution.Ring_RingOfRetribution_C" },
    { category = "Ring", name = "Ring of Spirits", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/RingOfSpirits/Ring_RingOfSpirits.Ring_RingOfSpirits_C" },
    { category = "Ring", name = "Ring of the Castaway", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/RingOfTheCastaway/Ring_RingOfTheCastaway.Ring_RingOfTheCastaway_C" },
    { category = "Ring", name = "Ring of the Damned", classPath = "/Game/World_Fae/Items/Trinkets/Rings/StrongArmBand/Ring_StrongArmBand.Ring_StrongArmBand_C" },
    { category = "Ring", name = "Ring of the Forest Spirit", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/RingOfTheForestSpirit/Ring_RingOfTheForestSpirit.Ring_RingOfTheForestSpirit_C" },
    { category = "Ring", name = "Ring Of The Robust", classPath = "/Game/World_Fae/Items/Trinkets/Rings/RingOfTheRobust/Ring_RingOfTheRobust.Ring_RingOfTheRobust_C" },
    { category = "Ring", name = "Ring of the Vain", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/RingOfTheVain/Ring_RingOfTheVain.Ring_RingOfTheVain_C" },
    { category = "Ring", name = "Rock of Anguish", classPath = "/Game/World_Base/Items/Trinkets/Rings/RockOfAnguish/Ring_RockOfAnguish.Ring_RockOfAnguish_C" },
    { category = "Ring", name = "Rotward", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/Rotward/Ring_Rotward.Ring_Rotward_C" },
    { category = "Ring", name = "Rusted Heirloom", classPath = "/Game/World_Fae/Items/Trinkets/Rings/RustedHeirloom/Ring_RustedHeirloom.Ring_RustedHeirloom_C" },
    { category = "Ring", name = "Sagestone", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/SageStone/Ring_Sagestone.Ring_Sagestone_C" },
    { category = "Ring", name = "Sapphire Dreamstone", classPath = "/Game/World_Fae/Items/Trinkets/Rings/SapphireDreamstone/Ring_SapphireDreamstone.Ring_SapphireDreamstone_C" },
    { category = "Ring", name = "Seal of the Empress", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/SealOfTheEmpress/Ring_SealOfTheEmpress.Ring_SealOfTheEmpress_C" },
    { category = "Ring", name = "Sealed Resin Loop", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/SealedResinLoop/Ring_SealedResinLoop.Ring_SealedResinLoop_C" },
    { category = "Ring", name = "Security Half-Measure", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/SecurityHalfMeasure/Ring_SecurityHalfMeasure.Ring_SecurityHalfMeasure_C" },
    { category = "Ring", name = "Shadow of Misery", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/ShadowOfMisery/Ring_ShadowOfMisery.Ring_ShadowOfMisery_C" },
    { category = "Ring", name = "Shaed Stone", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/ShaedStone/Ring_ShaedStone.Ring_ShaedStone_C" },
    { category = "Ring", name = "Shard Banded Ring", classPath = "/Game/World_Labyrinth/Items/Trinkets/Rings/ShardBandedRing/Ring_ShardBandedRing.Ring_ShardBandedRing_C" },
    { category = "Ring", name = "Shield Alternator", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/ShieldAlternator/Ring_ShieldAlternator.Ring_ShieldAlternator_C" },
    { category = "Ring", name = "Shiny Hog Lure", classPath = "/Game/World_Fae/Items/Trinkets/Rings/ShinyHogLure/Ring_ShinyHogLure.Ring_ShinyHogLure_C" },
    { category = "Ring", name = "Singed Ring", classPath = "/Game/World_Fae/Items/Trinkets/Rings/SingedRing/Ring_SingedRing.Ring_SingedRing_C" },
    { category = "Ring", name = "Siphon Filter", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/SiphonFilter/Ring_SiphonFilter.Ring_SiphonFilter_C" },
    { category = "Ring", name = "Slayer's Crest", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/SlayersCrest/Ring_SlayersCrest.Ring_SlayersCrest_C" },
    { category = "Ring", name = "Soul Feast", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/SoulFeast/Ring_SoulFeast.Ring_SoulFeast_C" },
    { category = "Ring", name = "Soul Guard", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/SoulGuard/Ring_SoulGuard.Ring_SoulGuard_C" },
    { category = "Ring", name = "Soul Link", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/SoulLink/Ring_SoulLink.Ring_SoulLink_C" },
    { category = "Ring", name = "Soul Shard", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/SoulShard/Ring_SoulShard.Ring_SoulShard_C" },
    { category = "Ring", name = "Spirit Alternator", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/SpiritAlternator/Ring_SpiritAlternator.Ring_SpiritAlternator_C" },
    { category = "Ring", name = "Spirit Stone", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/SpiritStone/Ring_SpiritStone.Ring_SpiritStone_C" },
    { category = "Ring", name = "Stockpile Charger", classPath = "/Game/World_Fae/Items/Trinkets/Rings/StockpileDelayLoop/Ring_StockpileCharger.Ring_StockpileCharger_C" },
    { category = "Ring", name = "Stone of Balance", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/StoneofBalance/Ring_StoneOfBalance.Ring_StoneOfBalance_C" },
    { category = "Ring", name = "Stone of Continuance", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/StoneOfContinuance/Ring_StoneOfContinuance.Ring_StoneOfContinuance_C" },
    { category = "Ring", name = "Stone of Expanse", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/StoneOfExpanse/Ring_StoneOfExpanse.Ring_StoneOfExpanse_C" },
    { category = "Ring", name = "Stone Of Malevolence", classPath = "/Game/World_Fae/Items/Trinkets/Rings/StoneOfMalevolence/Ring_StoneOfMalevolence.Ring_StoneOfMalevolence_C" },
    { category = "Ring", name = "Stone of Revelation", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/StoneOfRevelation/Ring_StoneOfRevelation.Ring_StoneOfRevelation_C" },
    { category = "Ring", name = "Strand of Sinew", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/StrandOfSinew/Ring_StrandOfSinew.Ring_StrandOfSinew_C" },
    { category = "Ring", name = "Stream Coupler", classPath = "/Game/World_Fae/Items/Trinkets/Rings/StreamCoupler/Ring_StreamCoupler.Ring_StreamCoupler_C" },
    { category = "Ring", name = "Subterfuge Link", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/SubterfugeLink/Ring_SubterfugeLink.Ring_SubterfugeLink_C" },
    { category = "Ring", name = "Suppression Ward", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/SuppressionWard/Ring_SuppressionWard.Ring_SuppressionWard_C" },
    { category = "Ring", name = "Symbol of Royalty", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/SymbolOfRoyalty/Ring_SymbolOfRoyalty.Ring_SymbolOfRoyalty_C" },
    { category = "Ring", name = "Targeting Jewel", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/TargetingJewel/Ring_TargetingJewel.Ring_TargetingJewel_C" },
    { category = "Ring", name = "Tarnished Ring", classPath = "/Game/World_Base/Items/Trinkets/Rings/TarnishedRing/Ring_TarnishedRing.Ring_TarnishedRing_C" },
    { category = "Ring", name = "Tear of Kaeula", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/TearOfKaeula/Ring_TearOfKaeula.Ring_TearOfKaeula_C" },
    { category = "Ring", name = "Tear of Lydusa", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/TearOfLydusa/Ring_TearOfLydusa.Ring_TearOfLydusa_C" },
    { category = "Ring", name = "Tempest Conduit", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/TempestConduit/Ring_TempestConduit.Ring_TempestConduit_C" },
    { category = "Ring", name = "Thalos Eyelet", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/ThalosEyelet/Ring_ThalosEyelet.Ring_ThalosEyelet_C" },
    { category = "Ring", name = "Tightly Wound Coil", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/TightlyWoundCoil/Ring_TightlyWoundCoil.Ring_TightlyWoundCoil_C" },
    { category = "Ring", name = "Timekeeper's Jewel", classPath = "/Game/World_Fae/Items/Trinkets/Rings/TimekeepersJewel/Ring_TimekeepersJewel.Ring_TimekeepersJewel_C" },
    { category = "Ring", name = "Token of Favor", classPath = "/Game/World_DLC2/Items/Trinkets/Rings/TokenOfFavor/Ring_TokenOfFavor.Ring_TokenOfFavor_C" },
    { category = "Ring", name = "Tolerance Band", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/ToleranceBand/Ring_ToleranceBand.Ring_ToleranceBand_C" },
    { category = "Ring", name = "Tomb Dweller's Ring", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/TombDwellersRing/Ring_TombDwellersRing.Ring_TombDwellersRing_C" },
    { category = "Ring", name = "Transient Cord", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/TransientCord/Ring_TransientCord.Ring_TransientCord_C" },
    { category = "Ring", name = "Vacuum Seal", classPath = "/Game/World_Nerud/Items/Trinkets/Rings/VacuumSeal/Ring_VacuumSeal.Ring_VacuumSeal_C" },
    { category = "Ring", name = "Vestige of Power", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/VestigeOfPower/Ring_VestigeOfPower.Ring_VestigeOfPower_C" },
    { category = "Ring", name = "Wax Sealed Ring", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/WaxSealedRing/Ring_WaxSealedRing.Ring_WaxSealedRing_C" },
    { category = "Ring", name = "White Glass Bead", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/WhiteGlassBead/Ring_WhiteGlassBead.Ring_WhiteGlassBead_C" },
    { category = "Ring", name = "White Pawn Stamp", classPath = "/Game/World_Fae/Items/Trinkets/Rings/WhitePawnStamp/Ring_WhitePawnStamp.Ring_WhitePawnStamp_C" },
    { category = "Ring", name = "Wind Hollow Circlet", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/WindHollowCirclet/Ring_WindHollowCirclet.Ring_WindHollowCirclet_C" },
    { category = "Ring", name = "Wired Inhibitor", classPath = "/Game/World_DLC3/Items/Trinkets/Rings/WiredInhibitor/Ring_WiredInhibitor.Ring_WiredInhibitor_C" },
    { category = "Ring", name = "Wood Ring", classPath = "/Game/World_DLC1/Items/Trinkets/Rings/WoodRing/Ring_WoodRing.Ring_WoodRing_C" },
    { category = "Ring", name = "Worn Admiral's Ring", classPath = "/Game/World_Base/Items/Trinkets/Rings/01_Graveyard/RingOfTheAdmiral/Ring_RingOfTheAdmiral.Ring_RingOfTheAdmiral_C" },
    { category = "Ring", name = "Zania's Malice", classPath = "/Game/World_Root/Items/Trinkets/Rings/ZaniasMalice/Ring_ZaniasMalice.Ring_ZaniasMalice_C" },
    { category = "Ring", name = "Zohee's Ring", classPath = "/Game/World_Jungle/Items/Trinkets/Rings/ZoheesRing/Ring_ZoheesRing.Ring_ZoheesRing_C" },
}

local function findOwnedInventoryComponent(pawn)
    local all = FindAllOf("RemnantPlayerInventoryComponent")
    if not all then return nil end
    for _, c in ipairs(all) do
        local ok, owner = pcall(function() return c:GetOuter() end)
        if ok and owner then
            local okSame, same = pcall(function() return owner:GetFullName() == pawn:GetFullName() end)
            if okSame and same then return c end
        end
    end
    return nil
end

-- Returns a set of owned class-path strings (lowercased) read from the live
-- Items array. Built fresh each check - session-lifetime caching can come
-- later once this is proven correct.
local function readOwnedClassPaths(inv)
    local owned = {}
    local okItems, items = pcall(function() return inv.Items end)
    if not okItems or items == nil then
        print("[InventoryTracker] readOwnedClassPaths: inv.Items unreadable.\n")
        return owned
    end
    local okLen, len = pcall(function() return #items end)
    if not okLen then
        print("[InventoryTracker] readOwnedClassPaths: #items unreadable.\n")
        return owned
    end
    for i = 1, len do
        local okEntry, entry = pcall(function() return items[i] end)
        if okEntry and entry ~= nil then
            local unwrapped = entry
            if type(entry) == "userdata" then
                local okGet, inner = pcall(function() return entry:get() end)
                if okGet and inner ~= nil then unwrapped = inner end
            end
            local okClass, itemClass = pcall(function() return unwrapped.ItemBP end)
            if okClass and itemClass ~= nil then
                local okPath, path = pcall(function() return itemClass:GetFullName() end)
                if okPath and path then
                    -- GetFullName() looks like "BlueprintGeneratedClass /Game/.../Ring_X.Ring_X_C";
                    -- keep just the "/Game/..." part to compare against MASTER_LIST classPath.
                    local assetPath = string.match(path, "(/Game/.+)$")
                    if assetPath then owned[string.lower(assetPath)] = true end
                end
            end
        end
    end
    return owned
end

RegisterKeyBind(Key.F8, function()
    print("[InventoryTracker] F8 pressed - checking rings/amulets.\n")
    ExecuteInGameThread(function()
        local pawns = FindAllOf("Character_Master_Player_Base_C")
        local pawn = nil
        if pawns then
            for _, p in ipairs(pawns) do
                local ok, valid = pcall(function() return p:IsValid() end)
                if ok and valid then pawn = p break end
            end
        end
        if not pawn then
            print("[InventoryTracker] F8: no valid pawn - load a save first.\n")
            return
        end

        local inv = findOwnedInventoryComponent(pawn)
        if not inv then
            print("[InventoryTracker] F8: no Inventory component found.\n")
            return
        end

        local owned = readOwnedClassPaths(inv)
        local ownedCount, missingCount = 0, 0
        for _, item in ipairs(MASTER_LIST) do
            local has = owned[string.lower(item.classPath)] == true
            if has then ownedCount = ownedCount + 1 else missingCount = missingCount + 1 end
            print(string.format("[InventoryTracker]   [%s] (%s) %s\n", has and "X" or " ", item.category, item.name))
        end
        print(string.format("[InventoryTracker] F8: %d owned, %d missing (of %d total).\n",
            ownedCount, missingCount, #MASTER_LIST))
    end)
end)

print("[InventoryTracker] Ready - press F8 to check rings/amulets.\n")
