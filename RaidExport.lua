-- RaidExport.lua : le rapport de la soirée pour le site (/opus raid export), au format OLS1:R: de docs/contrat-butin.md
-- Un en-tête E (id du rapport, instantané utilisé, maître du butin, début, fin), puis chaque événement du journal dans
-- l'ordre : lettre, identifiant, date, puis ses champs propres. Exporter plusieurs fois ne compte rien en double : le
-- site garde chaque événement par son identifiant, et un rapport exporté en cours de soirée se complète au suivant.
-- À l'export, une attribution pas encore remise est notée « pas_remis » (K) ; une remise venue plus tard la résout.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

-- un texte libre (motif, boss) ne doit pas contenir les séparateurs du contrat
local function Champ (v)
	if v == nil then return "" end
	return (tostring(v):gsub("[;~]", " "))
end
local function Liste (t)
	local r = {}
	for k, v in ipairs(t or {}) do r[k] = (Champ(v):gsub(",", " ")) end
	return table.concat(r, ",")
end

-- les champs propres de chaque lettre, dans l'ordre du contrat
local CHAMPS = {
	T = function (e) return { Champ(e.boss), e.item, Liste(e.presents) } end,
	O = function (e) return { e.tombe, Champ(e.candidat), Liste(e.scores) } end,
	X = function (e) return { e.proposition, Champ(e.auteur) } end,
	V = function (e)
		local abstentions = math.max(0, (e.electeurs or 0) - (e.pour or 0) - (e.contre or 0))
		-- puis le gagnant (vide : égalité ou quorum non atteint) et les voix de chaque candidat, « nom:voix,… »
		local detail = {}
		for k, v in ipairs(e.detail or {}) do detail[k] = (Champ(v):gsub(",", " ")) end
		return { e.objection, e.pour or 0, e.contre or 0, abstentions, e.quorum or 0, Champ(e.gagnant), table.concat(detail, ",") }
	end,
	D = function (e) return { e.proposition or "", Champ(e.attributaire), Champ(e.officier), Champ(e.motif) } end,
	A = function (e) return { e.tombe, Champ(e.attributaire), e.voie } end,
	M = function (e) return { e.attribution, Champ(e.destinataire), e.mode } end,
	K = function (e) return { e.attribution, e.nature, Champ(e.detail) } end,
}

-- Les attributions sans remise : un écart « pas_remis », noté une fois.
local function PasRemis (s)
	local remis, signales, attributions = {}, {}, {}
	for _, e in ipairs(s.evenements) do
		if e.lettre == "M" then remis[e.attribution] = true end
		if e.lettre == "K" and e.nature == "pas_remis" then signales[e.attribution] = true end
		if e.lettre == "A" and e.attributaire ~= "" and e.voie ~= "banque" then attributions[#attributions + 1] = e end
	end
	local n = 0
	for _, a in ipairs(attributions) do
		if not remis[a.id] and not signales[a.id] then
			Raid.Noter("K", { attribution = a.id, nature = "pas_remis", detail = a.attributaire })
			n = n + 1
		end
	end
	return n
end

-- Le rapport de la soirée en cours (ou de la dernière) ; nil s'il n'y en a pas. sansEcarts : sans noter les
-- attributions pas encore remises (la soirée continue peut-être).
function Raid.Rapport (sansEcarts)
	local s = Raid.db.soiree
	if not s or #s.evenements == 0 then return nil end
	local nonRemis = sansEcarts and 0 or PasRemis(s)
	local lignes = { table.concat({ "E", s.ml .. "/" .. s.debut, Champ(s.instantane), Champ(s.ml), s.debut, s.derniere or time() }, ";") }
	local compte = {}
	for _, e in ipairs(s.evenements) do
		local f = CHAMPS[e.lettre]
		if f then
			local champs = { e.lettre, e.id, e.t }
			for _, v in ipairs(f(e)) do champs[#champs + 1] = v end
			lignes[#lignes + 1] = table.concat(champs, ";")
			compte[e.lettre] = (compte[e.lettre] or 0) + 1
		end
	end
	return Raid.Signer("OLS1:R:" .. table.concat(lignes, "~")), compte, nonRemis
end

-- Le rapport déposé pour le bridge (OpusDB.raid.rapport), qui l'envoie au site quand WoW écrit ses SavedVariables :
-- à la déconnexion ou au /reload. Seulement une soirée de guilde, et seulement si elle a changé depuis le dernier dépôt.
function Raid.Deposer (sansEcarts)
	local s = Raid.db.soiree
	-- une soirée d'essai (instantané « essai-… ») reste en jeu
	if not s or not s.guilde or tostring(s.instantane or ""):match("^essai") then return end
	local d = Raid.db.rapport
	if d and d.id == s.ml .. "/" .. s.debut and d.n == #s.evenements and (sansEcarts or d.complet) then return end
	local chaine = Raid.Rapport(sansEcarts)
	if not chaine then return end
	-- compté après coup : les écarts « pas_remis » viennent de s'ajouter au journal
	Raid.db.rapport = { id = s.ml .. "/" .. s.debut, n = #s.evenements, complet = not sansEcarts or nil, chaine = chaine, t = time() }
end

-- à la déconnexion (ou au /reload) : la soirée en cours part telle quelle, les écarts attendent sa fermeture
Opus.Ecoute("PLAYER_LOGOUT", function () if Raid.db then Raid.Deposer(Raid.db.ouverte ~= nil) end end)

------------------------------------------------------------------------
-- la fenêtre : la chaîne sélectionnée, à copier (Ctrl+C) et coller sur le site
------------------------------------------------------------------------

local f

local function Construire ()
	f = Raid.Cadre("OpusRaidExport")
	f:SetSize(460, 170) f:SetPoint("CENTER") f:SetFrameStrata("DIALOG") f:SetToplevel(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetTitle("Rapport de la soirée pour le site")
	tinsert(UISpecialFrames, "OpusRaidExport")
	local z = f.Inset
	local aide = z:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	aide:SetPoint("TOPLEFT", 12, -12) aide:SetPoint("TOPRIGHT", -12, -12)
	aide:SetJustifyH("LEFT") aide:SetSpacing(3)
	aide:SetText("Avec le bridge, le rapport part tout seul au site à la déconnexion (ou au /reload). Sans lui : copie la chaîne "
		.. "(Ctrl+C, elle est déjà sélectionnée) et colle-la sur le site Opus, page « Rapports » du palier. Rien ne compte en double.")
	f.texte = CreateFrame("EditBox", nil, z, "InputBoxTemplate")
	f.texte:SetSize(410, 20) f.texte:SetPoint("TOPLEFT", 18, -56) f.texte:SetAutoFocus(true)
	f.texte:SetMaxLetters(0)
	if f.texte.SetMaxBytes then f.texte:SetMaxBytes(0) end
	-- la chaîne ne se modifie pas : toute frappe la remet en place
	f.texte:SetScript("OnTextChanged", function (self, parUtilisateur)
		if parUtilisateur and self:GetText() ~= f.chaine then self:SetText(f.chaine) self:HighlightText() end
	end)
	f.texte:SetScript("OnEditFocusGained", function (self) self:HighlightText() end)
	f.texte:SetScript("OnEscapePressed", function () f:Hide() end)
	f.etat = z:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.etat:SetPoint("TOPLEFT", 12, -84) f.etat:SetPoint("TOPRIGHT", -12, -84) f.etat:SetJustifyH("LEFT")
	local fermer = CreateFrame("Button", nil, z, "SharedButtonSmallTemplate")
	fermer:SetSize(100, 24) fermer:SetText("Fermer") fermer:SetPoint("BOTTOMRIGHT", -12, 12)
	fermer:SetScript("OnClick", function () f:Hide() end)
	f:Hide()
end

local NOMS = { T = "objet", A = "attribution", M = "remise", K = "écart", X = "objection", D = "décision" }

local function Exporter ()
	local chaine, compte, nonRemis = Raid.Rapport()
	if not chaine then Msg("rien à exporter : aucune annonce dans la soirée.") return end
	Raid.Deposer()
	if not f then Construire() end
	f.chaine = chaine
	f.texte:SetText(chaine)
	local parties = {}
	for _, l in ipairs({ "T", "A", "M", "K", "X", "D" }) do
		local n = compte[l] or 0
		if n > 0 then parties[#parties + 1] = n .. " " .. NOMS[l] .. (n > 1 and "s" or "") end
	end
	local s = Raid.db.soiree
	f.etat:SetText(string.format("Soirée du %s, %s. %d caractères.", date("%d/%m à %H:%M", s.debut), table.concat(parties, ", "), #chaine))
	if nonRemis > 0 then
		Msg(string.format("|cffffd100%d attribution%s pas encore remise%s|r : noté%s pour la revue (/opus raid remises).",
			nonRemis, nonRemis > 1 and "s" or "", nonRemis > 1 and "s" or "", nonRemis > 1 and "es" or "e"))
	end
	f:Show()
	f.texte:SetFocus()
	f.texte:HighlightText()
end

Raid.Exporter = Exporter
Raid.Commande("export", "export", "le rapport de la soirée, à coller sur le site", Exporter)
