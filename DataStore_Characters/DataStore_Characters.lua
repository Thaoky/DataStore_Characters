--[[	*** DataStore_Characters ***
Written by : Thaoky, EU-Marécages de Zangar
July 18th, 2009
--]]
if not DataStore then return end

local addonName, addon = ...
local thisCharacter
local guildRanks
local options

local DataStore = DataStore
local UnitName, UnitLevel, UnitClass, UnitRace, UnitSex, UnitXP, UnitXPMax = UnitName, UnitLevel, UnitClass, UnitRace, UnitSex, UnitXP, UnitXPMax
local GetRealZoneText, GetSubZoneText, GetGuildInfo, GetXPExhaustion, GetMoney, GetBindLocation = GetRealZoneText, GetSubZoneText, GetGuildInfo, GetXPExhaustion, GetMoney, GetBindLocation
local IsResting, IsXPUserDisabled, format, time = IsResting, IsXPUserDisabled, format, time
local C_CovenantSanctumUI, C_Covenants, C_Soulbinds, C_CreatureInfo, C_ClassColor = C_CovenantSanctumUI, C_Covenants, C_Soulbinds, C_CreatureInfo, C_ClassColor
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

local bit64 = LibStub("LibBit64")
local bAnd = bit.band
local bOr = bit.bor

local isCoreDataMissing
local MAX_LOGOUT_TIMESTAMP = 5000000000	-- 5 billion, current values are at ~1.4 billion, in seconds, that leaves us 110+ years, I think we're covered..
local MAX_ALT_LEVEL = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC
	and MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()]
	or MAX_PLAYER_LEVEL


-- *** Scanning functions ***
local function ScanBaseInfo()
	thisCharacter.BaseInfo = UnitLevel("player")						-- bits 0-6 = level
		+ bit64:LeftShift(select(3, UnitClass("player")), 7)		-- bits 7-10 = classID
		+ bit64:LeftShift(select(3, UnitRace("player")), 11)		-- bits 11-17 = raceID
		+ bit64:LeftShift(UnitSex("player"), 18)						-- bits 18-19 = gender
end

local function ScanPlayerLocation()
	local char = thisCharacter
	
	char.zone = GetRealZoneText()
	char.subZone = GetSubZoneText()
end

local function ScanCovenant()
	thisCharacter.CovenantInfo = C_CovenantSanctumUI.GetRenownLevel()		-- bits 0-6 = renown level
		+ bit64:LeftShift(C_Covenants.GetActiveCovenantID(), 7)				-- bits 7-10 = covenantID
		+ bit64:LeftShift(C_Soulbinds.GetActiveSoulbindID(), 11)				-- bits 11+ = soulbindID
end


-- *** Event Handlers ***
local function OnPlayerGuildUpdate()

	-- at login this event is called between OnEnable and PLAYER_ALIVE, where GetGuildInfo returns a wrong value
	-- however, the value returned here is correct
	local char = thisCharacter
	local guildID = DataStore:GetCharacterGuildID(DataStore.ThisCharKey)
	
	if IsInGuild() and guildID then
		
		-- point to the guild
		guildRanks[guildID] = guildRanks[guildID] or {}
		local guildData = guildRanks[guildID]
		
		-- find a way to improve this, it's minor, but it's called too often at login
		local _, rank, index = GetGuildInfo("player")
		guildData[index] = rank
		
		char.guildRankIndex = index
	end
	
	-- If the event is triggered after a gkick/gquit, be sure to clean the guild info
	-- char.guildRankIndex = nil
	
	-- if the character had a guild when entering this function, but is no longer in a guild, then trigger the event
	if guildID then
		DataStore:Broadcast("DATASTORE_GUILD_LEFT")
	end
end

local function ScanXPDisabled()
	thisCharacter.BaseInfo = IsXPUserDisabled()
		and bit64:SetBit(thisCharacter.BaseInfo, 20)
		or bit64:ClearBit(thisCharacter.BaseInfo, 20)
end

local function OnPlayerUpdateResting()
	thisCharacter.BaseInfo = IsResting()
		and bit64:SetBit(thisCharacter.BaseInfo, 21)
		or bit64:ClearBit(thisCharacter.BaseInfo, 21)
end

local function OnPlayerXPUpdate()
	-- In cataclysm, max xp goes beyond 20 bits or 1 million, so revert back to plain values
	-- thisCharacter.XPInfo = UnitXP("player")				-- bits 0-19 = player XP
		-- + bit64:LeftShift(UnitXPMax("player"), 20)		-- bits 20-39 = XP Max
		-- + bit64:LeftShift(GetXPExhaustion() or 0, 40)	-- bits 40+ = rest XP
		
	thisCharacter.XP = UnitXP("player")
	thisCharacter.maxXP = UnitXPMax("player") 
	thisCharacter.restXP = GetXPExhaustion()
	thisCharacter.XPInfo = nil		-- kill the old value
end

local function OnPlayerMoney()
	thisCharacter.money = GetMoney()
end

local function OnPlayerAlive()
	local char = thisCharacter

	char.name = UnitName("player")		-- to simplify processing a bit, the name is saved in the table too, in addition to being part of the key
	char.bindLocation = GetBindLocation()
	char.lastLogoutTimestamp = MAX_LOGOUT_TIMESTAMP
	
	ScanBaseInfo()
	
	OnPlayerMoney()
	OnPlayerXPUpdate()
	OnPlayerUpdateResting()
	OnPlayerGuildUpdate()
	
	if isRetail then
		ScanXPDisabled()
		ScanCovenant()
	end
	
	char.lastUpdate = time()
end

local function OnPlayerLogout()
	local char = thisCharacter
	
	char.lastLogoutTimestamp = time()
	char.lastUpdate = time()
end

local function OnPlayerLevelUp(event, newLevel)
	
	-- update the first 7 bits only
	local cleared = bAnd(thisCharacter.BaseInfo, 0xFFFFFF80)
	thisCharacter.BaseInfo =  bOr(cleared, bAnd(newLevel, 0x7F))
end

local function OnHearthstoneBound(event)
	thisCharacter.bindLocation = GetBindLocation()
end

local function OnTimePlayedMsg(event, totalTime, currentLevelTime)
	thisCharacter.played = totalTime
	thisCharacter.playedThisLevel = currentLevelTime
end


-- ** Mixins **
local function _GetCharacterName(character)
	return character.name
end

local function _GetCharacterLevel(character)
	return bit64:GetBits(character.BaseInfo, 0, 7)	-- bits 0-6 = level
end

local function _GetCharacterRace(character)
	local raceID = bit64:GetBits(character.BaseInfo, 11, 7)	-- bits 11-17 = raceID
	local info = C_CreatureInfo.GetRaceInfo(raceID)
	
	-- localized name, e.g. "Night Elf" + non-localized name, e.g. "NightElf"
	return info.raceName or "", info.clientFileString or "", raceID
end

local function _GetCharacterClass(character)
	local classID = bit64:GetBits(character.BaseInfo, 7, 4)	-- bits 7-10 = classID
	local info = C_CreatureInfo.GetClassInfo(classID)

	-- Localized name, e.g. "Warrior" or "Guerrier" + "WARRIOR" + 1
	return info.className or "", info.classFile or "", classID
end

local classColors

if not isRetail then
	classColors = {
		["HUNTER"] = "|cffaad372",
		["WARRIOR"] = "|cffc69b6d",
		["PALADIN"] = "|cfff48cba",
		["MAGE"] = "|cff3fc6ea",
		["PRIEST"] = "|cFFFFFFFF",
		["SHAMAN"] = "|cff0070dd",
		["WARLOCK"] = "|cff8787ed",
		["DEMONHUNTER"] = "|cffa330c9",
		["DEATHKNIGHT"] = "|cffc41e3a",
		["DRUID"] = "|cffff7c0a",
		["MONK"] = "|cff00ff96",
		["ROGUE"] = "|cfffff468",
		["EVOKER"] = "|cff33937f",
	}
end

local function _GetClassColor(class)
	return isRetail
		and C_ClassColor.GetClassColor(class):GenerateHexColorMarkup()
		or classColors[class]
end

local function _GetCharacterClassColor(character)
	local _, englishClass = _GetCharacterClass(character)

	-- return just the color of this character's class (based on the character key)
	return _GetClassColor(englishClass)
end

local function _GetColoredCharacterName(character)
	return format("%s%s", _GetCharacterClassColor(character), character.name)
end

local function _GetCharacterFaction(character)
	local raceID = bit64:GetBits(character.BaseInfo, 11, 7)	-- bits 11-17 = raceID
	local info = C_CreatureInfo.GetFactionInfo(raceID)

	-- faction, localized faction name
	return info.groupTag or "", info.name or ""
end

local factionColors = {
	["Alliance"] = "|cFF2459FF",
	["Horde"] = "|cFFFF0000",
	["Neutral"] = "|cFF909090",
}

local function _GetColoredCharacterFaction(character)
	local faction = _GetCharacterFaction(character)
	
	-- for young pandas, who have a "Neutral" faction, use this color if by any chance the group tag is unknown.
	return factionColors[faction] and factionColors[faction] or factionColors["Neutral"]
end

local function _GetCharacterGender(character)
	return bit64:GetBits(character.BaseInfo, 18, 2) or ""	-- bits 18-19 = gender
end

local function _GetLastLogout(character)
	return character.lastLogoutTimestamp or 0
end

local function _GetMoney(character)
	return character.money or 0
end

local function _GetBindLocation(character)
	return character.bindLocation or ""
end

local function _IsResting(character)
	-- isResting = bit 21
	return bit64:TestBit(character.BaseInfo, 21)
end

local function _GetXP(character)
	return character.XPInfo
		and bit64:GetBits(character.XPInfo, 0, 20)	-- bits 0-19 = player XP
		or character.XP 
end

local function _GetXPMax(character)
	return character.XPInfo
		and bit64:GetBits(character.XPInfo, 20, 20)	-- bits 20-39 = XP Max
		or character.maxXP
end

local function _GetRestXP(character)
	return character.XPInfo
		and bit64:RightShift(character.XPInfo, 40)	-- bits 40+ = rest XP
		or character.restXP
end

local function _GetXPRate(character)
	return floor((_GetXP(character) / _GetXPMax(character)) * 100)
end

local function _GetRestXPRate(character)
	-- after extensive tests, it seems that the known formula to calculate rest xp is incorrect.
	-- I believed that the maximum rest xp was exactly 1.5 level, and since 8 hours of rest = 5% of a level
	-- being 100% rested would mean having 150% xp .. but there's a trick...
	-- One would expect that 150% of rest xp would be split over the following levels, and that calculating the exact amount of rest
	-- would require taking into account that 30% are over the current level, 100% over lv+1, and the remaining 20% over lv+2 ..
	
	-- .. But that is not the case.Blizzard only takes into account 150% of rest xp AT THE CURRENT LEVEL RATE.
	-- ex: at level 15, it takes 13600 xp to go to 16, therefore the maximum attainable rest xp is:
	--	136 (1% of the level) * 150 = 20400 

	-- thus, to calculate the exact rate (ex at level 15): 
		-- divide xptonext by 100 : 		13600 / 100 = 136	==> 1% of the level
		-- multiply by 1.5				136 * 1.5 = 204
		-- divide rest xp by this value	20400 / 204 = 100	==> rest xp rate
	
	--[[
		17/09/2018 : After even more extensive tests since right after the launch of BfA, it is now clear that Blizzard is not 
		consistent in their reporting of rest xp.
		
		A simple example: my 110 druid with exactly 0xp / 717.000 should be able to earn 1.5 levels of rest xp at current level rate.
		This should set the maximum at 1.075.500 xp.
		Nevertheless, my druid actually has 1.505.792 xp, and this is not a value that I actually process in datastore before saving it.
		I had the same issue a week ago on my horde monk, which had 2.9M rest xp for a maximum of 3 levels (2.1M xp).
	
	--]] 
	
	local rate = 0
	local multiplier = 1.5
	
	if _GetCharacterRace(character) == "Pandaren" then
		multiplier = 3
	end
	
	local savedXP = 0
	local savedRate = 0
	local xpMax = _GetXPMax(character)
	local restXP = _GetRestXP(character)
	
	local maxXP = xpMax * multiplier
	if restXP then
		rate = restXP / (maxXP / 100)
		savedXP = restXP
		savedRate = rate
	end
	
	-- get the known rate of rest xp (the one saved at last logout) + the rate represented by the elapsed time since last logout
	-- (elapsed time / 3600) * 0.625 * (2/3)  simplifies to elapsed time / 8640
	-- 0.625 comes from 8 hours rested = 5% of a level, *2/3 because 100% rested = 150% of xp (1.5 level)

	local xpEarnedResting = 0
	local rateEarnedResting = 0
	local isFullyRested = false
	local timeUntilFullyRested = 0
	local now = time()
	
	-- time since last logout, MAX_LOGOUT_TIMESTAMP for current char, <> for all others
	if character.lastLogoutTimestamp ~= MAX_LOGOUT_TIMESTAMP then	
		local oneXPBubble = xpMax / 20		-- 5% at current level 
		local elapsed = (now - character.lastLogoutTimestamp)		-- time since last logout, in seconds
		local numXPBubbles = elapsed / 28800		-- 28800 seconds = 8 hours => get the number of xp bubbles earned
		
		xpEarnedResting = numXPBubbles * oneXPBubble
		
		if not _IsResting(character) then
			xpEarnedResting = xpEarnedResting / 4
		end

		-- cap earned XP
		if (xpEarnedResting + savedXP) > maxXP then
			xpEarnedResting = xpEarnedResting - ((xpEarnedResting + savedXP) - maxXP)
		end
	
		-- non negativity
		if xpEarnedResting < 0 then xpEarnedResting = 0 end
		
		rateEarnedResting = xpEarnedResting / (maxXP / 100)
		
		if (savedXP + xpEarnedResting) >= maxXP then
			isFullyRested = true
			rate = 100
		else
			local xpUntilFullyRested = maxXP - (savedXP + xpEarnedResting)
			timeUntilFullyRested = math.floor((xpUntilFullyRested / oneXPBubble) * 28800) -- num bubbles * duration of one bubble in seconds
			
			rate = rate + rateEarnedResting
		end
	end
	
	-- ensure to report that a max level has not earned xp while resting
	if _GetCharacterLevel(character) == MAX_ALT_LEVEL then
		xpEarnedResting = -1
	end
	
	return rate, savedXP, savedRate, rateEarnedResting, xpEarnedResting, maxXP, isFullyRested, timeUntilFullyRested
end

local function _IsXPDisabled(character)
	-- isXPDisabled = bit 20
	return bit64:TestBit(character.BaseInfo, 20)
end
	
local function _GetGuildInfo(character, guildID)
	local ranks = guildRanks[guildID]
	
	if ranks then
		local index = character.guildRankIndex
		return ranks[index], index
	end
end

local function _GetPlayTime(character)
	return options.HideRealPlayTime and 0 or character.played, character.playedThisLevel
end

local function _GetRealPlayTime(character)
	-- return the real play time, not to be displayed, but just for computing (ex: which alt has the highest/lowest played ?)
	return character.played
end

local function _GetLocation(character)
	return character.zone, character.subZone
end

local function _GetCovenantInfo(character)
	local renownLevel = bit64:GetBits(character.CovenantInfo, 0, 7)	-- bits 0-6 = renown level
	local covenantID = bit64:GetBits(character.CovenantInfo, 7, 4)		-- bits 7-10 = covenantID
	local soulbindID = bit64:RightShift(character.CovenantInfo, 11)	-- bits 11+ = soulbindID

	return covenantID, soulbindID, renownLevel
end

local function _GetCovenantName(character)
	local id = bit64:GetBits(character.CovenantInfo, 7, 4)		-- bits 7-10 = covenantID
	local data = C_Covenants.GetCovenantData(id)
	
	return data and data.name or ""
end

DataStore:OnAddonLoaded(addonName, function()
	DataStore:RegisterModule({
		addon = addon,
		addonName = addonName,
		rawTables = {
			"DataStore_Characters_GuildRanks",
			"DataStore_Characters_Options"
		},
		characterTables = {
			["DataStore_Characters_Info"] = {
				GetCharacterName = _GetCharacterName,
				GetCharacterLevel = _GetCharacterLevel,
				GetCharacterRace = _GetCharacterRace,
				GetCharacterClass = _GetCharacterClass,
				GetCharacterClassColor = _GetCharacterClassColor,
				GetColoredCharacterName = _GetColoredCharacterName,
				GetCharacterFaction = _GetCharacterFaction,
				GetColoredCharacterFaction = _GetColoredCharacterFaction,
				GetCharacterGender = _GetCharacterGender,
				GetLastLogout = _GetLastLogout,
				GetMoney = _GetMoney,
				GetBindLocation = _GetBindLocation,
				GetXP = _GetXP,
				GetXPRate = _GetXPRate,
				GetXPMax = _GetXPMax,
				GetRestXP = _GetRestXP,
				GetRestXPRate = _GetRestXPRate,
				IsResting = _IsResting,
				IsXPDisabled = _IsXPDisabled,
				GetGuildInfo = _GetGuildInfo,
				GetLocation = _GetLocation,
				GetPlayTime = _GetPlayTime,
				GetRealPlayTime = _GetRealPlayTime,
				GetCovenantInfo = isRetail and _GetCovenantInfo,
				GetCovenantName = isRetail and _GetCovenantName,
			},
		}
	})

	DataStore:RegisterMethod(addon, "GetClassColor", _GetClassColor)
	
	if isRetail then
		DataStore:RegisterMethod(addon, "GetCovenantNameByID", function(id)
			local data = C_Covenants.GetCovenantData(id)
			return data and data.name or ""
		end)
	end
	
	thisCharacter = DataStore:GetCharacterDB("DataStore_Characters_Info", true)
	guildRanks = DataStore_Characters_GuildRanks
	
	-- Some players seem not to get a proper PLAYER_ALIVE event ..
	ScanBaseInfo()
end)

DataStore:OnPlayerLogin(function()
	options = DataStore:SetDefaults("DataStore_Characters_Options", {
		RequestPlayTime = true,			-- Request play time at logon
		HideRealPlayTime = false,		-- Hide real play time to client addons (= return 0 instead of real value)
	})	
	
	addon:ListenTo("PLAYER_ALIVE", OnPlayerAlive)
	addon:ListenTo("PLAYER_ENTERING_WORLD", OnPlayerAlive)
	addon:ListenTo("PLAYER_LOGOUT", OnPlayerLogout)
	addon:ListenTo("PLAYER_LEVEL_UP", OnPlayerLevelUp)
	addon:ListenTo("PLAYER_MONEY", OnPlayerMoney)
	addon:ListenTo("PLAYER_XP_UPDATE", OnPlayerXPUpdate)
	addon:ListenTo("PLAYER_UPDATE_RESTING", OnPlayerUpdateResting)
	addon:ListenTo("HEARTHSTONE_BOUND", OnHearthstoneBound)
	addon:ListenTo("PLAYER_GUILD_UPDATE", OnPlayerGuildUpdate)				-- for gkick, gquit, etc..
	addon:ListenTo("ZONE_CHANGED", ScanPlayerLocation)
	addon:ListenTo("ZONE_CHANGED_NEW_AREA", ScanPlayerLocation)
	addon:ListenTo("ZONE_CHANGED_INDOORS", ScanPlayerLocation)
	addon:ListenTo("TIME_PLAYED_MSG", OnTimePlayedMsg)					-- register the event if RequestTimePlayed is not called afterwards. If another addon calls it, we want to get the data anyway.
	
	if isRetail then
		addon:ListenTo("ENABLE_XP_GAIN", ScanXPDisabled)
		addon:ListenTo("DISABLE_XP_GAIN", ScanXPDisabled)
		addon:ListenTo("COVENANT_CHOSEN", ScanCovenant)
		addon:ListenTo("COVENANT_SANCTUM_RENOWN_LEVEL_CHANGED", ScanCovenant)
	else
		addon:SetupOptions()
	end
	
	if options.RequestPlayTime then
		RequestTimePlayed()	-- trigger a TIME_PLAYED_MSG event
	end
end)
