-- Opus.lua : socle de l'addon (base de données, liste de guilde, commandes)
local ADDON, Opus = ...
_G.Opus = Opus
Opus.version = "0.32.0"
Opus.build = "23 nov. 21h · kit visuel, fenêtres du butin et des joueurs, Ce soir, Ma liste"   -- la version du code en cours de route, entre deux sorties (/opus raid diag)

local DEFAUTS = {
	dureeEssai = { Apprenti = 14, Aspirant = 14 },
	arrivees = {},              -- [nom] = time() de l'arrivée vue en jeu
	montees = {},               -- [nom] = { depuis = grade d'essai, cible = grade visé } : promotions en cours
	banque = { evenements = {}, releve = 0, pairs = {} },   -- pairs : [membre] = dernier partage reçu de lui   -- opérations relevées dans les journaux de la banque (Banque.lua)
	page = "essais",            -- dernier onglet ouvert de la fenêtre
	configs = {},               -- [guilde] = grille de la guilde (Config.lua)
	vus = {},                   -- [membre] = première fois que l'addon l'a vu dans la guilde
	classes = {},               -- [membre] = sa classe, gardée après son départ (blasons du calendrier)
	alts = {},                  -- [personnage] = son joueur (le premier de ses personnages) : Cotisation.lua
	discord = {},               -- [guilde] = qui joue quels personnages, importé du bot Discord (Lien.lua)
	notes = {},                 -- [guilde] = { pub, off } : notes publiques et d'officier de l'addon (Notes.lua)
	niveaux = {},               -- [guilde] = { suivi, dings } : montées de niveau des membres (Niveaux.lua)
	envies = {},                -- [guilde] = { [id] = envie } : envies de donjon de la guilde (Envies.lua)
	contenu = {},               -- [guilde] = { [onglet] = photo de son contenu } (Contenu.lua)
	objets = {},                -- [id] = nom d'un objet vu à la banque, tant que le jeu ne le connaît pas
	registre = {},              -- [guilde] = { [id] = prêt, remboursement ou remise } (Registre.lua)
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

-- Un nom tel qu'Opus le range : « Prénom Nom », comme le roster. Sur Forever, il n'y a pas de royaume mais un nom de
-- famille, que le jeu écrit parfois après un tiret (« Basara-Nore ») ; un libellé de serveur collé à la fin est retiré.
-- Les prénoms ne sont pas uniques (Basara Auberdine, Basara Nore…) : ne jamais réduire un nom à son prénom.
local function SansEspaces (s) return (s:gsub("[%s%-]", "")):lower() end
function Opus.Court (nom)
	if type(nom) ~= "string" then return nil end
	nom = strtrim(nom)
	local avant, fin = nom:match("^(.+)%-([^%-]+)$")
	local serveur = GetRealmName and GetRealmName()
	if avant and serveur and serveur ~= "" and SansEspaces(fin) == SansEspaces(serveur) then nom = avant end
	return (nom:gsub("%-", " "))
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
				if classe then Opus.db.classes[m.nom] = classe end
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
	local prenom, famille = UnitName("player")
	return Opus.Court(famille and famille ~= "" and (prenom .. "-" .. famille) or prenom)
end

-- un expéditeur de message d'addon est-il ce membre ? (le jeu peut n'y mettre que le prénom) — pour vérifier un nom
-- annoncé dans le message ; pour trouver qui a écrit, Opus.Identifier, qui ne devine pas entre deux mêmes prénoms
function Opus.EstMembre (nom, expediteur)
	local court = Opus.Court(expediteur)
	if not nom or not court then return false end
	if nom == court then return true end
	local m = Opus.Identifier(expediteur, true)
	if m then return m.nom == nom end
	-- pas tranché (deux mêmes prénoms en ligne) : le prénom suffit pour vérifier un nom annoncé
	local prenom = court:match("^(%S+)")
	return nom:sub(1, #prenom + 1) == prenom .. " "
end

-- Le membre que désigne un nom (expéditeur, partenaire d'échange, saisie) : le nom complet d'abord ; un prénom seul
-- seulement s'il ne désigne qu'un membre, ou qu'un membre en ligne (souvent les personnages d'un même joueur).
-- Pour un expéditeur de message de guilde, forcément membre, le prénom compte aussi quand le jeu le fait suivre d'autre
-- chose qu'un nom de la guilde (un serveur qu'on ne reconnaît pas, par exemple).
-- Sinon nil : mieux vaut ignorer que mettre au compte d'un autre.
function Opus.Identifier (nom, expediteur)
	local court = Opus.Court(nom)
	if not court or court == "" then return nil end
	local bas = court:lower()
	local membres, tous, enLigne = Opus.Membres(), {}, {}
	for _, m in ipairs(membres) do
		if m.nom == court or m.nom:lower() == bas then return m end
	end
	if bas:find(" ", 1, true) then
		if not expediteur then return nil end
		bas = bas:match("^(%S+)")
	end
	for _, m in ipairs(membres) do
		if m.nom:lower():sub(1, #bas + 1) == bas .. " " then
			tous[#tous + 1] = m
			if m.enLigne then enLigne[#enLigne + 1] = m end
		end
	end
	if #tous == 1 then return tous[1] end
	if #enLigne == 1 then return enLigne[1] end
	return nil
end

-- le membre qui a envoyé un message d'addon
function Opus.TrouverExpediteur (expediteur)
	return Opus.Identifier(expediteur, true)
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
	-- 0.25.1 comptait deux fois l'achat d'un onglet : on oublie ces relevés, relus au prochain passage à la banque
	if not OpusDB.ongletsRelus then
		local garde = {}
		for _, e in ipairs(OpusDB.banque.evenements) do if e.q ~= "ong" then garde[#garde + 1] = e end end
		OpusDB.banque.evenements, OpusDB.ongletsRelus = garde, true
	end
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
