-- PageJournal.lua : l'historique de la guilde (arrivées, départs, grades), du plus récent au plus ancien
local _, Opus = ...

local LIGNES, HAUTEUR = 18, 20
local lignes, decalage, filtre = {}, 0, "tout"

local function Rafraichir (cadre)
	cadre.filtre:GenerateMenu()
	local membres = {}
	for _, m in ipairs(Opus.Membres()) do membres[m.nom] = m end
	local function Nom (n)
		local m = membres[n]
		return m and (Opus.Couleur(m.classe) .. n .. "|r") or Opus.Gris(n)
	end

	local liste = Opus.Evenements(filtre)
	decalage = math.max(0, math.min(decalage, #liste - LIGNES))
	for i = 1, LIGNES do
		local l, e = lignes[i], liste[i + decalage]
		l:SetShown(e ~= nil)
		if e then
			l.e = e
			l.quand:SetText(Opus.Depuis(e.t))
			l.texte:SetText(Opus.Phrase(e, Nom))
		end
	end
	cadre.vide:SetShown(#liste == 0)

	local journal = Opus.db.journal
	local plusAncien = liste[#liste]
	cadre.info:SetText(journal.releve > 0
		and ("%d événement(s)%s · relevé il y a %s"):format(#liste,
			plusAncien and (" depuis le " .. date("%d/%m", plusAncien.t * 3600)) or "", Opus.Depuis(math.floor(journal.releve / 3600)))
		or Opus.Gris("pas encore relevé"))
	return LIGNES * HAUTEUR
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30

	cadre.filtre = Opus.Menu(barre, 190, { { "tout", "Tous les événements" }, { "mouvements", "Arrivées et départs" }, { "grades", "Changements de grade" } },
		function () return filtre end,
		function (v) filtre, decalage = v, 0 Opus.Rafraichir() end)
	cadre.filtre:SetPoint("LEFT", 0, 0)
	cadre.info = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.info:SetPoint("RIGHT", 0, 0)

	for i = 1, LIGNES do
		local l = CreateFrame("Frame", nil, cadre)
		l:SetSize(largeur, HAUTEUR)
		l:SetPoint("TOPLEFT", 0, -(i - 1) * HAUTEUR)
		l:EnableMouse(true)
		Opus.Survol(l)
		l.quand = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		l.quand:SetPoint("LEFT", 2, 0) l.quand:SetWidth(52) l.quand:SetJustifyH("RIGHT")
		l.texte = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.texte:SetPoint("LEFT", 64, 0) l.texte:SetPoint("RIGHT", -2, 0) l.texte:SetJustifyH("LEFT") l.texte:SetWordWrap(false)
		-- la date approchée au survol (le jeu ne donne que « il y a N heures »)
		Opus.Bulle(l, function (self) return date("Vers le %d/%m/%Y, %H h", self.e.t * 3600) end)
		lignes[i] = l
	end

	cadre.vide = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	cadre.vide:SetPoint("TOPLEFT", 4, -4)
	cadre.vide:SetText("Rien pour l'instant : le journal de guilde se relève à la connexion, puis toutes les 10 minutes.")
end

Opus.Page("journal", "Journal", Construire, Rafraichir, function (_, d) decalage = decalage - d * 3 end)
