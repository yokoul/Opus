-- Envies.lua : les envies de donjon. Un membre annonce qu'il veut faire un ou plusieurs donjons (pour des quêtes, des
-- objets, de l'expérience), quand il est disponible (maintenant, ce soir, ce week-end, ou une précision libre) et pour
-- combien de temps l'envie reste affichée (3 jours par défaut). « Moi aussi » publie la même envie pour soi. Toute la
-- guilde voit toutes les envies (un reroll peut être du bon niveau) ; une notification annonce les nouvelles, et prévient
-- quand assez de monde est disponible maintenant pour former un groupe.
-- Messages : « V » (une envie, publiée, modifiée ou retirée : une fin passée la retire), « e » (rattrapage à la connexion).
local _, Opus = ...

local FS = Opus.FS
local DONJONS_MAX = 3
local MAINTENANT = 2 * 3600        -- « maintenant » vaut deux heures
local ENVIES_MAX = 60              -- envies renvoyées au plus pour une demande

Opus.CRENEAUX = { { "maintenant", "Maintenant" }, { "soir", "Ce soir" }, { "weekend", "Ce week-end" }, { "autre", "Autre (préciser)" } }
Opus.DUREES_ENVIE = { { "soir", "Jusqu'à ce soir" }, { "24h", "24 heures" }, { "3j", "3 jours" }, { "7j", "7 jours" } }
Opus.POURQUOI = { { "quetes", "Quêtes" }, { "objets", "Objets" }, { "xp", "Expérience" } }
local BITS = { quetes = 1, objets = 2, xp = 4 }
local NOMS_CRENEAUX = {}
for _, c in ipairs(Opus.CRENEAUX) do NOMS_CRENEAUX[c[1]] = c[2] end

------------------------------------------------------------------------
-- les donjons : ceux de Dungeon Journal s'il est installé, sinon ceux de Forever retenus ici
------------------------------------------------------------------------

-- Les donjons de Forever : clé (celle de Dungeon Journal), nom français, tranche recommandée. Tranches du guide Wowhead
-- « Dungeons Overview » de Forever (relevé le 19/11/2026) ; elles l'emportent aussi sur celles de Dungeon Journal quand il
-- est installé (on ne lui prend que ses noms traduits). Maraudon (trois ailes chez Wowhead : 45-53, 45-53, 48-57) reste un
-- seul donjon, de 45 à 57 ; les ailes de Hache-Tripes et de Stratholme ont la tranche du donjon entier.
local FOREVER = {
	{ "Hall of Thanes", "La salle des Thanes", 13, 18 }, { "Ragefire Chasm", "Gouffre de Ragefeu", 13, 18 },
	{ "Ruins of Lordaeron", "Ruines de Lordaeron", 15, 20 }, { "Wailing Caverns", "Cavernes des Lamentations", 15, 25 },
	{ "The Deadmines", "Les Mortemines", 18, 23 }, { "Shadowfang Keep", "Donjon d'Ombrecroc", 22, 30 },
	{ "The Stockade", "La Prison", 22, 30 }, { "Excavation Site: Wetlands", "Excavations : les Paluns", 24, 29 },
	{ "Blackfathom Deeps", "Profondeurs de Brassenoire", 24, 32 }, { "City of Dalaran", "Cité de Dalaran", 28, 33 },
	{ "Scarlet Monastery: Graveyard", "Monastère Écarlate - cimetière", 28, 38 }, { "Gnomeregan", "Gnomeregan", 29, 38 },
	{ "Scarlet Monastery: Library", "Monastère Écarlate - bibliothèque", 29, 39 }, { "Razorfen Kraul", "Kraal de Tranchebauge", 30, 40 },
	{ "Scarlet Monastery: Armory", "Monastère Écarlate - armurerie", 32, 42 }, { "The Drowned City", "La cité Submergée", 35, 40 },
	{ "Scarlet Monastery: Cathedral", "Monastère Écarlate - cathédrale", 35, 45 }, { "Krol'dok Stronghold", "Bastion Krol'dok", 40, 45 },
	{ "Razorfen Downs", "Souilles de Tranchebauge", 40, 50 }, { "Uldaman", "Uldaman", 42, 52 }, { "Zul'Farrak", "Zul'Farrak", 44, 54 },
	{ "Maraudon", "Maraudon", 45, 57 }, { "Alcaz Prison", "Prison d'Alcaz", 48, 53 },
	{ "Sunken Temple", "Le temple d'Atal'Hakkar", 50, 60 }, { "Blackrock Depths", "Profondeurs de Rochenoire", 52, 60 },
	{ "Blackmaw Hold", "Repaire des Noiregueules", 55, 60 }, { "Lower Blackrock Spire", "Pic de Rochenoire inférieur", 55, 60 },
	{ "Shaper's Terrace", "La terrasse du Façonneur", 58, 60 }, { "Upper Blackrock Spire", "Pic de Rochenoire supérieur", 58, 60 },
	{ "Dire Maul: East", "Hache-Tripes - est", 58, 60 }, { "Dire Maul: West", "Hache-Tripes - ouest", 58, 60 },
	{ "Dire Maul: North", "Hache-Tripes - nord", 58, 60 }, { "Scholomance", "Scholomance", 58, 60 },
	{ "Stratholme: Living", "Stratholme - vivants", 58, 60 }, { "Stratholme: Undead", "Stratholme - morts-vivants", 58, 60 },
}
local TRANCHES = {}
for _, d in ipairs(FOREVER) do TRANCHES[d[1]] = { d[3], d[4] } end

-- Le niveau minimal pour entrer, et la tranche recommandée, tels que le jeu les donne (activités de la recherche de
-- groupe, catégorie donjons) : retrouvés par leur nom traduit. Lus une fois ; rien si l'API manque.
local jeu
local function InfosDuJeu ()
	if jeu then return jeu end
	jeu = {}
	local L = C_LFGList
	if not (L and L.GetAvailableActivities and L.GetActivityInfoTable) then return jeu end
	local ok, ids = pcall(L.GetAvailableActivities, 2)
	for _, id in ipairs(ok and ids or {}) do
		local ok2, a = pcall(L.GetActivityInfoTable, id)
		if ok2 and a and a.fullName then
			jeu[#jeu + 1] = { nom = a.fullName, min = a.minLevel, de = a.minLevelSuggestion, a = a.maxLevelSuggestion }
		end
	end
	return jeu
end

local function Plier (s) return Opus.Pli and Opus.Pli((s or ""):gsub("[%p%s]+", " ")) or (s or ""):lower() end

local function DuJeu (nom)
	local cle = Plier(nom)
	for _, a in ipairs(InfosDuJeu()) do
		if Plier(a.nom) == cle then return a end
	end
	return nil
end

-- tous les donjons : { cle, nom, min, max, entree }, du plus bas au plus haut ; entree = niveau minimal pour entrer
function Opus.TousLesDonjons ()
	local liste, vus = {}, {}
	-- de Dungeon Journal, seulement les donjons de la liste (pas ses raids : Onyxia…), pour leurs noms traduits
	for _, d in ipairs(Opus.Donjons()) do
		if TRANCHES[d.cle] then liste[#liste + 1] = d vus[d.cle] = true end
	end
	for _, d in ipairs(FOREVER) do
		if not vus[d[1]] then liste[#liste + 1] = { cle = d[1], nom = d[2], min = d[3], max = d[4] } end
	end
	for _, d in ipairs(liste) do
		local t = TRANCHES[d.cle]
		if t then d.min, d.max = t[1], t[2] end
		local a = DuJeu(d.nom)
		if a and a.min and a.min > 0 then d.entree = a.min end
	end
	table.sort(liste, function (x, y) if x.min ~= y.min then return x.min < y.min end return x.nom < y.nom end)
	return liste
end

Opus.Commande("diagdonjons", "diagdonjons", "les donjons tels que le jeu les donne (niveau d'entrée, tranche recommandée)", function ()
	jeu = nil
	local infos = InfosDuJeu()
	Opus.Msg(#infos .. " activité(s) de donjon lues dans le jeu :")
	for _, a in ipairs(infos) do
		DEFAULT_CHAT_FRAME:AddMessage(("  %s : entrée %s, recommandé %s-%s"):format(a.nom, tostring(a.min), tostring(a.de), tostring(a.a)))
	end
	local sans = {}
	for _, d in ipairs(Opus.TousLesDonjons()) do if not d.entree then sans[#sans + 1] = d.nom end end
	if #sans > 0 then DEFAULT_CHAT_FRAME:AddMessage("  sans niveau d'entrée reconnu : " .. table.concat(sans, ", ")) end
end)

function Opus.DonjonDe (cle)
	for _, d in ipairs(Opus.TousLesDonjons()) do if d.cle == cle then return d end end
	return { cle = cle, nom = cle }
end

------------------------------------------------------------------------
-- les envies : db.envies[guilde][id] = { id, par, m, fin, donjons = { cle }, pourquoi = { quetes = true }, creneau,
-- precision, note, roles, suite }
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
		return time({ year = d.year, month = d.month, day = d.day, hour = 23, min = 59 })
	end
	return maintenant + (duree == "24h" and 86400 or duree == "7j" and 7 * 86400 or 3 * 86400)
end

-- la durée qui va avec un créneau : « maintenant » et « ce soir » finissent ce soir, le reste dure 3 jours
function Opus.DureePourCreneau (creneau)
	return (creneau == "maintenant" or creneau == "soir") and "soir" or "3j"
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

-- publie une envie : { donjons, pourquoi, creneau, precision, note, duree, suite }
function Opus.PublierEnvie (x)
	if not IsInGuild() or #x.donjons == 0 then return end
	local e = {
		id = Opus.NouvelId(), par = Opus.MonNom(), m = time(), fin = Opus.FinEnvie(x.duree),
		donjons = {}, pourquoi = x.pourquoi or {},
		creneau = x.creneau or "maintenant", precision = x.precision, note = x.note, roles = Opus.MesRoles(), suite = x.suite,
	}
	for i = 1, math.min(#x.donjons, DONJONS_MAX) do e.donjons[i] = x.donjons[i] end
	Retenir(e)
	Envoyer(e)
	Opus.Msg("envie publiée : la guilde est prévenue.")
	if Opus.VerifierGroupes then Opus.VerifierGroupes() end
	if Opus.Rafraichir then Opus.Rafraichir() end
end

function Opus.RetirerEnvie (id)
	local d = Donnees()
	local e = d and d[id]
	if not e or e.par ~= Opus.MonNom() then return end
	local retiree = Opus.Copie(e)
	retiree.m = math.max(time(), e.m + 1)
	retiree.fin = retiree.m
	d[id] = nil
	Envoyer(retiree)
	if Opus.Rafraichir then Opus.Rafraichir() end
end

------------------------------------------------------------------------
-- groupes possibles : assez de monde disponible maintenant, en ligne, pour un même donjon
------------------------------------------------------------------------

-- les joueurs disponibles maintenant pour un donjon, et la composition qu'on en tire : places[i] = nom
function Opus.CompositionPossible (cle)
	local dispo, vus = {}, {}
	for _, e in ipairs(Opus.Envies()) do
		local m = Opus.TrouverMembre(e.par)
		if not vus[e.par] and m and m.enLigne and Opus.DispoMaintenant(e) then
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
-- la notification : une petite fenêtre en haut de l'écran, quelques secondes
------------------------------------------------------------------------

local toast, file, DUREE = nil, {}, 4
local function Suivante ()
	local n = table.remove(file, 1)
	if not n then toast:Hide() return end
	toast.titre:SetText(n.titre)
	toast.texte:SetText(n.texte)
	toast.clic = n.clic
	toast:SetHeight(math.max(56, 30 + (tonumber(toast.texte:GetStringHeight()) or 14)))
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
	toast:SetScript("OnUpdate", function (self)
		local t = GetTime() - (self.debut or 0)
		if self:IsMouseOver() then self.debut = GetTime() - 0.3 t = 0.3 end
		self:SetAlpha(t < 0.3 and t / 0.3 or t > DUREE - 0.5 and math.max(0, (DUREE - t) / 0.5) or 1)
		if t >= DUREE then Suivante() end
	end)
	toast:SetScript("OnClick", function (self)
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
	if not toast:IsShown() then Suivante() end
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
