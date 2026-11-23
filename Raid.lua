-- Raid.lua : socle du butin de raid (WishVote) : ses données, la soirée de guilde, ses droits et ses commandes
-- Venu de l'addon Opus Raid, fusionné dans Opus en 0.30.0. Les fichiers Raid*.lua partagent la table Opus.Raid ; les
-- noms, les membres et les événements sont ceux d'Opus. Les données vivent dans OpusDB.raid (celles d'Opus Raid,
-- OpusRaidDB, y sont reprises une fois).
--
-- Garde-fou : l'addon ne s'engage que dans une soirée de guilde. Le maître du butin (ou un officier) l'ouvre de lui-même,
-- et seulement si assez du raid est de la guilde (80 % par défaut) ; si le raid change en cours de soirée et passe
-- sous ce seuil, tout est suspendu (pas d'annonce, pas de fenêtre du butin) jusqu'à ce qu'il redevienne un raid de
-- guilde. Hors groupe, pour essayer, rien n'est envoyé : l'essai reste possible sans soirée.
local ADDON, Opus = ...
local Raid = {}
Opus.Raid = Raid
Raid.version = Opus.version

local DEFAUTS = {
	instantane = nil,           -- le dernier instantané importé du site (RaidInstantane.lua)
	reglages = {                -- echangeAuto (RaidRemise.lua) ; duree_objection, duree_vote, duree_sk (Raid.Duree)
		seuilGuilde = 0.8,      -- part du raid qui doit être de la guilde pour ouvrir une soirée
	},
	ouverte = nil,              -- la soirée de guilde ouverte : { debut, par }
	droits = {                  -- qui gère le butin sur ce client (/opus raid droits) : un garde-fou, pas une sécurité
		officiers = true,       -- le chef et les officiers de la guilde, même hors raid (pour préparer la soirée)
		chef = true,            -- le chef du raid
		ml = true,              -- le maître du butin
		assistants = true,      -- les assistants du raid (promus)
		tous = false,           -- tout le monde : pour les essais
	},
}

function Raid.Msg (s)
	DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37Opus|r raid : " .. s)
end

local function Defauts (db, ref)
	for k, v in pairs(ref) do
		if db[k] == nil then
			if type(v) == "table" then db[k] = {} Defauts(db[k], v) else db[k] = v end
		elseif type(v) == "table" and type(db[k]) == "table" then
			Defauts(db[k], v)
		end
	end
end

-- les noms, les membres et les événements : ceux d'Opus
Raid.Court, Raid.Membres, Raid.MonNom, Raid.Identifier = Opus.Court, Opus.Membres, Opus.MonNom, Opus.Identifier
Raid.Ecoute = Opus.Ecoute

-- Les fenêtres du butin : un cadre sombre à liseré doré (comme les notifications d'Opus), un titre et une croix. Pas le
-- modèle des fenêtres du jeu : sans portrait, il laisse une bande grise sous le titre et des bords qui dépassent.
-- f.Inset reçoit le contenu (le même nom qu'avec le modèle) ; f:SetTitle(texte).
function Raid.Cadre (nom)
	local f = CreateFrame("Frame", nom, UIParent, "BackdropTemplate")
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
		f:SetBackdropBorderColor(0.83, 0.69, 0.22)
	end
	f.titre = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.titre:SetPoint("TOPLEFT", 12, -9) f.titre:SetPoint("TOPRIGHT", -30, -9) f.titre:SetJustifyH("LEFT")
	f.SetTitle = function (self, texte) self.titre:SetText(texte) end
	f.filet = f:CreateTexture(nil, "ARTWORK")
	f.filet:SetHeight(1) f.filet:SetPoint("TOPLEFT", 8, -26) f.filet:SetPoint("TOPRIGHT", -8, -26)
	f.filet:SetColorTexture(0.83, 0.69, 0.22, 0.35)
	f.fermer = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.fermer:SetSize(24, 24) f.fermer:SetPoint("TOPRIGHT", -3, -3)
	f.Inset = CreateFrame("Frame", nil, f)
	f.Inset:SetPoint("TOPLEFT", 4, -26) f.Inset:SetPoint("BOTTOMRIGHT", -4, 4)
	f:SetFrameStrata("DIALOG") f:SetToplevel(true) f:SetClampedToScreen(true)
	f:EnableMouse(true) f:SetMovable(true) f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving) f:SetScript("OnDragStop", f.StopMovingOrSizing)
	return f
end

-- L'infobulle d'un objet : par son lien, ou par son itemID quand le jeu ne l'a pas encore (elle le charge au passage).
function Raid.Infobulle (proprio, lien, id)
	GameTooltip:SetOwner(proprio, "ANCHOR_RIGHT")
	if lien and (lien:find("|H", 1, true) or lien:find("^item:")) then GameTooltip:SetHyperlink(lien)
	elseif tonumber(id) and GameTooltip.SetItemByID then GameTooltip:SetItemByID(tonumber(id))
	elseif tonumber(id) then GameTooltip:SetHyperlink("item:" .. tonumber(id))
	else GameTooltip:Hide() return end
	GameTooltip:Show()
end

-- Un lien encore provisoire (« objet 19876 ») : le vrai, si le jeu l'a reçu entre-temps.
function Raid.LienAJour (lien, id)
	if (lien and lien:find("|H", 1, true)) or not Raid.LienDe or not tonumber(id) then return lien end
	return Raid.LienDe(tonumber(id))
end

-- L'icône d'un objet, qui se survole comme son lien : un bouton carré ; b.lien et b.id posés par Raid.PoserIcone.
local IconeDe = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
function Raid.Icone (parent, taille)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(taille, taille)
	b.image = b:CreateTexture(nil, "ARTWORK") b.image:SetAllPoints()
	b.image:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b:SetScript("OnEnter", function (self) Raid.Infobulle(self, self.lien, self.id) end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	-- Maj+clic : le lien dans la discussion, comme ailleurs dans le jeu
	b:SetScript("OnClick", function (self) if IsModifiedClick("CHATLINK") and self.lien and self.lien:find("|H", 1, true) then ChatEdit_InsertLink(self.lien) end end)
	return b
end
function Raid.PoserIcone (b, id, lien)
	id = tonumber(id)
	b.id, b.lien = id, lien
	b.image:SetTexture((id and IconeDe and IconeDe(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
end

-- le chef et les grades « officier » en jeu
function Raid.EstOfficier () return Opus.PeutConfigurer() end

-- le mode de butin et le maître du butin : C_PartyInfo sur les clients récents, GetLootMethod sur les anciens ;
-- rend vrai si le joueur est maître du butin
local MASTER = Enum and Enum.LootMethod and (Enum.LootMethod.Masterlooter or Enum.LootMethod.MasterLooter)
function Raid.EstMaitreButin ()
	local lire = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
	if not lire then return false end
	local ok, methode, groupe, raid = pcall(lire)
	if not ok or not (methode == "master" or (MASTER and methode == MASTER)) then return false end
	if raid then return UnitIsUnit("raid" .. raid, "player") and true or false end
	return groupe == 0
end

-- Qui gère le butin : le chef et les officiers de la guilde, le chef du raid, le maître du butin, les assistants,
-- selon les réglages. Rend vrai et le titre retenu, ou faux.
local TITRES = {
	{ "officiers", "officier de la guilde", function () return Raid.EstOfficier() end },
	{ "ml", "maître du butin", function () return Raid.EstMaitreButin() end },
	{ "chef", "chef du raid", function () return IsInRaid() and UnitIsGroupLeader("player") end },
	{ "assistants", "assistant du raid", function () return IsInRaid() and UnitIsGroupAssistant("player") end },
	{ "tous", "tout le monde (essais)", function () return true end },
}
Raid.titres = TITRES

function Raid.PeutGerer ()
	local d = Raid.db and Raid.db.droits or {}
	for _, t in ipairs(TITRES) do
		if d[t[1]] then
			local ok, oui = pcall(t[3])
			if ok and oui then return true, t[2] end
		end
	end
	return false
end

-- le message de refus : qui peut, d'après les réglages
function Raid.QuiPeut ()
	local d, qui = Raid.db and Raid.db.droits or {}, {}
	for _, t in ipairs(TITRES) do if d[t[1]] then qui[#qui + 1] = t[2] end end
	if #qui == 0 then return "impossible : personne n'en a le droit sur ce client (/opus raid droits)" end
	return "réservé à : " .. table.concat(qui, ", ") .. " (/opus raid droits)"
end

------------------------------------------------------------------------
-- la soirée de guilde
------------------------------------------------------------------------

-- La part du raid (ou du groupe) qui est de la guilde : rend la part (0 à 1), le nombre de membres de la guilde et la
-- taille du raid. Hors groupe : nil.
function Raid.PartGuilde ()
	if not IsInRaid() and not IsInGroup() then return nil end
	local liste = Raid.MembresDuRaid()
	if #liste == 0 then return nil end
	local guilde = 0
	for _, m in ipairs(liste) do if m.sur then guilde = guilde + 1 end end
	return guilde / #liste, guilde, #liste
end

local function Seuil () return Raid.db and Raid.db.reglages.seuilGuilde or 0.8 end
Raid.Seuil = Seuil

-- Les durées des tours, en secondes : réglables (Réglages, vue « Butin »), elles comptent chez le maître du butin.
local DUREES = { objection = 180, vote = 120, sk = 60 }
function Raid.Duree (quoi)
	local r = Raid.db and Raid.db.reglages
	return (r and tonumber(r["duree_" .. quoi])) or DUREES[quoi]
end
-- « 3 min », « 1 min 30 », « 45 s »
function Raid.TexteDuree (s)
	s = math.floor(s or 0)
	if s < 60 then return s .. " s" end
	local m, r = math.floor(s / 60), s % 60
	return r == 0 and (m .. " min") or string.format("%d min %02d", m, r)
end

-- Hors groupe : essai, rien ne part. En raid (ou en groupe, pour essayer à quelques-uns) : seulement dans la soirée de
-- guilde ouverte, et tant que le raid est assez de la guilde. Rend vrai, ou faux et la raison.
function Raid.Actif ()
	if not IsInRaid() and not IsInGroup() then return true end
	if not Raid.db or not Raid.db.ouverte then return false, "aucune soirée de guilde ouverte (onglet Raids, ou /opus raid ouvrir)" end
	local part, guilde, taille = Raid.PartGuilde()
	if part and part < Seuil() then
		return false, string.format("soirée suspendue : %d membres de la guilde sur %d dans le raid (%d %% demandés)", guilde, taille, Seuil() * 100)
	end
	return true
end

local suspendue = false
local function Verifier ()
	if not Raid.db or not Raid.db.ouverte then suspendue = false return end
	if not IsInRaid() and not IsInGroup() then
		Raid.db.ouverte = nil
		suspendue = false
		if Raid.Deposer then Raid.Deposer() end
		Raid.Msg("plus de raid : la soirée de guilde est fermée. Le rapport part au site par le bridge à la déconnexion.")
		if Opus.Rafraichir then Opus.Rafraichir() end
		return
	end
	local actif, raison = Raid.Actif()
	if not actif and not suspendue then
		suspendue = true
		Raid.Msg("|cffff5555" .. raison .. "|r. Le butin attend que le raid redevienne un raid de guilde.")
	elseif actif and suspendue then
		suspendue = false
		Raid.Msg("le raid est de nouveau un raid de guilde : la soirée reprend.")
	end
	if Opus.Rafraichir then Opus.Rafraichir() end
end
Raid.VerifierSoiree = Verifier

-- Ouvre la soirée de guilde : en raid (ou en groupe, pour essayer), avec le droit de gérer le butin, et un raid assez
-- de la guilde.
function Raid.OuvrirSoiree ()
	if not Raid.PeutGerer() then Raid.Msg("ouvrir la soirée " .. Raid.QuiPeut() .. ".") return false end
	if not IsInRaid() and not IsInGroup() then Raid.Msg("une soirée de guilde s'ouvre en raid.") return false end
	local part, guilde, taille = Raid.PartGuilde()
	if not part or part < Seuil() then
		Raid.Msg(string.format("|cffff5555pas un raid de guilde|r : %d membres de la guilde sur %d (il en faut %d %%). Rien n'est ouvert.",
			guilde or 0, taille or 0, Seuil() * 100))
		return false
	end
	Raid.db.ouverte = { debut = time(), par = Raid.MonNom() }
	suspendue = false
	Raid.Annoncer(string.format("Soirée de guilde ouverte : le butin suit les règles d'Opus (%d sur %d de la guilde).", guilde, taille))
	if Opus.Rafraichir then Opus.Rafraichir() end
	return true
end

function Raid.FermerSoiree ()
	if not Raid.db.ouverte then Raid.Msg("aucune soirée ouverte.") return end
	if not Raid.PeutGerer() then Raid.Msg("fermer la soirée " .. Raid.QuiPeut() .. ".") return end
	Raid.db.ouverte = nil
	if Raid.Deposer then Raid.Deposer() end
	Raid.Msg("soirée de guilde fermée. Le rapport part au site par le bridge à la déconnexion ; sans bridge, exporte-le (onglet Raids).")
	if Opus.Rafraichir then Opus.Rafraichir() end
end

Opus.Ecoute("GROUP_ROSTER_UPDATE", Verifier)

-- L'ancien addon OpusRaid, s'il est encore activé : il mène le butin à sa façon (ses fenêtres, « [Opus Raid] », ses
-- durées) en même temps qu'Opus, et les deux se répondent. On le dit, en rouge, à chaque connexion.
function Raid.AncienActif ()
	local charge = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return charge and charge("OpusRaid") and true or false
end
local AVERTI = "|cffff5555l'ancien addon OpusRaid est encore activé sur ce personnage : il mène le butin à la place d'Opus (fenêtre « Opus Raid : butin », annonces « [Opus Raid] », durées fixes). Désactive-le dans la liste des addons, ou supprime son dossier AddOns/OpusRaid, puis relance le jeu.|r"
Raid.AVERTI_ANCIEN = AVERTI
Opus.Ecoute("PLAYER_LOGIN", function ()
	C_Timer.After(5, function () if Raid.AncienActif() then Raid.Msg(AVERTI) end end)
end)

------------------------------------------------------------------------
-- données
------------------------------------------------------------------------

Opus.Ecoute("ADDON_LOADED", function (nom)
	if nom ~= ADDON then return end
	-- Opus.lua a déjà préparé OpusDB (il est chargé avant)
	OpusDB.raid = OpusDB.raid or {}
	Defauts(OpusDB.raid, DEFAUTS)
	Raid.db = OpusDB.raid
end)

-- L'ancien addon encore activé : ses données (OpusRaidDB, dans son propre fichier, que seul lui charge) sont reprises
-- si Opus n'a encore ni instantané ni soirée ; puis on demande de le désactiver, sans quoi les deux réagiraient aux
-- mêmes messages.
Opus.Ecoute("PLAYER_LOGIN", function ()
	local charge = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)
	if not (charge and charge("OpusRaid")) then return end
	local ancien = type(OpusRaidDB) == "table" and OpusRaidDB or nil
	if ancien and not Raid.db.instantane and not Raid.db.soiree then
		Raid.db.instantane, Raid.db.soiree = ancien.instantane, ancien.soiree
		if type(ancien.droits) == "table" then Raid.db.droits = ancien.droits end
		if type(ancien.reglages) == "table" then
			for k, v in pairs(ancien.reglages) do if Raid.db.reglages[k] == nil then Raid.db.reglages[k] = v end end
		end
		Raid.Msg("données d'Opus Raid reprises (instantané, soirée, droits).")
	end
	Raid.Msg("|cffff5555l'addon Opus Raid est encore activé|r : il fait maintenant partie d'Opus. Désactive-le (liste des addons) et fais /reload.")
end)

------------------------------------------------------------------------
-- commandes : /opus raid … (et /opusraid, /oraid)
------------------------------------------------------------------------

Raid.commandes = {}

local function Aide ()
	Raid.Msg("commandes du raid :")
	for _, c in ipairs(Raid.commandes) do
		DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/opus raid " .. c.usage .. "|r — " .. c.aide)
	end
end

function Raid.Commande (mot, usage, aide, f)
	table.insert(Raid.commandes, { mot = mot, usage = usage, aide = aide, f = f })
end

local function Executer (texte)
	local mot, reste = (texte or ""):match("^%s*(%S*)%s*(.-)%s*$")
	mot = (mot or ""):lower()
	if mot == "" and Opus.Fenetre then Opus.Fenetre(true) if Opus.Afficher then Opus.Afficher("raids") end return end
	for _, c in ipairs(Raid.commandes) do
		if c.mot == mot then c.f(reste) return end
	end
	Aide()
end
Raid.Executer = Executer

Opus.Commande("raid", "raid [commande]", "le butin de raid : l'onglet Raids, ou une commande (/opus raid aide)", Executer)
SLASH_OPUSRAID1 = "/opusraid"
SLASH_OPUSRAID2 = "/oraid"
SlashCmdList["OPUSRAID"] = Executer

Raid.Commande("aide", "aide", "cette liste", Aide)
Raid.Commande("ouvrir", "ouvrir", "ouvrir la soirée de guilde (en raid, si assez du raid est de la guilde)", function () Raid.OuvrirSoiree() end)
Raid.Commande("fermer", "fermer", "fermer la soirée de guilde", function () Raid.FermerSoiree() end)

-- /opus raid seuil <pourcentage> : la part du raid qui doit être de la guilde
Raid.Commande("seuil", "seuil [pourcentage]", "la part du raid qui doit être de la guilde pour ouvrir une soirée (80 par défaut)", function (texte)
	local n = tonumber(texte)
	if n then
		if not Raid.EstOfficier() then Raid.Msg("le seuil se règle par le chef et les officiers.") return end
		if n < 50 or n > 100 then Raid.Msg("entre 50 et 100.") return end
		Raid.db.reglages.seuilGuilde = n / 100
		Verifier()
	end
	Raid.Msg(string.format("une soirée de guilde demande %d %% du raid dans la guilde.", Seuil() * 100))
end)

-- /opus raid droits : la liste ; /opus raid droits <qui> on|off : un réglage. Réglé sur ce client seulement.
local function Droits (texte)
	local qui, valeur = (texte or ""):lower():match("^(%S*)%s*(%S*)$")
	local d = Raid.db.droits
	if qui ~= "" then
		local t
		for _, x in ipairs(Raid.titres) do if x[1] == qui then t = x end end
		if not t or (valeur ~= "on" and valeur ~= "off") then
			Raid.Msg("usage : /opus raid droits <officiers|ml|chef|assistants|tous> <on|off>")
			return
		end
		d[qui] = valeur == "on"
	end
	Raid.Msg("qui gère le butin sur ce client (vert = toi, maintenant) :")
	for _, t in ipairs(Raid.titres) do
		local ok, oui = pcall(t[3])
		local etat = d[t[1]] and "|cff40ff40on|r" or "|cff808080off|r"
		local moi = d[t[1]] and ok and oui and " |cff40ff40← toi|r" or ""
		DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s %s — %s%s", t[1], etat, t[2], moi))
	end
end
Raid.Commande("droits", "droits [qui on|off]", "qui peut importer et gérer le butin : officiers, ml, chef, assistants, tous", Droits)
