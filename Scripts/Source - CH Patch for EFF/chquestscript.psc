Scriptname CHQuestScript extends Quest Conditional
{Script by Alek (mitchalek@yahoo.com).
Attached to CH quest, on game load SKSE detection, horse faction relation changes, automatic mode changes and horse alias management.}

import Game
import Utility
import Debug

; Constants
Int property SKSEVersionReleaseMinReq = 43 autoReadOnly
Float property CHVersion = 5.0 autoReadOnly

; Scripts and Aliases
CHHorseAliasScript property HorseScript auto
CHHorseAliasScript property HorseSummonScript auto
CHPlayerAliasScript property PlayerScript auto
ReferenceAlias property Alias_Horse auto
ReferenceAlias property Alias_HorseSummon auto
ReferenceAlias property Alias_Sack auto

; Globals
GlobalVariable property CHFactionRelationsMode auto
GlobalVariable property CHFactionRelationsUpdate auto
GlobalVariable property CHControlMode auto
GlobalVariable property CHHorseEquipmentMode auto
GlobalVariable property CHHorseTrackingDisable auto
GlobalVariable property CHHorseInventoryWeightLimit auto

; Keywords
Keyword property CHHorseArmor auto
Keyword property CHRequiresDawnguard auto

; Horse inventory weight limiter
ActorBase property CHHorseSackMedium auto
ObjectReference property SpawnMarker auto

; Configuration Power
Spell property CHConfigurationPower auto

; Horse race for armor restriction
Race property HorseRace auto

; Factions
Faction property CHHorseFaction auto

; Form lists
FormList property CHHorseEquipmentList auto
FormList property CHHarvestableList auto
FormList property CHFactionList auto
FormList property CHRidableWorldList auto
FormList property CHAvoidLocationList auto
FormList property CHWeapMaterialKeywordList auto
FormList property CHMCDaggerList auto
FormList property CHMCSwordList auto
FormList property CHMCWarAxeList auto
FormList property CHMCMaceList auto
FormList property CHMCGreatswordList auto
FormList property CHMCBattleaxeList auto
FormList property CHMCWarhammerList auto
FormList property CHFollowerIgnoreList auto
FormList property CHBlacksmithingMaterialList auto
FormList property CHEnchantingMaterialList auto

; Messages
Message property CHModeBoundKeyMessage auto
Message property CHModeMultiTapMessage auto
Message property CHFactionUpdateMessage auto
Message property CHFactionCompleteNeutralMessage auto
Message property CHFactionCompleteFriendlyMessage auto
Message property CHHorseInventoryRecoveryMessage auto

; Quick inventory transfer menu conditionals
Bool property QuickTransferAlchemy auto hidden conditional
Bool property QuickTransferBlacksmithing auto hidden conditional
Bool property QuickTransferEnchanting auto hidden conditional

; Detected plugins
Bool property SKSEOK auto hidden conditional
Bool property SkyUIOK auto hidden conditional
Bool property DawnguardOK auto hidden conditional
Bool property DragonbornOK auto hidden conditional
Bool property HearthFiresOK auto hidden conditional
Bool property HerdingOK auto hidden conditional
Bool property EFFOK auto hidden conditional
Bool property UFOOK auto hidden conditional
Bool property HothOK auto hidden conditional
Bool property ValfarOK auto hidden conditional
Bool property ArissaOK auto hidden conditional
Bool property FalskaarOK auto hidden conditional
Bool property WyrmstoothOK auto hidden conditional
Bool property InterestingNPCsOK auto hidden conditional
Bool property SkyTESTOK auto hidden conditional

; Track the init state of plugins whose resources are added to local form lists
Float VersionInit
Bool DawnguardInit
Bool DragonbornInit
Bool HearthFiresInit
Bool HothInit
Bool ValfarInit
Bool ArissaInit
Bool FalskaarInit
Bool WyrmstoothInit
Bool SkyTESTInit

; Horse mane removal tracking
Actor ManeTrackedHorse
Bool IsManeHidden


Bool bGameLoaded = true
Bool property GameLoaded hidden	; Set from CHPlayerAliasScript game load event
	Bool Function Get()
		if bGameLoaded
			Trace("========== Convenient Horses: Scanning for supported plugins...")
			Trace("========== ERRORS RELATED TO MISSING FILES SHOULD BE IGNORED!")
			SKSEOK = SKSE.GetVersionRelease() >= SKSEVersionReleaseMinReq
			SkyUIOK = (GetFormFromFile(0x814, "SkyUI.esp") as Quest) as Bool	; SKI_MainInstance
			DawnguardOK = (GetFormFromFile(0x2c09, "Dawnguard.esm") as Quest) as Bool	; DLC1Init
			DragonbornOK = (GetFormFromFile(0x16e02, "Dragonborn.esm") as Quest) as Bool	; DLC2Init
			HearthFiresOK = (GetFormFromFile(0xa7b33, "HearthFires.esm") as Quest) as Bool	; HousePurchase
			FalskaarOK = (GetFormFromFile(0xa1cf42, "Falskaar.esm") as WorldSpace) as Bool	; Falskaar
			WyrmstoothOK = (GetFormFromFile(0xd62, "Wyrmstooth.esp") as WorldSpace) as Bool	; WyrmstoothWorld
			HerdingOK = (GetFormFromFile(0x13fca7, "Convenient Horse Herding.esp") as Quest) as Bool	; CHHerding
			EFFOK = (GetFormFromFile(0xeff, "EFFCore.esm") as Quest) as Bool	; FollowerExtension
			UFOOK = (GetFormFromFile(0x53a2e, "UFO - Ultimate Follower Overhaul.esp") as Quest) as Bool	; 0fLokii_FollowerControl
			InterestingNPCsOK = (GetFormFromFile(0x13184c, "3DNPC.esp") as Quest) as Bool	; DialogueFollower3DNPC
			HothOK = (GetFormFromFile(0xd62, "HothFollower.esp") as ActorBase) as Bool	; HirelingHoth
			ValfarOK = (GetFormFromFile(0xd63, "CompanionValfar.esp") as ActorBase) as Bool	; OS_CV_Valfar
			ArissaOK = (GetFormFromFile(0xd62, "CompanionArissa.esp") as ActorBase) as Bool	; Arissa
			SkyTESTOK = (GetFormFromFile(0x1cbf8, "SkyTEST-RealisticAnimals&Predators.esp") as Faction) as Bool	; SkyTESTHorseWildFaction
			Trace("========== Convenient Horses: Scan complete.")
			bGameLoaded = false
			return true
		else
			return false
		endif
	EndFunction
	Function Set(bool value)
		bGameLoaded = value
		RegisterForSingleUpdate(0)
	EndFunction
EndProperty


Event OnInit()
	RegisterForSingleUpdate(1)
EndEvent

Event OnUpdate()
	; Prevents update event loop if parent quest is not running
	if !IsRunning()
		return
	endif

	; Initialize once on game load
	if GameLoaded
		InitializeExternalResources()
		UpdateBoundKeys()
		; Make sure player gets config power if no MCM available
		if !GetPlayer().HasSpell(CHConfigurationPower) && (!SkyUIOK || !SKSEOK)
			GetPlayer().AddSpell(CHConfigurationPower, False)
		endif
		; Encumbrance listener - balloon deployment related
		PlayerScript.RegisterForSingleUpdate(1)
	endif

	; Horse management
	if !CheckLastRiddenHorse()
		GoToMode("")
		RegisterForSingleUpdate(5)
		return
	endif
	
	; Control mode changes
	if !SKSEOK || CHControlMode.GetValue()
		GoToMode("MultiTap")
	else
		GoToMode("BoundKey")
	endif

	; Update faction relations
	if CHFactionRelationsUpdate.GetValue()
		SetFactionRelations(CHFactionRelationsMode.GetValue() as bool)
		CHFactionRelationsUpdate.SetValue(0)
	endif

	; Speed up processing while horse tracking disable is pending
	if CHHorseTrackingDisable.GetValue() && GetPlayersLastRiddenHorse()
		RegisterForSingleUpdate(0.5)
	else
		RegisterForSingleUpdate(2)
	endif
EndEvent

Function InitializeExternalResources()
	; Do not re-initialize unless mod configuration has changed
	if CHVersion == VersionInit && DawnguardOK == DawnguardInit && DragonbornOK == DragonbornInit && HearthFiresOK == HearthFiresInit && FalskaarOK == FalskaarInit && WyrmstoothOK == WyrmstoothInit && HothOK == HothInit && ValfarOK == ValfarInit && ArissaOK == ArissaInit && SkyTESTOK == SkyTESTInit
		return
	endif

	; Reset all formlists
	CHHarvestableList.Revert()
	CHFactionList.Revert()
	CHRidableWorldList.Revert()
	CHAvoidLocationList.Revert()
	CHFollowerIgnoreList.Revert()
	CHWeapMaterialKeywordList.Revert()
	CHMCDaggerList.Revert()
	CHMCSwordList.Revert()
	CHMCWarAxeList.Revert()
	CHMCMaceList.Revert()
	CHMCGreatswordList.Revert()
	CHMCBattleaxeList.Revert()
	CHMCWarhammerList.Revert()
	CHBlacksmithingMaterialList.Revert()
	CHEnchantingMaterialList.Revert()

	; Dawnguard resources
	if DawnguardOK
		CHHarvestableList.AddForm(GetFormFromFile(0x12db9, "Dawnguard.esm"))	; DLC01SoulHustk01
		CHHarvestableList.AddForm(GetFormFromFile(0x12dba, "Dawnguard.esm"))	; DLC01SoulHustk02
		CHHarvestableList.AddForm(GetFormFromFile(0x10f37, "Dawnguard.esm"))	; DLC01Gleamblossom01
		CHHarvestableList.AddForm(GetFormFromFile(0x2842, "Dawnguard.esm"))	; DLC01SoulCairnFissureTrig
		CHRidableWorldList.AddForm(GetFormFromFile(0x1408, "Dawnguard.esm"))	; DLC01SoulCairn
		CHRidableWorldList.AddForm(GetFormFromFile(0x1db8, "Dawnguard.esm"))	; DLC1HunterHQWorld
		CHAvoidLocationList.AddForm(GetFormFromFile(0x4c20, "Dawnguard.esm"))	; DLC1VampireCastleLocation
		CHWeapMaterialKeywordList.AddForm(GetFormFromFile(0x19822, "Dawnguard.esm"))	; DLC1WeapMaterialDragonbone
		CHFollowerIgnoreList.AddForm(GetFormFromFile(0x2b6c, "Dawnguard.esm"))	; DLC1Serana

		CHFactionList.AddForm(GetFormFromFile(0x14cbd, "Dawnguard.esm"))	; DLC1VampireFeedNoCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x14b5b, "Dawnguard.esm"))	; DLC1MothPriestCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x14638, "Dawnguard.esm"))	; DLC1GunmarFaction
		CHFactionList.AddForm(GetFormFromFile(0x145c3, "Dawnguard.esm"))	; DLC1WE01AttackPlayerFaction
		CHFactionList.AddForm(GetFormFromFile(0x1459e, "Dawnguard.esm"))	; DLC1VampireSeductionBoostFaction
		CHFactionList.AddForm(GetFormFromFile(0x13814, "Dawnguard.esm"))	; DLC1_BF_BossFightFaction
		CHFactionList.AddForm(GetFormFromFile(0x1380f, "Dawnguard.esm"))	; DLC1LD_AetherialStaffBusyFaction
		CHFactionList.AddForm(GetFormFromFile(0x137ba, "Dawnguard.esm"))	; DLC1SeranaCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x12eab, "Dawnguard.esm"))	; DLC1VQDoorBlockerFaction
		CHFactionList.AddForm(GetFormFromFile(0x12d13, "Dawnguard.esm"))	; DLC1TutorialFaction
		CHFactionList.AddForm(GetFormFromFile(0x12cd7, "Dawnguard.esm"))	; DLC1VQ08HunterSiegeFaction
		CHFactionList.AddForm(GetFormFromFile(0x12c2e, "Dawnguard.esm"))	; DLC1VQ08VampireSiegeFaction
		CHFactionList.AddForm(GetFormFromFile(0x123e6, "Dawnguard.esm"))	; DLC1VampireCastleDoorFaction
		CHFactionList.AddForm(GetFormFromFile(0x11e2e, "Dawnguard.esm"))	; DLC1VQ02LockedDoorFaction
		CHFactionList.AddForm(GetFormFromFile(0x11be3, "Dawnguard.esm"))	; DLC1WE08SpecialCombatFaction
		CHFactionList.AddForm(GetFormFromFile(0x11be2, "Dawnguard.esm"))	; DLC1UndeadGuardianFaction
		CHFactionList.AddForm(GetFormFromFile(0x10ec1, "Dawnguard.esm"))	; DLC1DawnguardExteriorGuardFaction
		CHFactionList.AddForm(GetFormFromFile(0xfc7e, "Dawnguard.esm"))	; DLC1dunHarkonBattleEnemyFaction
		CHFactionList.AddForm(GetFormFromFile(0xe65d, "Dawnguard.esm"))	; DLC1dunHarkonBattleAllyFaction
		CHFactionList.AddForm(GetFormFromFile(0xd921, "Dawnguard.esm"))	; DLC1VQ01ChatterFaction
		CHFactionList.AddForm(GetFormFromFile(0x4246, "Dawnguard.esm"))	; DLC1VQ03FightFaction
		CHFactionList.AddForm(GetFormFromFile(0x1aa75, "Dawnguard.esm"))	; DLC1HireableDogFaction
		CHFactionList.AddForm(GetFormFromFile(0x1a52c, "Dawnguard.esm"))	; DLC1VQ01DraugrFaction
		CHFactionList.AddForm(GetFormFromFile(0x19c5b, "Dawnguard.esm"))	; SoulCairnSummonedBonemenFaction
		CHFactionList.AddForm(GetFormFromFile(0x19818, "Dawnguard.esm"))	; DLC1DexionThrall
		CHFactionList.AddForm(GetFormFromFile(0x18c4f, "Dawnguard.esm"))	; DLC1VampireCompanionFaction
		CHFactionList.AddForm(GetFormFromFile(0x18819, "Dawnguard.esm"))	; DLC1VQ01CaptiveFaction
		CHFactionList.AddForm(GetFormFromFile(0x18818, "Dawnguard.esm"))	; DLC1VQ01PuzzleRoomVampireFaction
		CHFactionList.AddForm(GetFormFromFile(0x183a5, "Dawnguard.esm"))	; DLC1SeranaFaction
		CHFactionList.AddForm(GetFormFromFile(0x17f71, "Dawnguard.esm"))	; DLC1VampireCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x17a07, "Dawnguard.esm"))	; DLC1VQ03InnkeepersFaction
		CHFactionList.AddForm(GetFormFromFile(0x16849, "Dawnguard.esm"))	; DLC1FerrySystemFaction
		CHFactionList.AddForm(GetFormFromFile(0x1681b, "Dawnguard.esm"))	; DLC1GeleborFaction
		CHFactionList.AddForm(GetFormFromFile(0x162f7, "Dawnguard.esm"))	; DLC1ThrallFaction
		CHFactionList.AddForm(GetFormFromFile(0x1603e, "Dawnguard.esm"))	; SoulCairnSpecialFaction
		CHFactionList.AddForm(GetFormFromFile(0x15758, "Dawnguard.esm"))	; DLC1RadiantDisguisedFollowPlayerFaction
		CHFactionList.AddForm(GetFormFromFile(0x15755, "Dawnguard.esm"))	; DLC1RadiantDisguisedVampireFactionAdvisor
		CHFactionList.AddForm(GetFormFromFile(0x15754, "Dawnguard.esm"))	; DLC1RadiantDisguisedVampireFactionPilgrim
		CHFactionList.AddForm(GetFormFromFile(0x15753, "Dawnguard.esm"))	; DLC1RadiantDisguisedVampireFactionMerchant
		CHFactionList.AddForm(GetFormFromFile(0x15752, "Dawnguard.esm"))	; DLC1RadiantDisguisedHunterFactionPilgrim
		CHFactionList.AddForm(GetFormFromFile(0x15751, "Dawnguard.esm"))	; DLC1RadiantDisguisedHunterFactionMerchant
		CHFactionList.AddForm(GetFormFromFile(0x15750, "Dawnguard.esm"))	; DLC1RadiantDisguisedVampireFactionBard
		CHFactionList.AddForm(GetFormFromFile(0x1574f, "Dawnguard.esm"))	; DLC1RadiantDisguisedHunterFactionBard
		CHFactionList.AddForm(GetFormFromFile(0x150b0, "Dawnguard.esm"))	; SoulCairnSoulFaction
		CHFactionList.AddForm(GetFormFromFile(0x14bfa, "Dawnguard.esm"))	; DLC1_WESC09Faction
		CHFactionList.AddForm(GetFormFromFile(0x146c0, "Dawnguard.esm"))	; DLC1LD_KatriaFaction
		CHFactionList.AddForm(GetFormFromFile(0x14351, "Dawnguard.esm"))	; DLC1RV07CoffinOwnerFaction
		CHFactionList.AddForm(GetFormFromFile(0x142e7, "Dawnguard.esm"))	; DLC1TurningIntoVampireFaction
		CHFactionList.AddForm(GetFormFromFile(0x142e6, "Dawnguard.esm"))	; DLC1PotentialVampireFaction
		CHFactionList.AddForm(GetFormFromFile(0x14217, "Dawnguard.esm"))	; DLC1DawnguardFaction
		CHFactionList.AddForm(GetFormFromFile(0x13cf6, "Dawnguard.esm"))	; DLC1HunterBaseIntroBearFaction
		CHFactionList.AddForm(GetFormFromFile(0x1393f, "Dawnguard.esm"))	; DLC1dunRedwaterDenMerchant
		CHFactionList.AddForm(GetFormFromFile(0x135bd, "Dawnguard.esm"))	; DLC1RuunvaldFaction
		CHFactionList.AddForm(GetFormFromFile(0x127ef, "Dawnguard.esm"))	; DLC1WEJS06EnemiesFaction
		CHFactionList.AddForm(GetFormFromFile(0x1047f, "Dawnguard.esm"))	; DLC1ServicesRonthil
		CHFactionList.AddForm(GetFormFromFile(0x1047e, "Dawnguard.esm"))	; DLC1ServicesHestla
		CHFactionList.AddForm(GetFormFromFile(0x1047d, "Dawnguard.esm"))	; DLC1ServicesFeran
		CHFactionList.AddForm(GetFormFromFile(0xf82d, "Dawnguard.esm"))	; DLC1ServicesFlorentius
		CHFactionList.AddForm(GetFormFromFile(0xf827, "Dawnguard.esm"))	; DLC1ServicesGunmar
		CHFactionList.AddForm(GetFormFromFile(0xf1a7, "Dawnguard.esm"))	; DLC1ServicesSorineJurard
		CHFactionList.AddForm(GetFormFromFile(0xc3cc, "Dawnguard.esm"))	; DLC1RadiantQuestgiverTopicFaction
		CHFactionList.AddForm(GetFormFromFile(0xb544, "Dawnguard.esm"))	; DLC1RV07ThankFaction
		CHFactionList.AddForm(GetFormFromFile(0x7f51, "Dawnguard.esm"))	; DLC1PriestEscortVampires
		CHFactionList.AddForm(GetFormFromFile(0x8e1e, "Dawnguard.esm"))	; DLC1dunRedwaterDenFaction
		CHFactionList.AddForm(GetFormFromFile(0x8876, "Dawnguard.esm"))	; DLC1PriestCampVigilants
		CHFactionList.AddForm(GetFormFromFile(0x8875, "Dawnguard.esm"))	; DLC1PriestEscortVigilants
		CHFactionList.AddForm(GetFormFromFile(0x8874, "Dawnguard.esm"))	; DLC1MothPriestFaction
		CHFactionList.AddForm(GetFormFromFile(0x83a6, "Dawnguard.esm"))	; DLC1DurnehviirEnemyFaction
		CHFactionList.AddForm(GetFormFromFile(0x83a5, "Dawnguard.esm"))	; DLC1DurnehviirFaction
		CHFactionList.AddForm(GetFormFromFile(0x83a3, "Dawnguard.esm"))	; DLC1ValericaEnemyFaction
		CHFactionList.AddForm(GetFormFromFile(0x83a2, "Dawnguard.esm"))	; DLC1ValericaFaction
		CHFactionList.AddForm(GetFormFromFile(0x7c41, "Dawnguard.esm"))	; DLC1RadiantVampireBanditNecroAllys
		CHFactionList.AddForm(GetFormFromFile(0x7a66, "Dawnguard.esm"))	; SoulCairnFaction
		CHFactionList.AddForm(GetFormFromFile(0x71d3, "Dawnguard.esm"))	; DLC1PlayerVampireLordFaction
		CHFactionList.AddForm(GetFormFromFile(0x5e37, "Dawnguard.esm"))	; DLC1VampireIntroEnemyFaction
		CHFactionList.AddForm(GetFormFromFile(0x588d, "Dawnguard.esm"))	; DLC1PlayerTurnedVampire
		CHFactionList.AddForm(GetFormFromFile(0x4c2d, "Dawnguard.esm"))	; DLC1RV01TargetFaction
		CHFactionList.AddForm(GetFormFromFile(0x4c27, "Dawnguard.esm"))	; DLC1RadiantQuestGiver
		CHFactionList.AddForm(GetFormFromFile(0x3376, "Dawnguard.esm"))	; DLC1VampireFaction
		CHFactionList.AddForm(GetFormFromFile(0x3375, "Dawnguard.esm"))	; DLC1HunterFaction

		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x11999, "Dawnguard.esm"))	; DLC1DeerHide
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x1199a, "Dawnguard.esm"))	; DLC1SabreCatHide
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x195aa, "Dawnguard.esm"))	; DLC1ShellbugChitin
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x2993, "Dawnguard.esm"))	; DLC1BoneHawkSkull
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x2994, "Dawnguard.esm"))	; DLC1BoneHawkFeathers

		CHMCDaggerList.AddForm(GetFormFromFile(0xba1a6, "Convenient Horses.esp"))	; CHMCDragonboneDagger
		CHMCSwordList.AddForm(GetFormFromFile(0xba1a9, "Convenient Horses.esp"))	; CHMCDragonboneSword
		CHMCWarAxeList.AddForm(GetFormFromFile(0xba1aa, "Convenient Horses.esp"))	; CHMCDragonboneWarAxe
		CHMCMaceList.AddForm(GetFormFromFile(0xba1a8, "Convenient Horses.esp"))	; CHMCDragonboneMace
		CHMCGreatswordList.AddForm(GetFormFromFile(0xba1a7, "Convenient Horses.esp"))	; CHMCDragonboneGreatsword
		CHMCBattleaxeList.AddForm(GetFormFromFile(0xba1a5, "Convenient Horses.esp"))	; CHMCDragonboneBattleaxe
		CHMCWarhammerList.AddForm(GetFormFromFile(0xba1ab, "Convenient Horses.esp"))	; CHMCDragonboneWarhammer
	endif
	; Dragonborn resources
	if DragonbornOK
		CHHarvestableList.AddForm(GetFormFromFile(0x17005, "Dragonborn.esm"))	; DLC2FloraTramaRoot01
		CHHarvestableList.AddForm(GetFormFromFile(0x184ef, "Dragonborn.esm"))	; DLC2FloraTramaRoot02
		CHHarvestableList.AddForm(GetFormFromFile(0x18b19, "Dragonborn.esm"))	; DLC2FloraTramaRoot03
		CHHarvestableList.AddForm(GetFormFromFile(0x195dc, "Dragonborn.esm"))	; DLC2FloraCreepClusterAsh
		CHHarvestableList.AddForm(GetFormFromFile(0x195dd, "Dragonborn.esm"))	; DLC2FloraCreepClusterAshRock
		CHHarvestableList.AddForm(GetFormFromFile(0x3828c, "Dragonborn.esm"))	; DLC2PearlOysterLarge01
		CHHarvestableList.AddForm(GetFormFromFile(0x3828d, "Dragonborn.esm"))	; DLC2PearlOysterThin01
		; CHHarvestableList.AddForm(GetFormFromFile(0x38a7a, "Dragonborn.esm"))	; DLC2HorkerMeat01
		; CHHarvestableList.AddForm(GetFormFromFile(0x38a83, "Dragonborn.esm"))	; DLC2HorkerDead01
		CHHarvestableList.AddForm(GetFormFromFile(0x16e24, "Dragonborn.esm"))	; DLC2TreeFloraSpikyGrassAsh01
		CHHarvestableList.AddForm(GetFormFromFile(0x16e25, "Dragonborn.esm"))	; DLC2TreeFloraSpikyGrassAsh02
		CHHarvestableList.AddForm(GetFormFromFile(0x17e93, "Dragonborn.esm"))	; DLC2TreeFloraScathecraw01
		CHHarvestableList.AddForm(GetFormFromFile(0x17e94, "Dragonborn.esm"))	; DLC2TreeFloraScathecraw02
		CHHarvestableList.AddForm(GetFormFromFile(0x1ff64, "Dragonborn.esm"))	; DLC2TreeFloraHangingMoss01
		CHHarvestableList.AddForm(GetFormFromFile(0x1ff65, "Dragonborn.esm"))	; DLC2TreeFloraHangingMoss02
		CHHarvestableList.AddForm(GetFormFromFile(0x1ff66, "Dragonborn.esm"))	; DLC2TreeFloraHangingMoss03
		; CHHarvestableList.AddForm(GetFormFromFile(0x206e8, "Dragonborn.esm"))	; DLC2TreeFloraAshYam01

		CHRidableWorldList.AddForm(GetFormFromFile(0x800, "Dragonborn.esm"))	; DLC2SolstheimWorld

		CHAvoidLocationList.AddForm(GetFormFromFile(0x142c0, "Dragonborn.esm"))	; DLC2AbandonedLodgeLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142c5, "Dragonborn.esm"))	; DLC2AshfallowLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x3a07f, "Dragonborn.esm"))	; DLC2BloodskalBarrowBanditLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142c1, "Dragonborn.esm"))	; DLC2BrokenTuskMineLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x1429e, "Dragonborn.esm"))	; DLC2CastleKarstaagRuinsLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142a0, "Dragonborn.esm"))	; DLC2FahlbtharzLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x14293, "Dragonborn.esm"))	; DLC2FortFrostmothLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x184fc, "Dragonborn.esm"))	; DLC2HighpointTowerLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142c3, "Dragonborn.esm"))	; DLC2HrodulfsHouseLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142a2, "Dragonborn.esm"))	; DLC2KagrumezLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142da, "Dragonborn.esm"))	; DLC2MoesringPassLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142b4, "Dragonborn.esm"))	; DLC2NchardakLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x19d2b, "Dragonborn.esm"))	; DLC2SaeringsWatchLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142c9, "Dragonborn.esm"))	; DLC2StridentSquallLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x143bc, "Dragonborn.esm"))	; DLC2TelMithrynLocation
		CHAvoidLocationList.AddForm(GetFormFromFile(0x142b6, "Dragonborn.esm"))	; DLC2TempleOfMiraakLocation

		CHFactionList.AddForm(GetFormFromFile(0x17775, "Dragonborn.esm"))	; DLC2TelMithrynFaction
		CHFactionList.AddForm(GetFormFromFile(0x17785, "Dragonborn.esm"))	; DLC2encAshGuardianFaction
		CHFactionList.AddForm(GetFormFromFile(0x177c5, "Dragonborn.esm"))	; DLC2ServicesTelMithrynElynea
		CHFactionList.AddForm(GetFormFromFile(0x177c6, "Dragonborn.esm"))	; DLC2ServicesTelMithrynTalvas
		CHFactionList.AddForm(GetFormFromFile(0x177c7, "Dragonborn.esm"))	; DLC2ServicesTelMithrynNeloth
		CHFactionList.AddForm(GetFormFromFile(0x17960, "Dragonborn.esm"))	; DLC2ExpSpiderEnemyFaction
		CHFactionList.AddForm(GetFormFromFile(0x17964, "Dragonborn.esm"))	; DLC2ExpSpiderFriendFaction
		CHFactionList.AddForm(GetFormFromFile(0x17ebd, "Dragonborn.esm"))	; DLC2TameDragonFaction
		CHFactionList.AddForm(GetFormFromFile(0x18279, "Dragonborn.esm"))	; DLC2CrimeRavenRockFaction
		CHFactionList.AddForm(GetFormFromFile(0x1841e, "Dragonborn.esm"))	; DLC2RRMorvaynManorFaction
		CHFactionList.AddForm(GetFormFromFile(0x1841f, "Dragonborn.esm"))	; DLC2RRBulwarkFaction
		CHFactionList.AddForm(GetFormFromFile(0x18420, "Dragonborn.esm"))	; DLC2RRTempleFaction
		CHFactionList.AddForm(GetFormFromFile(0x18421, "Dragonborn.esm"))	; DLC2RRNetchFaction
		CHFactionList.AddForm(GetFormFromFile(0x18423, "Dragonborn.esm"))	; DLC2RRGloverMalloryFaction
		CHFactionList.AddForm(GetFormFromFile(0x18424, "Dragonborn.esm"))	; DLC2RRCresciusCaerelliusHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18425, "Dragonborn.esm"))	; DLC2RRSeverinManorFaction
		CHFactionList.AddForm(GetFormFromFile(0x18426, "Dragonborn.esm"))	; DLC2RRIenthFarmFaction
		CHFactionList.AddForm(GetFormFromFile(0x184a9, "Dragonborn.esm"))	; DLC2RRAranoSpouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x184bd, "Dragonborn.esm"))	; DLC2RRAlorHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x184c9, "Dragonborn.esm"))	; DLC2RRCresciusSpouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x184d1, "Dragonborn.esm"))	; DLC2RRSeverinSpouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18f1e, "Dragonborn.esm"))	; DLC2RRBeggarFaction
		CHFactionList.AddForm(GetFormFromFile(0x18f9a, "Dragonborn.esm"))	; DLC2SkaalVillageCitizenFaction
		CHFactionList.AddForm(GetFormFromFile(0x18f9b, "Dragonborn.esm"))	; DLC2SVOslafsHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18fa6, "Dragonborn.esm"))	; DLC2SVDeorWoodcuttersHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18fab, "Dragonborn.esm"))	; DLC2SVMorwensHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18faf, "Dragonborn.esm"))	; DLC2SVWulfWildbloodsHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18fb6, "Dragonborn.esm"))	; DLC2SVBaldorIronShapersHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18fbc, "Dragonborn.esm"))	; DLC2SVEdlasHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x18fc6, "Dragonborn.esm"))	; DLC2SVGreathallFaction
		CHFactionList.AddForm(GetFormFromFile(0x195ad, "Dragonborn.esm"))	; DLC2RavenRockGuardFaction
		CHFactionList.AddForm(GetFormFromFile(0x19b8a, "Dragonborn.esm"))	; DLC2StaffMakerFaction
		CHFactionList.AddForm(GetFormFromFile(0x19ccc, "Dragonborn.esm"))	; DLC2MQ04MiraakFaction
		CHFactionList.AddForm(GetFormFromFile(0x19ccd, "Dragonborn.esm"))	; DLC2MQ04MiraakEnemyFaction
		CHFactionList.AddForm(GetFormFromFile(0x1a514, "Dragonborn.esm"))	; DLC2ThirskNordFaction
		CHFactionList.AddForm(GetFormFromFile(0x1aaf9, "Dragonborn.esm"))	; DLC2MQ02MiraakEnemyFaction
		CHFactionList.AddForm(GetFormFromFile(0x1b63b, "Dragonborn.esm"))	; DLC2AshSpawnFaction
		CHFactionList.AddForm(GetFormFromFile(0x1c4e5, "Dragonborn.esm"))	; DLC2PillarBuilderFaction
		CHFactionList.AddForm(GetFormFromFile(0x1d750, "Dragonborn.esm"))	; DLC2SummonedAshGuardianFaction
		CHFactionList.AddForm(GetFormFromFile(0x1d9c9, "Dragonborn.esm"))	; DLC2RieklingFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dc43, "Dragonborn.esm"))	; DLC2SVMorwensBedFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dc61, "Dragonborn.esm"))	; DLC2dunFrostmoonWerewolvesFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dc62, "Dragonborn.esm"))	; DLC2dunFrostmoonWerewolvesVendorFaction
		CHFactionList.AddForm(GetFormFromFile(0x1e8bc, "Dragonborn.esm"))	; DLC2MQ05AllyFaction
		CHFactionList.AddForm(GetFormFromFile(0x1e8bd, "Dragonborn.esm"))	; DLC2MQ05DragonFaction
		CHFactionList.AddForm(GetFormFromFile(0x1eec4, "Dragonborn.esm"))	; DLC2DremoraMerchantFaction
		CHFactionList.AddForm(GetFormFromFile(0x1f88c, "Dragonborn.esm"))	; DLC2SkaalMerchant
		CHFactionList.AddForm(GetFormFromFile(0x1f899, "Dragonborn.esm"))	; DLC2SkaalBlacksmith
		CHFactionList.AddForm(GetFormFromFile(0x1fb95, "Dragonborn.esm"))	; DLC2MQ06DragonFaction
		CHFactionList.AddForm(GetFormFromFile(0x1ff1d, "Dragonborn.esm"))	; DLC2BendWillFollowerFaction
		CHFactionList.AddForm(GetFormFromFile(0x200e7, "Dragonborn.esm"))	; DLC2BendWillImmuneFaction
		CHFactionList.AddForm(GetFormFromFile(0x208d9, "Dragonborn.esm"))	; DLC2ThirskRieklingFaction
		CHFactionList.AddForm(GetFormFromFile(0x2173a, "Dragonborn.esm"))	; DLC2SV02ThalmorCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x23f72, "Dragonborn.esm"))	; DLC2MQ06NonHostileFaction
		CHFactionList.AddForm(GetFormFromFile(0x23f77, "Dragonborn.esm"))	; DLC2MQ06HostileFaction
		CHFactionList.AddForm(GetFormFromFile(0x24cab, "Dragonborn.esm"))	; DLC2BanditDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x2501a, "Dragonborn.esm"))	; DLC2RRServicesRavenRockMilore
		CHFactionList.AddForm(GetFormFromFile(0x25025, "Dragonborn.esm"))	; DLC2RRServicesRavenRockFethis
		CHFactionList.AddForm(GetFormFromFile(0x25026, "Dragonborn.esm"))	; DLC2RRServicesRavenRockGaryn
		CHFactionList.AddForm(GetFormFromFile(0x25027, "Dragonborn.esm"))	; DLC2RRServicesRavenRockGlover
		CHFactionList.AddForm(GetFormFromFile(0x25028, "Dragonborn.esm"))	; DLC2RRServicesRavenRockGeldis
		CHFactionList.AddForm(GetFormFromFile(0x2507c, "Dragonborn.esm"))	; DLC2NetchFaction
		CHFactionList.AddForm(GetFormFromFile(0x2645d, "Dragonborn.esm"))	; DLC2MQ02Faction
		CHFactionList.AddForm(GetFormFromFile(0x2655f, "Dragonborn.esm"))	; DLC2TribalWerebearFaction
		CHFactionList.AddForm(GetFormFromFile(0x265fe, "Dragonborn.esm"))	; DLC2SV01TombFaction
		CHFactionList.AddForm(GetFormFromFile(0x27107, "Dragonborn.esm"))	; DLC2ServicesThirskHalbarn
		CHFactionList.AddForm(GetFormFromFile(0x271ff, "Dragonborn.esm"))	; DLC2MogrulFaction
		CHFactionList.AddForm(GetFormFromFile(0x27291, "Dragonborn.esm"))	; DLC2SkaalShamanFaction
		CHFactionList.AddForm(GetFormFromFile(0x27802, "Dragonborn.esm"))	; DLC2dunKolbjornMinerFaction
		CHFactionList.AddForm(GetFormFromFile(0x2783f, "Dragonborn.esm"))	; DLC2WaterStoneSailors
		CHFactionList.AddForm(GetFormFromFile(0x279eb, "Dragonborn.esm"))	; DLC2BBReward3Exclude
		CHFactionList.AddForm(GetFormFromFile(0x279ec, "Dragonborn.esm"))	; DLC2DremoraPCAlly
		CHFactionList.AddForm(GetFormFromFile(0x27e12, "Dragonborn.esm"))	; DLC2AncarionServicesFaction
		CHFactionList.AddForm(GetFormFromFile(0x2856c, "Dragonborn.esm"))	; DLC2SeekerFaction
		CHFactionList.AddForm(GetFormFromFile(0x2929a, "Dragonborn.esm"))	; DLC2MoragTongFaction
		CHFactionList.AddForm(GetFormFromFile(0x2b0f2, "Dragonborn.esm"))	; DLC2BenthicLurkerFaction
		CHFactionList.AddForm(GetFormFromFile(0x2bc5c, "Dragonborn.esm"))	; DLC2MiraakDragonAllyFaction
		CHFactionList.AddForm(GetFormFromFile(0x2bc5d, "Dragonborn.esm"))	; DLC2MiraakFaction
		CHFactionList.AddForm(GetFormFromFile(0x2bc5e, "Dragonborn.esm"))	; DLC2ApocryphaFaction
		CHFactionList.AddForm(GetFormFromFile(0x31786, "Dragonborn.esm"))	; DLC2SkaalDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x31846, "Dragonborn.esm"))	; DLC2WyrmFaction
		CHFactionList.AddForm(GetFormFromFile(0x32801, "Dragonborn.esm"))	; dlc2MerchMerchantFaction
		CHFactionList.AddForm(GetFormFromFile(0x339cb, "Dragonborn.esm"))	; DLC2Book01Seeker1stFloorFaction
		CHFactionList.AddForm(GetFormFromFile(0x339cc, "Dragonborn.esm"))	; DLC2Book01Seeker2ndFloorFaction
		CHFactionList.AddForm(GetFormFromFile(0x339cd, "Dragonborn.esm"))	; DLC2Book01Seeker3rdFloorFaction
		CHFactionList.AddForm(GetFormFromFile(0x34b93, "Dragonborn.esm"))	; DLC2MQ02AllyFaction
		CHFactionList.AddForm(GetFormFromFile(0x34fbc, "Dragonborn.esm"))	; DLC2CultistFaction
		CHFactionList.AddForm(GetFormFromFile(0x3572d, "Dragonborn.esm"))	; DLC2ServicesThirskElmus
		CHFactionList.AddForm(GetFormFromFile(0x376f3, "Dragonborn.esm"))	; DLC2NorthernMaidenFaction
		CHFactionList.AddForm(GetFormFromFile(0x3789d, "Dragonborn.esm"))	; DLC2ApocryphaTrapOwnerFaction
		CHFactionList.AddForm(GetFormFromFile(0x38562, "Dragonborn.esm"))	; DLC2HirelingTeldrynCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x39231, "Dragonborn.esm"))	; DLC2TTF1AshGuardianFriendFaction
		CHFactionList.AddForm(GetFormFromFile(0x397e3, "Dragonborn.esm"))	; DLC2ApoTentacleNoHitFaction
		CHFactionList.AddForm(GetFormFromFile(0x398e9, "Dragonborn.esm"))	; DLC2BookReadingCommentFaction
		CHFactionList.AddForm(GetFormFromFile(0x39d11, "Dragonborn.esm"))	; DLC2RavenRockMinersFaction
		CHFactionList.AddForm(GetFormFromFile(0x3a4ca, "Dragonborn.esm"))	; DLC2HunterFaction
		CHFactionList.AddForm(GetFormFromFile(0x3bda0, "Dragonborn.esm"))	; DLC2MH02SpecialCombatFaction
		CHFactionList.AddForm(GetFormFromFile(0x3d126, "Dragonborn.esm"))	; DLC2ThirskNordCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x3d2f3, "Dragonborn.esm"))	; DLC2TamedDragonTrackingFaction
		CHFactionList.AddForm(GetFormFromFile(0x3d2fb, "Dragonborn.esm"))	; DLC2MorasGraspExcludedFaction
		CHFactionList.AddForm(GetFormFromFile(0x3d3ae, "Dragonborn.esm"))	; DLC2RR01VelethAllyFaction
		CHFactionList.AddForm(GetFormFromFile(0x3d5c4, "Dragonborn.esm"))	; DLC2MQ06MiraakFaction

		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x2b06b, "Dragonborn.esm"))	; DLC2OreStalhrim
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x1cd7c, "Dragonborn.esm"))	; DLC2NetchLeather
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x2b04e, "Dragonborn.esm"))	; DLC2ChitinPlate

		CHEnchantingMaterialList.AddForm(GetFormFromFile(0x17749, "Dragonborn.esm"))	; DLC2HeartStone
		CHEnchantingMaterialList.AddForm(GetFormFromFile(0x7e646, "Dragonborn.esm"))	; StaffTemplateAlteration
		CHEnchantingMaterialList.AddForm(GetFormFromFile(0x7e647, "Dragonborn.esm"))	; StaffTemplateConjuration
		CHEnchantingMaterialList.AddForm(GetFormFromFile(0xbe11f, "Dragonborn.esm"))	; StaffTemplateDestruction
		CHEnchantingMaterialList.AddForm(GetFormFromFile(0x7a91b, "Dragonborn.esm"))	; StaffTemplateIIllusion
		CHEnchantingMaterialList.AddForm(GetFormFromFile(0x51b0c, "Dragonborn.esm"))	; StaffTemplateRestoration
		CHEnchantingMaterialList.AddForm(GetFormFromFile(0xcc826, "Dragonborn.esm"))	; StaffTemplateForsworn
	endif
	; Hearth Fires resources
	if HearthFiresOK
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x5a69, "HearthFires.esm"))	; BYOHMaterialGlass
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x5a68, "HearthFires.esm"))	; BYOHMaterialStraw
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x306c, "HearthFires.esm"))	; BYOHMaterialStoneBlock
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x3043, "HearthFires.esm"))	; BYOHMaterialClay
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x303f, "HearthFires.esm"))	; BYOHMaterialHornGoat
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x3035, "HearthFires.esm"))	; BYOHMaterialFittingsIron
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x3012, "HearthFires.esm"))	; BYOHMaterialLock
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x3011, "HearthFires.esm"))	; BYOHMaterialHinge
		CHBlacksmithingMaterialList.AddForm(GetFormFromFile(0x300f, "HearthFires.esm"))	; BYOHMaterialNails
	endif
	; SkyTEST - realistic animals and predators
	if SkyTESTOK
		CHFactionList.AddForm(GetFormFromFile(0x1dec, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfRedMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1deb, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfBlackFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0xbb91, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestMudCrabFaction
		CHFactionList.AddForm(GetFormFromFile(0xbb7d, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestDeerFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dea, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfBlackMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1de9, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfWhiteFaction
		CHFactionList.AddForm(GetFormFromFile(0xc717, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfFaction
		CHFactionList.AddForm(GetFormFromFile(0xc716, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearFaction
		CHFactionList.AddForm(GetFormFromFile(0xc715, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestPreyFaction
		CHFactionList.AddForm(GetFormFromFile(0xc714, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestPredatorFaction
		CHFactionList.AddForm(GetFormFromFile(0x1de8, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfRedFaction
		CHFactionList.AddForm(GetFormFromFile(0x1de7, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfBlackFaction
		CHFactionList.AddForm(GetFormFromFile(0x1de5, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSabreCatRegularFaction
		CHFactionList.AddForm(GetFormFromFile(0x1de4, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSabreCatRegularMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1548f, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestFriendlyFaction
		CHFactionList.AddForm(GetFormFromFile(0x1de3, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSabreCatRegularFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1311, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearBrownFaction
		CHFactionList.AddForm(GetFormFromFile(0x2363, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfIceFaction
		CHFactionList.AddForm(GetFormFromFile(0x1312, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearWhiteFaction
		CHFactionList.AddForm(GetFormFromFile(0x16a23, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfGrayMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x16a22, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfGrayFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x16a21, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfGrayFaction
		CHFactionList.AddForm(GetFormFromFile(0x28c8, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSlaughterfishGatorFaction
		CHFactionList.AddForm(GetFormFromFile(0x28c7, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSlaughterfishBroodFaction
		CHFactionList.AddForm(GetFormFromFile(0x6c29, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSlaughterfishFaction
		CHFactionList.AddForm(GetFormFromFile(0x28c6, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSlaughterfishFryFaction
		CHFactionList.AddForm(GetFormFromFile(0x1315, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearBlackFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1316, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearBlackMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1317, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearBrownMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1318, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearBrownFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1319, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearWhiteFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x38bb3, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTESTGKFaction
		CHFactionList.AddForm(GetFormFromFile(0x1310, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearBlackFaction
		CHFactionList.AddForm(GetFormFromFile(0x187d, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestAnimalFaction
		CHFactionList.AddForm(GetFormFromFile(0x131a, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestBearWhiteMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1e00, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestGoatMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dff, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestGoatFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x2d515, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTESTSheepFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dfe, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestDeerFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x2da82, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTESTPigFaction
		CHFactionList.AddForm(GetFormFromFile(0x2da80, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTESTGooseFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dfd, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestDeerMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dfc, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestElkFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dfb, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestElkMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1cbf8, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTESTHorseWildFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dfa, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestElkFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df9, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestPreySmallFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df8, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestInsectSmallFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df7, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSpiderSmallFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df4, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestCrabSmallFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df3, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestRatSmallFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df2, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSabreCatSnowMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df1, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSabreCatSnowFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1df0, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSabreCatSnowFaction
		CHFactionList.AddForm(GetFormFromFile(0x1fca1, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestSabreCatsFaction
		CHFactionList.AddForm(GetFormFromFile(0x1fc8a, "SkyTEST-RealisticAnimals&Predators.esp"))	; FoxFactionSkyTEST
		CHFactionList.AddForm(GetFormFromFile(0x1def, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfWhiteFemaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1dee, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfWhiteMaleFaction
		CHFactionList.AddForm(GetFormFromFile(0x1ded, "SkyTEST-RealisticAnimals&Predators.esp"))	; SkyTestWolfRedFemaleFaction
	endif

	; Falskaar
	if FalskaarOK
		CHRidableWorldList.AddForm(GetFormFromFile(0xa1cf42, "Falskaar.esm"))	; Falskaar
		CHFactionList.AddForm(GetFormFromFile(0x18bb1b, "Falskaar.esm"))	; FSServicesAmberCreekKunnariLong
		CHFactionList.AddForm(GetFormFromFile(0x18cc0e, "Falskaar.esm"))	; FSServicesHelena
		CHFactionList.AddForm(GetFormFromFile(0x18cc0d, "Falskaar.esm"))	; FSAudmundFarmFaction
		CHFactionList.AddForm(GetFormFromFile(0x18e35f, "Falskaar.esm"))	; FSServicesAmberCreekSvea
		CHFactionList.AddForm(GetFormFromFile(0x18e910, "Falskaar.esm"))	; FSServicesHenrik
		CHFactionList.AddForm(GetFormFromFile(0x18eed6, "Falskaar.esm"))	; FSServicesHelenaLimited
		CHFactionList.AddForm(GetFormFromFile(0x18ff80, "Falskaar.esm"))	; FalskaarBrawlFaction
		CHFactionList.AddForm(GetFormFromFile(0x30f36, "Falskaar.esm"))	; FalskaarSoldierDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0xfe34a, "Falskaar.esm"))	; FalskaarBanditFaction
		CHFactionList.AddForm(GetFormFromFile(0x508a3, "Falskaar.esm"))	; FalskaarChildDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x123532, "Falskaar.esm"))	; FSSQ14CowFaction
		CHFactionList.AddForm(GetFormFromFile(0x128c81, "Falskaar.esm"))	; FSSQ15SingleWolfFaction
		CHFactionList.AddForm(GetFormFromFile(0x128c7f, "Falskaar.esm"))	; FSSQ15WolfFaction
		CHFactionList.AddForm(GetFormFromFile(0x508a8, "Falskaar.esm"))	; FalskaarEvilDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x50ed4, "Falskaar.esm"))	; FalskaarFarmerDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x13ac13, "Falskaar.esm"))	; FSSQ17SpiderFaction
		CHFactionList.AddForm(GetFormFromFile(0x13b183, "Falskaar.esm"))	; FSSQ17ElkFaction
		CHFactionList.AddForm(GetFormFromFile(0x72a75, "Falskaar.esm"))	; FSMQ05ABanditFaction
		CHFactionList.AddForm(GetFormFromFile(0x82520, "Falskaar.esm"))	; FSMQ08GoodFaction
		CHFactionList.AddForm(GetFormFromFile(0x82521, "Falskaar.esm"))	; FSMQ08BadFaction
		CHFactionList.AddForm(GetFormFromFile(0xdf260, "Falskaar.esm"))	; FSAmberMeadInnFaction
		CHFactionList.AddForm(GetFormFromFile(0xdf261, "Falskaar.esm"))	; FSBorvaldurManorFaction
		CHFactionList.AddForm(GetFormFromFile(0x145b21, "Falskaar.esm"))	; FSRangarrsHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0xdf2da, "Falskaar.esm"))	; FSRuriksHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0xdf25f, "Falskaar.esm"))	; FSDocksTraderFaction
		CHFactionList.AddForm(GetFormFromFile(0xe08a2, "Falskaar.esm"))	; FSGeneralStoreFaction
		CHFactionList.AddForm(GetFormFromFile(0x14d6f0, "Falskaar.esm"))	; FSMQ09YngvarrFaction
		CHFactionList.AddForm(GetFormFromFile(0x198bd1, "Falskaar.esm"))	; FSHjorgunnarCabinFaction
		CHFactionList.AddForm(GetFormFromFile(0x15999d, "Falskaar.esm"))	; FalskaarCrimeFaction
		CHFactionList.AddForm(GetFormFromFile(0x19d08b, "Falskaar.esm"))	; FSKunnarisFarmFaction
		CHFactionList.AddForm(GetFormFromFile(0x19d08c, "Falskaar.esm"))	; FSOudinsHouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x15af64, "Falskaar.esm"))	; FSServicesAmberCreekAmberMeadInn
		CHFactionList.AddForm(GetFormFromFile(0xa07f4, "Falskaar.esm"))	; FSSQ01BanditFaction
		CHFactionList.AddForm(GetFormFromFile(0x30f37, "Falskaar.esm"))	; FalskaarPriestDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x2febb, "Falskaar.esm"))	; FalskaarBanditDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x2feda, "Falskaar.esm"))	; FalskaarMinerDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x15c533, "Falskaar.esm"))	; FSServicesAudmund
		CHFactionList.AddForm(GetFormFromFile(0x30f38, "Falskaar.esm"))	; FalskaarTownsfolkDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0xa07f3, "Falskaar.esm"))	; FalskaarDocksFaction
		CHFactionList.AddForm(GetFormFromFile(0x2233c, "Falskaar.esm"))	; FalskaarUniqueDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x15caba, "Falskaar.esm"))	; FSServicesAmberCreekRangarr
		CHFactionList.AddForm(GetFormFromFile(0x16fb61, "Falskaar.esm"))	; FSMainQuestAllyFaction
		CHFactionList.AddForm(GetFormFromFile(0x16fb62, "Falskaar.esm"))	; FSTownDocksFaction
		CHFactionList.AddForm(GetFormFromFile(0x16fb60, "Falskaar.esm"))	; FSTownAmberCreekFaction
		CHFactionList.AddForm(GetFormFromFile(0x2febc, "Falskaar.esm"))	; FalskaarGuardDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x30f39, "Falskaar.esm"))	; FalskaarNecromancerDialogueFaction
		CHFactionList.AddForm(GetFormFromFile(0x17a0d7, "Falskaar.esm"))	; FSMQ07GuardFaction
		CHFactionList.AddForm(GetFormFromFile(0x17a0c5, "Falskaar.esm"))	; FSMQ07TemporaryFriends
		CHFactionList.AddForm(GetFormFromFile(0x17d276, "Falskaar.esm"))	; FSSQ01CaptiveFightFaction
		CHFactionList.AddForm(GetFormFromFile(0x182bd8, "Falskaar.esm"))	; FSMQ05BNecroLeaderFaction
		CHFactionList.AddForm(GetFormFromFile(0x17a7b5, "Falskaar.esm"))	; FalskaarNecromancerFaction
		CHFactionList.AddForm(GetFormFromFile(0x188c08, "Falskaar.esm"))	; FSSQ10JonulvFaction
		CHFactionList.AddForm(GetFormFromFile(0x17bd7e, "Falskaar.esm"))	; FSTownBorvaldFaction
		CHFactionList.AddForm(GetFormFromFile(0x17c2fc, "Falskaar.esm"))	; FalskaarGuardFaction
		CHFactionList.AddForm(GetFormFromFile(0x18bb1a, "Falskaar.esm"))	; FSServicesAmberCreekKunnariShort
	endif
	; Wyrmstooth
	if WyrmstoothOK
		CHRidableWorldList.AddForm(GetFormFromFile(0xd62, "Wyrmstooth.esp"))	; WyrmstoothWorld
		CHFactionList.AddForm(GetFormFromFile(0x26993, "Wyrmstooth.esp"))	; WTDaenlitEscapeSolitudePrison
		CHFactionList.AddForm(GetFormFromFile(0x603da, "Wyrmstooth.esp"))	; WTServicesGeneralTrader
		CHFactionList.AddForm(GetFormFromFile(0x12bd14, "Wyrmstooth.esp"))	; WTHallOfTheDead
		CHFactionList.AddForm(GetFormFromFile(0x12bd15, "Wyrmstooth.esp"))	; WTFarmingFaction
		CHFactionList.AddForm(GetFormFromFile(0x603d7, "Wyrmstooth.esp"))	; WTServicesApothecary
		CHFactionList.AddForm(GetFormFromFile(0x14b101, "Wyrmstooth.esp"))	; WTKidsFaction
		CHFactionList.AddForm(GetFormFromFile(0x222976, "Wyrmstooth.esp"))	; WTBazrobFaction
		CHFactionList.AddForm(GetFormFromFile(0x222975, "Wyrmstooth.esp"))	; WTGashnagFaction
		CHFactionList.AddForm(GetFormFromFile(0x272c19, "Wyrmstooth.esp"))	; WTChillwaterFaction
		CHFactionList.AddForm(GetFormFromFile(0x60422, "Wyrmstooth.esp"))	; WTServicesBlacksmith
		CHFactionList.AddForm(GetFormFromFile(0x2cc98a, "Wyrmstooth.esp"))	; WTFortValusFaction
		CHFactionList.AddForm(GetFormFromFile(0x1076b0, "Wyrmstooth.esp"))	; WTFallenAdventurerFaction
		CHFactionList.AddForm(GetFormFromFile(0x119a44, "Wyrmstooth.esp"))	; WTImperialDragonHunt
		CHFactionList.AddForm(GetFormFromFile(0x119a33, "Wyrmstooth.esp"))	; WTVulthurkrahFaction
		CHFactionList.AddForm(GetFormFromFile(0x28ef6, "Wyrmstooth.esp"))	; WTEastEmpireFaction
		CHFactionList.AddForm(GetFormFromFile(0x12297e, "Wyrmstooth.esp"))	; WTTradehouseFaction
		CHFactionList.AddForm(GetFormFromFile(0x12297d, "Wyrmstooth.esp"))	; WTTheHermitFaction
		CHFactionList.AddForm(GetFormFromFile(0x12297c, "Wyrmstooth.esp"))	; WTHulgardSvenjaFaction
		CHFactionList.AddForm(GetFormFromFile(0x12297f, "Wyrmstooth.esp"))	; WTRepairWyrmstoothFaction
		CHFactionList.AddForm(GetFormFromFile(0x124e85, "Wyrmstooth.esp"))	; WTNalionGildanFaction
		CHFactionList.AddForm(GetFormFromFile(0x124d50, "Wyrmstooth.esp"))	; WTArgonianHouse
		CHFactionList.AddForm(GetFormFromFile(0x127230, "Wyrmstooth.esp"))	; WTLaeniusFaction
		CHFactionList.AddForm(GetFormFromFile(0x127235, "Wyrmstooth.esp"))	; WTLumbermillFaction
		CHFactionList.AddForm(GetFormFromFile(0xe4b3, "Wyrmstooth.esp"))	; WTMinersFaction
		CHFactionList.AddForm(GetFormFromFile(0x49cc22, "Wyrmstooth.esp"))	; WTSaeglopurFaction
		CHFactionList.AddForm(GetFormFromFile(0x4b9dd7, "Wyrmstooth.esp"))	; WTMerchantFortValusGardenFaction
		CHFactionList.AddForm(GetFormFromFile(0x4b9dd8, "Wyrmstooth.esp"))	; WTMerchantFortValusKitchenFaction
		CHFactionList.AddForm(GetFormFromFile(0x4b9dd6, "Wyrmstooth.esp"))	; WTMerchantFortValusBlacksmithFaction
	endif
	; Hoth custom follower
	if HothOK
		CHFollowerIgnoreList.AddForm(GetFormFromFile(0xd62, "HothFollower.esp"))	; HirelingHoth
	endif
	; Valfar custom follower
	if ValfarOK
		CHFollowerIgnoreList.AddForm(GetFormFromFile(0xd63, "CompanionValfar.esp"))	; OS_CV_Valfar
	endif
	; Arissa custom follower
	if ArissaOK
		CHFollowerIgnoreList.AddForm(GetFormFromFile(0xd62, "CompanionArissa.esp"))	; Arissa
	endif
	
	; Queue for a faction relations update if new factions were added
	if (DawnguardOK && !DawnguardInit) || (DragonbornOK && !DragonbornInit) || (FalskaarOK && !FalskaarInit) || (WyrmstoothOK && !WyrmstoothInit) || (SkyTESTOK && !SkyTESTInit)
		CHFactionRelationsUpdate.SetValue(1)
	endif

	; Remember which mods were initialized
	VersionInit = CHVersion
	DawnguardInit = DawnguardOK
	DragonbornInit = DragonbornOK
	HearthFiresInit = HearthFiresOK
	FalskaarInit = FalskaarOK
	WyrmstoothInit = WyrmstoothOK
	HothInit = HothOK
	ValfarInit = ValfarOK
	ArissaInit = ArissaOK
	SkyTESTInit = SkyTESTOK
EndFunction

bool Function CheckLastRiddenHorse()
	actor HorseLastRiddenRef = GetPlayersLastRiddenHorse()
	actor HorseOwnedRef = Alias_Horse.GetActorReference()
	actor HorseSummonRef = Alias_HorseSummon.GetActorReference()

	; Check last ridden horse
	if HorseLastRiddenRef
		if HorseLastRiddenRef.IsDisabled() || HorseLastRiddenRef.IsDeleted() || HorseLastRiddenRef.IsDead()
			HorseLastRiddenRef = None
		endif
	endif

	; Check owned horse - clear alias if invalid
	if HorseOwnedRef
		if HorseOwnedRef.IsDeleted()
			HorseScript.ForceDismissal()
			HorseOwnedRef = None
		endif
	endif

	; Check summoned horse - clear alias if invalid
	if HorseSummonRef
		if HorseSummonRef.IsDisabled() || HorseSummonRef.IsDeleted()
			HorseSummonScript.ForceDismissal()
			HorseSummonRef = None
		endif
	endif

	; No horses
	if !(HorseLastRiddenRef || HorseOwnedRef || HorseSummonRef)
		return false
	endif

	; Last ridden horse management
	if HorseLastRiddenRef
		; Summoned horse alias handling
		if HorseLastRiddenRef.IsCommandedActor()
			if HorseLastRiddenRef != HorseSummonRef
				; Set alias to last ridden horse
				HorseSummonScript.SetNewHorse(HorseLastRiddenRef)
				HorseSummonRef = HorseLastRiddenRef
			endif
		; Owned horse alias handling
		else
			if HorseLastRiddenRef != HorseOwnedRef
				; Set alias to last ridden horse
				HorseScript.SetNewHorse(HorseLastRiddenRef)
				HorseOwnedRef = HorseLastRiddenRef
			endif
		endif

		; Clear last ridden horse handle on player
		if SKSEOK && CHHorseTrackingDisable.GetValue()
			if HorseLastRiddenRef == HorseOwnedRef && !HorseOwnedRef.IsBeingRidden()
				SetPlayersLastRiddenMount(None)
			endif
		endif
	endif

	; Summoned horse maintenance
	if HorseSummonRef
		; Make sure activation is blocked/unblocked
		if HorseSummonScript.GetState() == "MultiTap"
			if !HorseSummonRef.IsActivationBlocked()
				HorseSummonRef.BlockActivation(True)
			endif
		elseif PlayerScript.GetState() == "BoundKey"
			if HorseSummonRef.IsActivationBlocked()
				HorseSummonRef.BlockActivation(False)
			endif
		endif
	endif

	; Owned horse maintenance
	if HorseOwnedRef
		; Make sure activation is blocked/unblocked
		if HorseScript.GetState() == "MultiTap"
			if !HorseOwnedRef.IsActivationBlocked()
				HorseOwnedRef.BlockActivation(True)
			endif
		elseif PlayerScript.GetState() == "BoundKey"
			if HorseOwnedRef.IsActivationBlocked()
				HorseOwnedRef.BlockActivation(False)
			endif
		endif
		; Update Horse armor
		UpdateHorseEquipment(HorseOwnedRef)
	endif

	return true
EndFunction

Function SetPlayersLastRiddenMount(Actor akHorse = none, Bool abRestore = false)
	if !SKSEOK
		return
	endif
	if abRestore
		akHorse = Alias_Horse.GetActorReference()
	endif
	SetPlayersLastRiddenHorse(akHorse)	; This function requires SKSE 1.6.10+
EndFunction

Function UpdateHorseEquipment(Actor akHorse, Bool abForceRemove = false)
	if !akHorse
		return
	endif
	if akHorse.GetRace() != HorseRace
		return
	endif
	if abForceRemove || !IsValidEquipment((CHHorseEquipmentMode.GetValue() as Int) - 1)
		if akHorse.GetItemCount(CHHorseEquipmentList)
			akHorse.RemoveItem(CHHorseEquipmentList)
			HideMane(akHorse, true, false, false)
		endif
	elseif !akHorse.IsEquipped(CHHorseEquipmentList.GetAt((CHHorseEquipmentMode.GetValue() as Int) - 1))
		if akHorse.GetItemCount(CHHorseEquipmentList)
			akHorse.RemoveItem(CHHorseEquipmentList)
		endif
		akHorse.EquipItem(CHHorseEquipmentList.GetAt((CHHorseEquipmentMode.GetValue() as Int) - 1))
		if CHHorseEquipmentList.GetAt((CHHorseEquipmentMode.GetValue() as Int) - 1).HasKeyword(CHHorseArmor)
			HideMane(akHorse, false, false, false)
		else
			HideMane(akHorse, true, false, false)
		endif
	endif
EndFunction

Function HideMane(Actor akHorse, bool abShowMane = false, bool abInstant = false, bool abForceAnimation = false)
	; new horse
	if ManeTrackedHorse != akHorse
		ManeTrackedHorse = akHorse
		IsManeHidden = false
		;abForceAnimation = true
	endif
	; handle mane
	if akHorse
		if abShowMane
			if abForceAnimation || IsManeHidden
				if akHorse.Is3DLoaded()
					if abInstant
						akHorse.PlaySubGraphAnimation("ManeThere")
					else
						akHorse.PlaySubGraphAnimation("ManeFadeIn")
					endif
				endif
			endif
			IsManeHidden = false
		else
			if abForceAnimation || !IsManeHidden
				if akHorse.Is3DLoaded()
					if abInstant
						akHorse.PlaySubGraphAnimation("ManeGone")
					else
						akHorse.PlaySubGraphAnimation("ManeFadeOut")
					endif
				endif
			endif
			IsManeHidden = true
		endif
	endif
EndFunction

Bool Function IsValidEquipment(Int EquipmentIndex)
	if EquipmentIndex < 0 || EquipmentIndex >= CHHorseEquipmentList.GetSize()
		return false
	endif
	if CHHorseEquipmentList.GetAt(EquipmentIndex).HasKeyword(CHRequiresDawnguard) && !DawnguardOK
		return false
	endif
	return true
EndFunction

Function GoToMode(string asMode = "", bool abForceMessage = false)	; Manage horse and player script states
	if !asMode
		if PlayerScript.GetState()
			PlayerScript.GoToState("")
		endif
		if HorseScript.GetState()
			HorseScript.GoToState("")
		endif
		if HorseSummonScript.GetState()
			HorseSummonScript.GoToState("")
		endif
	elseif asMode == "MultiTap"
		if HorseScript.GetState() != "MultiTap" || HorseSummonScript.GetState() != "MultiTap"
			HorseScript.GoToState("MultiTap")
			HorseSummonScript.GoToState("MultiTap")
			if !abForceMessage
				CHModeMultiTapMessage.Show()
			endif
		endif
		if PlayerScript.GetState()
			PlayerScript.GoToState("")
		endif
		if abForceMessage
			CHModeMultiTapMessage.Show()
		endif
	elseif asMode == "BoundKey"
		if PlayerScript.GetState() != "BoundKey"
			PlayerScript.GoToState("BoundKey")
			if !abForceMessage
				CHModeBoundKeyMessage.Show()
			endif
		endif
		if HorseScript.GetState() || HorseSummonScript.GetState()
			HorseScript.GoToState("")
			HorseSummonScript.GoToState("")
		endif
		if abForceMessage
			CHModeBoundKeyMessage.Show()
		endif
	endif
EndFunction

Function SetFactionRelations(bool abIsFriendly = true)	; Update horse faction relations
	faction curFaction
	float timeStart = GetCurrentRealTime()
	int numFactions = CHFactionList.GetSize()
	int factionIndex = 0
	while factionIndex < numFactions
		curFaction = CHFactionList.GetAt(factionIndex) as faction
		if curFaction
			if abIsFriendly
				CHHorseFaction.SetAlly(curFaction, true, true)	; friendly two-way relation
			else
				CHHorseFaction.SetEnemy(curFaction, true, true)	; neutral two-way relation
			endif
		endif
		factionIndex += 1
		if (GetCurrentRealTime() - timeStart) > 4	; prevents message spam
			CHFactionUpdateMessage.Show((factionIndex as float / numFactions) * 100)
			timeStart = GetCurrentRealTime()
		endif
	endwhile
	if abIsFriendly
		CHFactionCompleteFriendlyMessage.Show()
	else
		CHFactionCompleteNeutralMessage.Show()
	endif
EndFunction

Function UpdateBoundKeys()
	; This will re-register keys via state's begin/end events
	if PlayerScript.GetState() == "BoundKey"
		PlayerScript.GoToState("BoundKey")
	endif
EndFunction

Function OpenHorseInventory()
	; already in menu mode, can't open
	if IsInMenuMode()
		return
	endif
	; weight limited - indirect access, spawn temporary actor that will act as a medium
	if CHHorseInventoryWeightLimit.GetValue() > 0
		Actor SackMedium = SpawnMarker.PlaceAtMe(CHHorseSackMedium, abInitiallyDisabled = true) as Actor
		if !SackMedium
			return
		endif
		; mod the carry weight limit on spawned actor - base should be 0 according to race it uses
		SackMedium.ModActorValue("CarryWeight", CHHorseInventoryWeightLimit.GetValue())
		; transfer all items from main container
		Alias_Sack.GetReference().RemoveAllItems(SackMedium, true, true)
		; open actor's inventory
		SackMedium.OpenInventory(true)
		; wait till menu closes
		wait(0.1)
		; transfer back items and delete temporary actor
		SackMedium.RemoveAllItems(Alias_Sack.GetReference(), true, true)
		SackMedium.Delete()
		SackMedium = None
	; weight unlimited - access items directly
	else
		; open main container
		Alias_Sack.GetReference().Activate(GetPlayer())
	endif
EndFunction
