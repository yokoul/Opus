-- RaidFiche.lua : la fiche de décision d'un objet, pour le maître du butin et les officiers
-- Chaque candidat présent sur une ligne : sa couleur de classe, son rang et son rôle, son score en barre décomposée
-- (rang, prios perdues, dernier loot, gain, aux poids de l'instantané) et ce qu'il a déjà reçu ce soir et sur le
-- palier. Avant l'annonce, elle se lit (et « Annoncer » part d'ici) ; quand un vote renverse la proposition, elle
-- remplace la fenêtre « Trancher » : un clic sur un nom (ou Suicide King, Désenchantement), un motif en un clic,
-- Entrée décide.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

local LARGEUR = 560
local BARRE = 170                   -- la largeur d'un score de 100
local HAUT_LIGNE = 26
local MAX_LIGNES = 12

-- les quatre termes du score, dans l'ordre de la barre ; les couleurs se distinguent aussi sans la teinte (clarté)
local TERMES = {
	{ cle = "perso", nom = "rang", r = 0.96, g = 0.76, b = 0.22 },
	{ cle = "perdues", nom = "prios perdues", r = 0.36, g = 0.58, b = 0.96 },
	{ cle = "dernier", nom = "dernier loot", r = 0.42, g = 0.80, b = 0.46 },
	{ cle = "gain", nom = "gain", r = 0.72, g = 0.48, b = 0.90 },
}

-- les motifs tout prêts, complétés au clavier si besoin
local MOTIFS = {
	{ "Rang 1", "rang 1 de sa liste" },
	{ "Moins servi", "moins servi du palier" },
	{ "Rôle", "besoin du rôle" },
}

------------------------------------------------------------------------
-- ce que chacun a déjà reçu
------------------------------------------------------------------------

-- ce soir : les attributions du journal (liste et Suicide King ; ni désenchantement ni banque)
local function RecuCeSoir ()
	local n, s = {}, Raid.db.soiree
	for _, e in ipairs(s and s.evenements or {}) do
		if e.lettre == "A" and e.attributaire ~= "" and (e.voie == "wish" or e.voie == "sk") then
			n[e.attributaire] = (n[e.attributaire] or 0) + 1
		end
	end
	return n
end

-- sur le palier : les soirées validées que le bridge apporte, pour le palier de l'instantané (id « T1-… »)
local HORS = { ["désenchantement"] = true, ["banque de guilde"] = true }
local function RecuPalier ()
	local n, flux = {}, Raid.Flux and Raid.Flux()
	local id = Raid.db.instantane and Raid.db.instantane.id or ""
	if not flux then return nil end
	for _, p in ipairs(flux.paliers) do
		local code = tostring(p.code or ""):lower()
		if code ~= "" and id:lower():sub(1, #code + 1) == code .. "-" then
			for _, s in ipairs(p.soirees or {}) do
				for _, a in ipairs(s.attributions or {}) do
					if a.pour and a.pour ~= "" and not HORS[a.comment] then n[a.pour] = (n[a.pour] or 0) + 1 end
				end
			end
			return n
		end
	end
	return nil
end

------------------------------------------------------------------------
-- la fenêtre
------------------------------------------------------------------------

local f, lignes = nil, {}

local function Teinte (t, r, g, b, a) t:SetColorTexture(r, g, b, a or 1) end

local function Ligne (n)
	if lignes[n] then return lignes[n] end
	local z = f.Inset
	local l = CreateFrame("Button", nil, z)
	l:SetSize(LARGEUR - 40, HAUT_LIGNE - 2)
	l:SetPoint("TOPLEFT", 12, -f.haut - (n - 1) * HAUT_LIGNE)
	l.fond = l:CreateTexture(nil, "BACKGROUND") l.fond:SetAllPoints() Teinte(l.fond, 1, 1, 1, 0)
	l.survol = l:CreateTexture(nil, "HIGHLIGHT") l.survol:SetAllPoints() Teinte(l.survol, 1, 1, 1, 0.05)
	l.classe = l:CreateTexture(nil, "ARTWORK") l.classe:SetSize(3, HAUT_LIGNE - 8) l.classe:SetPoint("LEFT", 2, 0)
	l.nom = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	l.nom:SetPoint("LEFT", 12, 0) l.nom:SetWidth(132) l.nom:SetJustifyH("LEFT") l.nom:SetWordWrap(false)
	l.rang = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	l.rang:SetPoint("LEFT", 148, 0) l.rang:SetWidth(70) l.rang:SetJustifyH("LEFT") l.rang:SetWordWrap(false)
	l.piste = l:CreateTexture(nil, "BORDER") l.piste:SetSize(BARRE, 10) l.piste:SetPoint("LEFT", 222, 0) Teinte(l.piste, 0, 0, 0, 0.45)
	l.segments = {}
	for k, t in ipairs(TERMES) do
		local s = l:CreateTexture(nil, "ARTWORK")
		s:SetHeight(10) Teinte(s, t.r, t.g, t.b)
		l.segments[k] = s
	end
	l.score = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l.score:SetPoint("LEFT", 222 + BARRE + 6, 0) l.score:SetWidth(40) l.score:SetJustifyH("RIGHT")
	l.soir = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.soir:SetPoint("LEFT", 222 + BARRE + 56, 0) l.soir:SetWidth(52) l.soir:SetJustifyH("LEFT")
	l.palier = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.palier:SetPoint("LEFT", 222 + BARRE + 108, 0) l.palier:SetWidth(52) l.palier:SetJustifyH("LEFT")
	l:SetScript("OnClick", function (self) if f.decider and self.choix then f.choix = self.choix Raid.RafraichirFiche() end end)
	l:SetScript("OnEnter", function (self)
		local c = self.candidat
		if not c then return end
		local p = Raid.db.instantane.poids
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(c.nom .. " — " .. Raid.Score(c.score), 1, 1, 1)
		for _, t in ipairs(TERMES) do
			local v = c.termes[t.cle]
			GameTooltip:AddDoubleLine(string.format("%s (%.2f × %d)", t.nom, v, p[t.cle]), Raid.Score(v * p[t.cle]), t.r, t.g, t.b, 1, 1, 1)
		end
		if f.decider then GameTooltip:AddLine("Clic : lui attribuer l'objet.", 0.6, 0.6, 0.6) end
		GameTooltip:Show()
	end)
	l:SetScript("OnLeave", GameTooltip_Hide)
	lignes[n] = l
	return l
end

local function Construire ()
	f = CreateFrame("Frame", "OpusRaidFiche", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetWidth(LARGEUR) f:SetPoint("TOPLEFT", 260, -280) f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "OpusRaidFiche")
	local z = f.Inset
	f.objet = CreateFrame("Button", nil, z)
	f.objet:SetSize(LARGEUR - 40, 18) f.objet:SetPoint("TOPLEFT", 12, -10)
	f.objet.texte = f.objet:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.objet.texte:SetAllPoints() f.objet.texte:SetJustifyH("LEFT") f.objet.texte:SetWordWrap(false)
	f.objet:SetScript("OnEnter", function (self)
		if not f.lien or not f.lien:find("|H", 1, true) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetHyperlink(f.lien) GameTooltip:Show()
	end)
	f.objet:SetScript("OnLeave", GameTooltip_Hide)
	f.etat = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.etat:SetPoint("TOPLEFT", 12, -32) f.etat:SetPoint("TOPRIGHT", -12, -32) f.etat:SetJustifyH("LEFT") f.etat:SetWordWrap(false)
	-- les en-têtes de colonnes
	local function Tete (texte, x, l, j)
		local t = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		t:SetPoint("TOPLEFT", 12 + x, -52) t:SetWidth(l) t:SetJustifyH(j or "LEFT") t:SetText(texte)
	end
	Tete("candidat présent", 12, 132) Tete("rang · rôle", 148, 70) Tete("score", 222, BARRE)
	Tete("ce soir", 222 + BARRE + 56, 52) Tete("palier", 222 + BARRE + 108, 52)
	f.haut = 66
	f.absents = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.absents:SetJustifyH("LEFT") f.absents:SetWidth(LARGEUR - 40) f.absents:SetWordWrap(false)
	-- la légende de la barre
	f.legende = CreateFrame("Frame", nil, z)
	f.legende:SetSize(LARGEUR - 40, 14)
	local x = 0
	for _, t in ipairs(TERMES) do
		local carre = f.legende:CreateTexture(nil, "ARTWORK")
		carre:SetSize(10, 10) carre:SetPoint("LEFT", x, 0) Teinte(carre, t.r, t.g, t.b)
		local nom = f.legende:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		nom:SetPoint("LEFT", x + 14, 0) nom:SetText(t.nom)
		x = x + 18 + math.max(40, nom:GetStringWidth() + 10)
	end
	f.palierAbsent = f.legende:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.palierAbsent:SetPoint("RIGHT") f.palierAbsent:SetJustifyH("RIGHT")

	-- la décision : Suicide King, désenchantement, motifs, motif libre, « Décider »
	f.bas = CreateFrame("Frame", nil, z)
	f.bas:SetSize(LARGEUR - 40, 84)
	f.sk = Opus.Bouton(f.bas, "Suicide King", 120, function () f.choix = { voie = "sk" } Raid.RafraichirFiche() end, true)
	f.sk:SetPoint("TOPLEFT", 0, 0)
	f.de = Opus.Bouton(f.bas, "Désenchantement", 130, function () f.choix = { voie = "de" } Raid.RafraichirFiche() end, true)
	f.de:SetPoint("LEFT", f.sk, "RIGHT", 6, 0)
	f.choisi = f.bas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.choisi:SetPoint("LEFT", f.de, "RIGHT", 12, 0) f.choisi:SetPoint("RIGHT", f.bas, "RIGHT") f.choisi:SetJustifyH("LEFT")
	local precedent
	f.motifs, f.lignes = {}, lignes
	for k, m in ipairs(MOTIFS) do
		local b = Opus.Bouton(f.bas, m[1], 96, function ()
			local t = strtrim(f.motif:GetText() or "")
			if not t:find(m[2], 1, true) then f.motif:SetText(t == "" and m[2] or (t .. ", " .. m[2])) end
			f.motif:SetFocus()
		end, true)
		if k == 1 then b:SetPoint("TOPLEFT", 0, -28) else b:SetPoint("LEFT", precedent, "RIGHT", 6, 0) end
		precedent, f.motifs[k] = b, b
	end
	f.motif = CreateFrame("EditBox", nil, f.bas, "InputBoxTemplate")
	f.motif:SetSize(LARGEUR - 180, 20) f.motif:SetPoint("TOPLEFT", 6, -56) f.motif:SetAutoFocus(false) f.motif:SetMaxLetters(120)
	f.motif:SetScript("OnEscapePressed", function () f:Hide() end)
	f.ok = Opus.Bouton(f.bas, "Décider", 110, function ()
		local c = f.choix
		if not c then Msg("choisis à qui va l'objet : un clic sur son nom, ou Suicide King, ou Désenchantement.") return end
		if Raid.Decider(f.attribution, c.nom, c.voie, f.motif:GetText()) then f:Hide() end
	end)
	f.ok:SetPoint("TOPRIGHT", 0, -54)
	f.motif:SetScript("OnEnterPressed", function () f.ok:Click() end)
	f.motifAide = f.bas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.motifAide:SetPoint("LEFT", precedent, "RIGHT", 12, 0) f.motifAide:SetText("motif annoncé au raid, obligatoire")
	-- avant l'annonce : « Annoncer » d'ici
	f.annoncer = Opus.Bouton(z, "Annoncer", 110, function ()
		if f.objetButin and Raid.AnnoncerObjet then Raid.AnnoncerObjet(f.objetButin) end
	end)
	f:Hide()
end

local function Etat (a, r)
	if not a then
		if not r then return "pas d'instantané : /opus raid import" end
		local c1 = r.candidats[1]
		return c1 and ("Proposé : " .. c1.nom .. (r.egalite and " (ex aequo, au maître du butin de trancher)" or "") .. " · pas encore annoncé")
			or "aucun candidat présent » Suicide King"
	end
	local texte = (a.propose and a.propose ~= "?") and ("Proposé : " .. a.propose .. " · ") or ""
	if a.objecteurs and #a.objecteurs > 0 then texte = texte .. "objection de " .. table.concat(a.objecteurs, ", ") .. " · " end
	if a.etat == "trancher" then
		local pour, contre = 0, 0
		for _, v in pairs(a.votes or {}) do if v == "pour" then pour = pour + 1 else contre = contre + 1 end end
		if pour + contre > 0 then texte = texte .. string.format("vote %d pour, %d contre · ", pour, contre) end
		return texte .. "|cffffd100aux officiers de trancher|r"
	end
	return (Raid.EtatAttribution(a):gsub("^#%d+ ", ""))
end

function Raid.RafraichirFiche ()
	if not f or not f:IsShown() then return end
	-- annoncé depuis la fiche (ou la fenêtre du butin) : la fiche suit l'attribution
	if f.objetButin and f.objetButin.attribution then f.attribution, f.objetButin = f.objetButin.attribution, nil end
	local a = f.attribution
	f.decider = a and a.etat == "trancher" and Raid.PeutGerer() or false
	local r = Raid.Proposer(f.id, Raid.Presents())
	f.objet.texte:SetText(f.lien)
	f.etat:SetText(Etat(a, r))
	f:SetTitle(a and ("Fiche de décision #" .. a.n) or "Fiche de décision")
	local soir, palier = RecuCeSoir(), RecuPalier()
	local poids = Raid.db.instantane and Raid.db.instantane.poids
	local candidats = r and r.candidats or {}
	for _, l in ipairs(lignes) do l:Hide() end
	local n = math.min(#candidats, MAX_LIGNES)
	for k = 1, n do
		local c, l = candidats[k], Ligne(k)
		l.candidat, l.choix = c, { nom = c.nom, voie = "wish" }
		local classe = Opus.db.classes and Opus.db.classes[c.nom]
		local couleur = classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classe]
		if couleur then Teinte(l.classe, couleur.r, couleur.g, couleur.b) else Teinte(l.classe, 0.5, 0.5, 0.5) end
		l.nom:SetText(Opus.Couleur(classe) .. c.nom .. "|r")
		l.rang:SetText("r" .. c.rang .. (c.role ~= "" and (" · " .. c.role) or ""))
		local x = 0
		for i, t in ipairs(TERMES) do
			local largeur = BARRE * c.termes[t.cle] * poids[t.cle] / 100
			local s = l.segments[i]
			s:ClearAllPoints()
			if largeur >= 1 then s:SetPoint("LEFT", l.piste, "LEFT", x, 0) s:SetWidth(largeur) s:Show() else s:Hide() end
			x = x + largeur
		end
		l.score:SetText(Raid.Score(c.score))
		local ns, np = soir[c.nom] or 0, palier and (palier[c.nom] or 0)
		l.soir:SetText(ns > 0 and Opus.Blanc(ns .. " reçu" .. (ns > 1 and "s" or "")) or Opus.Gris("rien"))
		l.palier:SetText(not np and Opus.Gris("?") or np > 0 and Opus.Blanc(tostring(np)) or Opus.Gris("0"))
		local choisi = f.decider and f.choix and f.choix.voie == "wish" and f.choix.nom == c.nom
		Teinte(l.fond, 1, 0.82, 0, choisi and 0.18 or (k == 1 and 0.05 or 0))
		l:Show()
	end
	local y = f.haut + n * HAUT_LIGNE + 4
	local absents = r and r.absents or {}
	local reste = #candidats - n
	f.absents:SetText((#absents > 0 and ("absents en liste : " .. table.concat(absents, ", ")) or "")
		.. (reste > 0 and ((#absents > 0 and " · " or "") .. reste .. " autre" .. (reste > 1 and "s" or "") .. " plus bas") or "")
		.. ((n == 0 and #absents == 0) and "personne n'a cet objet en liste" or ""))
	f.absents:ClearAllPoints() f.absents:SetPoint("TOPLEFT", 12, -y)
	y = y + 18
	f.legende:ClearAllPoints() f.legende:SetPoint("TOPLEFT", 12, -y)
	f.palierAbsent:SetText(palier and "" or "palier : pas de flux du bridge")
	y = y + 22
	f.bas:SetShown(f.decider)
	f.annoncer:SetShown(not a and f.objetButin ~= nil and Raid.PeutGerer())
	if f.decider then
		f.bas:ClearAllPoints() f.bas:SetPoint("TOPLEFT", 12, -y)
		local c = f.choix
		f.choisi:SetText(not c and Opus.Gris("clic sur un nom pour choisir")
			or c.voie == "sk" and "» Suicide King" or c.voie == "de" and "» Désenchantement" or ("» " .. c.nom))
		y = y + 88
	elseif f.annoncer:IsShown() then
		f.annoncer:ClearAllPoints() f.annoncer:SetPoint("TOPRIGHT", -12, -y)
		y = y + 30
	end
	f:SetHeight(y + 40)
end

-- La fiche d'un objet : o = { lien, id, attribution? } (une ligne de la fenêtre du butin), ou une attribution.
function Raid.OuvrirFiche (o)
	if not Raid.db.instantane then Msg("pas d'instantané : /opus raid import.") return end
	if not f then Construire() end
	local a = o.attribution or (o.etat and o) or nil
	if f.attribution ~= a or f.id ~= o.id then f.choix = nil f.motif:SetText("") end
	f.attribution, f.id, f.lien = a, o.id, o.lien
	f.objetButin = (not o.etat) and o or nil
	f:Show()
	Raid.RafraichirFiche()
	if f.decider then f.motif:SetFocus() end
end

-- « Trancher… » : la fiche, en mode décision
function Raid.OuvrirDecision (a)
	if not Raid.PeutGerer() then Msg("décision " .. Raid.QuiPeut() .. ".") return end
	Raid.OuvrirFiche(a)
end

-- les comptes à rebours d'une fiche ouverte sur une attribution en cours
C_Timer.NewTicker(1, function ()
	local a = f and f:IsShown() and f.attribution
	if a and (a.etat == "delai" or a.etat == "vote" or a.etat == "sk") then Raid.RafraichirFiche() end
end)
