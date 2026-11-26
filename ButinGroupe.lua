-- ButinGroupe.lua : en donjon, à chaque jet de butin de groupe, qui peut équiper l'objet, ce qu'il y gagne, et qui jette quoi
-- Activé dans les réglages, vue « Butin » (« Comparer le butin en donjon »). En groupe (pas en raid), chaque objet mis en
-- jeu a sa bande, accrochée à droite du cadre de jet du jeu (dé, cupidité, passer) et partie avec lui : une ligne par
-- membre qui peut le porter (sans cadre du jeu visible, la fenêtre « Opus : butin du groupe » prend le relais). Pour
-- chaque membre, s'il peut le porter (classe, niveau), ce qu'il porte à cet emplacement et l'écart de
-- niveau d'objet (l'inspection de RaidEquipement.lua), puis son choix (besoin, cupidité, passe) et son jet, lus dans
-- le journal du butin : rien n'est demandé aux autres, un membre sans Opus apparaît comme les autres.
local _, Opus = ...
local Raid = Opus.Raid

local GARDER = 20                   -- secondes d'affichage après le gagnant (dans la fenêtre)
local LARGE_BANDE = 372
local LARGEUR = 560
local HAUT_MEMBRE = 20
local TETE = 52                     -- la hauteur de l'objet et des en-têtes, au-dessus des membres
-- les colonnes
local PEUT, PORTE, CHANGE, CHOIX_X, JET = 124, 180, 270, 400, 474

local tirages = {}                  -- { rollID, id, lien, fin, choix = { [nom] = { quoi, jet } }, gagnant, finie }
local essai = false                 -- /opus raid jet : la fenêtre, seul et hors groupe
local masquee = false               -- fermée par le joueur : elle ne revient qu'au prochain jet

function Opus.ButinGroupeActif ()
	return Opus.db and Opus.db.butinGroupe == true and IsInGroup() and not IsInRaid()
end

------------------------------------------------------------------------
-- le journal du butin : les phrases du jeu, dans la langue du client
------------------------------------------------------------------------

-- une phrase du jeu (« %s a choisi Besoin pour : %s », « %1$s… ») en motif, et l'ordre de ses arguments
local function Motif (format)
	if type(format) ~= "string" then return nil end
	local ordre, n = {}, 0
	local p = format:gsub("%%(%d)%$([sd])", function (pos, t) n = n + 1 ordre[n] = tonumber(pos) return "\1" .. t end)
	p = p:gsub("%%([sd])", function (t) n = n + 1 ordre[n] = n return "\1" .. t end)
	p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
	p = p:gsub("\1s", "(.+)"):gsub("\1d", "(%%d+)")
	return "^" .. p .. "$", ordre
end

-- chaque phrase : ce qu'elle dit, et où sont le nom, l'objet et le jet (nil : c'est moi)
local PHRASES = {
	{ "LOOT_ROLL_NEED", "besoin", nom = 1, objet = 2 },
	{ "LOOT_ROLL_GREED", "cupidité", nom = 1, objet = 2 },
	{ "LOOT_ROLL_DISENCHANT", "désenchanter", nom = 1, objet = 2 },
	{ "LOOT_ROLL_PASSED", "passe", nom = 1, objet = 2 },
	{ "LOOT_ROLL_PASSED_AUTO", "passe", nom = 1, objet = 2 },
	{ "LOOT_ROLL_PASSED_AUTO_FEMALE", "passe", nom = 1, objet = 2 },
	{ "LOOT_ROLL_NEED_SELF", "besoin", objet = 1 },
	{ "LOOT_ROLL_GREED_SELF", "cupidité", objet = 1 },
	{ "LOOT_ROLL_DISENCHANT_SELF", "désenchanter", objet = 1 },
	{ "LOOT_ROLL_PASSED_SELF", "passe", objet = 1 },
	{ "LOOT_ROLL_PASSED_SELF_AUTO", "passe", objet = 1 },
	{ "LOOT_ROLL_ROLLED_NEED", "jet", jet = 1, objet = 2, nom = 3 },
	{ "LOOT_ROLL_ROLLED_GREED", "jet", jet = 1, objet = 2, nom = 3 },
	{ "LOOT_ROLL_ROLLED_DE", "jet", jet = 1, objet = 2, nom = 3 },
	{ "LOOT_ROLL_WON", "gagne", nom = 1, objet = 2 },
	{ "LOOT_ROLL_YOU_WON", "gagne", objet = 1 },
	{ "LOOT_ROLL_ALL_PASSED", "personne", objet = 1 },
}
local motifs
local function Motifs ()
	if motifs then return motifs end
	motifs = {}
	for _, p in ipairs(PHRASES) do
		local m, ordre = Motif(_G[p[1]])
		if m then motifs[#motifs + 1] = { motif = m, ordre = ordre, phrase = p } end
	end
	-- les plus longues d'abord : « … (automatiquement) » avant la phrase courte qu'elle contient
	table.sort(motifs, function (a, b) return #a.motif > #b.motif end)
	return motifs
end

-- une ligne du journal : { quoi, nom, id, jet } ou nil
local function Lire (message)
	for _, m in ipairs(Motifs()) do
		local captures = { message:match(m.motif) }
		if #captures > 0 then
			local args = {}
			for i, v in ipairs(captures) do args[m.ordre[i]] = v end
			local p = m.phrase
			local objet = args[p.objet] or ""
			return {
				quoi = p[2],
				nom = p.nom and Raid.Court(args[p.nom]) or Raid.MonNom(),
				id = tonumber(objet:match("item:(%d+)")),
				jet = p.jet and tonumber(args[p.jet]) or nil,
			}
		end
	end
end

------------------------------------------------------------------------
-- les membres du groupe, et ce que l'objet vaut pour chacun
------------------------------------------------------------------------

local function Membres ()
	local m = { { unite = "player", nom = Raid.MonNom() } }
	for k = 1, GetNumSubgroupMembers() do
		local u = "party" .. k
		local nom = Raid.Court(GetUnitName(u, true))
		if nom then m[#m + 1] = { unite = u, nom = nom } end
	end
	return m
end

local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local Info = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- « oui », « non », « niv. 45 » (bientôt), ou nil si l'objet ne s'équipe pas
local function Peut (unite, id)
	local _, _, _, emplacement, _, classID, sousClasse = Instant(id)
	if not Raid.CasesDe(id) then return nil end
	local _, classe = UnitClass(unite)
	local niveau = UnitLevel(unite) or 0
	if not classe or not Opus.Portable(classe, niveau, classID, sousClasse, emplacement) then return "non" end
	local minNiveau = select(5, Info(id)) or 0
	if minNiveau > niveau then return "niv. " .. minNiveau end
	return "oui"
end

Opus.PeutPorter = Peut              -- la fiche de décision, pour les objets hors liste

------------------------------------------------------------------------
-- la fenêtre
------------------------------------------------------------------------

local f, blocs = nil, {}

local function Construire ()
	f = Raid.Cadre("OpusButinGroupe")
	f:SetWidth(LARGEUR) f:SetPoint("LEFT", UIParent, "CENTER", 140, 60) f:SetFrameStrata("DIALOG")
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("Opus : butin du groupe")
	-- fermée (croix, Échap) : elle attend le prochain jet au lieu de revenir à chaque seconde
	tinsert(UISpecialFrames, "OpusButinGroupe")
	f:SetScript("OnHide", function () masquee = #tirages > 0 end)
	f:Hide()
end

local CHOIX = {
	besoin = "|cff40ff40Besoin|r", ["cupidité"] = "|cffffd100Cupidité|r", ["désenchanter"] = "|cffc080ffDésenchanter|r",
	passe = "|cff808080Passe|r",
}

local function Membre (b, k)
	if b.membres[k] then return b.membres[k] end
	local m = CreateFrame("Button", nil, b)
	m:SetSize(LARGEUR - 40, HAUT_MEMBRE)
	m.survol = m:CreateTexture(nil, "HIGHLIGHT") m.survol:SetAllPoints() m.survol:SetColorTexture(1, 1, 1, 0.05)
	-- au survol : ce qu'il porte, et ce que l'objet lui changerait, caractéristique par caractéristique
	m:SetScript("OnEnter", function (self)
		local t = self.tirage
		if not t then return end
		Raid.Ancrer(self)
		GameTooltip:AddLine(self.nomMembre, 1, 1, 1)
		if self.portable == "non" then GameTooltip:AddLine("Ne peut pas porter cet objet.", 0.6, 0.6, 0.6)
		else Raid.InfobulleEquipement(self.nomMembre, t.id, t.lien, self.classeNom) end
		GameTooltip:Show()
	end)
	m:SetScript("OnLeave", GameTooltip_Hide)
	m:SetPoint("TOPLEFT", 0, -TETE - (k - 1) * HAUT_MEMBRE)
	m.nom = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.nom:SetPoint("LEFT", 4, 0) m.nom:SetWidth(118) m.nom:SetJustifyH("LEFT") m.nom:SetWordWrap(false)
	m.peut = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.peut:SetPoint("LEFT", PEUT, 0) m.peut:SetWidth(52) m.peut:SetJustifyH("LEFT")
	m.portes = {}
	for i = 1, 2 do
		local icone = Raid.Icone(m, 16)
		icone:SetPoint("LEFT", PORTE + (i - 1) * 18, 0)
		icone.vide = icone:CreateTexture(nil, "BACKGROUND") icone.vide:SetAllPoints() icone.vide:SetColorTexture(0, 0, 0, 0.45)
		m.portes[i] = icone
	end
	m.verdict = Raid.Verdict(m)
	m.change = Raid.Pastilles(m, 2)
	m.change:SetPoint("LEFT", CHANGE, 0)
	m.choix = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.choix:SetPoint("LEFT", CHOIX_X, 0) m.choix:SetWidth(72) m.choix:SetJustifyH("LEFT")
	m.jet = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.jet:SetPoint("LEFT", JET, 0) m.jet:SetWidth(36) m.jet:SetJustifyH("RIGHT")
	b.membres[k] = m
	return m
end

local function Bloc (k)
	if blocs[k] then return blocs[k] end
	local b = CreateFrame("Frame", nil, f.Inset)
	b:SetWidth(LARGEUR - 40)
	b.icone = Raid.Icone(b, 32)
	b.icone:SetPoint("TOPLEFT", 0, 0)
	b.objet = CreateFrame("Button", nil, b)
	b.objet:SetSize(LARGEUR - 90, 16) b.objet:SetPoint("TOPLEFT", 40, 0)
	b.objet.texte = b.objet:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.objet.texte:SetAllPoints() b.objet.texte:SetJustifyH("LEFT") b.objet.texte:SetWordWrap(false)
	b.objet:SetScript("OnEnter", function (self) Raid.Infobulle(self, self.lien, self.id) end)
	b.objet:SetScript("OnLeave", GameTooltip_Hide)
	b.etat = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.etat:SetPoint("TOPLEFT", 40, -18) b.etat:SetWidth(LARGEUR - 90) b.etat:SetJustifyH("LEFT")
	for _, t in ipairs({ { "membre", 4 }, { "équipe ?", PEUT }, { "porté", PORTE }, { "ce qui change", CHANGE }, { "choix", CHOIX_X }, { "jet", JET } }) do
		local e = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		e:SetPoint("TOPLEFT", t[2], -38) e:SetText(t[1])
	end
	b.membres = {}
	blocs[k] = b
	return b
end

------------------------------------------------------------------------
-- la bande, accrochée au cadre de jet du jeu
------------------------------------------------------------------------

-- le cadre de jet du jeu pour ce tirage, s'il est affiché
local function CadreDeJet (rollID)
	for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
		local c = _G["GroupLootFrame" .. i]
		if c and c:IsShown() and c.rollID == rollID then return c end
	end
end

local bandes = {}                   -- [cadre de jet du jeu] = bande

local COURT = { besoin = "|cff40ff40Besoin|r", ["cupidité"] = "|cffffd100Cupidité|r", ["désenchanter"] = "|cffc080ffDés.|r", passe = "|cff808080Passe|r" }

local function LigneBande (b, k)
	if b.lignes[k] then return b.lignes[k] end
	local m = CreateFrame("Button", nil, b)
	m:SetSize(LARGE_BANDE - 12, HAUT_MEMBRE)
	m:SetPoint("TOPLEFT", 6, -6 - (k - 1) * HAUT_MEMBRE)
	m.survol = m:CreateTexture(nil, "HIGHLIGHT") m.survol:SetAllPoints() m.survol:SetColorTexture(1, 1, 1, 0.05)
	m:SetScript("OnEnter", function (self)
		local t = self.tirage
		if not t then return end
		Raid.Ancrer(self)
		GameTooltip:AddLine(self.nomMembre, 1, 1, 1)
		if self.portable == "non" then GameTooltip:AddLine("Ne peut pas porter cet objet.", 0.6, 0.6, 0.6)
		elseif self.portable then Raid.InfobulleEquipement(self.nomMembre, t.id, t.lien, self.classeNom) end
		GameTooltip:Show()
	end)
	m:SetScript("OnLeave", GameTooltip_Hide)
	m.nom = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.nom:SetPoint("LEFT", 2, 0) m.nom:SetWidth(108) m.nom:SetJustifyH("LEFT") m.nom:SetWordWrap(false)
	m.verdict = Raid.Verdict(m)
	m.verdict:SetPoint("LEFT", 112, 0)
	m.niveau = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.niveau:SetPoint("LEFT", 112, 0)
	m.change = Raid.Pastilles(m, 2)
	m.change:SetPoint("LEFT", 162, 0)
	m.choix = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.choix:SetPoint("LEFT", 286, 0) m.choix:SetWidth(52) m.choix:SetJustifyH("LEFT")
	m.jet = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.jet:SetPoint("LEFT", 334, 0) m.jet:SetWidth(24) m.jet:SetJustifyH("RIGHT")
	b.lignes[k] = m
	return m
end

local function BandeDe (cadre)
	if bandes[cadre] then return bandes[cadre] end
	-- enfant du cadre du jeu : même étage d'affichage que lui (un sac ouvert passe devant les deux), et partie avec lui
	local b = CreateFrame("Frame", nil, cadre, "BackdropTemplate")
	if b.SetBackdrop then
		b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		b:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		b:SetBackdropBorderColor(0.83, 0.69, 0.22, 0.8)
	end
	b:SetWidth(LARGE_BANDE)
	b:SetPoint("TOPLEFT", cadre, "TOPRIGHT", 4, 0)
	b.lignes = {}
	-- le cadre du jeu s'en va (jet fini, objet ramassé) : la bande avec lui
	cadre:HookScript("OnHide", function () b:Hide() end)
	bandes[cadre] = b
	return b
end

-- Les lignes d'un tirage : ceux qui peuvent le porter (ou bientôt), puis ceux qui ne peuvent pas mais ont fait un
-- choix (un « Besoin » se remarque) ; pour un objet qui ne s'équipe pas, ceux qui ont choisi.
local function LignesDuTirage (t, membres)
	local lignes = {}
	for i, mb in ipairs(membres) do
		local peut = Peut(mb.unite, t.id)
		local choix = t.choix[mb.nom]
		if peut == "oui" or (peut and peut ~= "non") or (choix and choix.quoi) then
			lignes[#lignes + 1] = { mb = mb, peut = peut, i = i }
		end
	end
	table.sort(lignes, function (a, z)
		local pa = a.peut == "oui" and 0 or (a.peut and a.peut ~= "non") and 1 or 2
		local pz = z.peut == "oui" and 0 or (z.peut and z.peut ~= "non") and 1 or 2
		if pa ~= pz then return pa < pz end
		return a.i < z.i
	end)
	return lignes
end

local function PoserBande (t, cadre, membres)
	local b = BandeDe(cadre)
	for _, m in ipairs(b.lignes) do m:Hide() end
	local lignes = LignesDuTirage(t, membres)
	if #lignes == 0 then b:Hide() return end
	for k, o in ipairs(lignes) do
		local mb, peut = o.mb, o.peut
		local m = LigneBande(b, k)
		local _, classe = UnitClass(mb.unite)
		m.tirage, m.nomMembre, m.portable, m.classeNom = t, mb.nom, peut, classe
		m.nom:SetText(Opus.Couleur(classe) .. mb.nom .. "|r")
		m:SetAlpha(peut == "oui" and 1 or 0.55)
		local eq = peut == "oui" and Raid.Comparer(mb.nom, t.id) or nil
		m.niveau:SetText(peut and peut ~= "oui" and peut ~= "non" and ("|cffff8040" .. peut .. "|r") or (peut == "non" and Opus.Gris("ne peut pas")) or "")
		if eq then Raid.PoserVerdict(m.verdict, eq, t.id, t.lien, classe) else m.verdict:Hide() end
		Raid.PoserPastilles(m.change, eq, t.id, t.lien)
		local c = t.choix[mb.nom]
		m.choix:SetText(c and c.quoi and COURT[c.quoi] or Opus.Gris("…"))
		m.jet:SetText(c and c.jet and ("|cffffffff" .. c.jet .. "|r") or "")
		m:Show()
	end
	b:SetHeight(12 + #lignes * HAUT_MEMBRE)
	b:Show()
end

function Opus.RafraichirButinGroupe ()
	-- les tirages finis depuis un moment s'en vont
	local garde = {}
	for _, t in ipairs(tirages) do
		-- sans gagnant lu dans le journal, le tirage se termine avec son temps
		if not t.finie and GetTime() > t.fin + 5 then t.finie = GetTime() end
		if not t.finie or GetTime() - t.finie < GARDER then garde[#garde + 1] = t end
	end
	tirages = garde
	if #tirages == 0 then essai, masquee = false, false end
	if #tirages == 0 or not (Opus.ButinGroupeActif() or essai) then
		if f then f:Hide() end
		for _, b in pairs(bandes) do b:Hide() end
		return
	end
	local membres = Membres()
	-- chaque tirage dont le cadre de jet du jeu est affiché : sa bande ; les autres, dans la fenêtre
	local enFenetre = {}
	for _, t in ipairs(tirages) do
		local cadre = t.rollID and t.rollID > 0 and CadreDeJet(t.rollID)
		if cadre then t.aEuCadre = true PoserBande(t, cadre, membres)
		elseif not t.aEuCadre and GetTime() - (t.debut or 0) > 1 then enFenetre[#enFenetre + 1] = t end
	end
	-- avec le volet (Volet.lua), les jets s'y suivent : plus de fenêtre de secours
	if Opus.db and not (Opus.db.volet and Opus.db.volet.ancien) then enFenetre = {} end
	if #enFenetre == 0 then
		if f then f:Hide() end
		return
	end
	if not f then Construire() end
	if masquee then return end
	-- tout est joué : la fenêtre s'efface d'elle-même (le résultat reste lisible quelques secondes)
	local enCours = false
	for _, t in ipairs(enFenetre) do if not t.finie then enCours = true end end
	if not enCours and not f:IsShown() then return end
	for _, b in ipairs(blocs) do b:Hide() end
	local y = 10
	for k, t in ipairs(enFenetre) do
		if k > 4 then break end
		local b = Bloc(k)
		t.lien = Raid.LienAJour(t.lien, t.id)
		b.objet.texte:SetText(t.lien)
		b.objet.lien, b.objet.id = t.lien, t.id
		Raid.PoserIcone(b.icone, t.id, t.lien)
		local reste = math.max(0, math.floor((t.fin or 0) - GetTime()))
		local niveau = select(4, Info(t.id))
		b.etat:SetText((niveau and ("niv. d'objet " .. niveau .. " · ") or "")
			.. (t.gagnant and ("gagné par " .. Opus.Blanc(t.gagnant)) or t.finie and "tout le monde a passé" or ("jets encore " .. reste .. " s")))
		for _, m in ipairs(b.membres) do m:Hide() end
		-- ceux qui peuvent l'équiper d'abord ; les autres en bas, estompés
		local ordre = {}
		for i, mb in ipairs(membres) do ordre[i] = { mb = mb, peut = Peut(mb.unite, t.id), i = i } end
		table.sort(ordre, function (a, b2)
			local pa, pb = a.peut == "oui" and 0 or 1, b2.peut == "oui" and 0 or 1
			if pa ~= pb then return pa < pb end
			return a.i < b2.i
		end)
		for i, o in ipairs(ordre) do
			local mb, peut = o.mb, o.peut
			local m = Membre(b, i)
			local _, classe = UnitClass(mb.unite)
			m.nom:SetText((mb.nom == t.gagnant and "|cffffd100» |r" or "") .. Opus.Couleur(classe) .. mb.nom .. "|r")
			m.tirage, m.nomMembre, m.portable = t, mb.nom, peut
			m:SetAlpha((peut == "oui" or peut == nil) and 1 or 0.45)
			m.peut:SetText(peut == "oui" and "|cff40ff40peut|r" or peut == "non" and Opus.Gris("non") or peut and ("|cffff8040" .. peut .. "|r") or Opus.Gris("—"))
			local eq = peut and peut ~= "non" and Raid.Comparer(mb.nom, t.id) or nil
			for j, icone in ipairs(m.portes) do
				local c = eq and eq.cases and eq.cases[j]
				if c and c.id then Raid.PoserIcone(icone, c.id, c.lien) icone.image:Show() icone.vide:Hide() icone:Show()
				elseif c then icone.id, icone.lien = nil, nil icone.image:Hide() icone.vide:Show() icone:Show()
				else icone:Hide() end
			end
			m.verdict:ClearAllPoints()
			m.verdict:SetPoint("LEFT", PORTE + (eq and eq.cases and #eq.cases or 0) * 18 + 2, 0)
			Raid.PoserVerdict(m.verdict, eq, t.id, t.lien, classe)
			m.classeNom = classe
			Raid.PoserPastilles(m.change, eq, t.id, t.lien)
			local c = t.choix[mb.nom]
			m.choix:SetText(c and c.quoi and CHOIX[c.quoi] or Opus.Gris(t.finie and "—" or "…"))
			m.jet:SetText(c and c.jet and ((mb.nom == t.gagnant and "|cffffd100" or "|cffffffff") .. c.jet .. "|r") or "")
			m:Show()
		end
		b:ClearAllPoints() b:SetPoint("TOPLEFT", 12, -y)
		b:SetHeight(TETE + #membres * HAUT_MEMBRE)
		b:Show()
		y = y + TETE + #membres * HAUT_MEMBRE + 12
	end
	f:SetHeight(y + 30)
	f:Show()
end

------------------------------------------------------------------------
-- les événements
------------------------------------------------------------------------

-- Les jets se suivent en groupe (pas en raid), même sans la comparaison : le volet les montre. La bande accrochée au
-- cadre de jet du jeu, elle, reste réservée au réglage « Comparer le butin en donjon ».
local function Suivre () return Opus.ButinGroupeActif() or (IsInGroup() and not IsInRaid()) end

Raid.Ecoute("START_LOOT_ROLL", function (rollID, duree)
	if not Suivre() then return end
	local lien = GetLootRollItemLink and GetLootRollItemLink(rollID)
	local id = lien and tonumber(lien:match("item:(%d+)"))
	if not id then return end
	tirages[#tirages + 1] = { rollID = rollID, id = id, lien = lien, fin = GetTime() + (duree or 60000) / 1000, choix = {}, debut = GetTime() }
	masquee = false
	-- le jeu affiche son cadre de jet dans le même instant : on repasse juste après pour s'y accrocher
	C_Timer.After(0.2, Opus.RafraichirButinGroupe)
	-- tout le groupe passe devant à l'inspection
	local noms = {}
	for _, m in ipairs(Membres()) do noms[#noms + 1] = m.nom end
	Raid.Prioriser(noms)
	Opus.RafraichirButinGroupe()
end)

-- le tirage auquel se rapporte une ligne : le plus ancien en cours pour cet objet, où ce membre n'a pas encore cette info
local function Tirage (l)
	for _, t in ipairs(tirages) do
		if t.id == l.id and not t.finie then
			local c = t.choix[l.nom]
			if l.quoi == "gagne" or l.quoi == "personne" or (l.quoi == "jet" and not (c and c.jet)) or (l.quoi ~= "jet" and not (c and c.quoi)) then return t end
		end
	end
end

Raid.Ecoute("CHAT_MSG_LOOT", function (message)
	if #tirages == 0 or type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then return end
	local l = Lire(message)
	if not l or not l.id then return end
	local t = Tirage(l)
	if not t then return end
	if l.quoi == "gagne" then t.gagnant, t.finie = l.nom, GetTime()
	elseif l.quoi == "personne" then t.finie = GetTime()
	else
		local c = t.choix[l.nom] or {}
		if l.quoi == "jet" then c.jet = l.jet else c.quoi = l.quoi end
		t.choix[l.nom] = c
	end
	Opus.RafraichirButinGroupe()
end)

C_Timer.NewTicker(1, function () if #tirages > 0 then Opus.RafraichirButinGroupe() end end)

-- pour essayer sans attendre un objet, même seul
Raid.Commande("jet", "jet <itemID>", "essayer la fenêtre du butin de groupe (donjon) sur un objet", function (texte)
	local id = tonumber((texte or ""):match("%d+"))
	if not id then Raid.Msg("/opus raid jet <itemID> (le numéro de l'objet, par exemple sur wowhead).") return end
	essai, masquee = true, false
	tirages[#tirages + 1] = { rollID = -1, id = id, lien = Raid.LienDe(id), fin = GetTime() + 60, choix = {}, debut = GetTime() - 2 }
	Raid.Prioriser((function () local n = {} for _, m in ipairs(Membres()) do n[#n + 1] = m.nom end return n end)())
	Opus.RafraichirButinGroupe()
end)
Opus.ButinGroupeLire = Lire

-- pour le volet (Volet.lua) : les jets en cours et récents, les membres, et un jet d'essai
Opus.ButinGroupeTirages = function () return tirages end
Opus.ButinGroupeMembres = Membres
function Opus.ButinGroupeEssai (id, duree)
	local t = { rollID = -1, id = id, lien = Raid.LienDe(id), fin = GetTime() + duree, choix = {}, debut = GetTime() }
	tirages[#tirages + 1] = t
	return t
end
