--[[	*** DataStore_Characters ***
Written by : Thaoky, EU-Marécages de Zangar
July 18th, 2009
--]]
if not DataStore then return end

local addonName = "DataStore_Characters"

_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

local addon = _G[addonName]

local isCoreDataMissing
local MAX_LOGOUT_TIMESTAMP = 5000000000	-- 5 billion, current values are at ~1.4 billion, in seconds, that leaves us 110+ years, I think we're covered..

-- Replace RAID_CLASS_COLORS which is not always loaded when we need it.
local classColors = {
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

local AddonDB_Defaults = {
	global = {
		Options = {
			RequestPlayTime = true,		-- Request play time at logon
			HideRealPlayTime = false,	-- Hide real play time to client addons (= return 0 instead of real value)
		},
		Characters = {
			['*'] = {				-- ["Account.Realm.Name"] 
				-- ** General Stuff **
				lastUpdate = nil,		-- last time this char was updated. Set at logon & logout
				name = nil,				-- to simplify processing a bit, the name is saved in the table too, in addition to being part of the key
				level = nil,
				race = nil,
				englishRace = nil,
				class = nil,
				englishClass = nil,	-- "WARRIOR", "DRUID" .. english & caps, regardless of locale
				classID = nil,
				faction = nil,
				localizedFaction = nil,
				gender = nil,			-- UnitSex
				lastLogoutTimestamp = nil,
				money = nil,
				played = 0,				-- /played, in seconds
				playedThisLevel = 0,	-- /played at this level, in seconds
				zone = nil,				-- character location
				subZone = nil,
				bindLocation = nil,	-- location where the hearthstone is bound to
				
				-- ** XP **
				XP = nil,				-- current level xp
				XPMax = nil,			-- max xp at current level 
				RestXP = nil,
				isResting = nil,		-- nil = out of an inn
				isXPDisabled = nil,
				
				-- ** Guild  **
				guildName = nil,		-- nil = not in a guild, as returned by GetGuildInfo("player")
				guildRankName = nil,
				guildRankIndex = nil,
				
				-- ** Expansion Features / 9.0 - Shadowlands **
				renownLevel = 1,					-- Covenant Renown Level
				activeCovenantID = 0,			-- Active Covenant ID (0 = None)
				activeSoulbindID = 0,			-- Active Soulbind ID (0 = None)
			}
		}
	}
}

-- *** Utility functions ***
local function GetOption(option)
	return addon.db.global.Options[option]
end

-- *** Scanning functions ***
local function ScanPlayerLocation()
	local character = addon.ThisCharacter
	
	character.zone = GetRealZoneText()
	character.subZone = GetSubZoneText()
end

local function ScanCovenant()
	local character = addon.ThisCharacter
	
	character.activeCovenantID = C_Covenants.GetActiveCovenantID()
	character.activeSoulbindID = C_Soulbinds.GetActiveSoulbindID()
	character.renownLevel = C_CovenantSanctumUI.GetRenownLevel()
end


-- *** Event Handlers ***
local function OnPlayerGuildUpdate()

	-- at login this event is called between OnEnable and PLAYER_ALIVE, where GetGuildInfo returns a wrong value
	-- however, the value returned here is correct
	local character = addon.ThisCharacter
	local hasGuild = (character.guildName ~= nil)
	
	if IsInGuild() then
		-- find a way to improve this, it's minor, but it's called too often at login
		local name, rank, index = GetGuildInfo("player")
		if name and rank and index then
			character.guildName = name
			character.guildRankName = rank
			character.guildRankIndex = index
		end
	else
		-- If the event is triggered after a gkick/gquit, be sure to clean the guild info
		character.guildName = nil
		character.guildRankName = nil
		character.guildRankIndex = nil
		
		-- if the character had a guild when entering this function, but is no longer in a guild, then trigger the event
		if hasGuild then
			addon:SendMessage("DATASTORE_GUILD_LEFT")
		end
	end	
end

local function ScanXPDisabled()
	addon.ThisCharacter.isXPDisabled = IsXPUserDisabled() or nil
end

local function OnPlayerUpdateResting()
	addon.ThisCharacter.isResting = IsResting()
end

local function OnPlayerXPUpdate()
	local character = addon.ThisCharacter
	
	character.XP = UnitXP("player")
	character.XPMax = UnitXPMax("player")
	character.RestXP = GetXPExhaustion() or 0
end

local function OnPlayerMoney()
	addon.ThisCharacter.money = GetMoney()
end

local function OnPlayerAlive()
	local character = addon.ThisCharacter

	character.name = UnitName("player")		-- to simplify processing a bit, the name is saved in the table too, in addition to being part of the key
	character.level = UnitLevel("player")
	character.race, character.englishRace = UnitRace("player")
	character.class, character.englishClass, character.classID = UnitClass("player")
	character.gender = UnitSex("player")
	character.faction, character.localizedFaction = UnitFactionGroup("player")
	character.lastLogoutTimestamp = MAX_LOGOUT_TIMESTAMP
	character.bindLocation = GetBindLocation()
	character.lastUpdate = time()
	
	OnPlayerMoney()
	OnPlayerXPUpdate()
	OnPlayerUpdateResting()
	OnPlayerGuildUpdate()
	
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		ScanXPDisabled()
		ScanCovenant()
	end
end

local function OnPlayerLogout()
	addon.ThisCharacter.lastLogoutTimestamp = time()
	addon.ThisCharacter.lastUpdate = time()
end

local function OnPlayerLevelUp(event, newLevel)
	addon.ThisCharacter.level = newLevel
end

local function OnHearthstoneBound(event)
	addon.ThisCharacter.bindLocation = GetBindLocation()
end

local function OnTimePlayedMsg(event, totalTime, currentLevelTime)
	addon.ThisCharacter.played = totalTime
	addon.ThisCharacter.playedThisLevel = currentLevelTime
end

local function OnCovenantChosen()
	ScanCovenant()
end

local function OnSanctumRenownLevelChanged()
	ScanCovenant()
end


-- ** Mixins **
local function _GetCharacterName(character)
	return character.name
end

local function _GetCharacterLevel(character)
	return character.level or 0
end

local function _GetCharacterRace(character)
	return character.race or "", character.englishRace or ""
end

local function _GetCharacterClass(character)
	return character.class or "", character.englishClass or "", character.classID
end

local function _GetColoredCharacterName(character)
	-- check if name and englishClass are present, if they are not, core info is missing for at least one alt.
	-- but we can't say which.. and there might be many, so only show the message once.
	if (not character.name or not character.englishClass) and not isCoreDataMissing then
		addon:Print("Core information about one or more characters is missing. Be sure to logout and login again with that character.\nThe add-on should be enabled while no character is logged in, otherwise character information cannot properly be read!")
		isCoreDataMissing = true
	end

	return format("%s%s", classColors[character.englishClass], character.name)
end
	
local function _GetCharacterClassColor(character)
	-- return just the color of this character's class (based on the character key)
	return format("%s", classColors[character.englishClass])
end

local function _GetClassColor(class)
	-- return just the color of for any english class 	
	return format("%s", classColors[class]) or "|cFFFFFFFF"
end

local function _GetCharacterFaction(character)
	return character.faction or "", character.localizedFaction or ""
end
	
local function _GetColoredCharacterFaction(character)
	-- Localized version may not yet be there, only added with a bugfix in 9.0.010 
	-- removed the ELSE part later on, in the meantime, avoid generating loads of issues for players
	
	if character.localizedFaction then
		if character.localizedFaction == FACTION_ALLIANCE then
			return format("|cFF2459FF%s", FACTION_ALLIANCE)
			
		elseif character.localizedFaction == FACTION_HORDE then
			return format("|cFFFF0000%s", FACTION_HORDE)
			
		else	-- for young pandas, who have a "Neutral" faction
			return format("|cFF909090%s", character.localizedFaction)
		end
	else
		if character.faction == "Alliance" then
			return format("|cFF2459FF%s", "Alliance")
			
		elseif character.faction == "Horde" then
			return format("|cFFFF0000%s", "Horde")
			
		else	-- for young pandas, who have a "Neutral" faction
			return format("|cFF909090%s", character.faction)
		end
	end
end

local function _GetCharacterGender(character)
	return character.gender or ""
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

local function _GetXP(character)
	return character.XP or 0
end

local function _GetXPRate(character)
	return floor((character.XP / character.XPMax) * 100)
end

local function _GetXPMax(character)
	return character.XPMax or 0
end

local function _GetRestXP(character)
	return character.RestXP or 0
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
	
	if character.englishRace == "Pandaren" then
		multiplier = 3
	end
	
	local savedXP = 0
	local savedRate = 0
	local maxXP = character.XPMax * multiplier
	if character.RestXP then
		rate = character.RestXP / (maxXP / 100)
		savedXP = character.RestXP
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
		local oneXPBubble = character.XPMax / 20		-- 5% at current level 
		local elapsed = (now - character.lastLogoutTimestamp)		-- time since last logout, in seconds
		local numXPBubbles = elapsed / 28800		-- 28800 seconds = 8 hours => get the number of xp bubbles earned
		
		xpEarnedResting = numXPBubbles * oneXPBubble
		
		if not character.isResting then
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
	if character.level == MAX_PLAYER_LEVEL then
		xpEarnedResting = -1
	end
	
	return rate, savedXP, savedRate, rateEarnedResting, xpEarnedResting, maxXP, isFullyRested, timeUntilFullyRested
end

local function _IsResting(character)
	return character.isResting
end

local function _IsXPDisabled(character)
	return character.isXPDisabled
end
	
local function _GetGuildInfo(character)
	return character.guildName or "", character.guildRankName, character.guildRankIndex
end

local function _GetPlayTime(character)
	return (GetOption("HideRealPlayTime")) and 0 or character.played, character.playedThisLevel
end

local function _GetRealPlayTime(character)
	-- return the real play time, not to be displayed, but just for computing (ex: which alt has the highest/lowest played ?)
	return character.played
end

local function _GetLocation(character)
	return character.zone, character.subZone
end


local mixins = {
	GetCharacterName = _GetCharacterName,
	GetCharacterLevel = _GetCharacterLevel,
	GetCharacterRace = _GetCharacterRace,
	GetCharacterClass = _GetCharacterClass,
	GetColoredCharacterName = _GetColoredCharacterName,
	GetCharacterClassColor = _GetCharacterClassColor,
	GetClassColor = _GetClassColor,
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
	GetPlayTime = _GetPlayTime,
	GetRealPlayTime = _GetRealPlayTime,
	GetLocation = _GetLocation,
}

if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	mixins["GetCovenantInfo"] = function(character)
		return character.activeCovenantID, character.activeSoulbindID, character.renownLevel
	end

	mixins["GetCovenantNameByID"] = function(id)
		local data = C_Covenants.GetCovenantData(id)
		return (data) and data.name or ""
	end

	mixins["GetCovenantName"] = function(character)
		local id = character.activeCovenantID
		local data = C_Covenants.GetCovenantData(id)
		return (data) and data.name or ""	
	end
end

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(format("%sDB", addonName), AddonDB_Defaults)

	DataStore:RegisterModule(addonName, addon, mixins)
	DataStore:SetCharacterBasedMethod("GetCharacterName")
	DataStore:SetCharacterBasedMethod("GetCharacterLevel")
	DataStore:SetCharacterBasedMethod("GetCharacterRace")
	DataStore:SetCharacterBasedMethod("GetCharacterClass")
	DataStore:SetCharacterBasedMethod("GetColoredCharacterName")
	DataStore:SetCharacterBasedMethod("GetCharacterClassColor")
	DataStore:SetCharacterBasedMethod("GetCharacterFaction")
	DataStore:SetCharacterBasedMethod("GetColoredCharacterFaction")
	DataStore:SetCharacterBasedMethod("GetCharacterGender")
	DataStore:SetCharacterBasedMethod("GetLastLogout")
	DataStore:SetCharacterBasedMethod("GetMoney")
	DataStore:SetCharacterBasedMethod("GetBindLocation")
	DataStore:SetCharacterBasedMethod("GetXP")
	DataStore:SetCharacterBasedMethod("GetXPRate")
	DataStore:SetCharacterBasedMethod("GetXPMax")
	DataStore:SetCharacterBasedMethod("GetRestXP")
	DataStore:SetCharacterBasedMethod("GetRestXPRate")
	DataStore:SetCharacterBasedMethod("IsResting")
	DataStore:SetCharacterBasedMethod("IsXPDisabled")
	DataStore:SetCharacterBasedMethod("GetGuildInfo")
	DataStore:SetCharacterBasedMethod("GetPlayTime")
	DataStore:SetCharacterBasedMethod("GetRealPlayTime")
	DataStore:SetCharacterBasedMethod("GetLocation")
	
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		DataStore:SetCharacterBasedMethod("GetCovenantInfo")
		DataStore:SetCharacterBasedMethod("GetCovenantName")
	end
end

function addon:OnEnable()
	addon:RegisterEvent("PLAYER_ALIVE", OnPlayerAlive)
	addon:RegisterEvent("PLAYER_LOGOUT", OnPlayerLogout)
	addon:RegisterEvent("PLAYER_LEVEL_UP", OnPlayerLevelUp)
	addon:RegisterEvent("PLAYER_MONEY", OnPlayerMoney)
	addon:RegisterEvent("PLAYER_XP_UPDATE", OnPlayerXPUpdate)
	addon:RegisterEvent("PLAYER_UPDATE_RESTING", OnPlayerUpdateResting)
	addon:RegisterEvent("HEARTHSTONE_BOUND", OnHearthstoneBound)
	addon:RegisterEvent("PLAYER_GUILD_UPDATE", OnPlayerGuildUpdate)				-- for gkick, gquit, etc..
	addon:RegisterEvent("ZONE_CHANGED", ScanPlayerLocation)
	addon:RegisterEvent("ZONE_CHANGED_NEW_AREA", ScanPlayerLocation)
	addon:RegisterEvent("ZONE_CHANGED_INDOORS", ScanPlayerLocation)
	addon:RegisterEvent("TIME_PLAYED_MSG", OnTimePlayedMsg)					-- register the event if RequestTimePlayed is not called afterwards. If another addon calls it, we want to get the data anyway.
	
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		addon:RegisterEvent("ENABLE_XP_GAIN", ScanXPDisabled)
		addon:RegisterEvent("DISABLE_XP_GAIN", ScanXPDisabled)
		addon:RegisterEvent("COVENANT_CHOSEN", OnCovenantChosen)
		addon:RegisterEvent("COVENANT_SANCTUM_RENOWN_LEVEL_CHANGED", OnSanctumRenownLevelChanged)
	end
	
	addon:SetupOptions()
	
	if GetOption("RequestPlayTime") then
		RequestTimePlayed()	-- trigger a TIME_PLAYED_MSG event
	end
end

function addon:OnDisable()
	addon:UnregisterEvent("PLAYER_ALIVE")
	addon:UnregisterEvent("PLAYER_LOGOUT")
	addon:UnregisterEvent("PLAYER_LEVEL_UP")
	addon:UnregisterEvent("PLAYER_MONEY")
	addon:UnregisterEvent("PLAYER_XP_UPDATE")
	addon:UnregisterEvent("PLAYER_UPDATE_RESTING")
	addon:UnregisterEvent("PLAYER_GUILD_UPDATE")
	addon:UnregisterEvent("ZONE_CHANGED")
	addon:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	addon:UnregisterEvent("ZONE_CHANGED_INDOORS")
	addon:UnregisterEvent("TIME_PLAYED_MSG")
	
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		addon:UnregisterEvent("ENABLE_XP_GAIN")
		addon:UnregisterEvent("DISABLE_XP_GAIN")
		addon:UnregisterEvent("COVENANT_CHOSEN")
		addon:UnregisterEvent("COVENANT_SANCTUM_RENOWN_LEVEL_CHANGED")
	end
end
