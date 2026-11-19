-- PageAPropos.lua : ce qu'est l'addon, pour qui il est fait, qui contacter, et ses commandes
local _, Opus = ...

local CONTACT = "Illustre Inconnu"
local DISCORD = "https://discord.gg/XtSksuFU6v"

-- un champ dont on peut copier le texte (le jeu ne rend pas les liens cliquables), sans pouvoir le modifier
local function Copiable (parent, texte, largeur)
	local s = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	s:SetSize(largeur, 20)
	s:SetAutoFocus(false)
	s:SetText(texte)
	s:SetCursorPosition(0)
	s:SetScript("OnTextChanged", function (self, utilisateur) if utilisateur then self:SetText(texte) self:HighlightText() end end)
	s:SetScript("OnEditFocusGained", function (self) self:HighlightText() end)
	s:SetScript("OnEnterPressed", EditBox_ClearFocus)
	s:SetScript("OnEscapePressed", EditBox_ClearFocus)
	return s
end

local function Rafraichir (cadre)
	cadre.version:SetText(Opus.Gris("version " .. Opus.version))
	-- les commandes, telles que l'addon les connaît
	local lignes = {}
	for _, c in ipairs(Opus.commandes) do
		lignes[#lignes + 1] = Opus.Normal("/opus " .. c.usage) .. "  " .. Opus.Gris(c.aide)
	end
	cadre.commandes:SetText(table.concat(lignes, "\n"))
	return 150 + #lignes * 15 + 20
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	local titre = barre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	titre:SetPoint("LEFT", 0, 0)
	titre:SetText("À propos d'Opus")

	local embleme = cadre:CreateTexture(nil, "ARTWORK")
	embleme:SetTexture("Interface\\AddOns\\Opus\\Media\\Embleme")
	embleme:SetSize(96, 96)
	embleme:SetPoint("TOPLEFT", 4, -4)

	local nom = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	nom:SetPoint("TOPLEFT", embleme, "TOPRIGHT", 16, -6)
	nom:SetText("Opus")
	cadre.version = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.version:SetPoint("LEFT", nom, "RIGHT", 10, -2)

	local texte = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	texte:SetPoint("TOPLEFT", nom, "BOTTOMLEFT", 0, -8)
	texte:SetWidth(largeur - 120) texte:SetJustifyH("LEFT") texte:SetSpacing(3)
	texte:SetText("Outils de guilde pour WoW Forever, faits pour la guilde " .. Opus.Normal("Opus") .. " (royaume PvE, Europe) : tableau de la guilde "
		.. "(persos et rerolls, niveaux, notes, liens Discord, arrivées et départs), groupes et envies de donjon, banque partagée (prêts, sorties d'objets), "
		.. "essais et promotions, grille des grades. "
		.. Opus.Gris("Ce que l'addon partage reste dans la guilde (messages d'addon de guilde)."))

	local contact = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	contact:SetPoint("TOPLEFT", 120, -112)
	contact:SetText("Contact et support")
	local enJeu = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	enJeu:SetPoint("TOPLEFT", contact, "BOTTOMLEFT", 0, -6)
	enJeu:SetText("En jeu : " .. Opus.Blanc(CONTACT) .. "     Discord :")
	local lien = Copiable(cadre, DISCORD, 240)
	lien:SetPoint("LEFT", enJeu, "RIGHT", 10, 0)
	local astuce = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	astuce:SetPoint("LEFT", lien, "RIGHT", 8, 0)
	astuce:SetText("clic, puis Ctrl+C")

	local h = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOPLEFT", 4, -150)
	h:SetText("Commandes")
	cadre.commandes = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.commandes:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
	cadre.commandes:SetWidth(largeur - 8) cadre.commandes:SetJustifyH("LEFT") cadre.commandes:SetSpacing(3)
end

Opus.Page("apropos", "À propos", Construire, Rafraichir)
