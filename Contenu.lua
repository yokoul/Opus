-- Contenu.lua : ce que contient la banque de guilde, onglet par onglet, visible sans y aller
-- Le jeu ne donne le contenu d'un onglet que banque ouverte, et seulement des onglets que le personnage peut voir.
-- À l'ouverture, l'addon demande chacun d'eux, en prend une photo (objets et quantités) et la partage à la guilde ; la
-- photo la plus récente de chaque onglet l'emporte. Un onglet lu vide alors qu'il ne l'était pas n'efface la photo que
-- s'il est affiché (sinon, ses données ne sont peut-être pas encore arrivées).
-- Un membre ne voit que les onglets que son grade peut voir d'après la grille de la guilde (Config.lua).
-- Messages : « I » (un onglet, en morceaux), « i » (demande de rattrapage à la connexion).
local _, Opus = ...

local FS = Opus.FS
local CASES = MAX_GUILDBANK_SLOTS_PER_TAB or 98
local ONGLETS_MAX = 8

local function Contenu ()
	local guilde = GetGuildInfo("player")
	if not guilde or not Opus.db then return nil end
	local c = Opus.db.contenu[guilde] or {}
	Opus.db.contenu[guilde] = c
	return c
end

-- le nom d'un objet : celui du jeu s'il le connaît, sinon celui retenu à la lecture d'un onglet
function Opus.NomObjet (id)
	local nom = GetItemInfo and GetItemInfo(id)
	if nom then return nom end
	return Opus.db.objets[id]
end

-- ce perso peut-il voir cet onglet, d'après la grille de la guilde ? (sans réglage pour cet onglet : oui)
function Opus.OngletVisible (tab)
	if Opus.PeutConfigurer() then return true end
	local c = Opus.Config()
	local _, _, rang = GetGuildInfo("player")
	local g = c and rang and c.grades[rang + 1]
	local o = g and g.onglets and g.onglets[tab]
	return not o or o.voir ~= false
end

-- les onglets photographiés que ce perso peut voir : [tab] = { t, par, nom, objets = { [id] = n } }
function Opus.OngletsBanque ()
	local liste = {}
	for tab, o in pairs(Contenu() or {}) do
		if Opus.OngletVisible(tab) then liste[tab] = o end
	end
	return liste
end

------------------------------------------------------------------------
-- partage
------------------------------------------------------------------------

local function Partager (tab)
	local o = (Contenu() or {})[tab]
	if not o or not IsInGuild() then return end
	local liste = {}
	for id, n in pairs(o.objets) do liste[#liste + 1] = id .. ":" .. n end
	table.sort(liste)
	local entete = table.concat({ "I", tab, o.t, Opus.MotMsg(o.par or "", 48), (Opus.MotMsg(o.nom or "", 24):gsub(",", " ")) }, FS)
	local place, morceaux, courant, taille = Opus.MAX_MSG - #entete - 12, {}, {}, 0
	for _, r in ipairs(liste) do
		if taille + #r + 1 > place then morceaux[#morceaux + 1] = courant courant, taille = {}, 0 end
		courant[#courant + 1] = r
		taille = taille + #r + 1
	end
	morceaux[#morceaux + 1] = courant
	for i, m in ipairs(morceaux) do
		Opus.Envoyer(table.concat({ entete, i, #morceaux, table.concat(m, ",") }, FS))
	end
end

local enCours = {}
Opus.recepteurs.I = function (_, champs, _, canal)
	local tab, t, par, nom, i, total = tonumber(champs[2]), tonumber(champs[3]), champs[4], champs[5], tonumber(champs[6]), tonumber(champs[7])
	if canal ~= "GUILD" or not tab or tab < 1 or tab > ONGLETS_MAX or not t or t > time() + 86400 or not i or not total or total < 1 or total > 20 then return end
	local c = Contenu()
	if not c or (c[tab] and c[tab].t >= t) then return end
	local cle = table.concat({ tab, t, par }, FS)
	local r = enCours[cle] or { morceaux = {} }
	enCours[cle] = r
	r.morceaux[i] = champs[8] or ""
	for k = 1, total do if not r.morceaux[k] then return end end
	enCours[cle] = nil
	if not Opus.TrouverMembre(par) then return end
	local objets = {}
	for k = 1, total do
		for a, b in r.morceaux[k]:gmatch("(%d+):(%d+)") do
			local id, n = tonumber(a), tonumber(b)
			if n > 0 and n < 100000 then objets[id] = n end
		end
	end
	c[tab] = { t = t, par = par, nom = nom ~= "" and nom or nil, objets = objets }
	if Opus.Rafraichir then Opus.Rafraichir() end
end

-- rattrapage : la date de chaque onglet du demandeur ; qui a plus récent renvoie ces onglets
Opus.recepteurs.i = function (_, champs, _, canal)
	if canal ~= "GUILD" then return end
	local siennes, a_envoyer = {}, {}
	for tab, t in (champs[2] or ""):gmatch("(%d+)=(%d+)") do siennes[tonumber(tab)] = tonumber(t) end
	for tab, o in pairs(Contenu() or {}) do
		if o.t > (siennes[tab] or 0) + 60 then a_envoyer[#a_envoyer + 1] = tab end
	end
	if #a_envoyer == 0 then return end
	Opus.Repondre(champs[3], "GUILD", function () for _, tab in ipairs(a_envoyer) do Partager(tab) end end)
end

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	C_Timer.After(60, function ()
		local c = Contenu()
		if not c or not IsInGuild() then return end
		local dates = {}
		for tab, o in pairs(c) do dates[#dates + 1] = tab .. "=" .. o.t end
		Opus.Envoyer(table.concat({ "i", table.concat(dates, ","), Opus.NouvelId() }, FS))
	end)
end)

------------------------------------------------------------------------
-- photo des onglets, banque ouverte
------------------------------------------------------------------------

local function Pareil (a, b)
	for id, n in pairs(a) do if b[id] ~= n then return false end end
	for id in pairs(b) do if not a[id] then return false end end
	return true
end

local function Photographier (tab, affiche)
	local nom, _, visible = GetGuildBankTabInfo(tab)
	if not visible then return end
	local objets, n = {}, 0
	for case = 1, CASES do
		local lien = GetGuildBankItemLink(tab, case)
		local id = lien and tonumber(lien:match("item:(%d+)"))
		if id then
			local _, nombre = GetGuildBankItemInfo(tab, case)
			objets[id] = (objets[id] or 0) + (nombre or 1)
			Opus.db.objets[id] = lien:match("%[(.-)%]") or Opus.db.objets[id]
			n = n + 1
		end
	end
	local c = Contenu()
	local ancien = c[tab]
	if n == 0 and not affiche and ancien and next(ancien.objets) then return end
	-- partagé si le contenu a changé, ou si la photo partagée date (les autres la croient vieille)
	local partager = not ancien or not Pareil(ancien.objets, objets) or ancien.nom ~= nom or time() - ancien.t > 3600
	c[tab] = { t = time(), par = Opus.MonNom(), nom = nom, objets = objets }
	if partager then Partager(tab) end
end

local demandes, attente = {}, nil
Opus.Ecoute("GUILDBANKBAGSLOTS_CHANGED", function ()
	if not Opus.banqueOuverte or not Opus.db or not GetGuildBankItemLink then return end
	if attente then attente:Cancel() end
	attente = C_Timer.NewTimer(1.5, function ()
		attente = nil
		if not Opus.banqueOuverte then return end
		local affiche = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
		if affiche then demandes[affiche] = true end
		for tab in pairs(demandes) do Photographier(tab, tab == affiche) end
		if Opus.Rafraichir then Opus.Rafraichir() end
	end)
end)

-- à l'ouverture : chaque onglet visible est demandé au serveur, un par un
local function Ouverte ()
	demandes = {}
	if not QueryGuildBankTab or not GetNumGuildBankTabs then return end
	for tab = 1, GetNumGuildBankTabs() or 0 do
		C_Timer.After(1 + tab * 0.6, function ()
			if not Opus.banqueOuverte then return end
			local _, _, visible = GetGuildBankTabInfo(tab)
			if visible then demandes[tab] = true QueryGuildBankTab(tab) end
		end)
	end
end
local GUILDBANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
Opus.Ecoute("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function (t) if t == GUILDBANKER then Ouverte() end end)
Opus.Ecoute("GUILDBANKFRAME_OPENED", Ouverte)

-- les noms et infobulles arrivent après coup : la vue se met à jour, une fois que ça se calme
local rafraichir
Opus.Ecoute("GET_ITEM_INFO_RECEIVED", function ()
	if rafraichir or not Opus.Rafraichir then return end
	rafraichir = C_Timer.NewTimer(0.5, function () rafraichir = nil Opus.Rafraichir() end)
end)

------------------------------------------------------------------------
-- utile pour moi : portable par sa classe, à son niveau, et peut-être mieux que ce qu'il porte
------------------------------------------------------------------------

-- armures (0 divers, 1 tissu, 2 cuir, 3 mailles, 4 plaques, 6 bouclier) et armes que chaque classe peut porter
local ARMURE = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local BOUCLIER = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local ARMES = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 }, WARLOCK = { 7, 10, 15, 19 },
	DRUID = { 4, 5, 10, 13, 15 },
}
local EMPLACEMENTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function Portable (classe, niveau, classID, sousClasse, emplacement)
	if classID == 4 then
		if sousClasse == 6 then return BOUCLIER[classe] == true end
		if sousClasse == 0 or emplacement == "INVTYPE_CLOAK" then return true end
		local max = ARMURE[classe] or 1
		-- mailles et plaques au niveau 40 seulement
		if max >= 3 and niveau < 40 then max = max - 1 end
		return sousClasse >= 1 and sousClasse <= max
	elseif classID == 2 then
		for _, s in ipairs(ARMES[classe] or {}) do if s == sousClasse then return true end end
		return false
	end
	return false
end

-- { rang (3 amélioration, 2 peut-être mieux, 1 bientôt), texte } ou nil si l'objet ne lui sert pas
function Opus.UtilePourMoi (id)
	if not GetItemInfo then return nil end
	local _, lien, _, ilvl, minNiveau, _, _, _, emplacement, _, _, classID, sousClasse = GetItemInfo(id)
	if not lien or (classID ~= 2 and classID ~= 4) or not EMPLACEMENTS[emplacement] then return nil end
	local _, classe = UnitClass("player")
	local niveau = UnitLevel("player")
	if not Portable(classe, niveau, classID, sousClasse, emplacement) then return nil end
	minNiveau = minNiveau or 0
	if minNiveau > niveau then
		return minNiveau <= niveau + 5 and { 1, ("au niveau %d"):format(minNiveau) } or nil
	end
	-- Pawn, s'il est là, sait si c'est une amélioration pour la spé du joueur
	if PawnShouldItemLinkHaveUpgradeArrow then
		local ok, oui = pcall(PawnShouldItemLinkHaveUpgradeArrow, lien)
		if ok and oui then return { 3, "amélioration (Pawn)" } end
		if ok then return nil end
	end
	-- sinon, le niveau d'objet face à ce qu'il porte au même emplacement (le plus faible des deux pour bagues, bijoux)
	local porte
	for _, case in ipairs(EMPLACEMENTS[emplacement]) do
		local l = GetInventoryItemLink("player", case)
		local n = l and select(4, GetItemInfo(l)) or 0
		porte = porte and math.min(porte, n) or n
	end
	if (ilvl or 0) > (porte or 0) then
		return { 2, porte and porte > 0 and ("niv. d'objet %d, tu portes %d"):format(ilvl, porte) or "emplacement vide" }
	end
	return nil
end
