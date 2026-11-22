-- PageRaids.lua : l'onglet « Raids ». La soirée de guilde (l'ouvrir, la fermer, son état), l'instantané du site, les
-- annonces du soir, ce qui me concerne (ma liste de souhaits, ma place au Suicide King) et le rapport à rendre au site.
-- Les fenêtres du raid (butin, attributions, décision) restent à part : elles surgissent en pleine soirée.
local _, Opus = ...
local Raid = Opus.Raid

local MAX_ANNONCES = 8              -- annonces montrées ici ; /opus raid objections pour toutes
local MAX_SOUHAITS = 8

local function Pluriel (n, mot) return n .. " " .. mot .. (n > 1 and "s" or "") end

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

-- ma liste de souhaits dans l'instantané, du rang 1 au dernier
local function MesSouhaits (i, moi)
	local liste = {}
	for id, candidats in pairs(i.souhaits) do
		for _, c in ipairs(candidats) do
			if c.nom == moi then liste[#liste + 1] = { id = id, rang = c.rang } end
		end
	end
	table.sort(liste, function (a, b) return a.rang < b.rang end)
	return liste
end

local function Rafraichir (cadre)
	local i, gere = Raid.db.instantane, Raid.PeutGerer()

	-- la soirée
	cadre.soiree:SetText(EtatSoiree())
	cadre.ouvrir:SetShown(not Raid.db.ouverte)
	cadre.fermer:SetShown(Raid.db.ouverte ~= nil)
	cadre.ouvrir:SetEnabled(gere and IsInGroup())
	cadre.fermer:SetEnabled(gere)
	local aRemettre = #Raid.ARemettre()
	cadre.butin:SetEnabled(gere)
	cadre.remises:SetText(aRemettre > 0 and ("À remettre : " .. aRemettre) or "Rien à remettre")
	cadre.remises:SetEnabled(aRemettre > 0)

	-- l'instantané
	if i then
		cadre.instantane:SetText(string.format("%s · palier %s · %s, %s · importé le %s par %s",
			Opus.Blanc(i.id), i.tier ~= "" and i.tier or "?", Pluriel(i.nJoueurs, "joueur"), Pluriel(i.nObjets, "objet"),
			date("%d/%m à %H:%M", i.importe or i.date), i.par or "?"))
	else
		cadre.instantane:SetText(Opus.Gris("Aucun instantané : un officier ou le maître du butin colle celui du site (page Raids, « Instantané »)."))
	end
	cadre.importer:SetEnabled(gere)
	cadre.detail:SetEnabled(i ~= nil)

	-- les annonces du soir
	local lignes = {}
	for k = math.max(1, #Raid.attributions - MAX_ANNONCES + 1), #Raid.attributions do
		local a = Raid.attributions[k]
		lignes[#lignes + 1] = a.lien .. "  " .. Opus.Gris(Raid.EtatAttribution(a))
	end
	if #Raid.attributions > MAX_ANNONCES then
		table.insert(lignes, 1, Opus.Gris(string.format("… et %d plus tôt (/opus raid objections)", #Raid.attributions - MAX_ANNONCES)))
	end
	cadre.annonces:SetText(#lignes > 0 and table.concat(lignes, "\n") or Opus.Gris("Aucune annonce ce soir."))

	-- pour moi
	local moi = Raid.MonNom()
	if not i then
		cadre.moi:SetText(Opus.Gris("Ta liste apparaît ici une fois l'instantané importé."))
	elseif not i.joueurs[moi] then
		cadre.moi:SetText(Opus.Gris(moi .. " n'a pas de liste validée dans cet instantané. Les listes se font sur le site, page Raids."))
	else
		local souhaits, parts = MesSouhaits(i, moi), {}
		for k = 1, math.min(#souhaits, MAX_SOUHAITS) do
			parts[#parts + 1] = Opus.Normal(souhaits[k].rang .. ".") .. " " .. Raid.LienDe(souhaits[k].id)
		end
		if #souhaits > MAX_SOUHAITS then parts[#parts + 1] = Opus.Gris("… " .. (#souhaits - MAX_SOUHAITS) .. " de plus") end
		local sk = (Raid.db.soiree and Raid.db.soiree.sk) or i.sk or {}
		local place
		for k, nom in ipairs(sk) do if nom == moi then place = k end end
		cadre.moi:SetText(table.concat(parts, "\n") .. "\n" .. Opus.Gris("Suicide King : " ..
			(place and ("rang " .. place .. " sur " .. #sk) or "pas encore dans la liste (tu y entres en bas)")))
	end

	-- le rapport
	local s = Raid.db.soiree
	local n = s and #s.evenements or 0
	cadre.rapport:SetText(n > 0 and string.format("Soirée du %s : %s noté%s.", date("%d/%m à %H:%M", s.debut), Pluriel(n, "événement"), n > 1 and "s" or "")
		or Opus.Gris("Rien à rendre au site pour l'instant."))
	cadre.exporter:SetEnabled(n > 0)

	-- les hauteurs : les listes poussent ce qui suit
	local y = cadre.yAnnonces
	cadre.annonces:SetPoint("TOPLEFT", 16, y)
	y = y - math.max(16, cadre.annonces:GetStringHeight()) - 18
	cadre.titreMoi:SetPoint("TOPLEFT", 4, y)
	cadre.moi:SetPoint("TOPLEFT", 16, y - 22)
	y = y - 22 - math.max(16, cadre.moi:GetStringHeight()) - 18
	cadre.titreRapport:SetPoint("TOPLEFT", 4, y)
	cadre.rapport:SetPoint("TOPLEFT", 16, y - 26)
	cadre.exporter:SetPoint("TOPRIGHT", -8, y - 20)
	return -y + 60
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	local titre = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	titre:SetPoint("LEFT", 0, 0)
	titre:SetText("Raids de guilde · le butin suit les règles du site (opus-guild.eu, Raids)")

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

	-- la soirée de guilde
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

	-- l'instantané
	Section("Instantané du site", -90)
	cadre.instantane = Texte(-116)
	cadre.importer = Opus.Bouton(cadre, "Importer…", 100, function () Raid.OuvrirImport() end)
	cadre.importer:SetPoint("TOPRIGHT", -8, -110)
	Opus.Bulle(cadre.importer, "Importer l'instantané", "La chaîne « OLS1:I: » de la page Raids du site, avant la soirée.")
	cadre.detail = Opus.Bouton(cadre, "Détail", 80, function () Raid.Executer("etat") end)
	cadre.detail:SetPoint("RIGHT", cadre.importer, "LEFT", -6, 0)

	-- les annonces du soir
	Section("Ce soir", -150)
	cadre.yAnnonces = -176
	cadre.annonces = Texte(cadre.yAnnonces, largeur - 20)

	-- pour moi
	cadre.titreMoi = Section("Ma liste et ma place", -200)
	cadre.moi = Texte(-226, largeur - 20)

	-- le rapport
	cadre.titreRapport = Section("Rapport pour le site", -260)
	cadre.rapport = Texte(-286)
	cadre.exporter = Opus.Bouton(cadre, "Exporter le rapport", 160, function () Raid.Exporter() end)
	cadre.exporter:SetPoint("TOPRIGHT", -8, -280)
	Opus.Bulle(cadre.exporter, "Exporter le rapport", "À coller sur le site, page Raids, « Rapports » du palier. L'exporter plusieurs fois ne compte rien en double.")
end

Opus.Page("raids", "Raids", Construire, Rafraichir)

-- les comptes à rebours, tant que l'onglet est ouvert et qu'une annonce court
C_Timer.NewTicker(1, function ()
	if not Opus.db or Opus.db.page ~= "raids" or not OpusFenetre or not OpusFenetre:IsShown() then return end
	for _, a in ipairs(Raid.attributions) do
		if a.etat == "delai" or a.etat == "vote" or a.etat == "sk" then Opus.Rafraichir() return end
	end
end)
