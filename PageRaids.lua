-- PageRaids.lua : l'onglet « Raids », en trois vues.
--   Ce soir     la soirée de guilde (l'ouvrir, la fermer, son état), l'instantané du site, les annonces du soir et le
--               rapport à rendre au site ;
--   Ma liste    mes listes de souhaits (rangs, objets déjà reçus), mes compteurs et ma place au Suicide King ;
--   Historique  les soirées validées des paliers en cours et ce que chaque objet est devenu.
-- Ma liste et l'historique viennent du site, par le bridge (OpusBridgeFeed.raids, écrit à la connexion) ; à défaut,
-- ma liste est lue dans l'instantané importé. Les fenêtres du raid (butin, attributions, décision) restent à part :
-- elles surgissent en pleine soirée.
local _, Opus = ...
local Raid = Opus.Raid

local MAX_ANNONCES = 8              -- annonces montrées ici ; /opus raid objections pour toutes
local VUE_MAX = 480                 -- hauteur visible de Ma liste et de l'historique ; au-delà, la molette
local JOURS = { "dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam." }
local QUALITES = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

local vue = "soir"
local VUES = { { "soir", "Ce soir" }, { "liste", "Ma liste" }, { "historique", "Historique" } }
local defile = 0

local function Pluriel (n, mot) return n .. " " .. mot .. (n > 1 and "s" or "") end
local function Jour (t) local d = date("*t", t) return ("%s %d/%d"):format(JOURS[d.wday], d.day, d.month) end

------------------------------------------------------------------------
-- le flux du site (bridge)
------------------------------------------------------------------------

-- le bloc raids écrit par le bridge, et quand le site l'a produit ; nil sans bridge
function Raid.Flux ()
	local f = OpusBridgeFeed
	if type(f) ~= "table" or type(f.raids) ~= "table" or type(f.raids.paliers) ~= "table" then return nil end
	return f.raids, tonumber(f.raids.maj)
end

-- le lien d'un objet du flux : celui du jeu s'il est en cache, sinon son nom à la couleur de sa qualité
local function Lien (o)
	local _, lien = GetItemInfo(o.id)
	if lien then return lien end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, o.id) end
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[QUALITES[o.qualite or ""] or 1]
	local nom = "[" .. ((o.nom and o.nom ~= "") and o.nom or ("objet " .. o.id)) .. "]"
	return q and (q.hex .. nom .. "|r") or nom
end

-- sans bloc raids : le bridge manque, ou il est d'une version qui ne l'écrit pas encore
local function SansFlux (quoi)
	if type(OpusBridgeFeed) == "table" then
		return Opus.Gris(quoi .. " arrive" .. (quoi:find(" et ") and "nt" or "") .. " avec la dernière version du bridge : il se met à jour tout seul, puis reconnecte-toi.")
	end
	return Opus.Gris(quoi .. " arrive" .. (quoi:find(" et ") and "nt" or "") .. " ici avec le bridge : installe-le depuis opus-guild.eu/bridge (une ligne à coller), puis reconnecte-toi.")
end

local function Moi (nom) return nom and Raid.MonNom() and nom:lower() == Raid.MonNom():lower() end

local function Dernier (n)
	n = tonumber(n) or -1
	if n < 0 then return "jamais servi" end
	if n == 0 then return "servi à sa dernière soirée" end
	return "servi il y a " .. Pluriel(n, "soirée")
end

------------------------------------------------------------------------
-- Ma liste
------------------------------------------------------------------------

-- le texte de la vue : mes listes, celle du perso joué d'abord
local function TexteListe ()
	local flux = Raid.Flux()
	local lignes = {}
	local function L (t) lignes[#lignes + 1] = t or " " end
	if flux then
		for _, p in ipairs(flux.paliers) do
			local listes = {}
			for _, l in ipairs(type(p.listes) == "table" and p.listes or {}) do
				if Moi(l.perso) then table.insert(listes, 1, l) else listes[#listes + 1] = l end
			end
			if #listes > 0 then
				L(Opus.Normal(p.code .. " · " .. (p.nom or "")))
				for _, l in ipairs(listes) do
					local recus = 0
					for _, o in ipairs(l.objets or {}) do if o.recu then recus = recus + 1 end end
					L(Opus.Blanc(l.perso) .. Opus.Gris(" · liste " .. (l.statut or "?") .. (l.role and l.role ~= "" and (", " .. l.role) or "")
						.. " · " .. #(l.objets or {}) .. " objets, " .. recus .. " reçu" .. (recus > 1 and "s" or "")))
					L(Opus.Gris(("%s · %s · %s · Suicide King : %s"):format(Pluriel(tonumber(l.presences) or 0, "soirée"),
						Pluriel(tonumber(l.perdues) or 0, "prio perdue"), Dernier(l.dernier),
						(tonumber(l.sk) or 0) > 0 and (l.sk .. (l.sk == 1 and "er" or "e") .. " sur " .. l.skTotal) or "pas encore dans la liste")))
					for _, o in ipairs(l.objets or {}) do
						L("   " .. Opus.Normal(o.rang .. ".") .. " " .. Lien(o) .. (o.recu and Opus.Vert("  reçu le " .. Jour(o.recu)) or ""))
					end
					L()
				end
			end
		end
		if #lignes == 0 then L(Opus.Gris("Pas de liste sur le site pour les paliers en cours. Les listes se font sur opus-guild.eu, page Raids.")) end
		return table.concat(lignes, "\n")
	end
	-- sans bridge : ce que dit l'instantané importé (le maître du butin et son second)
	local i, moi = Raid.db.instantane, Raid.MonNom()
	if i and i.joueurs[moi] then
		local souhaits = {}
		for id, candidats in pairs(i.souhaits) do
			for _, c in ipairs(candidats) do if c.nom == moi then souhaits[#souhaits + 1] = { id = id, rang = c.rang } end end
		end
		table.sort(souhaits, function (a, b) return a.rang < b.rang end)
		L(Opus.Normal(i.tier ~= "" and i.tier or "Palier") .. Opus.Gris(" · d'après l'instantané importé"))
		for _, s in ipairs(souhaits) do L("   " .. Opus.Normal(s.rang .. ".") .. " " .. Raid.LienDe(s.id)) end
		local sk = (Raid.db.soiree and Raid.db.soiree.sk) or i.sk or {}
		for k, nom in ipairs(sk) do if nom == moi then L(Opus.Gris("Suicide King : rang " .. k .. " sur " .. #sk)) end end
		L()
	end
	L(SansFlux("Ta liste, tes soirées et l'historique des attributions"))
	return table.concat(lignes, "\n")
end

------------------------------------------------------------------------
-- Historique
------------------------------------------------------------------------

local function TexteHistorique ()
	local flux = Raid.Flux()
	if not flux then return SansFlux("L'historique des soirées") end
	local lignes = {}
	local function L (t) lignes[#lignes + 1] = t or " " end
	local moi = Raid.MonNom()
	for _, p in ipairs(flux.paliers) do
		local soirees = type(p.soirees) == "table" and p.soirees or {}
		if #soirees > 0 then
			L(Opus.Normal(p.code .. " · " .. (p.nom or "")) .. Opus.Gris(" · " .. Pluriel(#soirees, "soirée") .. " validée" .. (#soirees > 1 and "s" or "")))
			for _, s in ipairs(soirees) do
				local present = false
				for _, n in ipairs(s.presents or {}) do if Moi(n) then present = true end end
				L(Opus.Blanc(Jour(s.debut) .. date(" à %H:%M", s.debut)) .. Opus.Gris(" · " .. (s.ml or "?") .. " · " .. #(s.presents or {}) .. " présents")
					.. (present and Opus.Vert(" · tu y étais") or ""))
				local attributions = s.attributions or {}
				if #attributions == 0 then L(Opus.Gris("   aucun objet attribué")) end
				for _, a in ipairs(attributions) do
					local pour = (a.pour and a.pour ~= "") and (Moi(a.pour) and Opus.Vert(a.pour) or Opus.Blanc(a.pour)) or Opus.Gris("la guilde")
					L("   " .. Lien(a) .. "  " .. pour .. Opus.Gris(" · " .. (a.comment or "") .. (a.motif and (" : « " .. a.motif .. " »") or "")))
				end
				L()
			end
		end
	end
	if #lignes == 0 then return Opus.Gris("Aucune soirée validée pour les paliers en cours.") end
	return table.concat(lignes, "\n")
end

------------------------------------------------------------------------
-- Ce soir
------------------------------------------------------------------------

-- l'état de la soirée de guilde, en une ligne
local function EtatSoiree ()
	local o = Raid.db.ouverte
	local part, guilde, taille = Raid.PartGuilde()
	local compo = part and string.format(" · %d sur %d de la guilde", guilde, taille) or ""
	if not o then
		if not IsInGroup() then return Opus.Gris("Aucune soirée ouverte. Elle s'ouvre en raid, par le maître du butin ou un officier.") end
		if part and part < Raid.Seuil() then
			return Opus.Rouge(string.format("Pas un raid de guilde%s : il en faut %d %%.", compo, Raid.Seuil() * 100))
		end
		return "Raid de guilde" .. compo .. Opus.Gris(" · soirée pas encore ouverte : le butin ne bouge pas.")
	end
	local actif, raison = Raid.Actif()
	local debut = "Soirée de guilde ouverte à " .. date("%H:%M", o.debut) .. " par " .. Opus.Blanc(o.par or "?")
	return actif and (Opus.Vert(debut) .. compo) or (debut .. "\n" .. Opus.Rouge(raison))
end

-- l'instantané que le bridge a apporté (le palier le plus récent qui en a un), pour un officier du butin
local function InstantaneDuFlux ()
	local flux = Raid.Flux()
	if not flux or type(flux.instantanes) ~= "table" then return nil end
	for _, p in ipairs(flux.paliers) do
		local texte = flux.instantanes[p.code]
		if type(texte) == "string" and texte ~= "" then return texte, p.code end
	end
	return nil
end

local function RafraichirSoir (cadre)
	local i, gere = Raid.db.instantane, Raid.PeutGerer()

	cadre.soiree:SetText(EtatSoiree())
	cadre.ouvrir:SetShown(not Raid.db.ouverte)
	cadre.fermer:SetShown(Raid.db.ouverte ~= nil)
	cadre.ouvrir:SetEnabled(gere and IsInGroup())
	cadre.fermer:SetEnabled(gere)
	local aRemettre = #Raid.ARemettre()
	cadre.butin:SetEnabled(gere)
	cadre.remises:SetText(aRemettre > 0 and ("À remettre : " .. aRemettre) or "Rien à remettre")
	cadre.remises:SetEnabled(aRemettre > 0)

	if i then
		cadre.instantane:SetText(string.format("%s · palier %s · %s, %s · importé le %s par %s",
			Opus.Blanc(i.id), i.tier ~= "" and i.tier or "?", Pluriel(i.nJoueurs, "joueur"), Pluriel(i.nObjets, "objet"),
			date("%d/%m à %H:%M", i.importe or i.date), i.par or "?"))
	else
		cadre.instantane:SetText(Opus.Gris("Aucun instantané : un officier ou le maître du butin l'importe depuis le bridge, ou colle celui du site (page Raids, « Instantané »)."))
	end
	cadre.importer:SetEnabled(gere)
	local texte = InstantaneDuFlux()
	cadre.duBridge:SetEnabled(gere and texte ~= nil and not (i and texte:find(i.id, 1, true)))
	cadre.detail:SetEnabled(i ~= nil)

	local lignes = {}
	for k = math.max(1, #Raid.attributions - MAX_ANNONCES + 1), #Raid.attributions do
		local a = Raid.attributions[k]
		lignes[#lignes + 1] = a.lien .. "  " .. Opus.Gris(Raid.EtatAttribution(a))
	end
	if #Raid.attributions > MAX_ANNONCES then
		table.insert(lignes, 1, Opus.Gris(string.format("… et %d plus tôt (/opus raid objections)", #Raid.attributions - MAX_ANNONCES)))
	end
	cadre.annonces:SetText(#lignes > 0 and table.concat(lignes, "\n") or Opus.Gris("Aucune annonce ce soir. Les soirées passées sont dans l'historique."))

	local s = Raid.db.soiree
	local n = s and #s.evenements or 0
	cadre.rapport:SetText(n > 0 and string.format("Soirée du %s : %s noté%s.", date("%d/%m à %H:%M", s.debut), Pluriel(n, "événement"), n > 1 and "s" or "")
		or Opus.Gris("Rien à rendre au site pour l'instant."))
	cadre.exporter:SetEnabled(n > 0)

	-- les annonces poussent ce qui suit
	local y = cadre.yAnnonces - math.max(16, cadre.annonces:GetStringHeight()) - 18
	cadre.titreRapport:SetPoint("TOPLEFT", 4, y)
	cadre.rapport:SetPoint("TOPLEFT", 16, y - 26)
	cadre.exporter:SetPoint("TOPRIGHT", -8, y - 20)
	return -y + 60
end

local function ConstruireSoir (cadre, largeur)
	local function Section (texte, y)
		local s = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		s:SetPoint("TOPLEFT", 4, y) s:SetText(texte)
		return s
	end
	local function Texte (y, l)
		local t = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("TOPLEFT", 16, y) t:SetWidth(l or (largeur - 170)) t:SetJustifyH("LEFT") t:SetSpacing(3)
		return t
	end

	Section("Soirée de guilde", -4)
	cadre.soiree = Texte(-30)
	cadre.ouvrir = Opus.Bouton(cadre, "Ouvrir la soirée", 140, function () Raid.OuvrirSoiree() end)
	cadre.ouvrir:SetPoint("TOPRIGHT", -8, -24)
	Opus.Bulle(cadre.ouvrir, "Ouvrir la soirée de guilde", "En raid, par le maître du butin ou un officier. Refusé si moins de "
		.. "80 % du raid est de la guilde (/opus raid seuil). Sans soirée ouverte, l'addon ne touche pas au butin.")
	cadre.fermer = Opus.Bouton(cadre, "Fermer la soirée", 140, function () Raid.FermerSoiree() end)
	cadre.fermer:SetPoint("TOPRIGHT", -8, -24)
	cadre.butin = Opus.Bouton(cadre, "Fenêtre du butin", 140, function () Raid.MontrerButin() end)
	cadre.butin:SetPoint("TOPRIGHT", -8, -52)
	cadre.remises = Opus.Bouton(cadre, "Rien à remettre", 140, function () Raid.Executer("remises") end)
	cadre.remises:SetPoint("TOPRIGHT", -156, -52)

	Section("Instantané du site", -90)
	cadre.instantane = Texte(-116, largeur - 280)
	cadre.importer = Opus.Bouton(cadre, "Coller…", 80, function () Raid.OuvrirImport() end)
	cadre.importer:SetPoint("TOPRIGHT", -8, -110)
	Opus.Bulle(cadre.importer, "Coller l'instantané", "La chaîne « OLS1:I: » de la page Raids du site, avant la soirée.")
	cadre.duBridge = Opus.Bouton(cadre, "Du bridge", 90, function ()
		local texte = InstantaneDuFlux()
		if texte and Raid.ImporterInstantane(texte) then Opus.Rafraichir() end
	end)
	cadre.duBridge:SetPoint("RIGHT", cadre.importer, "LEFT", -6, 0)
	Opus.Bulle(cadre.duBridge, "Importer depuis le bridge", { "L'instantané du palier en cours, apporté par le bridge à ta connexion.",
		Opus.Gris("Il date de ta dernière connexion : un rapport validé depuis demande un /reload, le bridge allumé.") })
	cadre.detail = Opus.Bouton(cadre, "Détail", 70, function () Raid.Executer("etat") end)
	cadre.detail:SetPoint("RIGHT", cadre.duBridge, "LEFT", -6, 0)

	Section("Ce soir", -154)
	cadre.yAnnonces = -180
	cadre.annonces = Texte(cadre.yAnnonces, largeur - 20)

	cadre.titreRapport = Section("Rapport pour le site", -260)
	cadre.rapport = Texte(-286)
	cadre.exporter = Opus.Bouton(cadre, "Exporter le rapport", 160, function () Raid.Exporter() end)
	cadre.exporter:SetPoint("TOPRIGHT", -8, -280)
	Opus.Bulle(cadre.exporter, "Exporter le rapport", "À coller sur le site, page Raids, « Rapports » du palier. L'exporter plusieurs fois ne compte rien en double.")
end

------------------------------------------------------------------------
-- la page
------------------------------------------------------------------------

-- Ma liste et l'historique : un texte qui défile, aux liens d'objets survolables
local function ConstruireTexte (cadre, largeur)
	cadre.defile = CreateFrame("ScrollFrame", nil, cadre)
	cadre.defile:SetPoint("TOPLEFT") cadre.defile:SetWidth(largeur - 14) cadre.defile:SetHeight(VUE_MAX)
	local x = CreateFrame("Frame", nil, cadre.defile)
	x:SetWidth(largeur - 14) x:SetHeight(1)
	cadre.defile:SetScrollChild(x)
	x:SetHyperlinksEnabled(true)
	x:SetScript("OnHyperlinkEnter", function (self, lien)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		if pcall(GameTooltip.SetHyperlink, GameTooltip, lien) then GameTooltip:Show() else GameTooltip:Hide() end
	end)
	x:SetScript("OnHyperlinkLeave", function () GameTooltip:Hide() end)
	x:SetScript("OnHyperlinkClick", function (_, lien, texte, bouton) SetItemRef(lien, texte, bouton) end)
	cadre.texte = x:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.texte:SetPoint("TOPLEFT", 4, -4) cadre.texte:SetWidth(largeur - 30) cadre.texte:SetJustifyH("LEFT") cadre.texte:SetSpacing(4)
	cadre.ascenseur = Opus.Ascenseur(cadre, function (d) defile = d Opus.Rafraichir() end)
	cadre.ascenseur:SetPoint("TOPRIGHT", cadre.defile, "TOPRIGHT", 14, 0)
	cadre.ascenseur:SetPoint("BOTTOMRIGHT", cadre.defile, "BOTTOMRIGHT", 14, 0)
end

local function RafraichirTexte (cadre, texte)
	cadre.texte:SetText(texte)
	local total = cadre.texte:GetStringHeight() + 12
	local visible = math.min(total, VUE_MAX)
	cadre.defile:SetHeight(visible)
	defile = math.max(0, math.min(defile, total - visible))
	cadre.defile:SetVerticalScroll(defile)
	cadre.ascenseur:Recaler(defile, total, visible)
	return visible + 8
end

local function Rafraichir (cadre)
	cadre.vues:Maj()
	local _, maj = Raid.Flux()
	cadre.fraicheur:SetText(maj and ("site : " .. Jour(maj) .. date(" %H:%M", maj)) or "")
	for _, k in ipairs({ "soir", "liste", "historique" }) do cadre[k]:SetShown(vue == k) end
	if vue == "liste" then return RafraichirTexte(cadre.liste, TexteListe()) end
	if vue == "historique" then return RafraichirTexte(cadre.historique, TexteHistorique()) end
	return RafraichirSoir(cadre.soir)
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	cadre.vues = Opus.Onglets(barre, VUES, function () return vue end, function (v) vue = v defile = 0 Opus.Rafraichir() end)
	cadre.fraicheur = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.fraicheur:SetPoint("RIGHT", 0, 0)
	for _, k in ipairs({ "soir", "liste", "historique" }) do
		cadre[k] = CreateFrame("Frame", nil, cadre)
		cadre[k]:SetPoint("TOPLEFT") cadre[k]:SetPoint("TOPRIGHT") cadre[k]:SetHeight(1)
	end
	ConstruireSoir(cadre.soir, largeur)
	ConstruireTexte(cadre.liste, largeur)
	ConstruireTexte(cadre.historique, largeur)
end

Opus.Page("raids", "Raids", Construire, Rafraichir, function (_, d) defile = math.max(0, defile - d * 60) end)

-- un objet arrivé dans le cache du jeu : son vrai lien remplace le nom
local attente
Raid.Ecoute("GET_ITEM_INFO_RECEIVED", function ()
	if attente or not Opus.db or Opus.db.page ~= "raids" or vue == "soir" then return end
	attente = C_Timer.NewTimer(0.5, function () attente = nil Opus.Rafraichir() end)
end)

-- les comptes à rebours, tant que l'onglet est ouvert et qu'une annonce court
C_Timer.NewTicker(1, function ()
	if not Opus.db or Opus.db.page ~= "raids" or vue ~= "soir" or not OpusFenetre or not OpusFenetre:IsShown() then return end
	for _, a in ipairs(Raid.attributions) do
		if a.etat == "delai" or a.etat == "vote" or a.etat == "sk" then Opus.Rafraichir() return end
	end
end)
