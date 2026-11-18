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

local function Texte (s) return s and tostring(s):gsub("[;~]", " ") or "" end

local function Encoder (e)
	return table.concat({ e.q, Texte(e.nom), e.t, e.c or "", e.id or "", e.n or "", e.tab or "", Texte(e.o) }, FS)
end

local QUOI = { ["or+"] = true, ["or-"] = true, rep = true, ["obj+"] = true, ["obj-"] = true }

-- un enregistrement reçu, vérifié : un message mal formé ou invraisemblable ne laisse rien
local function Decoder (r)
	local q, nom, t, c, id, n, tab, o = strsplit(FS, r)
	t, c, id, n, tab = tonumber(t), tonumber(c), tonumber(id), tonumber(n), tonumber(tab)
	local maintenant = math.floor(time() / 3600)
	if not QUOI[q] or not nom or nom == "" or #nom > 48 or not t or t > maintenant + 2 or t < maintenant - 400 * 24 then return nil end
	local e = { q = q, nom = nom, t = t }
	if q == "or+" or q == "or-" or q == "rep" then
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

local function Envoyer (texte)
	local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIXE, texte, "GUILD")
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
	if Envoyer(file[1]) ~= "attendre" then table.remove(file, 1) end
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
		for nom, k in pairs(recusDepuis) do qui[#qui + 1] = Opus.Court(nom) total = total + k end
		recusDepuis = {}
		Msg(("banque : %d opération(s) reçue(s) de %s."):format(total, table.concat(qui, ", ")))
	end)
end

local function Recevoir (texte, expediteur)
	local enregistrements = { strsplit(RS, texte) }
	local entete = enregistrements[1]
	local genre, a, b, c = strsplit(FS, entete)
	if genre == "Q" then
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
	if prefixe ~= PREFIXE or canal ~= "GUILD" or not texte or not expediteur or not Opus.db then return end
	-- nos propres messages reviennent aussi : on les reconnaît à leur texte, et on apprend au passage sous quel nom
	-- les autres nous voient
	local envoye = envoyesRecents[texte]
	if envoye then
		envoyesRecents[texte] = nil
		if GetTime() - envoye < 120 then partage.moi = expediteur return end
	end
	if expediteur == partage.moi then return end
	Opus.db.banque.pairs[Opus.Court(expediteur)] = time()
	Recevoir(texte, expediteur)
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIXE) end

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	C_Timer.After(20, Opus.DemanderRattrapage)
end)

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
