local AddOn = "TotemPlates"

local numChildren = -1
local Table = {
   ["Nameplates"] = {},
   ["Snakes"] = {
      "Viper",
      "Venomous Snake",
   },
   ["Totems"] = {
      ["Mana Spring Totem VIII"] = true,
      ["Cleansing Totem"] = true,
      ["Magma Totem VII"] = false,
      ["Earth Elemental Totem"] = true,
      ["Earthbind Totem"] = true,
      ["Fire Resistance Totem VI"] = false,
      ["Flametongue Totem VIII"] = false,
      ["Frost Resistance Totem VI"] = false,
      ["Grounding Totem"] = true,
      ["Healing Stream Totem IX"] = false,
      ["Nature Resistance Totem VI"] = false,
      ["Searing Totem X"] = false,
      ["Sentry Totem"] = false,
      ["Stoneclaw Totem X"] = true,
      ["Stoneskin Totem X"] = false,
      ["Strength of Earth Totem VIII"] = false,
      ["Totem of Wrath IV"] = false,
      ["Tremor Totem"] = true,
      ["Windfury Totem"] = false,
      ["Wrath of Air Totem"] = false,
      ["Fire Elemental Totem"] = true,
      ["Mana Tide Totem"] = true,
   },
   xOfs = 0,
   yOfs = 0,
   Scale = 0.8,
}

local function UpdateObjects(hp)
   frame = hp:GetParent()
   local threat, hpborder, cbshield, cbborder, cbicon, overlay, oldname, level, bossicon, raidicon, elite = frame:GetRegions()
   local name = oldname:GetText()

   overlay:SetAlpha(1)
   threat:Show()
   hpborder:Show()
   oldname:Show()
   level:Show()
   hp:SetAlpha(1)
   if frame.totem then frame.totem:Hide() end

   for _,snake in pairs(Table["Snakes"]) do
      if ( name == snake ) then
         overlay:SetAlpha(1)
         threat:Hide()
         hpborder:Hide()
         oldname:Hide()
         level:Hide()
         hp:SetAlpha(1)
         break
      end
   end

   for totem in pairs(Table["Totems"]) do
      if ( name == totem and Table["Totems"][totem] == true ) then
         overlay:SetAlpha(0)
         threat:Hide()
         hpborder:Hide()
         oldname:Hide()
         level:Hide()
         hp:SetAlpha(0)
         if not frame.totem then
            frame.totem = frame:CreateTexture(nil, "BACKGROUND")
            frame.totem:ClearAllPoints()
            frame.totem:SetPoint("CENTER",frame,"CENTER",Table.xOfs,Table.yOfs)
         else
            frame.totem:Show()
         end   
         frame.totem:SetTexture("Interface\\AddOns\\" .. AddOn .. "\\Textures\\" .. totem)
         frame.totem:SetWidth(64 *Table.Scale)
         frame.totem:SetHeight(64 *Table.Scale)
         break
      elseif ( name == totem ) then
         overlay:SetAlpha(0)
         threat:Hide()
         hpborder:Hide()
         oldname:Hide()
         level:Hide()
         hp:SetAlpha(0)
         break
      end
   end
end

local function SkinObjects(frame)
   local HealthBar, CastBar = frame:GetChildren()
   local threat, hpborder, cbshield, cbborder, cbicon, overlay, oldname, level, bossicon, raidicon, elite = frame:GetRegions()

   HealthBar:HookScript("OnShow", UpdateObjects)
   HealthBar:HookScript("OnSizeChanged", UpdateObjects)

   UpdateObjects(HealthBar)
   Table["Nameplates"][frame] = true
end

local select = select
local function HookFrames(...)
   for index = 1, select('#', ...) do
      local frame = select(index, ...)
      local region = frame:GetRegions()

      if ( not Table["Nameplates"][frame] and not frame:GetName() and region and region:GetObjectType() == "Texture" and region:GetTexture() == "Interface\\TargetingFrame\\UI-TargetingFrame-Flash" ) then
         SkinObjects(frame)                  
         frame.region = region
      end
   end
end

local Frame = CreateFrame("Frame")
Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Frame:SetScript("OnUpdate", function(self, elapsed)
	if ( WorldFrame:GetNumChildren() ~= numChildren ) then
		numChildren = WorldFrame:GetNumChildren()
		HookFrames(WorldFrame:GetChildren())      
	end
end)
Frame:SetScript("OnEvent", function(self, event, name)
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		if ( not _G[AddOn .. "_PlayerEnteredWorld"] ) then
			ChatFrame1:AddMessage("|cff00ccff" .. AddOn .. "|cffffffff Loaded")
			_G[AddOn .. "_PlayerEnteredWorld"] = true
		end   
	end
end)