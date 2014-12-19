Scriptname CHFollowerQuestScript extends Quest Conditional
{Script by Alek (mitchalek@yahoo.com).
Attached to CHFollower quest, periodically collect refs from external follower aliases and manages local follower aliases.}

Import Game

; There are hard coded functions in this script that expect these constants so changing them alone will do only harm
Int property NumStandardFollowersSupported = 15 AutoReadOnly	; Recruited via DialogeFollower quest
Int property NumSpecialFollowersSupported = 7 AutoReadOnly	; Using unique recruitment mechanics

CHQuestScript property CH auto

GlobalVariable property CHFollowerCountTotal auto
GlobalVariable property CHFollowerCountFollowing auto
GlobalVariable property CHFollowerCountMountedCombat auto
Keyword property ActorTypeNPC auto
Faction property CurrentFollowerFaction auto
Faction property CHFollowerFaction auto
FormList property CHFollowerIgnoreList auto
ReferenceAlias[] property FollowerRefAlias auto

; Dark brotherhood follower related
DarkBrotherhood property DBScript auto
ReferenceAlias property DBCiceroRefAlias auto
ReferenceAlias property DBInitiate1RefAlias auto
ReferenceAlias property DBInitiate2RefAlias auto
ReferenceAlias property DBCiceroSourceRefAlias auto
ReferenceAlias property DBInitiate1SourceRefAlias auto
ReferenceAlias property DBInitiate2SourceRefAlias auto
; Serana follower related
ReferenceAlias property SeranaRefAlias auto
Quest SeranaSourceQuest
ReferenceAlias SeranaSourceRefAlias
Bool property IsSeranaQuestLineCompleted auto hidden conditional
Bool property IsSeranaFollowing auto hidden conditional
Bool property IsSeranaDismissed auto hidden conditional
; Arissa follower related
ReferenceAlias property ArissaRefAlias auto
Quest ArissaSourceQuest
ReferenceAlias ArissaSourceRefAlias
Bool property IsArissaFollowing auto hidden conditional
Bool property IsArissaWaiting auto hidden conditional
Bool property IsArissaDismissed auto hidden conditional
; Hoth follower related
ReferenceAlias property HothRefAlias auto
; Valfar follower related
ReferenceAlias property ValfarRefAlias auto
ReferenceAlias ValfarSourceRefAlias
GlobalVariable property ValfarFollowGlobal auto hidden
GlobalVariable property ValfarRelaxGlobal auto hidden
Bool property IsValfarFollowing auto hidden conditional
Bool property IsValfarRelaxing auto hidden conditional

Bool bGameLoaded = true
Bool property GameLoaded hidden	; Set from CHPlayerAliasScript game load event
	Bool Function Get()
		if bGameLoaded
			bGameLoaded = false
			return true
		else
			return false
		endif
	EndFunction
	Function Set(bool value)
		bGameLoaded = value
		RegisterForSingleUpdate(5)
	EndFunction
EndProperty

Quest FollowerQuestSource
ReferenceAlias[] FollowerQuestSourceAliasRefs

; Deferred dismount related
CHFollowerPlayerAliasScript property PlayerAliasScript auto
GlobalVariable property CHFollowerDeferredDismountEnable auto
Bool RegisteredForPlayerDismountEvent

Event OnInit()
	CHFollowerCountTotal.SetValue(0)
	CHFollowerCountFollowing.SetValue(0)
	CHFollowerCountMountedCombat.SetValue(0)
	RegisterForSingleUpdate(1)
EndEvent

Event OnUpdate()
	if !IsRunning()
		return
	endif

	int curSourceAlias	

	; detect follower source quest and fetch follower reference aliases - only on game load
	if GameLoaded
		FollowerQuestSourceAliasRefs = new ReferenceAlias[15]	; Create new array
		if CH.EFFOK
			FollowerQuestSource = GetFormFromFile(0xeff, "EFFCore.esm") as Quest	; EFF - FollowerExtension quest
		elseif CH.UFOOK
			FollowerQuestSource = GetFormFromFile(0x53a2e, "UFO - Ultimate Follower Overhaul.esp") as Quest	; UFO - 0fLokii_FollowerControl quest
		else
			FollowerQuestSource = GetForm(0x750ba) as Quest	; DialogueFollower quest
		endif
		if CH.DawnguardOK
			SeranaSourceQuest = GetFormFromFile(0x2b6e, "Dawnguard.esm") as Quest
			SeranaSourceRefAlias = SeranaSourceQuest.GetAlias(0) as ReferenceAlias
		else
			SeranaSourceQuest = None
			SeranaSourceRefAlias = None
		endif
		if CH.ArissaOK
			ArissaSourceQuest = GetFormFromFile(0x1d97, "CompanionArissa.esp") as Quest
			ArissaSourceRefAlias = ArissaSourceQuest.GetAlias(1) as ReferenceAlias
		else
			ArissaSourceQuest = None
			ArissaSourceRefAlias = None
		endif
		if CH.ValfarOK
			ValfarSourceRefAlias = (GetFormFromFile(0x7ab1, "CompanionValfar.esp") as Quest).GetAlias(0) as ReferenceAlias	; OS_CV_Recruitment quest
			ValfarFollowGlobal = GetFormFromFile(0xe6bd, "CompanionValfar.esp") as GlobalVariable
			ValfarRelaxGlobal = GetFormFromFile(0xc660, "CompanionValfar.esp") as GlobalVariable
		else
			ValfarSourceRefAlias = None
			ValfarFollowGlobal = None
			ValfarRelaxGlobal = None
		endif

		; follower source checks
		ReferenceAlias sourceRefAlias
		int numAliasIDs = 20	; probe source quest for this many IDs
		int curSourceAliasID = 0
		curSourceAlias = 0

		; if using Interesting NPCs mod
		if CH.InterestingNPCsOK
			sourceRefAlias = (GetFormFromFile(0x13184c, "3DNPC.esp") as Quest).GetAlias(18) as ReferenceAlias
			if sourceRefAlias
				FollowerQuestSourceAliasRefs[curSourceAlias] = sourceRefAlias
				curSourceAlias += 1			
			endif
		endif
		
		; incrementally search for alias IDs in source quest
		while curSourceAliasID < numAliasIDs && curSourceAlias < FollowerQuestSourceAliasRefs.length
			; skip if animal follower in DialogueFollower quest
			if curSourceAliasID == 1
				if !CH.EFFOK && !CH.UFOOK
					curSourceAliasID += 1
				endif
			endif
			sourceRefAlias = FollowerQuestSource.GetAlias(curSourceAliasID) as ReferenceAlias
			if sourceRefAlias
				FollowerQuestSourceAliasRefs[curSourceAlias] = sourceRefAlias
				curSourceAlias += 1
			endif
			curSourceAliasID += 1
		endwhile
		
		; recheck horse equipment on game load because some texture dependancies can go missing
		RegisterForHorseUpdate(false, true)
	endif
	
	; search through the RefAlias collection and try to add newly recruited followers
	int curLocalAlias
	Actor sourceFollowerRef
	curSourceAlias = 0
	while curSourceAlias < FollowerQuestSourceAliasRefs.length && FollowerQuestSourceAliasRefs[curSourceAlias]
		sourceFollowerRef = FollowerQuestSourceAliasRefs[curSourceAlias].GetActorReference()
		if sourceFollowerRef
			if sourceFollowerRef.HasKeyword(ActorTypeNPC) && sourceFollowerRef.IsInFaction(CurrentFollowerFaction) && !sourceFollowerRef.IsInFaction(CHFollowerFaction)
				if !CHFollowerIgnoreList.HasForm(sourceFollowerRef.GetActorBase())
					; find first empty local alias, add follower to it and start the script
					bool bLoop = true
					curLocalAlias = 0
					while curLocalAlias < FollowerRefAlias.length && bLoop
						if !FollowerRefAlias[curLocalAlias].GetActorReference()
							FollowerRefAlias[curLocalAlias].ForceRefTo(sourceFollowerRef)
							(FollowerRefAlias[curLocalAlias] as CHFollowerAliasScript).GoToState("Recruited")
							bLoop = false
						endif
						curLocalAlias += 1
					endwhile
				; handle followers that should be assigned to unique alias
				else
					if CH.HothOK
						if sourceFollowerRef.GetActorBase() == GetFormFromFile(0xd62, "HothFollower.esp")
							if HothRefAlias.GetActorReference() != sourceFollowerRef
								HothRefAlias.ForceRefTo(sourceFollowerRef)
								(HothRefAlias as CHFollowerAliasScript).GoToState("Recruited")
							endif
						endif
					endif
				endif
			endif
		endif
		curSourceAlias += 1
	endwhile

	; dark brotherhood followers
	if DBScript.CiceroFollower && !DBCiceroRefAlias.GetActorReference() && DBCiceroSourceRefAlias.GetActorReference()
		DBCiceroRefAlias.ForceRefTo(DBCiceroSourceRefAlias.GetActorReference())
		(DBCiceroRefAlias as CHFollowerAliasScript).GoToState("Recruited")
	endif
	if DBScript.Initiate1Follower && !DBInitiate1RefAlias.GetActorReference() && DBInitiate1SourceRefAlias.GetActorReference()
		DBInitiate1RefAlias.ForceRefTo(DBInitiate1SourceRefAlias.GetActorReference())
		(DBInitiate1RefAlias as CHFollowerAliasScript).GoToState("Recruited")
	endif
	if DBScript.Initiate2Follower && !DBInitiate2RefAlias.GetActorReference() && DBInitiate2SourceRefAlias.GetActorReference()
		DBInitiate2RefAlias.ForceRefTo(DBInitiate2SourceRefAlias.GetActorReference())
		(DBInitiate2RefAlias as CHFollowerAliasScript).GoToState("Recruited")
	endif

	if CH.DawnguardOK
		UpdateSerana()
	endif

	if CH.ArissaOK
		UpdateArissa()
	endif

	if CH.ValfarOK
		UpdateValfar()
	endif

	; Deferred dismount - (un)registers for dismount animation event
	if CHFollowerDeferredDismountEnable.GetValue() && !RegisteredForPlayerDismountEvent
		RegisteredForPlayerDismountEvent = PlayerAliasScript.RegisterForAnimationEvent(GetPlayer(), "HorseExitOut")
	elseif !CHFollowerDeferredDismountEnable.GetValue() && RegisteredForPlayerDismountEvent
		PlayerAliasScript.UnregisterForAnimationEvent(GetPlayer(), "HorseExitOut")
		RegisteredForPlayerDismountEvent = False
	endif

	RegisterForSingleUpdate(5)
EndEvent


; *** Serana related
; *******************
Function UpdateSerana()
	IsSeranaQuestLineCompleted = (SeranaSourceQuest as DLC1_NPCMentalModelScript).QuestLineCompleted
	IsSeranaFollowing = (SeranaSourceQuest as DLC1_NPCMentalModelScript).IsFollowing
	IsSeranaDismissed = (SeranaSourceQuest as DLC1_NPCMentalModelScript).IsDismissed
	if IsSeranaFollowing && !SeranaRefAlias.GetActorReference() && SeranaSourceRefAlias.GetActorReference()
		SeranaRefAlias.ForceRefTo(SeranaSourceRefAlias.GetActorReference())
		(SeranaRefAlias as CHFollowerAliasScript).GoToState("Recruited")
	endif
EndFunction
Bool Function GetSeranaQuestLineCompleted()
	if !CH.DawnguardOK
		return false
	endif
	IsSeranaQuestLineCompleted = (SeranaSourceQuest as DLC1_NPCMentalModelScript).QuestLineCompleted
	return IsSeranaQuestLineCompleted
EndFunction
Bool Function GetSeranaFollowing()
	if !CH.DawnguardOK
		return false
	endif
	IsSeranaFollowing = (SeranaSourceQuest as DLC1_NPCMentalModelScript).IsFollowing
	return IsSeranaFollowing
EndFunction
Bool Function GetSeranaDismissed()
	if !CH.DawnguardOK
		return false
	endif
	IsSeranaDismissed = (SeranaSourceQuest as DLC1_NPCMentalModelScript).IsDismissed
	return IsSeranaDismissed
EndFunction


; *** Arissa related
; ******************
Function UpdateArissa()
	IsArissaFollowing = (ArissaSourceQuest as _Arissa_iNPC_Behavior).IsFollowing
	IsArissaDismissed = (ArissaSourceQuest as _Arissa_iNPC_Behavior).IsDismissed
	IsArissaWaiting = (ArissaSourceQuest as _Arissa_iNPC_Behavior).IsWaiting
	if IsArissaFollowing && !ArissaRefAlias.GetActorReference() && ArissaSourceRefAlias.GetActorReference()
		if SetArissaUseOwnHorse(false)
			ArissaRefAlias.ForceRefTo(ArissaSourceRefAlias.GetActorReference())
			(ArissaRefAlias as CHFollowerAliasScript).GoToState("Recruited")
		endif
	endif
EndFunction
Bool Function GetArissaFollowing()
	if !CH.ArissaOK
		return false
	endif
	IsArissaFollowing = (ArissaSourceQuest as _Arissa_iNPC_Behavior).IsFollowing
	return IsArissaFollowing
EndFunction
Bool Function GetArissaWaiting()
	if !CH.ArissaOK
		return false
	endif
	IsArissaWaiting = (ArissaSourceQuest as _Arissa_iNPC_Behavior).IsWaiting
	return IsArissaWaiting
EndFunction
Bool Function GetArissaDismissed()
	if !CH.ArissaOK
		return false
	endif
	IsArissaDismissed = (ArissaSourceQuest as _Arissa_iNPC_Behavior).IsDismissed
	return IsArissaDismissed
EndFunction
Bool Function SetArissaUseOwnHorse(bool abEnable)
	if !CH.ArissaOK
		return false
	endif
	return (ArissaSourceQuest as _Arissa_iNPC_Behavior).SetUseOwnHorse(abEnable)
EndFunction


; *** Valfar related
; ******************
Function UpdateValfar()
	IsValfarFollowing = ValfarFollowGlobal.GetValue() as Bool
	IsValfarRelaxing = ValfarRelaxGlobal.GetValue() as Bool
	if IsValfarFollowing && !ValfarRefAlias.GetActorReference() && ValfarSourceRefAlias.GetActorReference()
		ValfarRefAlias.ForceRefTo(ValfarSourceRefAlias.GetActorReference())
		(ValfarRefAlias as CHFollowerAliasScript).GoToState("Recruited")
	endif
EndFunction
Bool Function GetValfarFollowing()
	if !CH.ValfarOK
		return false
	endif
	IsValfarFollowing = ValfarFollowGlobal.GetValue() as Bool
	return IsValfarFollowing
EndFunction
Bool Function GetValfarRelaxing()
	if !CH.ValfarOK
		return false
	endif
	IsValfarRelaxing = ValfarRelaxGlobal.GetValue() as Bool
	return IsValfarRelaxing
EndFunction



; *** Horse skin/armor update (via dialogue)
; ******************************************
Function FollowerHorseChange(Actor akFollower, Int aiPart, Int aiPartIndex)	; aiPart: 0 - Skin, 1 - Equipment
	if !akFollower || (aiPart != 0 && aiPart != 1)
		return
	endif
	; Search local aliases for passed in follower and update
	int index
	while index < FollowerRefAlias.length
		if FollowerRefAlias[index].GetActorReference() == akFollower
			if aiPart == 0
				(FollowerRefAlias[index] as CHFollowerAliasScript).HorseSkin = aiPartIndex
			elseif aiPart == 1
				(FollowerRefAlias[index] as CHFollowerAliasScript).HorseEquipment = aiPartIndex
			endif
			return
		endif
		index += 1
	endwhile
	if SeranaRefAlias.GetActorReference() == akFollower
		if aiPart == 0
			(SeranaRefAlias as CHFollowerAliasScript).HorseSkin = aiPartIndex
		elseif aiPart == 1
			(SeranaRefAlias as CHFollowerAliasScript).HorseEquipment = aiPartIndex
		endif
		return
	endif
	if ArissaRefAlias.GetActorReference() == akFollower
		if aiPart == 0
			(ArissaRefAlias as CHFollowerAliasScript).HorseSkin = aiPartIndex
		elseif aiPart == 1
			(ArissaRefAlias as CHFollowerAliasScript).HorseEquipment = aiPartIndex
		endif
		return
	endif
	if HothRefAlias.GetActorReference() == akFollower
		if aiPart == 0
			(HothRefAlias as CHFollowerAliasScript).HorseSkin = aiPartIndex
		elseif aiPart == 1
			(HothRefAlias as CHFollowerAliasScript).HorseEquipment = aiPartIndex
		endif
		return
	endif
	if ValfarRefAlias.GetActorReference() == akFollower
		if aiPart == 0
			(ValfarRefAlias as CHFollowerAliasScript).HorseSkin = aiPartIndex
		elseif aiPart == 1
			(ValfarRefAlias as CHFollowerAliasScript).HorseEquipment = aiPartIndex
		endif
		return
	endif
	if DBCiceroRefAlias.GetActorReference() == akFollower
		if aiPart == 0
			(DBCiceroRefAlias as CHFollowerAliasScript).HorseSkin = aiPartIndex
		elseif aiPart == 1
			(DBCiceroRefAlias as CHFollowerAliasScript).HorseEquipment = aiPartIndex
		endif
		return
	endif
	if DBInitiate1RefAlias.GetActorReference() == akFollower
		if aiPart == 0
			(DBInitiate1RefAlias as CHFollowerAliasScript).HorseSkin = aiPartIndex
		elseif aiPart == 1
			(DBInitiate1RefAlias as CHFollowerAliasScript).HorseEquipment = aiPartIndex
		endif
		return
	endif
	if DBInitiate2RefAlias.GetActorReference() == akFollower
		if aiPart == 0
			(DBInitiate2RefAlias as CHFollowerAliasScript).HorseSkin = aiPartIndex
		elseif aiPart == 1
			(DBInitiate2RefAlias as CHFollowerAliasScript).HorseEquipment = aiPartIndex
		endif
		return
	endif
EndFunction

; *** Queue for skin/equipment update on all followers' horses
; ************************************************************
Function RegisterForHorseUpdate(bool UpdateSkin = true, bool UpdateEquipment = true)
	if !UpdateSkin && !UpdateEquipment
		return
	endif
	int numFollowerScripts = GetNumFollowerAliasScripts()
	int index = 0
	while index < numFollowerScripts
		if UpdateSkin
			GetNthFollowerAliasScript(index).HorseSkin = -1
		endif
		if UpdateEquipment
			GetNthFollowerAliasScript(index).HorseEquipment = -1
		endif
		index += 1
	endwhile
EndFunction

; *** Gives back removed torches to all followers
; ***********************************************
Function GiveBackTorches()
	int numFollowerScripts = GetNumFollowerAliasScripts()
	int index = 0
	while index < numFollowerScripts
		GetNthFollowerAliasScript(index).RemovedTorchCount = 0
		index += 1
	endwhile
EndFunction

; *** Follower reference alias script repository
; **********************************************

Int Function GetNumFollowerAliasScripts()
	return NumStandardFollowersSupported + NumSpecialFollowersSupported
EndFunction

CHFollowerAliasScript Function GetNthFollowerAliasScript(Int aiIndex)
	; According to CHFollower quest aliasID assignment ...
	; Return special followers first
	if aiIndex == 0	; Serana
		return GetAlias(37) as CHFollowerAliasScript
	elseif aiIndex == 1	; Arissa
		return GetAlias(65) as CHFollowerAliasScript
	elseif aiIndex == 2	; Hoth
		return GetAlias(59) as CHFollowerAliasScript
	elseif aiIndex == 3	; Valfar
		return GetAlias(62) as CHFollowerAliasScript
	elseif aiIndex == 4	; DBCicero
		return GetAlias(31) as CHFollowerAliasScript
	elseif aiIndex == 5	; DBInitiate1
		return GetAlias(32) as CHFollowerAliasScript
	elseif aiIndex == 6	; DBInitiate2
		return GetAlias(33) as CHFollowerAliasScript
	; The rest are standard followers with aliasID ranging from 0 to 14
	else
		return GetAlias(aiIndex-NumSpecialFollowersSupported) as CHFollowerAliasScript
	endif
EndFunction


