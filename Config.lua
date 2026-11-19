-- Config.lua : la grille de la guilde du joueur, quelle qu'elle soit
-- Chaque guilde a sa configuration : pour chaque grade du jeu (par son numéro, le nom vient du jeu), son rôle, sa voie,
-- s'il est un essai et vers quels grades il mène, et les droits attendus. Chez Opus, elle part du préréglage de la
-- feuille ; ailleurs, des grades et des droits du jeu tels qu'ils sont. Le chef et les officiers la modifient
-- (PageGrades.lua) et elle se partage aux membres qui ont l'addon (Partage.lua). D'elle découlent Opus.GRADES,
-- Opus.SORTIES et Opus.BLOCS, que le reste de l'addon lit.
local _, Opus = ...

Opus.GRADES, Opus.SORTIES, Opus.BLOCS, Opus.ONGLETS = {}, {}, {}, {}

function Opus.Copie (t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = Opus.Copie(v) end
	return c
end

local function NomGuilde () return IsInGuild() and GetGuildInfo("player") or nil end

local function NomsDuJeu ()
	local noms = {}
	for i = 1, GuildControlGetNumRanks() or 0 do noms[i] = GuildControlGetRankName(i) end
	return noms
end

-- point de départ d'une guilde qui n'a pas encore de grille : ses grades et leurs droits tels qu'ils sont en jeu
local function DepuisLeJeu ()
	local grades = {}
	for i = 1, GuildControlGetNumRanks() or 0 do
		local g = { role = "", sorties = {}, or_ = 0 }
		local f = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags and C_GuildInfo.GuildControlGetRankFlags(i)
		if f then
			for _, d in ipairs(Opus.DROITS) do
				if d.cle ~= "ecouter" and d.cle ~= "parler" and d.cle ~= "retraitOr" then g[d.cle] = f[d.id] and true or nil end
			end
		end
		grades[i] = g
	end
	return { version = 0, grades = grades, onglets = {} }
end

-- la configuration de la guilde courante, créée à la première visite
function Opus.Config ()
	local guilde = NomGuilde()
	if not guilde or not Opus.db then return nil end
	local c = Opus.db.configs[guilde]
	if not c and (GuildControlGetNumRanks() or 0) > 0 then
		local noms = NomsDuJeu()
		-- chez Opus (mêmes grades que la feuille), le préréglage ; ailleurs, l'état du jeu
		local pre = Opus.PreReglageOpus()
		local opus = guilde == "Opus" and #noms == #pre.grades
		for i, g in ipairs(pre.grades) do opus = opus and noms[i] == g.nom end
		c = opus and pre or DepuisLeJeu()
		Opus.db.configs[guilde] = c
	end
	return c
end

-- Opus.GRADES (avec les noms du jeu), Opus.SORTIES (par nom), Opus.BLOCS (les essais) à partir de la configuration
function Opus.AppliquerConfig ()
	local c = Opus.Config()
	local grades, sorties, blocs = {}, {}, {}
	if c then
		local noms = NomsDuJeu()
		for i = 1, #noms do
			local g = Opus.Copie(c.grades[i] or { role = "", sorties = {} })
			g.nom = noms[i]
			grades[i] = g
		end
		for i, g in ipairs(grades) do
			if g.sorties and #g.sorties > 0 then
				sorties[g.nom] = {}
				for _, j in ipairs(g.sorties) do
					if grades[j] then table.insert(sorties[g.nom], grades[j].nom) end
				end
			end
			if g.essai then blocs[#blocs + 1] = g end
		end
		-- essais guilde d'abord (on entre par la guilde), puis essais raid
		table.sort(blocs, function (a, b)
			if a.essai ~= b.essai then return a.essai == "guilde" end
			return a.nom < b.nom
		end)
		for i, g in ipairs(blocs) do blocs[i] = g.nom end
	end
	Opus.GRADES, Opus.SORTIES, Opus.BLOCS = grades, sorties, blocs
	Opus.ONGLETS = c and c.onglets or {}
	if Opus.Rafraichir then Opus.Rafraichir() end
end

-- le nom d'une voie en clair (« Tour » : « voie du Tour ») ; une voie est un mot libre, Tour et Atelier chez Opus
local VOIES = { Tour = "voie du Tour", Atelier = "voie de l'Atelier" }
function Opus.NomVoie (v)
	if not v or v == "" then return nil end
	return VOIES[v] or ("voie : " .. v)
end

function Opus.RangDe (nomGrade)
	for i, g in ipairs(Opus.GRADES) do if g.nom == nomGrade then return i end end
	return nil
end

-- une restriction temporaire (chez Opus : avant l'ouverture des raids)
function Opus.Restriction ()
	local c = Opus.Config()
	local r = c and c.restriction
	if r and r.fin and time() < r.fin then return r end
	return nil
end
function Opus.AvantRaids () return Opus.Restriction() ~= nil end

-- ce qu'on attend d'un grade (2..n) aujourd'hui
function Opus.Attendu (rang)
	local g = Opus.GRADES[rang]
	if not g or rang < 2 then return nil end
	local a = {
		ecouter = true, parler = true,
		officier = g.officier or false, inviter = g.inviter or false,
		promouvoir = g.promouvoir or false, retrograder = g.retrograder or false, exclure = g.exclure or false,
		reparer = g.reparer or false, retraitOr = (g.or_ or 0) > 0, or_ = g.or_ or 0,
		onglets = g.onglets,
	}
	-- une restriction coupe les réparations et/ou les retraits d'or (les deux, sauf réglage contraire)
	local r = Opus.Restriction()
	if r then
		if r.coupeRep ~= false then a.reparer = false end
		if r.coupeOr ~= false then a.retraitOr, a.or_ = false, 0 end
	end
	return a
end

-- qui peut modifier la grille : le chef, et les grades « officier » en jeu
function Opus.PeutConfigurer (rang)
	if rang == nil then
		if IsGuildLeader() then return true end
		local _, _, r = GetGuildInfo("player")
		rang = r and r + 1
	end
	if rang == 1 then return true end
	local f = rang and C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags and C_GuildInfo.GuildControlGetRankFlags(rang)
	return f and f[22] and true or false
end

-- enregistre une modification locale : nouvelle version, partagée aux membres
function Opus.EnregistrerConfig (c)
	if not Opus.PeutConfigurer() then Opus.Msg("seuls le chef et les officiers modifient la grille.") return end
	c.version = time()
	c.par = Opus.MonNom()
	Opus.db.configs[NomGuilde()] = c
	Opus.AppliquerConfig()
	if Opus.PartagerConfig then Opus.PartagerConfig() end
end

-- reprend l'état du jeu : grades et droits tels qu'ils sont (rôles et voies conservés quand le grade existe encore)
function Opus.ReprendreLeJeu ()
	local ancienne, neuve = Opus.Config(), DepuisLeJeu()
	for i, g in ipairs(neuve.grades) do
		local a = ancienne and ancienne.grades[i]
		if a then g.role, g.voie, g.essai, g.desc, g.sorties, g.or_, g.onglets = a.role, a.voie, a.essai, a.desc, a.sorties, a.or_, a.onglets end
	end
	neuve.onglets = ancienne and ancienne.onglets or {}
	neuve.restriction = ancienne and ancienne.restriction
	neuve.cotisation = ancienne and ancienne.cotisation
	neuve.durees = ancienne and ancienne.durees
	Opus.EnregistrerConfig(neuve)
end

Opus.Ecoute("PLAYER_ENTERING_WORLD", function () if Opus.db then Opus.AppliquerConfig() end end)
Opus.Ecoute("GUILD_ROSTER_UPDATE", function () if Opus.db then Opus.AppliquerConfig() end end)
Opus.Ecoute("GUILD_RANKS_UPDATE", function () if Opus.db then Opus.AppliquerConfig() end end)
Opus.Ecoute("PLAYER_GUILD_UPDATE", function () if Opus.db then Opus.AppliquerConfig() end end)
