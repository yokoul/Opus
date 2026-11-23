-- ReglagesButin.lua : la vue « Butin » de l'onglet Réglages, pour ne pas charger la vue de base. Les durées des tours
-- d'attribution (objection, vote, Suicide King), la part de la guilde pour ouvrir une soirée, l'échange automatique, et
-- la comparaison du butin en donjon. Les durées comptent chez le maître du butin : c'est son addon qui mène les tours.
local _, Opus = ...
local Raid = Opus.Raid

local X_CONTROLE = 300           -- colonne des réglages, à droite des libellés (comme la vue de base)

local function Choix (secondes)
	local t = {}
	for _, s in ipairs(secondes) do t[#t + 1] = { s, Raid.TexteDuree(s) } end
	return t
end
local OBJECTION = Choix({ 60, 90, 120, 180, 240, 300 })
local VOTE = Choix({ 60, 90, 120, 180 })
local SK = Choix({ 30, 45, 60, 90, 120 })
local ANNONCES = { { "courtes", "Courtes" }, { "detaillees", "Détaillées" } }
local SEUILS = { { 0.5, "50 %" }, { 0.6, "60 %" }, { 0.7, "70 %" }, { 0.8, "80 %" }, { 0.9, "90 %" }, { 1, "100 %" } }

local function Construire (cadre)
	local y = -4
	local function Section (texte)
		local s = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		s:SetPoint("TOPLEFT", 4, y) s:SetText(texte)
		y = y - 26
	end
	local function Libelle (texte, aide)
		local t = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t:SetPoint("TOPLEFT", 16, y - 4) t:SetText(texte)
		if aide then
			local a = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			a:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2) a:SetWidth(X_CONTROLE - 30) a:SetJustifyH("LEFT") a:SetText(aide)
		end
	end
	local function Ligne (hauteur) y = y - (hauteur or 34) end
	local function Duree (cle, choix)
		local m = Opus.Menu(cadre, 160, choix,
			function () return Raid.Duree(cle) end,
			function (v) Raid.db.reglages["duree_" .. cle] = v end)
		m:SetPoint("TOPLEFT", X_CONTROLE, y)
		return m
	end
	local function Case (lire, ecrire)
		local c = CreateFrame("CheckButton", nil, cadre, "UICheckButtonTemplate")
		c:SetSize(24, 24) c:SetPoint("TOPLEFT", X_CONTROLE - 4, y)
		c:SetScript("OnClick", function (self) ecrire(self:GetChecked() and true or false) end)
		c.lire = lire
		return c
	end

	Section("Raids : les tours d'attribution")
	local note = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 16, y + 4) note:SetWidth(Opus.LARGEUR - 60) note:SetJustifyH("LEFT")
	note:SetText("Ils comptent quand tu es maître du butin : ton addon mène les tours et les annonce au raid.")
	Ligne(18)
	Libelle("Délai d'objection", "Après l'annonce d'un objet, pour objecter.")
	cadre.objection = Duree("objection", OBJECTION)
	Ligne(40)
	Libelle("Durée du vote", "Après une objection, pour voter entre les candidats.")
	cadre.vote = Duree("vote", VOTE)
	Ligne(40)
	Libelle("Durée du Suicide King", "Pour se déclarer sur un objet hors liste.")
	cadre.sk = Duree("sk", SK)
	Ligne(40)

	Libelle("Annonces au raid", "Courtes : l'objet, le proposé ou le gagnant, la commande. Détaillées : scores, suivants, quorum.")
	cadre.annonces = Opus.Menu(cadre, 160, ANNONCES,
		function () return Raid.db.reglages.annonces or "courtes" end,
		function (v) Raid.db.reglages.annonces = v end)
	cadre.annonces:SetPoint("TOPLEFT", X_CONTROLE, y)
	Ligne(40)

	Section("Raids : la soirée")
	Libelle("Part de la guilde dans le raid", "Pour ouvrir une soirée de guilde (chef et officiers).")
	cadre.seuil = Opus.Menu(cadre, 160, SEUILS,
		function () return Raid.Seuil() end,
		function (v) SlashCmdList.OPUSRAID("seuil " .. math.floor(v * 100 + 0.5)) end)
	cadre.seuil:SetPoint("TOPLEFT", X_CONTROLE, y)
	Ligne(40)
	Libelle("Échange automatique", "À l'échange avec un gagnant, son objet est posé tout seul.")
	cadre.echange = Case(function () return Raid.db.reglages.echangeAuto ~= false end,
		function (v) Raid.db.reglages.echangeAuto = v end)
	Ligne(40)

	Section("Donjons")
	Libelle("Comparer le butin en donjon", "À chaque jet de groupe : qui peut le porter, ce qu'il y gagne, qui jette quoi.")
	cadre.butinGroupe = Case(function () return Opus.db.butinGroupe == true end,
		function (v) Opus.db.butinGroupe = v end)
	Ligne(40)
	cadre.hauteur = -y + 8
end

local function Rafraichir (cadre)
	for _, m in ipairs({ cadre.objection, cadre.vote, cadre.sk, cadre.annonces, cadre.seuil }) do m:GenerateMenu() end
	for _, c in ipairs({ cadre.echange, cadre.butinGroupe }) do c:SetChecked(c.lire()) end
	return cadre.hauteur
end

Opus.ReglagesButin = { construire = Construire, rafraichir = Rafraichir }
