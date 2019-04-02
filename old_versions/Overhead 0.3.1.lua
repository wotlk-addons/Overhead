--[[
	Copyright (C) 2009 Timothy Yen
	Project: Overhead
	Credits: Kassay
	Description:
		Shows castbars on all enemy player nameplates and 'hides' non-player nameplates (pets, totems, mirror images,..etc.)
]]
--[[
	Modified by superk, adding showlist/hidelist and a command configuration, updated for 4.06+.
]]
local defaults = { enable = true, party = true, enemypet = true }
local cvartemp = {}
OverheadDB = OverheadDB or defaults
local Overhead = {}
Overhead.frame = CreateFrame("Frame")


local function log(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff32CD32Overhead:|r " .. msg) end

-- Upvalues
local WorldFrame = WorldFrame
local MAX_BATTLEFIELD_QUEUES = MAX_BATTLEFIELD_QUEUES
local select,strfind,next,pairs,unpack,floor,wipe,next = select,strfind,next,pairs,unpack,math.floor,table.wipe,next
local UnitHealthMax,UnitName,UnitExists,UnitCastingInfo,UnitChannelInfo = UnitHealthMax,UnitName,UnitExists,UnitCastingInfo,UnitChannelInfo
local GetTime,IsInInstance,GetBattlefieldStatus = GetTime,IsInInstance,GetBattlefieldStatus
local SetCVar,GetCVar = SetCVar,GetCVar

-- Displayer OnUpdate throttling
local displayThrottle, displayElapsed = 0.1, 0

-- Caches
local nameplates,castbars = {},{}
Overhead.nameplates = nameplates

-- Cast bars anchored to nameplates
local active = {}

-- Show nameplates when you have toggled the enemys' or friends' totems or guards in interface and automatically hide other totems and guards
-- This is default showlist 
local showlist = { 
	--["Tremor Totem"] = true,
	--["Earthbind Totem"] = true,
	--["Grounding Totem"] = true,
	--["Mana Tide Totem"] = true,
	--["Spirit Link Totem"] = true,
}
-- Hide nameplates of enemys' or friends' pet (or players) when you have toggled pets in interface and other pets (or players) will be showed
-- This is default hidelist
local hidelist = { 
	--["Treant"] = true,
	--["Shadowfiend"] = true,
}
OverheadDB.showlist = OverheadDB.showlist or showlist
OverheadDB.hidelist = OverheadDB.hidelist or hidelist
-- Arena Unit IDs

local uids = {"arena1","arenapet1","pet",
				"arena2","arenapet2","party1","partypet1",
				"arena3","arenapet3","party2","partypet2",
				"arena4","arenapet4","party3","partypet3",
				"arena5","arenapet5","party4","partypet4"}
local bracket = 19

-- AnchorNameplates for loop upper bound

-- Media
Overhead.CastBarBorder = "Interface\\Tooltips\\Nameplate-Border"
Overhead.BarTexture = "Interface\\TargetingFrame\\UI-StatusBar"
Overhead.Shield = "Interface\\Tooltips\\Nameplate-CasterBar-Shield"

-- Table storage
local cache = {}
local function new() local t = next(cache) or {}; cache[t] = nil; return t end
local function del(t) wipe(t); cache[t] = true end

-- Event handling
local handlers = {}
local function OnEvent(self,event,...)
	if handlers[event] then
		for func in pairs(handlers[event]) do
			Overhead[func](Overhead,...)
		end
	end
end

Overhead.frame:SetScript("OnEvent",OnEvent)

function Overhead:RegisterEvent(event,func)
	handlers[event] = handlers[event] or new()
	handlers[event][func or event] = true
	self.frame:RegisterEvent(event)
end

function Overhead:UnregisterEvent(event)
	self.frame:UnregisterEvent(event)
	if handlers[event] then 
		del(handlers[event])
		handlers[event] = nil
	end
end

function Overhead:UnregisterAllEvents()
	self.frame:UnregisterAllEvents()
	while next(handlers) do
		local event,tbl = next(handlers)
		del(tbl)
		handlers[event] = nil
	end
end

function Overhead:OnLoad()
	-- Initialize the db
	self.db = OverheadDB
	self.db.showlist = self.db.showlist or showlist
	self.db.hidelist = self.db.hidelist or hidelist
	for k,v in pairs(defaults) do 
		if self.db[k] == nil then self.db[k] = true end
	end
	-- Store the origenal CVar
	--[[cvartemp = {
		ShowVKeyCastbar = GetCVar("ShowVKeyCastbar"),
		spreadnameplates = GetCVar("spreadnameplates"),
		bloatTest = GetCVar("bloatTest"),
		bloatnameplates = GetCVar("bloatnameplates"),
		bloatthreat = GetCVar("bloatthreat")
	}]]
	-- Create slash commands
	SlashCmdList["Overhead"] = function(msg) self:Command(msg, tbl) end
	SLASH_Overhead1 = "/oh"
	SLASH_Overhead2 = "/overhead"
	log("type /oh for options.")
	-- Used to find new nameplates added to the WorldFrame
	self.Scanner = CreateFrame("Frame")
	self.Scanner:SetScript("OnUpdate",Overhead.ScanForNameplates)
	self.Scanner:Hide()
	-- Used to anchor castbars onto nameplates
	self.Displayer = CreateFrame("Frame")
	self.Displayer:SetScript("OnUpdate",Overhead.DisplayerOnUpdate)
	self.Displayer:Hide()
	self:RegisterEvent("PLAYER_ENTERING_WORLD","ZoneChange")
	--self:RegisterEvent("ZONE_CHANGED_NEW_AREA","ZoneChange")
end

-- Command table
function Overhead:Command(msg , tbl)
	local cmdtbl = tbl or 
	{
		["showlist"] = {
			["add"] = function(arg) self.db.showlist[arg] = true; log("add "..arg.." into showlist") end,
			["del"] = function(arg) self.db.showlist[arg] = false; log("delete "..arg.." from showlist") end,
			[""] = function()
				local s = ""
				for k,v in pairs(self.db.showlist) do 
					if v then s = s .. "\n".. k end
				end
				if s == "" then s = "your showlist is empty" end
				log("showlist:".. s)
			end,
		},
		["hidelist"] = {
			["add"] = function(arg) self.db.hidelist[arg] = true; log("add "..arg.." into hidelist") end,
			["del"] = function(arg) self.db.hidelist[arg] = false; log("delete "..arg.." from hidelist") end,
			[""] = function()
				local s = ""
				for k,v in pairs(self.db.hidelist) do 
					if v then s = s .. "\n".. k end
				end
				if s == "" then s = "your hidelist is empty" end
				log("hidelist:".. s)
			end,
		},
		["party"] = {
			["on"] = function() self.db.party = true; log("set party castbar on") end,
			["off"] = function() self.db.party = false; log("set party castbar off") end,
 		},
		["pet"] = {
			["on"] = function() self.db.enemypet = true; log("set enemypet castbar on") end,
			["off"] = function() self.db.enemypet = false; log("set enemypet castbar off") end,
		},
		["disable"] = function() self.db.enable = false; log("set to be disabled") end,
		["enable"] = function() self.db.enable = true; log("set to be enabled") end,
		["status"] = function() log ("addon[".. (self.db.enable and "on]" or "off]").."  pet["..(self.db.enemypet and "on]" or "off]").."  party["..(self.db.party and "on]" or "off]")) end,
		["reset"] = function() OverheadDB = {}; log("reset overhead's database") end,
 		["help"] = function() log("\n'/oh party [on/off]' to set party castbar\n'/oh pet [on/off]' to set enemypet castbar\n'/oh [disable/enable]' to set the whole(works after reloading)\n'/oh status' to see the status\n'/oh reset' to reset database(works after reloading)\n'/oh showlist [add/del] [name]' to show or set showlist\n'/oh hidelist [add/del] [name]' to show or set hidelist") end,
	}
	local cmd, arg = string.split(" ", msg, 2)
	local entry = cmdtbl[cmd:lower()]
	local which = type(entry)
	if which == "function" then
		entry(arg)
	elseif which == "table" then
		self:Command(arg or "" , entry)
	else
		self:Command("help")
	end
end


-- Nameplate OnHide handler
local function OnHide(self)
	self.name:SetText("")
	self.shouldShowArt = false
end

local function ShowArt(self)
	self.targetflash:SetAlpha(1)
	self.healthbar:SetAlpha(1)
	self.castborder:SetAlpha(1)
	self.castbar:SetAlpha(1)
	self.healthborder:SetAlpha(1)
	self.name:SetAlpha(1)
	self.shield:SetAlpha(1)
	self.level:SetAlpha(1)
	self.glow:SetAlpha(1)
	self.skull:SetAlpha(1)
	self.castbarfill:SetAlpha(1)
	self.healthbarfill:SetAlpha(1)
	self.raidicons:SetAlpha(1)
	self.eliteicon:SetAlpha(1)
	self.spellicon:SetAlpha(1)
end

local function HideArt(self)
	self.targetflash:SetAlpha(0)
	self.healthbar:SetAlpha(0)
	self.castborder:SetAlpha(0)
	self.castbar:SetAlpha(0)
	self.healthborder:SetAlpha(0)
	self.name:SetAlpha(0)
	self.shield:SetAlpha(0)
	self.level:SetAlpha(0)
	self.glow:SetAlpha(0)
	self.skull:SetAlpha(0)
	self.castbarfill:SetAlpha(0)
	self.healthbarfill:SetAlpha(0)
	self.raidicons:SetAlpha(0)
	self.eliteicon:SetAlpha(0)
	self.spellicon:SetAlpha(0)
end

-- Process nameplates and add to the cache
function Overhead:ProcessFrames(frame,...)
	if not frame then return end

	if not nameplates[frame] and strfind (frame:GetName() or "[NONE]","NamePlate") then
		local nameplate = frame		
		-- Get StatusBar children
		nameplate.healthbar, nameplate.castbar = nameplate:GetChildren()
		local castbar = nameplate.castbar
		-- Get regions 
		local targetflash, healthborder, glow, name, level, skull, raidicons, eliteicon = nameplate:GetRegions()
		local castbarfill, castborder, shield, spellicon = nameplate.castbar:GetRegions()
		local healthbarfill = nameplate.healthbar:GetRegions()
		nameplate.targetflash = targetflash
		nameplate.healthborder = healthborder
		nameplate.healthbarfill = healthbarfill
		nameplate.castborder = castborder
		nameplate.name = name
		nameplate.level = level
		nameplate.shield = shield
		nameplate.glow = glow
		nameplate.castbarfill = castbarfill
		nameplate.skull = skull
		nameplate.raidicons = raidicons
		nameplate.eliteicon = eliteicon
		nameplate.spellicon = spellicon
		nameplate.castbarfill = castbarfill
		nameplate.shield = shield
		-- Set OnHide. No default OnHide script
		nameplate:SetScript("OnHide",OnHide)

		-- Store the points for castbar anchoring
		nameplate.castbarpoint = {castbar:GetPoint()}
		nameplate.castborderpoint = {castborder:GetPoint()}
		nameplate.spelliconpoint = {spellicon:GetPoint()}
		-- nameplate.shieldpoint = {shield:GetPoint()}
		-- for some unknown reason the point sometimes is not correct, so set it myself
		nameplate.castbarpoint[5]=5.4848
		nameplate.spelliconpoint[5]=10.3428
	
		nameplate.castbarH = castbar:GetHeight()
		nameplate.castbarW = castbar:GetWidth()
		nameplate.castborderH = castborder:GetHeight()
		nameplate.castborderW = castborder:GetWidth()
		nameplate.spelliconH = spellicon:GetHeight()
		nameplate.spelliconW = spellicon:GetWidth()
		--nameplate.shieldH = shield:GetHeight()
		--nameplate.shieldW = shield:GetWidth()

		-- Add show/hide art
		nameplate.ShowArt = ShowArt
		nameplate.HideArt = HideArt

		-- Store in cache
		nameplates[nameplate] = true
	end
	return Overhead:ProcessFrames(...)
end

-- Scanner OnUpdate
local children
function Overhead:ScanForNameplates()
	if WorldFrame:GetNumChildren() ~= children then
		-- # of children changed
		children = WorldFrame:GetNumChildren()
		Overhead:ProcessFrames(WorldFrame:GetChildren())
	end
end

-- Retrieve a castbar to be anchored to a nameplate
function Overhead:GetCastBar(nameplate)
	local castbar
	castbar = next(castbars)
	if castbar then
		-- Castbar found, remove it from cache
		castbars[castbar] = nil
	else
		-- No castbar retrived from cache, create a new one
		castbar = CreateFrame("StatusBar")
		castbar:SetWidth(nameplate.castbarW); 
		castbar:SetHeight(nameplate.castbarH)
		castbar:SetStatusBarTexture(Overhead.BarTexture)
		castbar.border = castbar:CreateTexture(nil,"OVERLAY")
		castbar.border:SetTexture(Overhead.CastBarBorder)
		castbar.border:SetTexCoord(1,0,1,1,0,0,0,1) -- Rotates pi radians
		castbar.border:SetWidth(nameplate.castborderW)
		castbar.border:SetHeight(nameplate.castborderH)
		castbar.spellicon = CreateFrame("Frame",nil,castbar):CreateTexture(nil,"OVERLAY") -- Ensures icon is on top of the border
		castbar.spellicon:SetWidth(nameplate.spelliconW)
		castbar.spellicon:SetHeight(nameplate.spelliconH)
		--[[castbar.shield = castbar:CreateTexture(Overhead.Shield,"ARTWORK")
		castbar.shield:SetWidth(nameplate.shieldW)
		castbar.shield:SetHeight(nameplate.shieldH)]]
	end
	castbar:Hide()
	return castbar
end

-- Resets a castbar and adds it back to the cache
function Overhead:ReleaseCastBar(castbar)
	castbar:ClearAllPoints()
	castbar:Hide()
	castbar:SetScript("OnUpdate",nil)
	active[castbar.uid] = nil
	castbars[castbar] = true
	castbar.uid = nil
	castbar.casting = nil
	castbar.channeling = nil
end

-- Get a nameplate from the cache
function Overhead:GetNameplate(uid)
	local name = UnitName(uid)
	local max = UnitHealthMax(uid)
	for nameplate in pairs(nameplates) do
		-- Name text and healthbar's maxvalue must match
		if nameplate.name:GetText() == name and select(2,nameplate.healthbar:GetMinMaxValues()) == max then
			nameplate.shouldShowArt = true
			return nameplate
		end
	end
end

-- Puts castbars on visible arena ids
function Overhead:AnchorNameplates()
	for id=1,bracket do 
		local uid = uids[id]
		local nameplate = self:GetNameplate(uid)
		-- Nameplate found with no castbar on it
		if UnitExists(uid) and nameplate and not active[uid] then
			nameplate.shouldShowArt = true
			local castbar = self:GetCastBar(nameplate)
	
			castbar:SetPoint(unpack(nameplate.castbarpoint))
			castbar.spellicon:SetPoint(unpack(nameplate.spelliconpoint))
			castbar.border:SetPoint(unpack(nameplate.castborderpoint))
			--castbar.shield:SetPoint(unpack(nameplate.shieldpoint))
			castbar.uid = uid
			
			active[uid] = castbar
			if UnitCastingInfo(uid) then self:CastStart(uid)
			elseif UnitChannelInfo(uid) then self:ChannelStart(uid) end
		-- Castbar is floating around, release it
		elseif not nameplate and active[uid] then
			self:ReleaseCastBar(active[uid])
		end
	end
end

-- OnUpdate for Displayer frame
function Overhead:DisplayerOnUpdate(elapsed)
	displayElapsed = displayElapsed + elapsed
	if displayElapsed > displayThrottle then
		Overhead:AnchorNameplates()
		Overhead:UpdateArt()
	end
end

-- Show or hide nameplate art
function Overhead:UpdateArt()
	for nameplate in pairs(nameplates) do 
		local unit_name = nameplate.name:GetText() or "[NONE]"
		if self.db.hidelist[unit_name] then
			nameplate:HideArt()
		elseif self.db.showlist[unit_name] then
			nameplate:ShowArt()
		elseif nameplate.shouldShowArt then
			nameplate:ShowArt()
		else 
			nameplate:HideArt()
		end
	end
end

-- Used when entering a non-arena zone
function Overhead:ResetAllNameplates()
	for nameplate in pairs(nameplates) do nameplate:ShowArt(); nameplate.shouldShowArt = false end
end

-- Set bracket upvalue
-- http://www.wowwiki.com/API_GetBattlefieldStatus
function Overhead:UpdateBracket()  
	for i=1, MAX_BATTLEFIELD_QUEUES do
		local status,_,_,_,_,size = GetBattlefieldStatus(i)
		if status == "active" and size > 0 then
			bracket = size * 4 - 1 --enemy and his pet, party and partypet
			break
		end
	end
end


function Overhead:ZoneChange()
	local InArena = select(2,IsInInstance()) == "arena"
	if InArena and self.db.enable then
		self.Scanner:Show()
		self.Displayer:Show()
		self:UpdateBracket()
		-- Register casting events
		self:RegisterEvent("UNIT_SPELLCAST_START","CastStart")
		self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START","ChannelStart")
		self:RegisterEvent("UNIT_SPELLCAST_DELAYED","CastDelayed")
		self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "ChannelUpdate")
		self:RegisterEvent("UNIT_SPELLCAST_STOP","CastStop")
		self:RegisterEvent("UNIT_SPELLCAST_FAILED","CastStop")
		self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED","CastStop")
		self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP","CastStop")
		-- Set CVars to make overhead work well in arena
		SetCVar("ShowVKeyCastbar",0)
		--SetCVar("spreadnameplates",0)
		--SetCVar("bloatTest",1)
		--SetCVar("bloatnameplates",0)
		--SetCVar("bloatthreat",0)
	else
		self:ResetAllNameplates()
		self.Scanner:Hide()
		self.Displayer:Hide()
		self:UnregisterAllEvents()
		self:RegisterEvent("PLAYER_ENTERING_WORLD","ZoneChange")
		--self:RegisterEvent("ZONE_CHANGED_NEW_AREA","ZoneChange")
		-- Reset all castbars
		for _,cb in pairs(active) do self:ReleaseCastBar(cb) end
		-- Reset CVar
		SetCVar("ShowVKeyCastbar",1)
		--for k,v in pairs(cvartemp) do SetCVar(k, v or GetCVar(k)) end
	end
end


--[[
	Based off CastingBarFrame.lua
]]
function Overhead:CastOnUpdate(elapsed)
	-- Casting
	if self.casting then
		self.value = self.value + elapsed;
		if self.value > self.maxvalue then
			self.casting = nil
			self:SetScript("OnUpdate",nil)
			self:Hide()
			return
		end
		self:SetValue(self.value)
	-- Channeling
	elseif self.channeling then
		self.value = self.value - elapsed;
		if self.value < 0 then
			self.channeling = nil
			self:SetScript("OnUpdate",nil)
			self:Hide()
			return
		end
		self:SetValue(self.value)
	end
end

--[[local function castbarShield(self, uid)
	self.shield:Show()
end
local function castbarShieldDown(self, uid)
	self.shield:Hide()
end]]
--[[
	CastStart
		"UNIT_SPELLCAST_START"
]]

function Overhead:CastStart(uid)
	if uid:find("arenapet") and not self.db.enemypet then return end
	if uid:find("party") and not self.db.party then return end
	if uid:find("partypet") or uid == "pet" then return end
	if active[uid] then
		local _, _, _, icon, starttime, endtime, _, notInterruptible = UnitCastingInfo(uid)
		local castbar = active[uid]
		castbar.casting = true
		castbar:SetStatusBarColor(1.0, 0.7, 0.0)
		castbar.value = GetTime() - (starttime / 1000)
		castbar.maxvalue = (endtime - starttime) / 1000
		castbar:SetMinMaxValues(0, castbar.maxvalue)
		castbar:SetValue(castbar.value)
		castbar.spellicon:SetTexture(icon)
		--if notInterruptible then castbar.shield:Show() else castbar.shield:Hide() end
		local name = GetUnitName(uid)
		if not self.db.hidelist[name] then castbar:Show() end
		castbar:SetScript("OnUpdate",self.CastOnUpdate)
		--castbar:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE","castbarShield")
		--castbar:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE","castbarShieldDown")
	end
end

--[[
	ChannelStart
		"UNIT_SPELLCAST_CHANNEL_START"
]]

function Overhead:ChannelStart(uid)
	if uid:find("arenapet") and not self.db.enemypet then return end
	if uid:find("party") and not self.db.party then return end
	if uid:find("partypet") or uid == "pet" then return end
	if active[uid] then
		local _, _, _, icon, starttime, endtime, _, notInterruptible = UnitChannelInfo(uid)
		local castbar = active[uid]
		castbar.channeling = true
		castbar:SetStatusBarColor(0.0, 1.0, 0.0)
		castbar.value = (endtime / 1000) - GetTime()
		castbar.maxvalue = (endtime - starttime) / 1000
		castbar:SetMinMaxValues(0, castbar.maxvalue)
		castbar:SetValue(castbar.value)
		castbar.spellicon:SetTexture(icon)
		--if notInterruptible then castbar.shield:Show() else castbar.shield:Hide() end
		local name = GetUnitName(uid)
		if not self.db.hidelist[name] then castbar:Show() end
		castbar:SetScript("OnUpdate",self.CastOnUpdate)
		--castbar:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE","castbarShield")
		--castbar:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE","castbarShieldDown")
	end
end

--[[
	CastStop
		"UNIT_SPELLCAST_STOP"
		"UNIT_SPELLCAST_FAILED"
		"UNIT_SPELLCAST_INTERRUPTED"
		"UNIT_SPELLCAST_CHANNEL_STOP"
]]

function Overhead:CastStop(uid)
	if active[uid] then
		local castbar = active[uid]
		castbar.casting = nil
		castbar.channeling = nil
		castbar:Hide()
		castbar:SetScript("OnUpdate",nil)
		--castbar:UnregisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
		--castbar:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
	end
end

--[[
	CastDelayed
		"UNIT_SPELLCAST_DELAYED"
]]

function Overhead:CastDelayed(uid)
	if active[uid] then
		local _, _, _, _, starttime, endtime = UnitCastingInfo(uid)
		local castbar = active[uid]
		castbar.value = GetTime() - (starttime / 1000)
		castbar.maxvalue = (endtime - starttime) / 1000
		castbar:SetMinMaxValues(0, castbar.maxvalue)
	end
end

--[[
	ChannelUpdate
		"UNIT_SPELLCAST_CHANNEL_UPDATE"
]]

function Overhead:ChannelUpdate(uid)
	if active[uid] then
		local _, _, _, _, starttime, endtime = UnitChannelInfo(uid)
		local castbar = active[uid]
		castbar.value = GetTime() - (starttime / 1000)
		castbar.maxvalue = (endtime - starttime) / 1000
		castbar:SetMinMaxValues(0, castbar.maxvalue)
	end
end

Overhead:RegisterEvent("VARIABLES_LOADED","OnLoad")
_G.Overhead = Overhead