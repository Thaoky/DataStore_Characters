if not DataStore then return end

local addonName, addon = ...

function addon:SetupOptions()
	local f = DataStore.Frames.CharactersOptions
	
	DataStore:AddOptionCategory(f, addonName, "DataStore")

	-- restore saved options to gui
	local options = DataStore_Characters_Options
	
	f.RequestPlayTime:SetChecked(options.RequestPlayTime)
	f.HideRealPlayTime:SetChecked(options.HideRealPlayTime)
end
