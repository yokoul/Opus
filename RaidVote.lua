-- RaidVote.lua : chez chaque joueur, la fenêtre des annonces du maître du butin, pour objecter et voter d'un clic
-- Elle s'ouvre à la première annonce et se referme quand tout est attribué. Un candidat à l'objet peut objecter, pas
-- voter. Le canal raid (« !objection »…) reste possible : le maître du butin compte une voix par joueur.
local _, Opus = ...
local Raid = Opus.Raid

local GARDER = 20                   -- secondes d'affichage d'un résultat

Raid.annonces = {}                  -- reçues, dans l'ordre : { ml, n, id, lien, propose, etat, fin, candidat, monVote… }

local f, lignes = nil, {}

local function Trouver (ml, n)
	for _, a in ipairs(Raid.annonces) do if a.ml == ml and a.n == n then return a end end
end

local function Chrono (a)
	local reste = math.max(0, math.floor((a.fin or 0) - GetTime()))
	return string.format("%d:%02d", math.floor(reste / 60), reste % 60)
end

local function Texte (a)
	if a.etat == "delai" then return a.propose .. " — objections encore " .. Chrono(a) end
	if a.etat == "vote" then
		return "objection de " .. (a.auteur or "?") .. " — vote " .. Chrono(a) .. (a.candidat and " (candidat : tu ne votes pas)" or a.monVote and (" — ton vote : " .. a.monVote) or "")
	end
	if a.etat == "attribue" then return "attribué à " .. (a.attributaire ~= "" and a.attributaire or "?") end
	if a.etat == "trancher" then return "proposition renversée : les officiers tranchent" end
	if a.etat == "sk" then return "hors wishlist : Suicide King, encore " .. Chrono(a) .. (a.veut and " — tu es sur les rangs" or "") end
	if a.etat == "de" then return "désenchantement" .. (a.attributaire ~= "" and (" par " .. a.attributaire) or "") end
	if a.etat == "banque" then return "pour la banque de guilde" end
	return ""
end

local function Construire ()
	f = CreateFrame("Frame", "OpusRaidVote", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(470, 100) f:SetPoint("TOP", 0, -120) f:SetFrameStrata("DIALOG")
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("Opus : attributions")
	f:Hide()
end

local function Bouton (parent, texte, largeur)
	local b = CreateFrame("Button", nil, parent, "SharedButtonSmallTemplate")
	b:SetSize(largeur, 22) b:SetText(texte)
	return b
end

local function Ligne (k)
	if lignes[k] then return lignes[k] end
	local l = CreateFrame("Frame", nil, f.Inset)
	l:SetSize(440, 40) l:SetPoint("TOPLEFT", 10, -8 - (k - 1) * 44)
	l.objet = CreateFrame("Button", nil, l)
	l.objet:SetSize(270, 18) l.objet:SetPoint("TOPLEFT")
	l.objet.texte = l.objet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l.objet.texte:SetAllPoints() l.objet.texte:SetJustifyH("LEFT")
	l.objet:SetScript("OnEnter", function (self)
		if not self.lien or not self.lien:find("|H", 1, true) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetHyperlink(self.lien) GameTooltip:Show()
	end)
	l.objet:SetScript("OnLeave", GameTooltip_Hide)
	l.etat = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.etat:SetPoint("TOPLEFT", 0, -20) l.etat:SetWidth(300) l.etat:SetJustifyH("LEFT") l.etat:SetWordWrap(false)
	l.objecter = Bouton(l, "Objecter", 90)
	l.objecter:SetPoint("RIGHT")
	l.objecter:SetScript("OnClick", function (self)
		if Raid.Repondre("O", self.annonce.n) then self.annonce.objecte = true else SendChatMessage("!objection " .. self.annonce.n, IsInRaid() and "RAID" or "PARTY") self.annonce.objecte = true end
		Raid.RafraichirVote()
	end)
	l.veux = Bouton(l, "Je le veux", 100)
	l.veux:SetPoint("RIGHT")
	l.veux:SetScript("OnClick", function (self)
		if not Raid.Repondre("W", self.annonce.n) then SendChatMessage("!sk " .. self.annonce.n, IsInRaid() and "RAID" or "PARTY") end
		self.annonce.veut = true
		Raid.RafraichirVote()
	end)
	l.contre = Bouton(l, "Contre", 70)
	l.contre:SetPoint("RIGHT")
	l.pour = Bouton(l, "Pour", 70)
	l.pour:SetPoint("RIGHT", l.contre, "LEFT", -4, 0)
	for _, b in ipairs({ l.pour, l.contre }) do
		b:SetScript("OnClick", function (self)
			local mot = self == l.pour and "pour" or "contre"
			if not Raid.Repondre(mot == "pour" and "P" or "C", self.annonce.n) then
				SendChatMessage("!" .. mot .. " " .. self.annonce.n, IsInRaid() and "RAID" or "PARTY")
			end
			self.annonce.monVote = mot
			Raid.RafraichirVote()
		end)
	end
	lignes[k] = l
	return l
end

function Raid.RafraichirVote ()
	-- les résultats s'effacent après un moment
	for k = #Raid.annonces, 1, -1 do
		local a = Raid.annonces[k]
		if a.finie and GetTime() - a.finie > GARDER then table.remove(Raid.annonces, k) end
	end
	if #Raid.annonces == 0 then if f then f:Hide() end return end
	if not f then Construire() end
	for _, l in ipairs(lignes) do l:Hide() end
	for k, a in ipairs(Raid.annonces) do
		local l = Ligne(k)
		l.objet.lien = a.lien
		l.objet.texte:SetText(a.lien)
		l.etat:SetText(Texte(a))
		l.objecter.annonce, l.pour.annonce, l.contre.annonce, l.veux.annonce = a, a, a, a
		l.veux:SetShown(a.etat == "sk")
		l.veux:SetEnabled(not a.veut)
		l.veux:SetText(a.veut and "Sur les rangs" or "Je le veux")
		l.objecter:SetShown(a.etat == "delai")
		l.objecter:SetEnabled(not a.objecte)
		l.objecter:SetText(a.objecte and "Objecté" or "Objecter")
		local vote = a.etat == "vote" and not a.candidat
		l.pour:SetShown(vote) l.contre:SetShown(vote)
		l.pour:SetEnabled(a.monVote ~= "pour") l.contre:SetEnabled(a.monVote ~= "contre")
		l:Show()
	end
	f:SetHeight(64 + #Raid.annonces * 44)
	f:Show()
end

-- un message du maître du butin (Comm.lua)
function Raid.RecevoirAnnonce (ml, c)
	local genre, n = c[1], tonumber(c[2])
	if not n then return end
	if genre == "S" then
		local id, secondes = tonumber(c[3]), tonumber(c[4])
		if not id or not secondes then return end
		local a = Trouver(ml, n)
		if not a then
			a = { ml = ml, n = n, id = id, lien = Raid.LienDe(id), propose = "" }
			Raid.annonces[#Raid.annonces + 1] = a
		end
		a.etat, a.fin = "sk", GetTime() + secondes
	elseif genre == "A" then
		local id, secondes = tonumber(c[3]), tonumber(c[5])
		if not id or not secondes or Trouver(ml, n) then return end
		local moi, candidat = Raid.MonNom(), false
		for _, nom in ipairs(Raid.Liste(c[6])) do if nom == moi then candidat = true end end
		Raid.annonces[#Raid.annonces + 1] = { ml = ml, n = n, id = id, lien = Raid.LienDe(id), propose = c[4] or "?", etat = "delai", fin = GetTime() + secondes, candidat = candidat }
	else
		local a = Trouver(ml, n)
		if not a then return end
		if genre == "V" then
			a.etat, a.fin, a.auteur = "vote", GetTime() + (tonumber(c[3]) or 0), c[6]
		elseif genre == "R" then
			a.etat, a.attributaire = c[3] or "", c[4] or ""
			if a.etat ~= "trancher" then a.finie = GetTime() end
		end
	end
	Raid.RafraichirVote()
end

-- comptes à rebours, effacement des résultats, noms d'objets arrivés après coup
C_Timer.NewTicker(1, function () if #Raid.annonces > 0 then Raid.RafraichirVote() end end)
Raid.Ecoute("GET_ITEM_INFO_RECEIVED", function (id)
	for _, a in ipairs(Raid.annonces) do
		if a.id == id and not a.lien:find("|H", 1, true) then a.lien = Raid.LienDe(id) end
	end
end)
