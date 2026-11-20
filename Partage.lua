-- Partage.lua : les relevés de la banque passent d'un membre de la guilde à l'autre, par messages d'addon
-- Chaque relevé envoie ses nouvelles opérations sur le canal de guilde ; à la connexion, on demande ce qu'on a manqué
-- et un seul des membres en ligne (le premier à se proposer) répond. Ce qui arrive est fusionné comme un relevé :
-- une opération déjà connue n'est pas comptée deux fois. Les autres addons de Forever font pareil : messages de
-- 250 octets au plus, un toutes les 2 secondes, rien en combat ni en instance (restrictions des addons).
local _, Opus = ...
local Msg = Opus.Msg

local PREFIXE = "OpusBanque"
local FS, RS = ";", "~"             -- séparateurs de champs et d'enregistrements
local MAX_MSG = 250                 -- le jeu refuse au-delà de 255 octets
local INTERVALLE = 2                -- secondes entre deux messages
local RATTRAPAGE_MAX = 400          -- opérations envoyées au plus pour une demande de rattrapage
local RECUS_PAR_MINUTE = 600        -- au-delà, un expéditeur est ignoré jusqu'à la minute suivante

local R = (Enum and Enum.SendAddonMessageResult) or {}
local OK, THROTTLE, CANAL_THROTTLE, VERROU = R.Success or 0, R.AddonMessageThrottle or 3, R.ChannelThrottle or 8, R.AddOnMessageLockdown or 11

local file, pauseJusqua = {}, 0
local envoyesRecents = {}           -- [texte] = GetTime() : nos messages, qui nous reviennent aussi
local partage = { envoyes = 0, recus = 0, dernierResultat = nil }
Opus.partage = partage

-- une valeur que le jeu masque aux addons (secret) ne se compare même pas : on la laisse tomber
local function Propre (v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- en combat et en instance, les messages d'addon sont restreints : on attend
local function Restreint ()
	if InCombatLockdown() then return true end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return true end
	return Propre(IsInInstance()) == true
end

------------------------------------------------------------------------
-- encodage
------------------------------------------------------------------------

local function Texte (s) return s and (tostring(s):gsub(";", ","):gsub("~", "-")) or "" end

local function Encoder (e)
	return table.concat({ e.q, Texte(e.nom), e.t, e.c or "", e.id or "", e.n or "", e.tab or "", Texte(e.o) }, FS)
end

local QUOI = { ["or+"] = true, ["or-"] = true, rep = true, ong = true, ["obj+"] = true, ["obj-"] = true }

-- un enregistrement reçu, vérifié : un message mal formé ou invraisemblable ne laisse rien
local function Decoder (r)
	local q, nom, t, c, id, n, tab, o = strsplit(FS, r)
	t, c, id, n, tab = tonumber(t), tonumber(c), tonumber(id), tonumber(n), tonumber(tab)
	local maintenant = math.floor(time() / 3600)
	if not QUOI[q] or not nom or nom == "" or #nom > 48 or not t or t > maintenant + 2 or t < maintenant - 400 * 24 then return nil end
	local e = { q = q, nom = nom, t = t }
	if q == "or+" or q == "or-" or q == "rep" or q == "ong" then
		if not c or c <= 0 then return nil end
		e.c = c
	else
		if not n or n <= 0 then return nil end
		e.id, e.n, e.tab, e.o = id, n, tab, (o ~= "" and o or nil)
	end
	return e
end

------------------------------------------------------------------------
-- envoi
------------------------------------------------------------------------

local function Envoyer (texte, canal)
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIXE, texte, canal or "GUILD")
	if not ok then return "echec" end
	partage.dernierResultat = res
	if res == nil or res == true or res == OK then
		partage.envoyes = partage.envoyes + 1
		envoyesRecents[texte] = GetTime()
		return "ok"
	end
	if res == VERROU then pauseJusqua = GetTime() + 30 return "attendre" end
	if res == THROTTLE or res == CANAL_THROTTLE then pauseJusqua = GetTime() + 5 return "attendre" end
	return "echec"
end

C_Timer.NewTicker(INTERVALLE, function ()
	if #file == 0 or GetTime() < pauseJusqua or not IsInGuild() or Restreint() then return end
	-- un message est un texte (canal de guilde) ou { texte, canal } (« OFFICER » : seuls les officiers le reçoivent)
	local m = file[1]
	local r = type(m) == "table" and Envoyer(m[1], m[2]) or Envoyer(m)
	if r ~= "attendre" then table.remove(file, 1) end
end)

-- des opérations, en autant de messages que nécessaire, derrière un en-tête (« E » ou « Z;demande »)
local function Mettre (entete, evenements)
	local message = entete
	for _, e in ipairs(evenements) do
		local r = Encoder(e)
		if #message + 1 + #r > MAX_MSG then
			file[#file + 1] = message
			message = entete
		end
		message = message .. RS .. r
	end
	if message ~= entete then file[#file + 1] = message end
end

function Opus.PartagerBanque (evenements)
	if IsInGuild() then Mettre("E", evenements) end
end

------------------------------------------------------------------------
-- rattrapage : à la connexion, on demande ce qu'on a manqué
------------------------------------------------------------------------

local function Etat ()
	local plusRecent = 0
	for _, e in ipairs(Opus.db.banque.evenements) do plusRecent = math.max(plusRecent, e.t) end
	return plusRecent, #Opus.db.banque.evenements
end

local maDemande, propositions = nil, {}

function Opus.DemanderRattrapage ()
	if not IsInGuild() or not Opus.db then return end
	local plusRecent, n = Etat()
	maDemande = ("%04x%04x"):format(math.random(0, 65535), math.random(0, 65535))
	file[#file + 1] = table.concat({ "Q", plusRecent, n, maDemande }, FS)
end

-- une demande entendue : si on a mieux, on se propose après un délai au hasard ; si quelqu'un se propose
-- avant nous (« P »), on laisse tomber
local function Demande (plusRecentAutre, nAutre, rid)
	local plusRecent, n = Etat()
	if plusRecent <= plusRecentAutre and n <= nAutre + 5 then return end
	local depuis = plusRecent > plusRecentAutre and (plusRecentAutre - 48) or (math.floor(time() / 3600) - 30 * 24)
	propositions[rid] = C_Timer.NewTimer(3 + math.random() * 7, function ()
		propositions[rid] = nil
		local choix = {}
		for _, e in ipairs(Opus.db.banque.evenements) do
			if e.t >= depuis then choix[#choix + 1] = e end
		end
		table.sort(choix, function (a, b) return a.t > b.t end)
		while #choix > RATTRAPAGE_MAX do table.remove(choix) end
		file[#file + 1] = table.concat({ "P", rid }, FS)
		Mettre("Z" .. FS .. rid, choix)
	end)
end

------------------------------------------------------------------------
-- réception
------------------------------------------------------------------------

local cadence, recusDepuis, annonce = {}, {}, nil

local function Accepter (expediteur, nombre)
	local t, c = GetTime(), cadence[expediteur]
	if not c or t - c.debut > 60 then c = { debut = t, n = 0 } cadence[expediteur] = c end
	c.n = c.n + nombre
	return c.n <= RECUS_PAR_MINUTE
end

-- ce qui arrive est annoncé une fois, quand ça se calme
local function Annoncer (expediteur, n)
	recusDepuis[expediteur] = (recusDepuis[expediteur] or 0) + n
	if annonce then annonce:Cancel() end
	annonce = C_Timer.NewTimer(5, function ()
		annonce = nil
		local qui, total = {}, 0
		for nom, k in pairs(recusDepuis) do
			local m = Opus.TrouverExpediteur(nom)
			qui[#qui + 1] = m and m.nom or Opus.Court(nom)
			total = total + k
		end
		recusDepuis = {}
		Msg(("banque : %d opération(s) reçue(s) de %s."):format(total, table.concat(qui, ", ")))
	end)
end

------------------------------------------------------------------------
-- la grille de la guilde (Config.lua) : un en-tête « C », un message « G » par grade
------------------------------------------------------------------------

local DRAPEAUX = { officier = 1, inviter = 2, promouvoir = 4, retrograder = 8, exclure = 16, reparer = 32 }
-- un texte court, sans séparateurs, coupé à max octets sans casser une lettre accentuée
local function Coupe (s, max)
	if #s <= max then return s end
	return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
end
-- un texte libre (rôle, voie, description) ; un nom d'une liste (onglets) perd aussi la virgule qui les sépare
local function Mot (s, max) return Coupe(Texte(s), max or 60) end
local function NomListe (s, max) return Coupe((Texte(s):gsub(",", " ")), max) end

local function MessagesConfig (c)
	local messages, noms = {}, {}
	for t = 1, 3 do noms[t] = NomListe(c.onglets and c.onglets[t] or "", 24) end
	local r = c.restriction
	local entete = table.concat({ "C", c.version, #c.grades, Mot(c.par or "", 48), r and r.fin or "", table.concat(noms, ","), "" }, FS)
	messages[1] = entete .. (r and Mot(r.texte, MAX_MSG - #entete) or "")
	-- les réglages (« X ») : ce que coupe la restriction, et la cotisation ; envoyés avant les grades, donc reçus avant
	local co, tranches = c.cotisation, {}
	for _, t in ipairs(co and co.tranches or {}) do tranches[#tranches + 1] = t.min .. "-" .. t.max .. "-" .. t.montant end
	-- la durée des essais, par rang (« 6:14,8:21 ») : en dernier champ, ignoré par les versions d'avant 0.22
	local durees = {}
	for rang, j in pairs(c.durees or {}) do durees[#durees + 1] = rang .. ":" .. j end
	table.sort(durees)
	messages[2] = table.concat({ "X", c.version, r and r.coupeRep == false and 0 or 1, r and r.coupeOr == false and 0 or 1,
		co == nil and "" or (co.actif and 1 or 0), table.concat(tranches, ","), co and co.plafond or "", table.concat(durees, ",") }, FS)
	for i, g in ipairs(c.grades) do
		local bits = 0
		for cle, b in pairs(DRAPEAUX) do if g[cle] then bits = bits + b end end
		local onglets = {}
		for t = 1, 3 do
			local o = g.onglets and g.onglets[t]
			onglets[t] = o and ((o.voir and 1 or 0) .. ":" .. (o.deposer and 1 or 0) .. ":" .. (o.retraits or 0)) or ""
		end
		local m = table.concat({ "G", c.version, i, Mot(g.role, 40), Mot(g.voie or "", 20),
			g.essai or "", table.concat(g.sorties or {}, ","), bits, g.or_ or 0, table.concat(onglets, ","), "" }, FS)
		-- la description prend la place qui reste dans le message
		messages[#messages + 1] = m .. Mot(g.desc or "", MAX_MSG - #m)
	end
	return messages
end

function Opus.PartagerConfig ()
	local c = Opus.Config()
	if not IsInGuild() or not c or (c.version or 0) == 0 then return end
	for _, m in ipairs(MessagesConfig(c)) do file[#file + 1] = m end
end

local enCours = {}          -- [version] = grille reçue en morceaux
local function RecevoirConfig (genre, champs, expediteur)
	local version = tonumber(champs[2])
	if not version then return end
	local r = enCours[version] or { grades = {} }
	enCours[version] = r
	if genre == "X" then
		r.coupeRep, r.coupeOr = champs[3] ~= "0", champs[4] ~= "0"
		if champs[5] == "0" or champs[5] == "1" then
			local co = { actif = champs[5] == "1", tranches = {}, plafond = tonumber(champs[7]) }
			for a, b, m in (champs[6] or ""):gmatch("(%d+)%-(%d+)%-(%d+)") do
				co.tranches[#co.tranches + 1] = { min = tonumber(a), max = tonumber(b), montant = tonumber(m) }
			end
			r.cotisation = co
		end
		for x, y in (champs[8] or ""):gmatch("(%d+):(%d+)") do
			local rang, j = tonumber(x), tonumber(y)
			if rang >= 1 and rang <= 10 and j >= 1 and j <= 365 then r.durees = r.durees or {} r.durees[rang] = j end
		end
		return
	elseif genre == "C" then
		local n, par, fin, noms, texte = tonumber(champs[3]), champs[4], tonumber(champs[5]), champs[6] or "", champs[7]
		r.n, r.par = n, par ~= "" and par or nil
		r.onglets = {}
		for t, nom in ipairs({ strsplit(",", noms) }) do if nom ~= "" then r.onglets[t] = nom end end
		r.restriction = fin and { fin = fin, texte = texte or "" } or nil
	else
		local i = tonumber(champs[3])
		if not i or i < 1 or i > 10 then return end
		local g = { role = champs[4] or "", voie = champs[5] ~= "" and champs[5] or nil, sorties = {}, or_ = tonumber(champs[9]) or 0 }
		if champs[6] == "guilde" or champs[6] == "raid" then g.essai = champs[6] end
		for s in (champs[7] or ""):gmatch("%d+") do g.sorties[#g.sorties + 1] = tonumber(s) end
		local bits = tonumber(champs[8]) or 0
		for cle, b in pairs(DRAPEAUX) do if bit.band(bits, b) ~= 0 then g[cle] = true end end
		if champs[10] and champs[10] ~= ",," then
			g.onglets = {}
			for t, o in ipairs({ strsplit(",", champs[10]) }) do
				local v, d, k = o:match("^(%d):(%d):(%d+)$")
				if v then g.onglets[t] = { voir = v == "1", deposer = d == "1", retraits = tonumber(k) } end
			end
		end
		g.desc = champs[11] ~= "" and champs[11] or nil
		r.grades[i] = g
	end
	-- complète : plus récente que la nôtre, et écrite par quelqu'un qui peut la modifier (chef ou officier)
	if not r.n then return end
	for i = 1, r.n do if not r.grades[i] then return end end
	enCours[version] = nil
	local locale = Opus.Config()
	if not locale or version <= (locale.version or 0) then return end
	local auteur = r.par and Opus.TrouverMembre(r.par)
	if not auteur or not Opus.PeutConfigurer(auteur.grade) then return end
	if r.restriction then r.restriction.coupeRep, r.restriction.coupeOr = r.coupeRep ~= false, r.coupeOr ~= false end
	local c = { version = version, par = r.par, grades = r.grades, onglets = r.onglets or {}, restriction = r.restriction, cotisation = r.cotisation, durees = r.durees }
	Opus.db.configs[GetGuildInfo("player")] = c
	Opus.AppliquerConfig()
	Opus.Msg(("grille de la guilde mise à jour (par %s)."):format(r.par))
end

-- à la connexion, on donne la version de sa grille ; qui en a une plus récente la renvoie (un seul, le premier)
function Opus.DemanderConfig ()
	local c = Opus.Config()
	if not IsInGuild() or not c then return end
	file[#file + 1] = table.concat({ "K", c.version or 0, ("%04x"):format(math.random(0, 65535)) }, FS)
end

local function DemandeConfig (versionAutre, rid)
	local c = Opus.Config()
	if not c or (c.version or 0) <= versionAutre then return end
	propositions[rid] = C_Timer.NewTimer(2 + math.random() * 6, function ()
		propositions[rid] = nil
		file[#file + 1] = table.concat({ "P", rid }, FS)
		Opus.PartagerConfig()
	end)
end

------------------------------------------------------------------------
-- les dates d'essai (« A ») : tirées des notes d'officier, que seuls les officiers lisent
------------------------------------------------------------------------

function Opus.PartagerArrivees (dates)
	if not IsInGuild() then return end
	local liste = {}
	for nom, t in pairs(dates) do liste[#liste + 1] = { nom = nom, t = t } end
	local message = "A"
	for _, d in ipairs(liste) do
		local r = Texte(d.nom) .. FS .. d.t
		if #message + 1 + #r > MAX_MSG then file[#file + 1] = message message = "A" end
		message = message .. RS .. r
	end
	if message ~= "A" then file[#file + 1] = message end
end

-- une date reçue : retenue si on n'en a pas ; celle d'un officier l'emporte (elle vient de la note)
local function RecevoirArrivees (enregistrements, expediteur)
	local auteur = Opus.TrouverExpediteur(expediteur)
	local officier = auteur and Opus.PeutConfigurer(auteur.grade)
	local maintenant, change = time(), false
	for i = 2, #enregistrements do
		local nom, t = strsplit(FS, enregistrements[i])
		t = tonumber(t)
		if nom and nom ~= "" and #nom <= 48 and t and t > maintenant - 400 * 86400 and t <= maintenant + 86400 then
			if not Opus.db.arrivees[nom] or (officier and Opus.db.arrivees[nom] ~= t) then
				Opus.db.arrivees[nom] = t
				change = true
			end
		end
	end
	if change and Opus.Rafraichir then Opus.Rafraichir() end
end

-- les officiers rediffusent les dates des essais en cours à la connexion, pour ceux qui étaient absents
local function DiffuserArrivees ()
	if not Opus.PeutConfigurer() then return end
	local dates, n = {}, 0
	for _, m in ipairs(Opus.Essais()) do
		if m.debut then dates[m.nom] = m.debut n = n + 1 end
	end
	if n > 0 then Opus.PartagerArrivees(dates) end
end

------------------------------------------------------------------------
-- les spés (« S ») : chacun annonce la sienne (Specs.lua)
------------------------------------------------------------------------

function Opus.PartagerSpe (nom, s)
	if not IsInGuild() then return end
	file[#file + 1] = table.concat({ "S", Texte(nom), Mot(s.arbre, 40), s.icone or "", Mot(s.points, 20), s.t or time(), s.role or "" }, FS)
end

local function RecevoirSpe (champs, expediteur)
	local nom, arbre, icone, points, t = champs[2], champs[3], tonumber(champs[4]), champs[5], tonumber(champs[6])
	-- un ou plusieurs rôles (« soin,degats ») ; les versions d'avant 0.22 n'en lisent qu'un seul
	local role = table.concat(Opus.ListeRoles(champs[7]), ",")
	if role == "" then role = nil end
	-- on n'annonce que sa propre spé
	if not Opus.EstMembre(nom, expediteur) or not arbre or arbre == "" or not t then return end
	if Opus.RetenirSpe(nom, { arbre = arbre, icone = icone, points = points, role = role }, t) and Opus.Rafraichir then Opus.Rafraichir() end
end

-- ses personnages (« M ») : pour plafonner la cotisation par joueur (Cotisation.lua)
function Opus.PartagerPersos (noms)
	local liste = {}
	for _, n in ipairs(noms) do liste[#liste + 1] = (Texte(n):gsub(",", " ")) end
	file[#file + 1] = "M" .. FS .. table.concat(liste, ",")
end

-- les genres de message des autres modules (Lien.lua, Notes.lua) : [genre] = f(enregistrements, champs, expediteur, canal)
-- une lettre par genre de message : deux modules sur la même lettre, et l'un des deux ne reçoit plus rien (c'est arrivé
-- avec « W », banque et liaisons Discord) ; on le refuse dès le chargement
Opus.recepteurs = setmetatable({}, { __newindex = function (t, genre, f)
	if rawget(t, genre) then error("Opus : le genre de message « " .. genre .. " » est déjà pris") end
	rawset(t, genre, f)
end })

local function Recevoir (texte, expediteur, canal)
	local enregistrements = { strsplit(RS, texte) }
	local entete = enregistrements[1]
	local genre, a, b, c = strsplit(FS, entete)
	if Opus.recepteurs[genre] then
		if Accepter(expediteur, #enregistrements) then Opus.recepteurs[genre](enregistrements, { strsplit(FS, entete) }, expediteur, canal) end
		return
	elseif canal ~= "GUILD" and genre ~= "P" then
		return
	elseif genre == "M" then
		local noms = {}
		for n in (a or ""):gmatch("[^,]+") do if #noms < 12 then noms[#noms + 1] = n end end
		if Opus.RecevoirPersos then Opus.RecevoirPersos(noms, expediteur) end
		return
	elseif genre == "S" then
		RecevoirSpe({ strsplit(FS, entete) }, expediteur)
		return
	elseif genre == "J" then
		if Opus.RecevoirProposition then Opus.RecevoirProposition({ strsplit(FS, entete) }, expediteur) end
		return
	elseif genre == "R" then
		if Opus.RecevoirReponse then Opus.RecevoirReponse({ strsplit(FS, entete) }, expediteur) end
		return
	elseif genre == "D" then
		if Opus.RecevoirDonjon then Opus.RecevoirDonjon({ strsplit(FS, entete) }, expediteur) end
		return
	elseif genre == "A" then
		RecevoirArrivees(enregistrements, expediteur)
		return
	elseif genre == "C" or genre == "G" or genre == "X" then
		RecevoirConfig(genre, { strsplit(FS, entete) }, expediteur)
		return
	elseif genre == "K" then
		DemandeConfig(tonumber(a) or 0, b or "")
		if Opus.PublierSpe then C_Timer.After(5 + math.random() * 20, function () Opus.PublierSpe(true) end) end
		if Opus.PublierPersos then C_Timer.After(10 + math.random() * 20, Opus.PublierPersos) end
		return
	elseif genre == "Q" then
		if c ~= maDemande then Demande(tonumber(a) or 0, tonumber(b) or 0, c) end
		return
	elseif genre == "P" then
		if propositions[a] then propositions[a]:Cancel() propositions[a] = nil end
		return
	elseif genre ~= "E" and genre ~= "Z" then
		return
	end
	if not Accepter(expediteur, #enregistrements - 1) then return end
	local lus = {}
	for i = 2, #enregistrements do
		local e = Decoder(enregistrements[i])
		if e then lus[#lus + 1] = e end
	end
	local ajoutees = Opus.FusionnerBanque(lus)
	partage.recus = partage.recus + #ajoutees
	if #ajoutees > 0 then
		Opus.PurgerBanque()
		Annoncer(expediteur, #ajoutees)
		if Opus.Rafraichir then Opus.Rafraichir() end
	end
end

Opus.Ecoute("CHAT_MSG_ADDON", function (prefixe, texte, canal, expediteur)
	prefixe, texte, canal, expediteur = Propre(prefixe), Propre(texte), Propre(canal), Propre(expediteur)
	if prefixe ~= PREFIXE or (canal ~= "GUILD" and canal ~= "OFFICER") or not texte or not expediteur or not Opus.db then return end
	-- nos propres messages reviennent aussi : on les reconnaît à leur texte, et on apprend au passage sous quel nom
	-- les autres nous voient
	local envoye = envoyesRecents[texte]
	if envoye then
		envoyesRecents[texte] = nil
		if GetTime() - envoye < 120 then partage.moi = expediteur return end
	end
	if expediteur == partage.moi then return end
	-- les signatures brutes vues, pour /opus diagnoms (quelques-unes suffisent)
	local vus = Opus.db.signatures or {}
	Opus.db.signatures = vus
	if not vus[expediteur] then
		local n = 0
		for _ in pairs(vus) do n = n + 1 end
		if n < 40 then vus[expediteur] = time() end
	end
	-- les membres qui ont l'addon, sous leur nom du roster (l'expéditeur n'a parfois que le prénom)
	local membre = Opus.TrouverExpediteur(expediteur)
	Opus.db.banque.pairs[membre and membre.nom or Opus.Court(expediteur)] = time()
	Recevoir(texte, expediteur, canal)
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIXE) end

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	C_Timer.After(20, Opus.DemanderRattrapage)
	C_Timer.After(25, Opus.DemanderConfig)
	C_Timer.After(35, DiffuserArrivees)
end)

-- ce membre a-t-il l'addon ? (il s'est manifesté ces 7 derniers jours)
function Opus.AAddon (nom)
	local t = Opus.db.banque.pairs[nom]
	return t and t >= time() - 7 * 86400
end

-- un message prioritaire (proposition de groupe et sa réponse) : en tête de file
function Opus.EnvoyerVite (message) table.insert(file, 1, message) end

------------------------------------------------------------------------
-- pour les autres modules : envoyer, se proposer pour répondre à une demande, encoder un texte
------------------------------------------------------------------------

Opus.MAX_MSG, Opus.FS, Opus.RS = MAX_MSG, FS, RS
Opus.CoupeMsg, Opus.MotMsg = Coupe, Mot

-- un message en fin de file, sur le canal de guilde ou des officiers
function Opus.Envoyer (message, canal)
	file[#file + 1] = canal and canal ~= "GUILD" and { message, canal } or message
end

-- une demande entendue (identifiant rid) : on répond après un délai au hasard, sauf si quelqu'un se propose avant
-- (« P;rid ») ; repondre() met ses messages en file, la proposition « P » part sur le même canal
function Opus.Repondre (rid, canal, repondre)
	if not rid or rid == "" or propositions[rid] then return end
	propositions[rid] = C_Timer.NewTimer(3 + math.random() * 7, function ()
		propositions[rid] = nil
		Opus.Envoyer(table.concat({ "P", rid }, FS), canal)
		repondre()
	end)
end

function Opus.NouvelId () return ("%04x%04x"):format(math.random(0, 65535), math.random(0, 65535)) end

-- les membres dont l'addon s'est manifesté ces 7 derniers jours
function Opus.Pairs ()
	local n, limite = 0, time() - 7 * 86400
	for _, t in pairs(Opus.db.banque.pairs) do if t >= limite then n = n + 1 end end
	return n
end

function Opus.FileDePartage () return #file end

Opus.Commande("sync", "sync", "demande aux membres en ligne les opérations de banque qui te manquent", function ()
	Opus.DemanderRattrapage()
	Msg("demande de rattrapage envoyée à la guilde.")
end)

-- comment le jeu écrit les noms (Forever : prénom et nom de famille, pas de royaume ; les prénoms ne sont pas uniques)
Opus.Commande("diagnoms", "diagnoms", "comment le jeu écrit les noms (messages, échanges, roster)", function ()
	local function Brut (v) return v == nil and "nil" or ("« " .. tostring(v) .. " »") end
	local lignes = {}
	local function L (s) lignes[#lignes + 1] = s DEFAULT_CHAT_FRAME:AddMessage("  " .. s) end
	local prenom, famille = UnitName("player")
	Msg("noms tels que le jeu les donne (aussi dans les sauvegardes d'Opus après un /reload) :")
	L("UnitName : " .. Brut(prenom) .. ", " .. Brut(famille))
	L("GetRealmName : " .. Brut(GetRealmName and GetRealmName()) .. " ; normalisé : " .. Brut(GetNormalizedRealmName and GetNormalizedRealmName()))
	local guid, roster = UnitGUID("player"), nil
	for _, m in ipairs(Opus.Membres()) do if m.guid == guid then roster = m.complet end end
	L("roster : " .. Brut(roster) .. " ; Opus te range sous " .. Brut(Opus.MonNom()))
	L("tes messages d'addon arrivent signés : " .. Brut(partage.moi))
	L("dernier partenaire d'échange : " .. Brut(Opus.dernierPartenaire))
	local signatures = {}
	for nom in pairs(Opus.db.signatures or {}) do
		local m = Opus.TrouverExpediteur(nom)
		signatures[#signatures + 1] = Brut(nom) .. " -> " .. (m and m.nom or "?")
	end
	table.sort(signatures)
	L(("signatures des autres vues : %d"):format(#signatures))
	for _, x in ipairs(signatures) do L("  " .. x) end
	local prenoms, doubles = {}, {}
	for _, m in ipairs(Opus.Membres()) do
		local p = m.nom:match("^(%S+)")
		prenoms[p] = prenoms[p] or {}
		table.insert(prenoms[p], m.nom)
	end
	for _, noms in pairs(prenoms) do if #noms > 1 then table.sort(noms) doubles[#doubles + 1] = table.concat(noms, ", ") end end
	table.sort(doubles)
	L(("prénoms portés par plusieurs membres : %d"):format(#doubles))
	for _, x in ipairs(doubles) do L("  " .. x) end
	Opus.db.diagNoms = { t = time(), version = Opus.version, lignes = lignes }
end)
