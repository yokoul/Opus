-- ButinGroupe.lua : en donjon, à chaque jet de butin de groupe, qui peut équiper l'objet, ce qu'il y gagne, et qui jette quoi
-- Activé dans les réglages, vue « Butin » (« Comparer le butin en donjon »). En groupe (pas en raid), chaque objet mis en
-- jeu a sa bande, accrochée sous le cadre de jet du jeu (dé, cupidité, passer) et partie avec lui : une ligne qui
-- compte les choix puis nomme le gagnant, et au clic la liste des membres (sans cadre du jeu visible, la fenêtre
-- « Opus : butin du groupe » prend le relais). Pour
-- chaque membre, s'il peut le porter (classe, niveau), ce qu'il porte à cet emplacement et l'écart de
-- niveau d'objet (l'inspection de RaidEquipement.lua), puis son choix (besoin, cupidité, passe) et son jet, lus dans
-- le journal du butin : rien n'est demandé aux autres, un membre sans Opus apparaît comme les autres.
local _, Opus = ...
local Raid = Opus.Raid

local GARDER = 20                   -- secondes d'affichage après le gagnant (dans la fenêtre)
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
		local format = _G[p[1]]
		local m, ordre = Motif(format)
		-- les clients récents ouvrent la phrase sur un lien « [Butin] : » qui porte un numéro
		-- (|HlootHistory:%d|h) : les arguments qu'on attend viennent un cran plus loin
		local decale = type(format) == "string" and format:find("|HlootHistory:", 1, true) and 1 or 0
		if m then motifs[#motifs + 1] = { motif = m, ordre = ordre, phrase = p, decale = decale } end
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
			local p, d = m.phrase, m.decale
			local objet = args[p.objet + d] or ""
			return {
				quoi = p[2],
				nom = p.nom and Raid.Court(args[p.nom + d]) or Raid.MonNom(),
				id = tonumber(objet:match("item:(%d+)")),
				jet = p.jet and tonumber(args[p.jet + d]) or nil,
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
-- la bande, accrochée au cadre de jet du jeu : une ligne (« 2 besoin, 1 cupidité », puis « ✓ Seliane 87 »), la liste
-- de qui jette quoi au clic. Sous le cadre s'il y a la place, sinon à sa droite (les cadres du jeu s'empilent).
------------------------------------------------------------------------

local LIGNE, RANG = 20, 16              -- la ligne de résumé, une ligne de la liste
local ICONE = {
	besoin = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", ["cupidité"] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
	["désenchanter"] = "Interface\\Buttons\\UI-GroupLoot-DE-Up", passe = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}
local COCHE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local function Icone (quoi, taille) return "|T" .. ICONE[quoi] .. ":" .. (taille or 14) .. "|t" end

local faux = {}                     -- les cadres de jet imités des essais, [tirage] = cadre

-- un cadre de jet imité pour les essais (sans groupe, le jeu n'en montre pas) : l'objet et son nom
local function CadreFaux (t)
	if faux[t] then return faux[t] end
	local c = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	c:SetSize(244, 52)
	if c.SetBackdrop then
		c:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		c:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		c:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
	end
	c.icone = Raid.Icone(c, 36) c.icone:SetPoint("LEFT", 8, 0)
	c.nom = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	c.nom:SetPoint("TOPLEFT", 50, -10) c.nom:SetPoint("RIGHT", -8, 0) c.nom:SetJustifyH("LEFT") c.nom:SetWordWrap(false)
	c.sous = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.sous:SetPoint("TOPLEFT", 50, -28) c.sous:SetText("essai (le cadre de jet du jeu)")
	-- ils s'empilent vers le haut, comme ceux du jeu
	local n = 0
	for _ in pairs(faux) do n = n + 1 end
	c:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220 + n * 56)
	faux[t] = c
	return c
end

local function Cadres ()
	local l = {}
	for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
		local c = _G["GroupLootFrame" .. i]
		if c and c:IsShown() then l[#l + 1] = c end
	end
	for _, c in pairs(faux) do if c:IsShown() then l[#l + 1] = c end end
	return l
end

-- le cadre de jet pour ce tirage, s'il est affiché
local function CadreDeJet (t)
	if faux[t] then return faux[t]:IsShown() and faux[t] or nil end
	for _, c in ipairs(Cadres()) do if c.rollID == t.rollID then return c end end
end

-- la place sous ce cadre est-elle libre d'un autre cadre de jet, sur cette hauteur ?
local function LibreDessous (cadre, hauteur)
	local s = cadre:GetEffectiveScale()
	local g, d, b = (cadre:GetLeft() or 0) * s, (cadre:GetRight() or 0) * s, (cadre:GetBottom() or 0) * s
	for _, o in ipairs(Cadres()) do
		if o ~= cadre and o:GetLeft() then
			local so = o:GetEffectiveScale()
			local og, od, ob, oh = o:GetLeft() * so, o:GetRight() * so, o:GetBottom() * so, o:GetTop() * so
			if og < d and od > g and oh > b - hauteur * s and ob < b then return false end
		end
	end
	return true
end

local bandes = {}                   -- [tirage] = bande

local function Rang (b, k)
	if b.rangs[k] then return b.rangs[k] end
	local m = CreateFrame("Button", nil, b)
	m:SetHeight(RANG)
	m:SetPoint("TOPLEFT", 4, -LIGNE - 2 - (k - 1) * RANG) m:SetPoint("TOPRIGHT", -4, -LIGNE - 2 - (k - 1) * RANG)
	m.fond = m:CreateTexture(nil, "BACKGROUND") m.fond:SetAllPoints() m.fond:SetColorTexture(1, 0.82, 0, 0.12)
	m.survol = m:CreateTexture(nil, "HIGHLIGHT") m.survol:SetAllPoints() m.survol:SetColorTexture(1, 1, 1, 0.05)
	-- au survol : ce qu'il porte, et ce que l'objet lui changerait
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
	m.choix = m:CreateTexture(nil, "ARTWORK") m.choix:SetSize(14, 14) m.choix:SetPoint("LEFT", 2, 0)
	m.jet = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.jet:SetPoint("LEFT", 18, 0) m.jet:SetWidth(22) m.jet:SetJustifyH("RIGHT")
	m.nom = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.nom:SetPoint("LEFT", 46, 0) m.nom:SetPoint("RIGHT", -52, 0) m.nom:SetJustifyH("LEFT") m.nom:SetWordWrap(false)
	m.verdict = Raid.Verdict(m)
	m.verdict:SetPoint("RIGHT", 0, 0)
	m.note = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	m.note:SetPoint("RIGHT", -2, 0) m.note:SetJustifyH("RIGHT")
	b.rangs[k] = m
	return m
end

local accroches = {}                -- les cadres de jet déjà suivis à leur fermeture

local function BandeDe (t)
	if bandes[t] then return bandes[t] end
	-- pas enfant du cadre de jet : le jeu le cache dès qu'on a choisi, la bande reste jusqu'au résultat
	local b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	if b.SetBackdrop then
		b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
		b:SetBackdropColor(0.04, 0.04, 0.06, 0.88)
		b:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8)
	end
	-- la ligne : un clic montre ou cache la liste (le choix est gardé)
	b.ligne = CreateFrame("Button", nil, b)
	b.ligne:SetPoint("TOPLEFT", 4, -2) b.ligne:SetPoint("TOPRIGHT", -4, -2) b.ligne:SetHeight(LIGNE - 2)
	b.ligne.survol = b.ligne:CreateTexture(nil, "HIGHLIGHT") b.ligne.survol:SetAllPoints() b.ligne.survol:SetColorTexture(1, 1, 1, 0.05)
	b.ligne.texte = b.ligne:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.ligne.texte:SetPoint("LEFT", 4, 0) b.ligne.texte:SetPoint("RIGHT", -20, 0) b.ligne.texte:SetJustifyH("LEFT") b.ligne.texte:SetWordWrap(false)
	b.ligne.plus = b.ligne:CreateTexture(nil, "ARTWORK") b.ligne.plus:SetSize(14, 14) b.ligne.plus:SetPoint("RIGHT", -2, 0)
	b.ligne:SetScript("OnClick", function ()
		Opus.db.butinGroupeListe = not Opus.db.butinGroupeListe
		Opus.RafraichirButinGroupe()
	end)
	b.ligne:SetScript("OnEnter", function (self)
		Raid.Ancrer(self)
		GameTooltip:AddLine(Opus.db.butinGroupeListe and "Clic : cacher la liste" or "Clic : qui jette quoi, et qui peut le porter", 1, 1, 1)
		GameTooltip:Show()
	end)
	b.ligne:SetScript("OnLeave", GameTooltip_Hide)
	b.rangs = {}
	bandes[t] = b
	return b
end

-- Qui figure dans la liste : ceux qui peuvent le porter (ou bientôt), et ceux qui ont fait un choix ; pour un objet qui
-- ne s'équipe pas, tout le groupe. Le gagnant d'abord, puis besoin, cupidité, en attente, passe ; le meilleur jet devant.
local RANG_CHOIX = { besoin = 0, ["cupidité"] = 1, ["désenchanter"] = 1, passe = 3 }
local function LignesDuTirage (t, membres)
	local lignes = {}
	for i, mb in ipairs(membres) do
		local peut = mb.unite and Peut(mb.unite, t.id)
		local c = t.choix[mb.nom]
		if peut ~= "non" or (c and c.quoi) then lignes[#lignes + 1] = { mb = mb, peut = peut, c = c, i = i } end
	end
	local function Cle (o)
		if o.mb.nom == t.gagnant then return -1 end
		return o.c and o.c.quoi and RANG_CHOIX[o.c.quoi] or 2
	end
	table.sort(lignes, function (a, z)
		local ka, kz = Cle(a), Cle(z)
		if ka ~= kz then return ka < kz end
		local ja, jz = a.c and a.c.jet or -1, z.c and z.c.jet or -1
		if ja ~= jz then return ja > jz end
		return a.i < z.i
	end)
	return lignes
end

-- la ligne de résumé : pendant les jets, les choix comptés ; ensuite, le gagnant
local function Resume (t, membres)
	if t.gagnant then
		local c = t.choix[t.gagnant]
		local _, classe = UnitClass(t.gagnant == Raid.MonNom() and "player" or t.gagnant)
		return "|T" .. COCHE .. ":14|t " .. (c and c.quoi and ICONE[c.quoi] and (Icone(c.quoi) .. " ") or "")
			.. Opus.Couleur(classe) .. t.gagnant .. "|r" .. (c and c.jet and ("  |cffffd100" .. c.jet .. "|r") or "")
	end
	if t.finie then return Opus.Gris("Tout le monde a passé") end
	local n, attente = {}, 0
	for _, mb in ipairs(membres) do
		local c = t.choix[mb.nom]
		if c and c.quoi then n[c.quoi] = (n[c.quoi] or 0) + 1 else attente = attente + 1 end
	end
	local morceaux = {}
	for _, quoi in ipairs({ "besoin", "cupidité", "désenchanter", "passe" }) do
		if n[quoi] then morceaux[#morceaux + 1] = Icone(quoi) .. " " .. n[quoi] end
	end
	if attente > 0 then morceaux[#morceaux + 1] = Opus.Gris(attente .. " en attente") end
	return table.concat(morceaux, "   ")
end

local function PoserBande (t, cadre, membres)
	-- ceux que le journal a nommés sans être du groupe (un essai, un membre parti) comptent aussi
	local vus, tous = {}, {}
	for _, mb in ipairs(membres) do vus[mb.nom] = true tous[#tous + 1] = mb end
	for nom in pairs(t.choix) do if not vus[nom] then vus[nom] = true tous[#tous + 1] = { nom = nom } end end
	membres = tous
	local b = BandeDe(t)
	for _, m in ipairs(b.rangs) do m:Hide() end
	b.ligne.texte:SetText(Resume(t, membres))
	local liste = Opus.db.butinGroupeListe and LignesDuTirage(t, membres) or {}
	b.ligne.plus:SetTexture(Opus.db.butinGroupeListe and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
	for k, o in ipairs(liste) do
		local mb, peut, c = o.mb, o.peut, o.c
		local m = Rang(b, k)
		local _, classe = mb.unite and UnitClass(mb.unite)
		m.tirage, m.nomMembre, m.portable, m.classeNom = t, mb.nom, peut, classe
		m.fond:SetShown(mb.nom == t.gagnant)
		if c and c.quoi and ICONE[c.quoi] then m.choix:SetTexture(ICONE[c.quoi]) m.choix:Show() else m.choix:Hide() end
		m.jet:SetText(c and c.jet and ((mb.nom == t.gagnant and "|cffffd100" or "|cffffffff") .. c.jet .. "|r") or Opus.Gris(c and c.quoi and "" or "…"))
		m.nom:SetText(Opus.Couleur(classe) .. mb.nom .. "|r")
		m:SetAlpha((peut == "non" or (c and c.quoi == "passe")) and 0.5 or 1)
		-- à droite : ce que l'objet lui vaut (Pawn ou l'écart de niveau d'objet), ou pourquoi il ne peut pas le porter
		local eq = peut == "oui" and Raid.Comparer(mb.nom, t.id) or nil
		if eq then Raid.PoserVerdict(m.verdict, eq, t.id, t.lien, classe) m.note:SetText("")
		else
			m.verdict:Hide()
			m.note:SetText(peut == "non" and "ne peut pas" or (peut and peut ~= "oui") and ("|cffff8040" .. peut .. "|r") or "")
		end
		m:Show()
	end
	local hauteur = LIGNE + (#liste > 0 and (#liste * RANG + 6) or 2)
	b:SetHeight(hauteur)
	if cadre then
		-- sous le cadre, de sa largeur ; sinon (un autre cadre de jet dessous) à sa droite
		b:SetFrameStrata(cadre:GetFrameStrata()) b:SetFrameLevel(cadre:GetFrameLevel() + 5)
		b:ClearAllPoints()
		if LibreDessous(cadre, hauteur + 2) then
			b:SetPoint("TOPLEFT", cadre, "BOTTOMLEFT", 0, -2) b:SetPoint("TOPRIGHT", cadre, "BOTTOMRIGHT", 0, -2)
		else
			b:SetPoint("TOPLEFT", cadre, "TOPRIGHT", 4, 0) b:SetWidth(math.max(cadre:GetWidth() or 0, 240))
		end
		b.accrochee = true
		-- le jeu cache son cadre quand on a choisi (ou le réutilise) : la bande reste là, détachée
		if not accroches[cadre] then
			accroches[cadre] = true
			cadre:HookScript("OnHide", function () C_Timer.After(0, Opus.RafraichirButinGroupe) end)
		end
	elseif b.accrochee and b:GetLeft() then
		local g, h, l = b:GetLeft(), b:GetTop(), b:GetWidth()
		b:ClearAllPoints() b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g, h) b:SetWidth(l)
		b.accrochee = false
	end
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
	local restent = {}
	for _, g in ipairs(garde) do restent[g] = true end
	for t, c in pairs(faux) do if not restent[t] then c:Hide() faux[t] = nil end end
	for t, b in pairs(bandes) do if not restent[t] then b:Hide() bandes[t] = nil end end
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
		local f2 = faux[t]
		if f2 then
			-- le cadre imité d'un essai : l'objet ; comme celui du jeu, il s'en va quand on a choisi
			t.lien = Raid.LienAJour(t.lien, t.id)
			Raid.PoserIcone(f2.icone, t.id, t.lien) f2.nom:SetText(t.lien)
			local mien = t.choix[Raid.MonNom()]
			f2:SetShown(not (t.finie or (mien and mien.quoi)))
		end
		local cadre = (t.rollID > 0 or f2) and CadreDeJet(t)
		if cadre then t.aEuCadre = true end
		-- la bande vit du début du jet jusqu'à quelques secondes après le résultat, cadre du jeu ou pas
		if t.aEuCadre then
			if t.finie and GetTime() - t.finie > 8 then
				if bandes[t] then bandes[t]:Hide() end
			else PoserBande(t, cadre, membres) end
		elseif GetTime() - (t.debut or 0) > 1 then enFenetre[#enFenetre + 1] = t end
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

-- Les jets ne se suivent qu'avec le réglage « Comparer le butin en donjon » (éteint par défaut) : sans lui, Opus ne
-- montre rien en donjon, ni bande, ni languette, ni banderole.
local function Suivre () return Opus.ButinGroupeActif() end

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
	local t = { rollID = -1, id = id, lien = Raid.LienDe(id), fin = GetTime() + 60, choix = {}, debut = GetTime() - 2 }
	tirages[#tirages + 1] = t
	CadreFaux(t)
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
	-- la bande s'essaie sur un cadre de jet imité, même sans le réglage
	essai = true
	CadreFaux(t)
	return t
end
