-- Envies.lua : les envies de donjon. Un membre annonce qu'il veut faire un ou plusieurs donjons (pour des quêtes, des
-- objets, de l'expérience), quand il est disponible (maintenant, ce soir, ce week-end, ou une précision libre) et pour
-- combien de temps l'envie reste affichée (3 jours par défaut). « Moi aussi » publie la même envie pour soi. Toute la
-- guilde voit toutes les envies (un reroll peut être du bon niveau) ; une notification annonce les nouvelles, et prévient
-- quand assez de monde est disponible maintenant pour former un groupe.
-- Messages : « V » (une envie, publiée, modifiée ou retirée : une fin passée la retire), « e » (rattrapage à la connexion),
-- « F » (donjon fait : ceux du groupe qui y avaient une envie la retirent).
local _, Opus = ...

local FS = Opus.FS
local DONJONS_MAX = 3
local MAINTENANT = 2 * 3600        -- « maintenant » vaut deux heures
local ENVIES_MAX = 60              -- envies renvoyées au plus pour une demande

Opus.CRENEAUX = { { "maintenant", "Maintenant" }, { "soir", "Ce soir" }, { "weekend", "Ce week-end" }, { "autre", "Autre (préciser)" } }
Opus.DUREES_ENVIE = { { "soir", "Jusqu'à ce soir" }, { "24h", "24 heures" }, { "3j", "3 jours" }, { "7j", "7 jours" } }
Opus.POURQUOI = { { "quetes", "Quêtes" }, { "objets", "Objets" }, { "xp", "Expérience" } }
local BITS = { quetes = 1, objets = 2, xp = 4 }
-- « PL accepté » : le groupe veut bien d'un grand (un 60…) pour le booster, quitte à perdre l'XP des monstres ; dans le
-- même champ que les raisons, un bit que les versions d'avant ignorent
local BIT_PL = 8
local NOMS_CRENEAUX = {}
for _, c in ipairs(Opus.CRENEAUX) do NOMS_CRENEAUX[c[1]] = c[2] end

------------------------------------------------------------------------
-- les donjons : ceux de Dungeon Journal s'il est installé, sinon ceux de Forever retenus ici
------------------------------------------------------------------------

-- Les donjons de Forever : clé (celle de Dungeon Journal), activité de la recherche de groupe du jeu, nom et tranche
-- recommandée tels que le jeu les donne (relevés par /opus diagdonjons le 19/11/2026, client français ; ce sont aussi les
-- tranches de Dungeon Journal, qui les tient du jeu). En jeu, l'addon relit le nom et la tranche de chaque activité, au
-- cas où une mise à jour les change. Le jeu n'impose aucun niveau pour entrer (minimum 0 partout). La Prison n'apparaît
-- pas dans la recherche de groupe d'un personnage de la Horde : sa tranche vient de Dungeon Journal. Le sommet du pic
-- Rochenoire se fait à 10.
local FOREVER = {
	{ "Ragefire Chasm", 798, "Gouffre de Ragefeu", 13, 18 }, { "Hall of Thanes", 1984, "La salle des Thanes", 13, 20 },
	{ "Ruins of Lordaeron", 1982, "Ruines de Lordaeron", 15, 22 }, { "Wailing Caverns", 796, "Cavernes des lamentations", 15, 24 },
	{ "The Deadmines", 799, "Mortemines", 17, 26 }, { "Shadowfang Keep", 800, "Donjon d'Ombrecroc", 20, 30 },
	{ "The Stockade", nil, "La Prison", 24, 32 }, { "Blackfathom Deeps", 801, "Profondeurs de Brassenoire", 24, 32 },
	{ "Excavation Site: Wetlands", 1981, "Excavations : les Paluns", 26, 33 }, { "City of Dalaran", 1983, "Cité de Dalaran", 28, 35 },
	{ "Gnomeregan", 803, "Gnomeregan", 29, 38 }, { "Razorfen Kraul", 804, "Kraal de Tranchebauge", 29, 38 },
	{ "Scarlet Monastery: Graveyard", 805, "Monastère Écarlate (cimetière)", 30, 38 },
	{ "Scarlet Monastery: Library", 829, "Monastère Écarlate (bibliothèque)", 33, 41 },
	{ "The Drowned City", 1985, "La cité Submergée", 35, 42 },
	{ "Scarlet Monastery: Armory", 827, "Monastère Écarlate (armurerie)", 36, 44 },
	{ "Razorfen Downs", 806, "Souilles de Tranchebauge", 37, 46 },
	{ "Scarlet Monastery: Cathedral", 828, "Monastère Écarlate (cathédrale)", 38, 46 },
	{ "Krol'dok Stronghold", 1986, "Bastion Krol'dok", 40, 47 }, { "Uldaman", 807, "Uldaman", 41, 51 },
	{ "Zul'Farrak", 808, "Zul'Farrak", 44, 54 }, { "Maraudon", 809, "Maraudon", 46, 55 }, { "Alcaz Prison", 1980, "Prison d'Alcaz", 48, 55 },
	{ "Sunken Temple", 810, "Temple Englouti", 50, 60 }, { "Blackrock Depths", 811, "Profondeurs de Rochenoire", 52, 60 },
	{ "Dire Maul: East", 813, "Haches-Tripes (est)", 54, 60 }, { "Blackmaw Hold", 1979, "Repaire des Noiregueules", 55, 60 },
	{ "Lower Blackrock Spire", 812, "Bas du pic Rochenoire", 55, 60 }, { "Dire Maul: West", 814, "Haches-Tripes (ouest)", 56, 60 },
	{ "Dire Maul: North", 815, "Haches-Tripes (nord)", 56, 60 }, { "Shaper's Terrace", 1978, "La terrasse du Façonneur", 58, 60 },
	{ "Scholomance", 797, "Scholomance", 58, 60 }, { "Stratholme: Living", 816, "Stratholme (porte principale)", 58, 60 },
	{ "Stratholme: Undead", 1603, "Stratholme (porte de service)", 58, 60 }, { "Upper Blackrock Spire", 837, "Sommet du pic Rochenoire", 59, 60 },
}
local CONNUS = {}
for _, d in ipairs(FOREVER) do CONNUS[d[1]] = d end

-- ce que le jeu dit d'une activité (nom traduit, tranche, niveau pour entrer), lu une fois par session
local lus = {}
local function DuJeu (activite)
	if not activite then return nil end
	if lus[activite] == nil then
		local L = C_LFGList
		local ok, a = false, nil
		if L and L.GetActivityInfoTable then ok, a = pcall(L.GetActivityInfoTable, activite) end
		lus[activite] = ok and type(a) == "table" and a.fullName and a or false
	end
	return lus[activite] or nil
end

-- tous les donjons : { cle, nom, min, max, entree }, du plus bas au plus haut ; entree = niveau pour entrer, si le jeu en
-- impose un
function Opus.TousLesDonjons ()
	local liste = {}
	for _, x in ipairs(FOREVER) do
		local d = { cle = x[1], nom = x[3], min = x[4], max = x[5], activite = x[2] }
		local a = DuJeu(x[2])
		if a then
			d.nom = a.fullName
			if (a.minLevelSuggestion or 0) > 0 and (a.maxLevelSuggestion or 0) >= a.minLevelSuggestion then d.min, d.max = a.minLevelSuggestion, a.maxLevelSuggestion end
			if (a.minLevel or 0) > 0 then d.entree = a.minLevel end
		end
		liste[#liste + 1] = d
	end
	table.sort(liste, function (x, y) if x.min ~= y.min then return x.min < y.min end return x.nom < y.nom end)
	return liste
end

Opus.Commande("diagdonjons", "diagdonjons", "les donjons tels que le jeu les donne (niveau d'entrée, tranche recommandée)", function ()
	lus = {}
	-- tout part dans les données sauvegardées (OpusDB.diagDonjons), lisibles après un /reload : la liste est trop longue
	-- pour la discussion
	local sans = {}
	for _, d in ipairs(FOREVER) do if not DuJeu(d[2]) then sans[#sans + 1] = d[1] end end
	local brut = {}
	local L = C_LFGList
	if L and L.GetAvailableActivities and L.GetActivityInfoTable then
		for _, categorie in ipairs { 1, 2, 3 } do
			local ok, ids = pcall(L.GetAvailableActivities, categorie)
			for _, id in ipairs(ok and ids or {}) do
				local ok2, a = pcall(L.GetActivityInfoTable, id)
				if ok2 and type(a) == "table" then
					local copie = { id = id, categorie = categorie }
					for k, v in pairs(a) do if type(v) ~= "table" and type(v) ~= "function" then copie[k] = v end end
					brut[#brut + 1] = copie
				end
			end
		end
	end
	Opus.db.diagDonjons = { t = time(), version = Opus.version, brut = brut, sansActivite = sans,
		api = { C_LFGList = C_LFGList ~= nil, GetAvailableActivities = L and L.GetAvailableActivities ~= nil } }
	Opus.Msg(("%d activité(s) lues dans le jeu ; %d donjon(s) de la liste sans activité reconnue. "):format(#brut, #sans)
		.. "Détail enregistré : fais /reload pour l'écrire sur le disque.")
end)

function Opus.DonjonDe (cle)
	for _, d in ipairs(Opus.TousLesDonjons()) do if d.cle == cle then return d end end
	return { cle = cle, nom = cle }
end

------------------------------------------------------------------------
-- les envies : db.envies[guilde][id] = { id, par, m, fin, donjons = { cle }, pourquoi = { quetes = true }, creneau,
-- precision, note, roles, suite, pl }
------------------------------------------------------------------------

local function Donnees ()
	local guilde = GetGuildInfo("player")
	if not guilde or not Opus.db then return nil end
	local d = Opus.db.envies[guilde] or {}
	Opus.db.envies[guilde] = d
	return d
end

-- les envies en cours, les plus récentes d'abord ; les envies finies sont oubliées au passage
function Opus.Envies ()
	local d, maintenant, liste = Donnees(), time(), {}
	if not d then return liste end
	for id, e in pairs(d) do
		if e.fin <= maintenant then d[id] = nil else liste[#liste + 1] = e end
	end
	table.sort(liste, function (a, b) return a.m > b.m end)
	return liste
end

-- la fin d'une envie, selon la durée choisie
function Opus.FinEnvie (duree)
	local maintenant = time()
	if duree == "soir" then
		local d = date("*t", maintenant)
		-- tard le soir, elle dure au moins autant que « maintenant »
		return math.max(time({ year = d.year, month = d.month, day = d.day, hour = 23, min = 59 }), maintenant + MAINTENANT)
	end
	return maintenant + (duree == "24h" and 86400 or duree == "7j" and 7 * 86400 or 3 * 86400)
end

-- la durée qui va avec un créneau : « maintenant » et « ce soir » finissent ce soir, le reste dure 3 jours
function Opus.DureePourCreneau (creneau)
	return (creneau == "maintenant" or creneau == "soir") and "soir" or "3j"
end

-- un donjon où une envie accepte le PL : un grand y est bienvenu pour booster
function Opus.PLAccepte (cle)
	for _, e in ipairs(Opus.Envies()) do
		if e.pl then for _, c in ipairs(e.donjons) do if c == cle then return true end end end
	end
	return false
end

-- est-il disponible maintenant ? (« maintenant » vaut deux heures)
function Opus.DispoMaintenant (e) return e.creneau == "maintenant" and time() - e.m <= MAINTENANT end

-- le créneau en clair
function Opus.TexteCreneau (e)
	local t
	if e.creneau == "maintenant" then
		t = Opus.DispoMaintenant(e) and Opus.Vert("maintenant") or Opus.Gris("dispo il y a " .. Opus.Depuis(math.floor((time() - e.m) / 3600)))
	else
		t = (NOMS_CRENEAUX[e.creneau] or ""):lower()
		if e.creneau == "autre" then t = "" end
	end
	if e.precision and e.precision ~= "" then t = t ~= "" and (t .. ", " .. e.precision) or e.precision end
	return t
end

function Opus.TextePourquoi (e)
	local morceaux = {}
	for _, p in ipairs(Opus.POURQUOI) do if e.pourquoi[p[1]] then morceaux[#morceaux + 1] = p[2]:lower() end end
	return table.concat(morceaux, ", ")
end

------------------------------------------------------------------------
-- partage
------------------------------------------------------------------------

local function Encoder (e)
	local bits = 0
	for cle, b in pairs(BITS) do if e.pourquoi[cle] then bits = bits + b end end
	if e.pl then bits = bits + BIT_PL end
	local donjons = {}
	for _, cle in ipairs(e.donjons) do donjons[#donjons + 1] = (Opus.MotMsg(cle, 40):gsub(",", " ")) end
	local debut = table.concat({ "V", e.id, Opus.MotMsg(e.par, 48), e.m, e.fin, table.concat(donjons, ","), bits, e.creneau,
		e.roles or "", e.suite and 1 or 0, "" }, FS)
	local precision = Opus.CoupeMsg(Opus.MotMsg(e.precision or "", 40), math.max(0, Opus.MAX_MSG - #debut - 4))
	debut = debut .. precision .. FS
	return debut .. Opus.MotMsg(e.note or "", math.max(0, Opus.MAX_MSG - #debut))
end

local function Envoyer (e) Opus.Envoyer(Encoder(e)) end

local function Notifier (e)
	if Opus.db.notifEnvies == "aucune" then return end
	local m = Opus.TrouverMembre(e.par)
	local nom = (m and Opus.Couleur(m.classe) or "") .. e.par .. (m and "|r" or "")
	local donjons = {}
	for _, cle in ipairs(e.donjons) do donjons[#donjons + 1] = Opus.DonjonDe(cle).nom end
	local detail = { Opus.TexteCreneau(e) }
	local pourquoi = Opus.TextePourquoi(e)
	if pourquoi ~= "" then detail[#detail + 1] = pourquoi end
	if e.pl then detail[#detail + 1] = "PL accepté" end
	Opus.Notification(e.suite and "Partant pour un donjon" or "Envie de donjon",
		nom .. (e.suite and " est partant pour " or " cherche ") .. Opus.Blanc(table.concat(donjons, ", ")) .. "\n" .. Opus.Gris(table.concat(detail, " · ")),
		function () Opus.OuvrirEnvies() end)
end

-- une envie reçue ou publiée : retenue si elle est plus récente que celle qu'on a ; renvoie true si elle change
local function Retenir (e, annoncer)
	local d = Donnees()
	if not d then return false end
	local locale = d[e.id]
	if locale and locale.m >= e.m then return false end
	local nouvelle = not locale
	d[e.id] = e
	if e.fin <= time() then d[e.id] = nil end
	if annoncer and nouvelle and e.fin > time() and e.par ~= Opus.MonNom() then Notifier(e) end
	return true
end

Opus.recepteurs.V = function (_, champs, expediteur, canal)
	if canal ~= "GUILD" then return end
	local id, par, m, fin, donjons, bits = champs[2], champs[3], tonumber(champs[4]), tonumber(champs[5]), champs[6] or "", tonumber(champs[7]) or 0
	local creneau, roles, suite, precision, note = champs[8], champs[9], champs[10] == "1", champs[11], champs[12]
	-- une envie vient de son auteur, ou d'un membre qui la renvoie pour un rattrapage
	local auteur = par and Opus.TrouverMembre(par)
	if not id or id == "" or #id > 12 or not auteur or not m or not fin or m > time() + 86400 or fin > m + 8 * 86400 then return end
	if not NOMS_CRENEAUX[creneau] then return end
	local e = { id = id, par = auteur.nom, m = m, fin = fin, donjons = {}, pourquoi = {}, creneau = creneau,
		precision = precision ~= "" and precision or nil, note = note ~= "" and note or nil, suite = suite or nil }
	for cle in donjons:gmatch("[^,]+") do if #e.donjons < DONJONS_MAX then e.donjons[#e.donjons + 1] = cle end end
	if #e.donjons == 0 then return end
	for cle, b in pairs(BITS) do if bit.band(bits, b) ~= 0 then e.pourquoi[cle] = true end end
	e.pl = bit.band(bits, BIT_PL) ~= 0 or nil
	local r = table.concat(Opus.ListeRoles(roles), ",")
	e.roles = r ~= "" and r or nil
	-- seul l'auteur publie ou retire son envie ; les autres ne font que la renvoyer telle quelle (rattrapage)
	local direct = Opus.EstMembre(auteur.nom, expediteur)
	if Retenir(e, direct) then
		if Opus.VerifierGroupes then Opus.VerifierGroupes() end
		if Opus.Rafraichir then Opus.Rafraichir() end
	end
end

-- une demande de rattrapage : on renvoie les envies en cours
Opus.recepteurs.e = function (_, champs, _, canal)
	if canal ~= "GUILD" then return end
	local envies = Opus.Envies()
	if #envies == 0 then return end
	while #envies > ENVIES_MAX do table.remove(envies) end
	Opus.Repondre(champs[2], "GUILD", function () for _, e in ipairs(envies) do Envoyer(e) end end)
end

------------------------------------------------------------------------
-- publier, retirer
------------------------------------------------------------------------

function Opus.MesRoles ()
	-- sa spé retenue, sinon celle qu'on lit à l'instant (la publication n'a peut-être pas encore eu lieu)
	local s = Opus.db.spes[Opus.MonNom()] or (Opus.MaSpe and Opus.MaSpe())
	if s and not s.role then s = { arbre = s.arbre, role = Opus.db.monRole } end
	local liste = s and Opus.RolesDe(s) or Opus.ListeRoles(Opus.db.monRole)
	return #liste > 0 and table.concat(liste, ",") or nil
end

-- publie une envie : { donjons, pourquoi, creneau, precision, note, duree, suite, pl }
function Opus.PublierEnvie (x)
	if not IsInGuild() or #x.donjons == 0 then return end
	local e = {
		id = Opus.NouvelId(), par = Opus.MonNom(), m = time(), fin = Opus.FinEnvie(x.duree),
		donjons = {}, pourquoi = x.pourquoi or {},
		creneau = x.creneau or "maintenant", precision = x.precision, note = x.note, roles = x.roles or Opus.MesRoles(), suite = x.suite,
		pl = x.pl or nil,
	}
	for i = 1, math.min(#x.donjons, DONJONS_MAX) do e.donjons[i] = x.donjons[i] end
	-- elle remplace ses envies précédentes qui ne portaient que sur ces donjons-là (un nouveau créneau, pas un doublon)
	local nouveaux = {}
	for _, cle in ipairs(e.donjons) do nouveaux[cle] = true end
	for _, ancienne in ipairs(Opus.Envies()) do
		if ancienne.par == e.par then
			local incluse = true
			for _, cle in ipairs(ancienne.donjons) do if not nouveaux[cle] then incluse = false end end
			if incluse then Opus.RetirerEnvie(ancienne.id) end
		end
	end
	Retenir(e)
	Envoyer(e)
	Opus.Msg("envie publiée : la guilde est prévenue.")
	if Opus.VerifierGroupes then Opus.VerifierGroupes() end
	if Opus.Rafraichir then Opus.Rafraichir() end
end

-- une version modifiée de sa propre envie, partagée (même identifiant, plus récente)
local function Republier (e, champs)
	local d = Donnees()
	local nouvelle = Opus.Copie(e)
	for k, v in pairs(champs) do nouvelle[k] = v end
	if champs.roles == false then nouvelle.roles = Opus.MesRoles() end
	if champs.pl == false then nouvelle.pl = nil end
	nouvelle.m = math.max(time(), e.m + 1)
	if champs.creneau then nouvelle.fin = math.max(e.fin, Opus.FinEnvie(Opus.DureePourCreneau(champs.creneau))) end
	if nouvelle.fin <= nouvelle.m then d[e.id] = nil else d[e.id] = nouvelle end
	Envoyer(nouvelle)
	return nouvelle
end

-- sa propre envie, sans ce donjon-là (elle en couvre d'autres) ; renvoie false si c'était son seul donjon
local function Detacher (e, cle)
	if #e.donjons <= 1 then return false end
	local reste = {}
	for _, c in ipairs(e.donjons) do if c ~= cle then reste[#reste + 1] = c end end
	Republier(e, { donjons = reste })
	return true
end

local function Apres ()
	if Opus.VerifierGroupes then Opus.VerifierGroupes() end
	if Opus.Rafraichir then Opus.Rafraichir() end
end

-- modifie sa propre envie (rôles, créneau). Avec cle, pour ce donjon seulement : si l'envie en couvre plusieurs, ce
-- donjon en est détaché et devient une envie à lui (même raison, même note), les autres gardent l'envie d'origine.
function Opus.ModifierEnvie (id, champs, cle)
	local d = Donnees()
	local e = d and d[id]
	if not e or e.par ~= Opus.MonNom() then return end
	if cle and Detacher(e, cle) then
		local seule = Opus.Copie(e)
		seule.id, seule.donjons = Opus.NouvelId(), { cle }
		Republier(seule, champs)
	else
		Republier(e, champs)
	end
	Apres()
end

-- retire sa propre envie ; avec cle, ce donjon seulement (les autres restent)
function Opus.RetirerEnvie (id, cle)
	local d = Donnees()
	local e = d and d[id]
	if not e or e.par ~= Opus.MonNom() then return end
	if not (cle and Detacher(e, cle)) then Republier(e, { fin = math.max(time(), e.m + 1) }) end
	Apres()
end

-- donjon fait : on retire son envie, et on prévient les membres de son groupe qui en avaient une sur ce donjon, pour
-- qu'ils retirent la leur (seul l'auteur d'une envie peut la retirer)
local function MesEnviesSur (cle)
	local moi, liste = Opus.MonNom(), {}
	for _, e in ipairs(Opus.Envies()) do
		if e.par == moi then for _, c in ipairs(e.donjons) do if c == cle then liste[#liste + 1] = e break end end end
	end
	return liste
end

-- les membres de la guilde dans son groupe, qui ont une envie sur ce donjon
function Opus.GroupeAvecEnvie (cle)
	local interesses, noms = {}, {}
	for _, e in ipairs(Opus.Envies()) do
		for _, c in ipairs(e.donjons) do if c == cle then interesses[e.par] = true end end
	end
	local moi = Opus.MonNom()
	for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
		local unite = "party" .. i
		local guid, nom = UnitGUID(unite), UnitName(unite)
		for _, m in ipairs(Opus.Membres()) do
			if (guid and m.guid == guid) or (not m.guid and Opus.EstMembre(m.nom, nom)) then
				if interesses[m.nom] and m.nom ~= moi then noms[#noms + 1] = m.nom end
				break
			end
		end
	end
	return noms
end

function Opus.DonjonFait (cle)
	for _, e in ipairs(MesEnviesSur(cle)) do Opus.RetirerEnvie(e.id, cle) end
	local noms, morceaux = Opus.GroupeAvecEnvie(cle), {}
	if #noms > 0 then
		local debut = table.concat({ "F", (Opus.MotMsg(cle, 40):gsub(",", " ")), "" }, FS)
		for _, n in ipairs(noms) do
			local mot = (Opus.MotMsg(n, 48):gsub(",", " "))
			if #debut + #table.concat(morceaux, ",") + #mot + 1 <= Opus.MAX_MSG then morceaux[#morceaux + 1] = mot end
		end
		Opus.Envoyer(debut .. table.concat(morceaux, ","))
	end
	local nom = Opus.DonjonDe(cle).nom
	if #morceaux > 0 then
		Opus.Msg(("%s fait : ton envie est retirée, et celles de %s le seront aussi (s'ils ont l'addon à jour)."):format(nom, table.concat(morceaux, ", ")))
	else
		Opus.Msg(("%s fait : ton envie est retirée."):format(nom))
	end
	Apres()
end

Opus.recepteurs.F = function (_, champs, expediteur, canal)
	if canal ~= "GUILD" or not Opus.TrouverExpediteur(expediteur) then return end
	local cle, moi = champs[2], Opus.MonNom()
	if not cle or cle == "" then return end
	for n in (champs[3] or ""):gmatch("[^,]+") do
		if n == moi then
			local miennes = MesEnviesSur(cle)
			for _, e in ipairs(miennes) do Opus.RetirerEnvie(e.id, cle) end
			if #miennes > 0 then
				local par = Opus.TrouverExpediteur(expediteur)
				Opus.Msg(("%s a marqué %s comme fait : ton envie est retirée."):format(par.nom, Opus.DonjonDe(cle).nom))
				Apres()
			end
			return
		end
	end
end

------------------------------------------------------------------------
-- groupes possibles : assez de monde disponible maintenant, en ligne, pour un même donjon
------------------------------------------------------------------------

-- les joueurs disponibles maintenant pour un donjon, et la composition qu'on en tire : places[i] = nom ; avec tous,
-- tous les intéressés, quel que soit leur créneau (la composition prévue)
function Opus.CompositionPossible (cle, tous)
	local dispo, vus = {}, {}
	for _, e in ipairs(Opus.Envies()) do
		local m = Opus.TrouverMembre(e.par)
		if not vus[e.par] and m and (tous or (m.enLigne and Opus.DispoMaintenant(e))) then
			for _, c in ipairs(e.donjons) do
				if c == cle then vus[e.par] = true dispo[#dispo + 1] = { nom = e.par, roles = Opus.ListeRoles(e.roles) } break end
			end
		end
	end
	-- d'abord les rôles rares : tank, puis soin, parmi ceux qui ont le moins de rôles ; puis les dégâts
	table.sort(dispo, function (a, b) return #a.roles < #b.roles end)
	local places, pris = {}, {}
	for i, r in ipairs(Opus.PLACES) do
		for _, j in ipairs(dispo) do
			if not pris[j.nom] then
				local ok = #j.roles == 0 and r == "degats"
				for _, x in ipairs(j.roles) do if x == r then ok = true end end
				if ok then places[i] = j.nom pris[j.nom] = true break end
			end
		end
	end
	return dispo, places
end

local prevenus = {}      -- [donjon] = composition déjà annoncée
function Opus.VerifierGroupes ()
	local moi = Opus.MonNom()
	local donjons = {}
	for _, e in ipairs(Opus.Envies()) do for _, c in ipairs(e.donjons) do donjons[c] = true end end
	for cle in pairs(donjons) do
		local _, places = Opus.CompositionPossible(cle)
		local complet, moiDedans, noms = true, false, {}
		for i = 1, #Opus.PLACES do
			if not places[i] then complet = false end
			if places[i] == moi then moiDedans = true end
			noms[#noms + 1] = places[i] or ""
		end
		local signature = table.concat(noms, ",")
		if complet and moiDedans and prevenus[cle] ~= signature and Opus.db.notifEnvies ~= "aucune" then
			prevenus[cle] = signature
			Opus.Notification("Groupe complet possible", Opus.Blanc(Opus.DonjonDe(cle).nom) .. " : tank, soigneur et dégâts sont disponibles maintenant.\n"
				.. Opus.Gris("Clic : former le groupe."), function () Opus.FormerDepuisEnvie(cle) end)
		end
	end
end

-- remplit le panneau de groupe avec les joueurs disponibles pour ce donjon
function Opus.FormerDepuisEnvie (cle)
	local dispo, places = Opus.CompositionPossible(cle)
	local d = Opus.DonjonDe(cle)
	Opus.ViderGroupe()
	if d.min then Opus.ChoisirDonjon(d) end
	for i = 1, #Opus.PLACES do if places[i] then Opus.groupe.places[i] = places[i] end end
	for _, j in ipairs(dispo) do
		local m = Opus.TrouverMembre(j.nom)
		if m then Opus.AjouterAuGroupe(m) end
	end
	Opus.OuvrirGroupe()
end

------------------------------------------------------------------------
-- la notification : une petite fenêtre en haut de l'écran, 10 secondes par défaut (onglet Réglages ; 0 = jusqu'au clic).
-- Clic droit : la passer ; maj + clic droit : passer aussi celles en attente.
------------------------------------------------------------------------

local toast, file = nil, {}
local function Duree () return Opus.db and Opus.db.dureeNotif or 10 end
local function Aide () toast.aide:SetText(#file > 0 and ("clic droit : passer · %d en attente"):format(#file) or "clic droit : passer") end
local function Suivante ()
	local n = table.remove(file, 1)
	if not n then toast:Hide() return end
	toast.titre:SetText(n.titre)
	toast.texte:SetText(n.texte)
	toast.clic = n.clic
	Aide()
	toast:SetHeight(math.max(62, 42 + (tonumber(toast.texte:GetStringHeight()) or 14)))
	toast:SetAlpha(0)
	toast:Show()
	toast.debut = GetTime()
end

local function Construire ()
	toast = CreateFrame("Button", "OpusNotification", UIParent, "BackdropTemplate")
	toast:SetSize(340, 56)
	toast:SetPoint("TOP", UIParent, "TOP", 0, -150)
	toast:SetFrameStrata("DIALOG")
	if toast.SetBackdrop then
		toast:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		toast:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		toast:SetBackdropBorderColor(0.83, 0.69, 0.22)
	end
	local icone = toast:CreateTexture(nil, "ARTWORK")
	icone:SetTexture("Interface\\AddOns\\Opus\\Media\\Icone")
	icone:SetSize(36, 36) icone:SetPoint("TOPLEFT", 10, -10)
	toast.titre = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	toast.titre:SetPoint("TOPLEFT", icone, "TOPRIGHT", 10, 0)
	toast.texte = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	toast.texte:SetPoint("TOPLEFT", toast.titre, "BOTTOMLEFT", 0, -3)
	toast.texte:SetWidth(270) toast.texte:SetJustifyH("LEFT") toast.texte:SetSpacing(2)
	toast.aide = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	toast.aide:SetPoint("BOTTOMRIGHT", -10, 7)
	-- clic gauche : l'action de la notification ; clic droit : la passer ; maj + clic droit : tout passer
	toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	toast:SetScript("OnUpdate", function (self)
		local t, duree = GetTime() - (self.debut or 0), Duree()
		if self:IsMouseOver() or duree == 0 then self.debut = GetTime() - 0.3 t = 0.3 end
		self:SetAlpha(t < 0.3 and t / 0.3 or duree > 0 and t > duree - 0.5 and math.max(0, (duree - t) / 0.5) or 1)
		if duree > 0 and t >= duree then Suivante() end
	end)
	toast:SetScript("OnClick", function (self, bouton)
		if bouton == "RightButton" then
			if IsShiftKeyDown() then wipe(file) end
			Suivante()
			return
		end
		local clic = self.clic
		Suivante()
		if clic then clic() end
	end)
	toast:Hide()
end

function Opus.Notification (titre, texte, clic)
	if not toast then Construire() end
	file[#file + 1] = { titre = titre, texte = texte, clic = clic }
	pcall(PlaySound, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081)
	if not toast:IsShown() then Suivante() else Aide() end
end

------------------------------------------------------------------------
-- connexion
------------------------------------------------------------------------

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	C_Timer.After(55, function ()
		if IsInGuild() then Opus.Envoyer(table.concat({ "e", Opus.NouvelId() }, FS)) end
	end)
	-- « maintenant » expire, les membres se connectent : on revérifie de temps en temps
	C_Timer.NewTicker(120, function () if Opus.VerifierGroupes then Opus.VerifierGroupes() end end)
end)

Opus.Commande("envies", "envies", "les envies de donjon de la guilde (onglet Groupe)", function () Opus.OuvrirEnvies() end)
