if not DataStore then return end

local addonName = "DataStore_Characters"
local addon = _G[addonName]
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

function addon:SetupOptions()
	local f = DataStore.Frames.CharactersOptions
	
	DataStore:AddOptionCategory(f, addonName, "DataStore")

	-- restore saved options to gui
	f.RequestPlayTime:SetChecked(DataStore:GetOption(addonName, "RequestPlayTime"))
	f.HideRealPlayTime:SetChecked(DataStore:GetOption(addonName, "HideRealPlayTime"))
end
