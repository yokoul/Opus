-- Opus.lua : socle de l'addon (base de données, liste de guilde, commandes)
local ADDON, Opus = ...
_G.Opus = Opus
Opus.version = "0.20.1"

local DEFAUTS = {
	dureeEssai = { Apprenti = 14, Aspirant = 14 },
	arrivees = {},              -- [nom] = time() de l'arrivée vue en jeu
	montees = {},               -- [nom] = { depuis = grade d'essai, cible = grade visé } : promotions en cours
	banque = { evenements = {}, releve = 0, pairs = {} },   -- pairs : [membre] = dernier partage reçu de lui   -- opérations relevées dans les journaux de la banque (Banque.lua)
	page = "essais",            -- dernier onglet ouvert de la fenêtre
	configs = {},               -- [guilde] = grille de la guilde (Config.lua)
	vus = {},                   -- [membre] = première fois que l'addon l'a vu dans la guilde
	alts = {},                  -- [personnage] = son joueur (le premier de ses personnages) : Cotisation.lua
	discord = {},               -- [guilde] = qui joue quels personnages, importé du bot Discord (Lien.lua)
	notes = {},                 -- [guilde] = { pub, off } : notes publiques et d'officier de l'addon (Notes.lua)
	niveaux = {},               -- [guilde] = { suivi, dings } : montées de niveau des membres (Niveaux.lua)
	mesPersos = {},             -- [guilde] = { [personnage] = true } : nos personnages, vus sur ce compte
	spes = {},                  -- [membre] = { arbre, icone, points, t } : sa spé, annoncée par son addon (Specs.lua)
	journal = { evenements = {}, releve = 0 },  -- journal de guilde : arrivées, départs, grades (Journal.lua)
	minimap = { angle = 200, cache = false },   -- bouton de la minimap (Minimap.lua)
	fenetre = {},               -- position de la fenêtre (coin haut gauche)
}

function Opus.Msg (s)
	DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37Opus|r : " .. s)
end

function Opus.Safe (f, ...)
	if type(f) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(f, ...)
	if ok then return a, b, c, d end
	return nil
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

-- nom sans le royaume ("Yan-Forever" -> "Yan")
function Opus.Court (nom)
	return nom and (nom:match("^([^-]+)") or nom) or nil
end

------------------------------------------------------------------------
-- liste de guilde
------------------------------------------------------------------------

function Opus.DemanderListe ()
	if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
	elseif GuildRoster then GuildRoster() end
end

-- membres : { index, nom, complet, grade (1 = chef), nomGrade, niveau, classe, zone, note, noteOff, enLigne, guid,
-- absent (heures depuis la dernière connexion), vu (première fois que l'addon l'a vu dans la guilde) }
function Opus.Membres ()
	local liste = {}
	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local complet, nomGrade, rangIndex, niveau, _, zone, note, noteOff, enLigne, _, classe, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if complet then
			liste[#liste + 1] = {
				index = i, complet = complet, nom = Opus.Court(complet),
				grade = rangIndex + 1, nomGrade = nomGrade, niveau = niveau,
				classe = classe, zone = zone, note = note or "", noteOff = noteOff or "", enLigne = enLigne, guid = guid,
			}
			local m = liste[#liste]
			if not enLigne and GetGuildRosterLastOnline then
				local a, mo, j, h = GetGuildRosterLastOnline(i)
				if a then m.absent = ((a * 365 + mo * 30 + j) * 24) + h end
			end
			if Opus.db then
				Opus.db.vus[m.nom] = Opus.db.vus[m.nom] or time()
				m.vu = Opus.db.vus[m.nom]
			end
		end
	end
	return liste
end

function Opus.TrouverMembre (nom)
	for _, m in ipairs(Opus.Membres()) do
		if m.nom == nom or m.complet == nom then return m end
	end
	return nil
end

-- Son propre nom tel que le roster l'écrit (« Prénom Nom » sur Forever) : UnitName ne donne pas toujours le nom de
-- famille, alors on se retrouve par le GUID du personnage, le même dans le roster.
function Opus.MonNom ()
	local guid = UnitGUID("player")
	for _, m in ipairs(Opus.Membres()) do
		if guid and m.guid == guid then return m.nom end
	end
	return Opus.Court(UnitName("player"))
end

-- le membre qui a envoyé un message d'addon
function Opus.TrouverExpediteur (expediteur)
	for _, m in ipairs(Opus.Membres()) do
		if Opus.EstMembre(m.nom, expediteur) then return m end
	end
	return nil
end

-- un expéditeur de message d'addon est-il ce membre ? (le jeu peut n'y mettre que le prénom, et un royaume)
function Opus.EstMembre (nom, expediteur)
	local court = Opus.Court(expediteur)
	if not nom or not court then return false end
	return nom == court or nom:sub(1, #court + 1) == court .. " "
end

------------------------------------------------------------------------
-- événements
------------------------------------------------------------------------

Opus.banqueOuverte = false
local abonnes = {}               -- [événement] = { fonctions }
function Opus.Ecoute (evenement, f)
	abonnes[evenement] = abonnes[evenement] or {}
	table.insert(abonnes[evenement], f)
	-- un événement inconnu de ce client (Forever n'a pas tout) est ignoré au lieu de lever une erreur
	pcall(Opus.cadre.RegisterEvent, Opus.cadre, evenement)
end

Opus.cadre = CreateFrame("Frame")
Opus.cadre:SetScript("OnEvent", function (_, evenement, ...)
	for _, f in ipairs(abonnes[evenement] or {}) do f(...) end
end)

Opus.Ecoute("ADDON_LOADED", function (nom)
	if nom ~= ADDON then return end
	OpusDB = OpusDB or {}
	Defauts(OpusDB, DEFAUTS)
	Opus.db = OpusDB
end)

-- banque de guilde ouverte ou fermée (les droits des onglets ne se lisent qu'avec la banque ouverte)
local GUILDBANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
Opus.Ecoute("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function (t)
	if t == GUILDBANKER then Opus.banqueOuverte = true end
end)
Opus.Ecoute("GUILDBANKFRAME_OPENED", function () Opus.banqueOuverte = true end)
Opus.Ecoute("GUILDBANKFRAME_CLOSED", function () Opus.banqueOuverte = false end)
Opus.Ecoute("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function (t)
	if t == GUILDBANKER then Opus.banqueOuverte = false end
end)

------------------------------------------------------------------------
-- commandes : /opus
------------------------------------------------------------------------

Opus.commandes = {}

local function Aide ()
	Opus.Msg("version " .. Opus.version .. " — commandes :")
	for _, c in ipairs(Opus.commandes) do
		DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/opus " .. c.usage .. "|r — " .. c.aide)
	end
end

function Opus.Commande (mot, usage, aide, f)
	table.insert(Opus.commandes, { mot = mot, usage = usage, aide = aide, f = f })
end

SLASH_OPUS1 = "/opus"
SlashCmdList["OPUS"] = function (texte)
	local mot, reste = (texte or ""):match("^%s*(%S*)%s*(.-)%s*$")
	mot = (mot or ""):lower()
	if mot == "" then
		if Opus.Fenetre then Opus.Fenetre() else Aide() end
		return
	end
	for _, c in ipairs(Opus.commandes) do
		if c.mot == mot then c.f(reste) return end
	end
	Aide()
end
Opus.Commande("aide", "aide", "cette liste", Aide)
