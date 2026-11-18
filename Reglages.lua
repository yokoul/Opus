-- Reglages.lua : les réglages de la guilde qui ne sont pas des grades (chef et officiers) : une restriction temporaire
-- (jusqu'à une date, réparations et/ou retraits d'or coupés sauf pour le chef) et la cotisation hebdomadaire volontaire
-- (barème par niveau, plafond par joueur). Enregistrer crée une nouvelle version de la grille, partagée aux membres.
local _, Opus = ...

local f, brouillon
local TRANCHES = 4

local function Etiquette (parent, texte, x, y, police)
	local t = parent:CreateFontString(nil, "OVERLAY", police or "GameFontNormal")
	t:SetPoint("TOPLEFT", x, y) t:SetText(texte)
	return t
end

local function Saisie (parent, largeur, x, y, lettres)
	local s = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	s:SetSize(largeur, 20) s:SetPoint("TOPLEFT", x + 6, y) s:SetAutoFocus(false)
	if lettres then s:SetMaxLetters(lettres) end
	s:SetScript("OnEnterPressed", EditBox_ClearFocus)
	s:SetScript("OnEscapePressed", EditBox_ClearFocus)
	return s
end

local function Case (parent, texte, x, y)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24) c:SetPoint("TOPLEFT", x, y)
	local t = c.Text or c.text
	if t then t:SetText(texte) t:SetFontObject("GameFontHighlightSmall") end
	return c
end

-- les montants se saisissent en pièces d'or, décimales permises (« 0,5 » pour 50 pa)
local function VersPo (cuivre) return (tostring((cuivre or 0) / 10000):gsub("%.", ",")) end
local function DePo (texte) return math.floor((tonumber((texte or ""):gsub(",", ".")) or 0) * 10000 + 0.5) end

local function DateTexte (t) return t and date("%d/%m/%Y", t) or "" end
local function LireDate (texte)
	local j, m, a = (texte or ""):match("^(%d%d?)/(%d%d?)/(%d%d%d%d)$")
	return j and time({ year = tonumber(a), month = tonumber(m), day = tonumber(j), hour = 0 }) or nil
end

local function Remplir ()
	local r = brouillon.restriction
	f.restr:SetChecked(r ~= nil)
	f.fin:SetText(DateTexte(r and r.fin))
	f.coupeRep:SetChecked(not r or r.coupeRep ~= false)
	f.coupeOr:SetChecked(not r or r.coupeOr ~= false)
	f.texte:SetText(r and r.texte or "")
	local co = brouillon.cotisation or (GetGuildInfo("player") == "Opus" and Opus.Copie(Opus.COTISATION_OPUS)) or nil
	f.cotis:SetChecked(co ~= nil and co.actif ~= false)
	for i = 1, TRANCHES do
		local t, l = co and co.tranches[i], f.tranches[i]
		l.min:SetText(t and t.min or "") l.max:SetText(t and t.max or "") l.montant:SetText(t and VersPo(t.montant) or "")
	end
	f.plafond:SetText(co and co.plafond and VersPo(co.plafond) or "")
end

local function Enregistrer ()
	if f.restr:GetChecked() then
		local fin = LireDate(f.fin:GetText())
		if not fin then Opus.Msg("date de fin de la restriction : JJ/MM/AAAA.") return end
		brouillon.restriction = { fin = fin, texte = strtrim(f.texte:GetText()), coupeRep = f.coupeRep:GetChecked() and true or false,
			coupeOr = f.coupeOr:GetChecked() and true or false }
	else
		brouillon.restriction = nil
	end
	local co = { actif = f.cotis:GetChecked() and true or false, tranches = {}, plafond = f.plafond:GetText() ~= "" and DePo(f.plafond:GetText()) or nil }
	for i = 1, TRANCHES do
		local l = f.tranches[i]
		local min, max = tonumber(l.min:GetText()), tonumber(l.max:GetText())
		if min and max then co.tranches[#co.tranches + 1] = { min = min, max = max, montant = DePo(l.montant:GetText()) } end
	end
	brouillon.cotisation = co
	Opus.EnregistrerConfig(brouillon)
	f:Hide()
	Opus.Msg("réglages enregistrés et partagés avec les membres qui ont l'addon.")
end

local function Construire ()
	f = CreateFrame("Frame", "OpusReglages", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(440, 420) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("Réglages de la guilde")
	tinsert(UISpecialFrames, "OpusReglages")
	local z = f.Inset

	Etiquette(z, "Restriction temporaire", 12, -12)
	f.restr = Case(z, "Active jusqu'au", 12, -30)
	f.fin = Saisie(z, 100, 140, -32, 10)
	Etiquette(z, "JJ/MM/AAAA", 252, -36, "GameFontDisableSmall")
	f.coupeRep = Case(z, "Couper les réparations guilde", 12, -56)
	f.coupeOr = Case(z, "Couper les retraits d'or", 230, -56)
	Etiquette(z, "Texte affiché", 12, -86, "GameFontHighlightSmall")
	f.texte = Saisie(z, 400, 12, -102, 120)

	Etiquette(z, "Cotisation hebdomadaire (volontaire)", 12, -138)
	f.cotis = Case(z, "Active : barème par personnage, selon son niveau", 12, -156)
	local entetes = { { "Niveaux", 30 }, { "à", 92 }, { "Montant (po)", 150 } }
	for _, h in ipairs(entetes) do Etiquette(z, h[1], h[2], -186, "GameFontDisableSmall") end
	f.tranches = {}
	for i = 1, TRANCHES do
		local y = -202 - (i - 1) * 26
		f.tranches[i] = { min = Saisie(z, 40, 24, y, 2), max = Saisie(z, 40, 86, y, 2), montant = Saisie(z, 60, 150, y, 6) }
	end
	Etiquette(z, "Plafond par joueur (po, tous ses personnages)", 12, -314, "GameFontHighlightSmall")
	f.plafond = Saisie(z, 60, 300, -310, 6)

	local ok = Opus.Bouton(z, "Enregistrer", 140, Enregistrer)
	ok:SetPoint("BOTTOMRIGHT", -12, 12)
	local annuler = Opus.Bouton(z, "Annuler", 110, function () f:Hide() end)
	annuler:SetPoint("RIGHT", ok, "LEFT", -8, 0)
	f:Hide()
end

function Opus.OuvrirReglages ()
	if not Opus.PeutConfigurer() then Opus.Msg("seuls le chef et les officiers modifient les réglages.") return end
	if InCombatLockdown() then return end
	if not f then Construire() end
	brouillon = Opus.Copie(Opus.Config())
	Remplir()
	f:Show()
end

Opus.Commande("reglages", "reglages", "restriction temporaire et cotisation de la guilde (chef et officiers)", function () Opus.OuvrirReglages() end)
