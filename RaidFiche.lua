-- RaidFiche.lua : la fiche de décision d'un objet, pour le maître du butin et les officiers
-- Chaque candidat présent sur une ligne : sa couleur de classe, son rang et son rôle, son score en barre décomposée
-- (rang, prios perdues, dernier loot, gain, aux poids de l'instantané) et ce qu'il a déjà reçu ce soir et sur le
-- palier. Avant l'annonce, elle se lit (et « Annoncer » part d'ici) ; pendant le vote, les voix de chacun, et un clic
-- sur un nom y vote ; les officiers décident d'ici à tout moment (« Décision des officiers… », ou d'office après une
-- égalité) : un clic sur un nom (ou Suicide King, Désenchantement), un motif en un clic, Entrée décide.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

local LARGEUR = 810
local BARRE = 140                   -- la largeur d'un score de 100
local HAUT_LIGNE = 26
local MAX_LIGNES = 12
local PORTE = 222                   -- la colonne de l'équipement porté : deux icônes et le verdict (écart de niveau)
local CHANGE = 316                  -- ce qui change : les trois caractéristiques qui bougent le plus
local X = 470                       -- le début de la barre du score

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
	l.piste = l:CreateTexture(nil, "BORDER") l.piste:SetSize(BARRE, 10) l.piste:SetPoint("LEFT", X, 0) Teinte(l.piste, 0, 0, 0, 0.45)
	l.segments = {}
	for k, t in ipairs(TERMES) do
		local s = l:CreateTexture(nil, "ARTWORK")
		s:SetHeight(10) Teinte(s, t.r, t.g, t.b)
		l.segments[k] = s
	end
	l.score = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	l.score:SetPoint("LEFT", X + BARRE + 6, 0) l.score:SetWidth(40) l.score:SetJustifyH("RIGHT")
	l.soir = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.soir:SetPoint("LEFT", X + BARRE + 56, 0) l.soir:SetWidth(52) l.soir:SetJustifyH("LEFT")
	l.palier = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.palier:SetPoint("LEFT", X + BARRE + 108, 0) l.palier:SetWidth(52) l.palier:SetJustifyH("LEFT")
	-- ce qu'il porte à l'emplacement : une icône par case (deux pour bagues, bijoux, armes), l'écart de niveau
	l.portes = {}
	for k = 1, 2 do
		local b = Raid.Icone(l, 20)
		b:SetPoint("LEFT", PORTE + (k - 1) * 23, 0)
		b.vide = b:CreateTexture(nil, "BACKGROUND") b.vide:SetAllPoints() Teinte(b.vide, 0, 0, 0, 0.45)
		l.portes[k] = b
	end
	l.verdict = Raid.Verdict(l)
	l.change = Raid.Pastilles(l, 3)
	l.change:SetPoint("LEFT", CHANGE, 0)
	l:SetScript("OnClick", function (self)
		if not self.choix then return end
		if f.decider then f.choix = self.choix
		elseif f.electeur then Raid.Recevoir("vote", f.attribution.n, Raid.MonNom(), self.choix.nom) end
		Raid.RafraichirFiche()
	end)
	l:SetScript("OnEnter", function (self)
		local c = self.candidat
		if not c and self.membre then
			-- hors liste : le présent, ce qu'il porte et ce que l'objet lui changerait
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.membre, 1, 1, 1)
			if self.portable == "non" then GameTooltip:AddLine("Ne peut pas porter cet objet.", 0.6, 0.6, 0.6)
			else Raid.InfobulleEquipement(self.membre, f.id, f.lien) end
			if f.decider then GameTooltip:AddLine("Clic : lui attribuer l'objet.", 0.6, 0.6, 0.6) end
			GameTooltip:Show()
			return
		end
		if not c then return end
		local p = Raid.db.instantane.poids
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(c.nom .. " — " .. Raid.Score(c.score), 1, 1, 1)
		for _, t in ipairs(TERMES) do
			local v = c.termes[t.cle]
			GameTooltip:AddDoubleLine(string.format("%s (%.2f × %d)", t.nom, v, p[t.cle]), Raid.Score(v * p[t.cle]), t.r, t.g, t.b, 1, 1, 1)
		end
		Raid.InfobulleEquipement(c.nom, f.id, f.lien)
		if f.decider then GameTooltip:AddLine("Clic : lui attribuer l'objet.", 0.6, 0.6, 0.6)
		elseif f.electeur then GameTooltip:AddLine("Clic : voter pour lui.", 0.6, 0.6, 0.6) end
		GameTooltip:Show()
	end)
	l:SetScript("OnLeave", GameTooltip_Hide)
	lignes[n] = l
	return l
end

local function Construire ()
	f = Raid.Cadre("OpusRaidFiche")
	f:SetWidth(LARGEUR) f:SetPoint("TOPLEFT", 260, -280) f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "OpusRaidFiche")
	local z = f.Inset
	f.icone = Raid.Icone(z, 36)
	f.icone:SetPoint("TOPLEFT", 12, -8)
	f.objet = CreateFrame("Button", nil, z)
	f.objet:SetSize(LARGEUR - 84, 18) f.objet:SetPoint("TOPLEFT", 56, -10)
	f.objet.texte = f.objet:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.objet.texte:SetAllPoints() f.objet.texte:SetJustifyH("LEFT") f.objet.texte:SetWordWrap(false)
	f.objet:SetScript("OnEnter", function (self) Raid.Infobulle(self, f.lien, f.id) end)
	f.objet:SetScript("OnLeave", GameTooltip_Hide)
	f.etat = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.etat:SetPoint("TOPLEFT", 56, -32) f.etat:SetPoint("TOPRIGHT", -12, -32) f.etat:SetJustifyH("LEFT") f.etat:SetWordWrap(false)
	-- les en-têtes de colonnes
	local function Tete (texte, x, l, j)
		local t = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		t:SetPoint("TOPLEFT", 12 + x, -52) t:SetWidth(l) t:SetJustifyH(j or "LEFT") t:SetText(texte)
		return t
	end
	f.teteNom = Tete("candidat présent", 12, 132) f.teteRang = Tete("rang · rôle", 148, 70) Tete("porté", PORTE, 84) Tete("ce qui change", CHANGE, 140) f.teteScore = Tete("score", X, BARRE)
	f.teteSoir = Tete("ce soir", X + BARRE + 56, 52) Tete("palier", X + BARRE + 108, 52)
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
	-- pendant le vote, s'il est électeur (pas candidat) : sa voix, d'un clic sur un nom
	f.monVote = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.monVote:SetJustifyH("LEFT")
	-- la décision des officiers, à tout moment avant l'attribution
	f.forcerBouton = Opus.Bouton(z, "Décision des officiers…", 180, function () f.forcer = true f.choix = nil Raid.RafraichirFiche() f.motif:SetFocus() end)
	Opus.Bulle(f.forcerBouton, "Décision des officiers", "Pour le raid et le progress (rôle clé, boss bloquant…), à tout moment : elle remplace le délai ou le vote en cours. Motif obligatoire, annoncé au raid et noté au rapport.")
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
	local objection = a.objecteurs and #a.objecteurs > 0
	if objection then
		texte = texte .. "|cffff8040objection de " .. table.concat(a.objecteurs, ", ") .. (a.motif and (" (« " .. a.motif .. " »)") or "") .. "|r · "
	end
	if a.etat == "trancher" then return texte .. "|cffffd100égalité : aux officiers de trancher|r" end
	if a.etat == "delai" or a.etat == "vote" then return texte .. (Raid.EtatAttribution(a):gsub("^#%d+ ", ""):gsub("^.- — ", "")) end
	return (Raid.EtatAttribution(a):gsub("^#%d+ ", ""))
end

function Raid.RafraichirFiche ()
	if not f or not f:IsShown() then return end
	-- annoncé depuis la fiche (ou la fenêtre du butin) : la fiche suit l'attribution
	if f.objetButin and f.objetButin.attribution then f.attribution, f.objetButin = f.objetButin.attribution, nil end
	local a = f.attribution
	f.decider = a and Raid.Decidable(a) and Raid.PeutGerer() and (a.etat == "trancher" or f.forcer) or false
	local moi = Raid.MonNom()
	f.electeur = not f.decider and a and a.etat == "vote" and not (a.candidats and a.candidats[moi]) and (not a.electeurs or a.electeurs[moi]) or false
	local voix = {}
	if a and a.etat == "vote" then for _, c in ipairs((Raid.Decompte(a))) do voix[c.nom] = c.voix end end
	f.teteSoir:SetText(a and a.etat == "vote" and "voix" or "ce soir")
	local r = Raid.Proposer(f.id, Raid.Presents())
	f.lien = Raid.LienAJour(f.lien, f.id)
	f.objet.texte:SetText(f.lien)
	Raid.PoserIcone(f.icone, f.id, f.lien)
	f.etat:SetText(Etat(a, r))
	f:SetTitle(a and ("Détails de l'objet #" .. a.n) or "Détails de l'objet")
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
		local eq = Raid.Comparer(c.nom, f.id)
		for i, b in ipairs(l.portes) do
			local case = eq and eq.cases and eq.cases[i]
			if case and case.id then
				Raid.PoserIcone(b, case.id, case.lien) b.image:Show() b.vide:Hide() b:Show()
			elseif case then
				b.id, b.lien = nil, nil b.image:Hide() b.vide:Show() b:Show()
			else b:Hide() end
		end
		l.verdict:ClearAllPoints()
		l.verdict:SetPoint("LEFT", PORTE + (eq and eq.cases and #eq.cases or 0) * 23 + 2, 0)
		Raid.PoserVerdict(l.verdict, eq)
		Raid.PoserPastilles(l.change, eq, f.id, f.lien)
		l.score:SetText(Raid.Score(c.score))
		local ns, np = soir[c.nom] or 0, palier and (palier[c.nom] or 0)
		if a and a.etat == "vote" then
			local v = voix[c.nom] or 0
			local mien = a.votes and a.votes[moi] == c.nom
			l.soir:SetText(v > 0 and ((mien and "|cffffd100" or "|cffffffff") .. v .. " voix|r") or Opus.Gris(mien and "ton vote" or "0"))
		else
			l.soir:SetText(ns > 0 and Opus.Blanc(ns .. " reçu" .. (ns > 1 and "s" or "")) or Opus.Gris("rien"))
		end
		l.palier:SetText(not np and Opus.Gris("?") or np > 0 and Opus.Blanc(tostring(np)) or Opus.Gris("0"))
		local choisi = f.decider and f.choix and f.choix.voie == "wish" and f.choix.nom == c.nom
		Teinte(l.fond, 1, 0.82, 0, choisi and 0.18 or (k == 1 and 0.05 or 0))
		l:Show()
	end
	-- hors liste (Suicide King) : aucun candidat en liste, la fiche montre les présents qui peuvent s'en servir ; les
	-- déclarés d'abord, dans l'ordre de la liste Suicide King, puis ceux qui peuvent le porter, les autres estompés
	local horsListe = n == 0 and r ~= nil
	f.teteNom:SetText(horsListe and "présent" or "candidat présent")
	f.teteRang:SetText(horsListe and "liste SK" or "rang · rôle")
	f.teteScore:SetText(horsListe and "Suicide King" or "score")
	for _, l in ipairs(lignes) do l.piste:SetShown(not horsListe) l.membre, l.portable = nil, nil end
	if horsListe then
		local declares, pos = a and Raid.ClassementSK(a) or {}, {}
		local rangDeclare = {}
		for k, nom in ipairs(declares) do rangDeclare[nom] = k end
		for k, nom in ipairs(Raid.ListeSK()) do pos[nom] = k end
		local membres = {}
		for _, m in ipairs(Raid.Unites()) do
			if m.nom then
				local peut = Opus.PeutPorter and Opus.PeutPorter(m.unite, f.id)
				local _, classe = UnitClass(m.unite)
				membres[#membres + 1] = { nom = m.nom, peut = peut, classe = classe, declare = rangDeclare[m.nom] }
			end
		end
		table.sort(membres, function (x, z)
			if (x.declare or 99) ~= (z.declare or 99) then return (x.declare or 99) < (z.declare or 99) end
			local px, pz = (x.peut == "oui" or x.peut == nil) and 0 or 1, (z.peut == "oui" or z.peut == nil) and 0 or 1
			if px ~= pz then return px < pz end
			return (pos[x.nom] or 999) < (pos[z.nom] or 999)
		end)
		n = math.min(#membres, MAX_LIGNES)
		for k = 1, n do
			local m, l = membres[k], Ligne(k)
			l.candidat, l.membre, l.portable, l.choix = nil, m.nom, m.peut, { nom = m.nom, voie = "wish" }
			local couleur = m.classe and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.classe]
			if couleur then Teinte(l.classe, couleur.r, couleur.g, couleur.b) else Teinte(l.classe, 0.5, 0.5, 0.5) end
			l.nom:SetText(Opus.Couleur(m.classe) .. m.nom .. "|r")
			l.rang:SetText(pos[m.nom] and ("SK " .. pos[m.nom]) or Opus.Gris("hors liste"))
			for _, s in ipairs(l.segments) do s:Hide() end
			local eq = m.peut ~= "non" and Raid.Comparer(m.nom, f.id) or nil
			for i, b in ipairs(l.portes) do
				local case = eq and eq.cases and eq.cases[i]
				if case and case.id then Raid.PoserIcone(b, case.id, case.lien) b.image:Show() b.vide:Hide() b:Show()
				elseif case then b.id, b.lien = nil, nil b.image:Hide() b.vide:Show() b:Show()
				else b:Hide() end
			end
			l.verdict:ClearAllPoints()
			l.verdict:SetPoint("LEFT", PORTE + (eq and eq.cases and #eq.cases or 0) * 23 + 2, 0)
			if m.peut == "non" then l.verdict:Hide() Raid.PoserPastilles(l.change, nil)
			else Raid.PoserVerdict(l.verdict, eq) Raid.PoserPastilles(l.change, eq, f.id, f.lien) end
			l.score:SetText(m.declare == 1 and "|cffffd100en tête|r" or m.declare and "|cff40ff40le veut|r" or "")
			local ns, np = soir[m.nom] or 0, palier and (palier[m.nom] or 0)
			l.soir:SetText(ns > 0 and Opus.Blanc(ns .. " reçu" .. (ns > 1 and "s" or "")) or Opus.Gris("rien"))
			l.palier:SetText(not np and Opus.Gris("?") or np > 0 and Opus.Blanc(tostring(np)) or Opus.Gris("0"))
			l:SetAlpha((m.peut == "non" or (m.peut and m.peut ~= "oui")) and not m.declare and 0.45 or 1)
			local choisi = f.decider and f.choix and f.choix.voie == "wish" and f.choix.nom == m.nom
			Teinte(l.fond, 1, 0.82, 0, choisi and 0.18 or (m.declare == 1 and 0.08 or 0))
			l:Show()
		end
	else
		for k = 1, n do lignes[k]:SetAlpha(1) end
	end
	local y = f.haut + n * HAUT_LIGNE + 4
	local absents = r and r.absents or {}
	local reste = #candidats - n
	f.absents:SetText((#absents > 0 and ("absents en liste : " .. table.concat(absents, ", ")) or "")
		.. (reste > 0 and ((#absents > 0 and " · " or "") .. reste .. " autre" .. (reste > 1 and "s" or "") .. " plus bas") or "")
		.. (horsListe and "personne n'a cet objet en liste : Suicide King entre les présents" or ""))
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
	local forcer = not f.decider and a and Raid.Decidable(a) and a.etat ~= "trancher" and Raid.PeutGerer() or false
	f.forcerBouton:SetShown(forcer)
	f.monVote:SetShown(f.electeur or false)
	if f.electeur or forcer then
		f.forcerBouton:ClearAllPoints() f.forcerBouton:SetPoint("TOPRIGHT", -12, -y)
		local v = a.votes and a.votes[moi]
		f.monVote:ClearAllPoints() f.monVote:SetPoint("TOPLEFT", 12, -y - 6)
		f.monVote:SetText(v and ("ton vote : " .. v .. " (clic sur un autre nom pour changer)") or "ton vote : clic sur le nom de ton choix")
		y = y + 30
	end
	f:SetHeight(y + 38)
end

-- La fiche d'un objet : o = { lien, id, attribution? } (une ligne de la fenêtre du butin), ou une attribution.
function Raid.OuvrirFiche (o)
	if not Raid.db.instantane then Msg("pas d'instantané : /opus raid import.") return end
	if not f then Construire() end
	local a = o.attribution or (o.etat and o) or nil
	if f.attribution ~= a or f.id ~= o.id then f.choix, f.forcer = nil, false f.motif:SetText("") end
	f.attribution, f.id, f.lien = a, o.id, o.lien
	f.objetButin = (not o.etat) and o or nil
	Raid.PrioriserObjets({ o.id })
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
