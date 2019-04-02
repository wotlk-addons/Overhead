--[[
	Copyright (C) 2009 Timothy Yen
	Project: Overhead
	Credits: Kassay
	Description:
		Shows castbars on all enemy player nameplates and 'hides' non-player nameplates (pets, totems, mirror images,..etc.)
]]

local Overhead = {}
Overhead.frame = CreateFrame("Frame")

-- Upvalues
local WorldFrame = WorldFrame
local MAX_BATTLEFIELD_QUEUES = MAX_BATTLEFIELD_QUEUES
local select,next,pairs,unpack,floor,wipe,next = select,next,pairs,unpack,math.floor,table.wipe,next
local UnitHealthMax,UnitName,UnitExists,UnitCastingInfo,UnitChannelInfo = UnitHealthMax,UnitName,UnitExists,UnitCastingInfo,UnitChannelInfo
local GetTime,IsInInstance,GetBattlefieldStatus = GetTime,IsInInstance,GetBattlefieldStatus
local SetCVar = SetCVar

-- Displayer OnUpdate throttling
local displayThrottle, displayElapsed = 0.1, 0

-- Caches
local nameplates,castbars = {},{}
Overhead.nameplates = nameplates

-- Cast bars anchored to nameplates
local active = {}

-- Arena Unit IDs
local uids = {
	"arena1","arena2","arena3","arena4","arena5",
	"party1","party2","party3","party4"
}

-- AnchorNameplates for loop upper bound
local bracket

-- Media
Overhead.CastBarBorder = "Interface\\Tooltips\\Nameplate-Border"
Overhead.BarTexture = "Interface\\TargetingFrame\\UI-StatusBar"

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
	-- Used to find new nameplates added to the WorldFrame
	self.Scanner = CreateFrame("Frame")
	self.Scanner:SetScript("OnUpdate",Overhead.ScanForNameplates)
	self.Scanner:Hide()
	-- Used to anchor castbars onto nameplates
	self.Displayer = CreateFrame("Frame")
	self.Displayer:SetScript("OnUpdate",Overhead.DisplayerOnUpdate)
	self.Displayer:Hide()
	self:RegisterEvent("PLAYER_ENTERING_WORLD","ZoneChange")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA","ZoneChange")
end

-- Nameplate OnHide handler
local function OnHide(self)
	self.name:SetText("")
	self.shouldShowArt = false
end

local function ShowArt(self)
	self.healthbar:SetAlpha(1)
	self.healthborder:SetAlpha(1)
	self.name:SetAlpha(1)
	self.castborder2:SetAlpha(1)
	self.level:SetAlpha(1)
	self.glow:SetAlpha(1)
	self.skull:SetAlpha(1)
	self.raidicons:SetAlpha(1)
	self.eliteicon:SetAlpha(1)
end

local function HideArt(self)
	self.healthbar:SetAlpha(0)
	self.healthborder:SetAlpha(0)
	self.name:SetAlpha(0)
	self.castborder2:SetAlpha(0)
	self.level:SetAlpha(0)
	self.glow:SetAlpha(0)
	self.skull:SetAlpha(0)
	self.raidicons:SetAlpha(0)
	self.eliteicon:SetAlpha(0)
end

-- Process nameplates and add to the cache
function Overhead:ProcessFrames(frame,...)
	if not frame then return end
	local region = frame:GetRegions()
	if not frame:GetName() and not nameplates[frame] and region and region:GetObjectType() == "Texture" and region:GetTexture() == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash" then
		local nameplate = frame

		-- Get StatusBar children
		nameplate.healthbar, nameplate.castbar = nameplate:GetChildren()
		local castbar = nameplate.castbar
		-- Get regions
		local targetflash, healthborder, castborder, castborder2, spellicon, glow, name, level, skull, raidicons, eliteicon = nameplate:GetRegions()
		nameplate.healthborder = healthborder
		nameplate.castborder = castborder
		nameplate.name = name
		nameplate.level = level
		nameplate.castborder2 = castborder2
		nameplate.glow = glow
		nameplate.skull = skull
		nameplate.raidicons = raidicons
		nameplate.eliteicon = eliteicon
		
		-- Set OnHide. No default OnHide script
		nameplate:SetScript("OnHide",OnHide)

		-- Store the points for castbar anchoring
		nameplate.castbarpoint = {castbar:GetPoint()}
		nameplate.castborderpoint = {castborder:GetPoint()}
		nameplate.spelliconpoint = {spellicon:GetPoint()}

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
function Overhead:GetCastBar()
	local castbar
	castbar = next(castbars)
	if castbar then
		-- Castbar found, remove it from cache
		castbars[castbar] = nil
	else
		-- No castbar retrived from cache, create a new one
		castbar = CreateFrame("StatusBar")
		castbar:SetWidth(116.504); castbar:SetHeight(10.1796)
		castbar:SetStatusBarTexture(Overhead.BarTexture)
		castbar.border = castbar:CreateTexture(nil,"OVERLAY")
		castbar.border:SetTexture(Overhead.CastBarBorder)
		castbar.border:SetTexCoord(1,0,1,1,0,0,0,1) -- Rotates pi radians
		castbar.border:SetWidth(144.90595)
		castbar.border:SetHeight(36.226)
		castbar.spellicon = CreateFrame("Frame",nil,castbar):CreateTexture(nil,"OVERLAY") -- Ensures icon is on top of the border
		castbar.spellicon:SetWidth(14.495)
		castbar.spellicon:SetHeight(14.495)
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
function Overhead:GetNameplate(name,max)
	for nameplate in pairs(nameplates) do
		-- Name text and healthbar's maxvalue must match
		if nameplate.name:GetText() == name and select(2,nameplate.healthbar:GetMinMaxValues()) == max then
			return nameplate
		end
	end
end

-- Puts castbars on visible arena ids
function Overhead:AnchorNameplates()
	for id=1,(2*bracket-1) do 
		local uid = uids[id]
		local nameplate = self:GetNameplate(UnitName(uid),UnitHealthMax(uid))
		-- Nameplate found with no castbar on it
		if UnitExists(uid) and nameplate and not active[uid] then
			nameplate.shouldShowArt = true
			local castbar = self:GetCastBar()
			castbar:SetPoint(unpack(nameplate.castbarpoint))
			castbar.spellicon:SetPoint(unpack(nameplate.spelliconpoint))
			castbar.border:SetPoint(unpack(nameplate.castborderpoint))
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
		total = 0
	end
end

-- Show or hide nameplate art
function Overhead:UpdateArt()
	for nameplate in pairs(nameplates) do 
		if nameplate.shouldShowArt then nameplate:ShowArt()
		else nameplate:HideArt() end
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
			bracket = size
			break
		end
	end
end

function Overhead:ZoneChange()
	local InArena = select(2,IsInInstance()) == "arena"
	if InArena then
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
		SetCVar("ShowVKeyCastbar",0)
	else
		self:ResetAllNameplates()
		self.Scanner:Hide()
		self.Displayer:Hide()
		self:UnregisterAllEvents()
		self:RegisterEvent("PLAYER_ENTERING_WORLD","ZoneChange")
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA","ZoneChange")
		-- Reset all castbars
		for _,cb in pairs(active) do self:ReleaseCastBar(cb) end
		SetCVar("ShowVKeyCastbar",1)
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

--[[
	CastStart
		"UNIT_SPELLCAST_START"
]]

function Overhead:CastStart(uid)
	if active[uid] then
		local _, _, _, icon, starttime, endtime = UnitCastingInfo(uid)
		local castbar = active[uid]
		castbar.casting = true
		castbar:SetStatusBarColor(1.0, 0.7, 0.0)
		castbar.value = GetTime() - (starttime / 1000)
		castbar.maxvalue = (endtime - starttime) / 1000
		castbar:SetMinMaxValues(0, castbar.maxvalue)
		castbar:SetValue(castbar.value)
		castbar.spellicon:SetTexture(icon)
		castbar:Show()
		castbar:SetScript("OnUpdate",self.CastOnUpdate)
	end
end

--[[
	ChannelStart
		"UNIT_SPELLCAST_CHANNEL_START"
]]

function Overhead:ChannelStart(uid)
	if active[uid] then
		local _, _, _, icon, starttime, endtime= UnitChannelInfo(uid)
		local castbar = active[uid]
		castbar.channeling = true
		castbar:SetStatusBarColor(0.0, 1.0, 0.0)
		castbar.value = (endtime / 1000) - GetTime()
		castbar.maxvalue = (endtime - starttime) / 1000
		castbar:SetMinMaxValues(0, castbar.maxvalue)
		castbar:SetValue(castbar.value)
		castbar.spellicon:SetTexture(icon)
		castbar:Show()
		castbar:SetScript("OnUpdate",self.CastOnUpdate)
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
