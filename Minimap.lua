-- Minimap.lua : le bouton sur le bord de la minimap, et l'entrée dans le compartiment d'addons (la liste sous la
-- minimap) ; tous deux ouvrent la fenêtre, comme /opus. Clic gauche : ouvrir ou fermer ; clic droit : le journal ;
-- glisser : le déplacer autour de la minimap. /opus minimap le cache ou le remet.
local _, Opus = ...

local bouton

local function Forme ()
	if GetMinimapShape then
		local ok, s = pcall(GetMinimapShape)
		if ok and s then return s end
	end
	return "ROUND"
end

local function Placer ()
	local angle = math.rad(Opus.db.minimap.angle)
	local x, y = math.cos(angle), math.sin(angle)
	local w, h = (Minimap:GetWidth() or 140) / 2 + 8, (Minimap:GetHeight() or 140) / 2 + 8
	if Forme() == "SQUARE" then
		local m = math.max(math.abs(x), math.abs(y))
		x, y = x / m * (w - 2), y / m * (h - 2)
	else
		x, y = x * w, y * h
	end
	bouton:ClearAllPoints()
	bouton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- l'infobulle : ce qui attend, en un coup d'œil
local function Bulle (self, ancre)
	GameTooltip:SetOwner(self, ancre or "ANCHOR_LEFT")
	GameTooltip:SetText(GetGuildInfo("player") or "Opus", 1, 1, 1)
	if IsInGuild() and Opus.db then
		local essais, echus = 0, 0
		for _, m in ipairs(Opus.Essais()) do
			essais = essais + 1
			if m.echu and not m.montee then echus = echus + 1 end
		end
		GameTooltip:AddLine(("%d à l'essai%s"):format(essais, echus > 0 and (", " .. echus .. " à promouvoir") or ""), 1, 1, 1)
		local dernier = Opus.Evenements("tout")[1]
		if dernier then
			GameTooltip:AddLine("Dernier événement, il y a " .. Opus.Depuis(dernier.t) .. " :", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			GameTooltip:AddLine("  " .. Opus.Phrase(dernier, function (n) return n end), 1, 1, 1, true)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Clic gauche", "Ouvrir", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
	GameTooltip:AddDoubleLine("Clic droit", "Tableau de la guilde", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
	if self == bouton then
		GameTooltip:AddDoubleLine("Glisser", "Déplacer", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function Clic (bouton_souris)
	if bouton_souris == "RightButton" then
		Opus.DemanderJournal()
		Opus.OuvrirGuilde("voies")
	else
		Opus.Fenetre()
	end
end

local function Creer ()
	if bouton or not Minimap then return end
	bouton = CreateFrame("Button", "OpusBoutonMinimap", Minimap)
	bouton:SetSize(32, 32)
	bouton:SetFrameStrata("MEDIUM")
	bouton:SetFrameLevel(8)
	bouton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bouton:RegisterForDrag("LeftButton")
	local fond = bouton:CreateTexture(nil, "BACKGROUND")
	fond:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	fond:SetSize(22, 22)
	fond:SetPoint("CENTER")
	bouton.icone = bouton:CreateTexture(nil, "ARTWORK")
	bouton.icone:SetTexture("Interface\\AddOns\\Opus\\Media\\Icone")
	bouton.icone:SetSize(20, 20)
	bouton.icone:SetPoint("CENTER")
	local bord = bouton:CreateTexture(nil, "OVERLAY")
	bord:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	bord:SetSize(54, 54)
	bord:SetPoint("TOPLEFT")
	bouton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	bouton:SetScript("OnMouseDown", function (self) self.icone:SetPoint("CENTER", 1, -1) end)
	bouton:SetScript("OnMouseUp", function (self) self.icone:SetPoint("CENTER", 0, 0) end)
	bouton:SetScript("OnClick", function (self, b) if not self.glisse then Clic(b) end end)
	bouton:SetScript("OnDragStart", function (self)
		self.glisse = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function ()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local echelle = Minimap:GetEffectiveScale()
			Opus.db.minimap.angle = math.deg(math.atan2(py / echelle - my, px / echelle - mx)) % 360
			Placer()
		end)
	end)
	bouton:SetScript("OnDragStop", function (self)
		self:SetScript("OnUpdate", nil)
		C_Timer.After(0.05, function () self.glisse = false end)
	end)
	bouton:SetScript("OnEnter", function (self) if not self.glisse then Bulle(self) end end)
	bouton:SetScript("OnLeave", GameTooltip_Hide)
	Placer()
	bouton:SetShown(not Opus.db.minimap.cache)
end

Opus.Ecoute("PLAYER_ENTERING_WORLD", function () if Opus.db then Creer() end end)

-- le compartiment d'addons (## AddonCompartmentFunc dans le .toc) : des fonctions globales
function Opus_Compartiment (_, bouton_souris) Clic(bouton_souris) end
function Opus_CompartimentSurvol (_, cadre) Bulle(cadre, "ANCHOR_LEFT") end
function Opus_CompartimentSortie () GameTooltip:Hide() end

Opus.Commande("minimap", "minimap", "cache ou remet le bouton de la minimap", function ()
	Opus.db.minimap.cache = not Opus.db.minimap.cache
	Creer()
	bouton:SetShown(not Opus.db.minimap.cache)
	Opus.Msg(Opus.db.minimap.cache and "bouton de la minimap caché (/opus minimap pour le remettre)." or "bouton de la minimap affiché.")
end)
