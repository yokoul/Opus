-- RaidAttribution.lua : d'une annonce à l'attribution, avec le délai, l'objection et le vote (WishVote)
-- Tout passe par le canal raid, sans que les joueurs aient besoin de l'addon :
--   « !objection n » pendant les 3 minutes après l'annonce n° n (n facultatif s'il n'y a qu'une annonce en cours) ;
--   une objection ouvre un vote de 2 minutes : « !pour n » (la proposition tient) ou « !contre n ». Seuls votent les
--   présents qui ne sont pas candidats à l'objet ; le dernier vote de chacun compte. Quorum : la moitié des électeurs.
--   Sans objection, ou si le vote ne renverse pas la proposition, l'objet est attribué au proposé ; sinon les officiers
--   tranchent, avec un motif.
-- Seul le client qui a annoncé compte : c'est celui du maître du butin. Chaque étape est notée pour le rapport.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

local DELAI = 180                   -- secondes pour objecter
local VOTE = 120                    -- secondes pour voter
local QUORUM = 0.5                  -- part des électeurs qui doivent voter

Raid.DELAI, Raid.VOTE = DELAI, VOTE
Raid.attributions = {}              -- de la soirée, dans l'ordre des annonces : { n, lien, id, etat, … }

-- un texte que le jeu masque aux addons (valeur secrète) ne se lit pas : on l'ignore
local function Propre (v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

------------------------------------------------------------------------
-- le journal de la soirée (les événements du rapport, docs/contrat-butin.md)
------------------------------------------------------------------------

-- Une soirée commence à la première annonce, et se termine après 6 heures sans annonce.
local function Soiree ()
	local s = Raid.db.soiree
	if not s or time() - (s.derniere or 0) > 6 * 3600 then
		local i = Raid.db.instantane
		local sk = {}
		for k, nom in ipairs(i and i.sk or {}) do sk[k] = nom end
		-- sk : la liste Suicide King de la soirée, qui bouge à chaque objet gagné (SuicideKing.lua)
		s = { debut = time(), ml = Raid.MonNom(), instantane = i and i.id, evenements = {}, n = 0, sk = sk }
		Raid.db.soiree = s
		wipe(Raid.attributions)
	end
	s.derniere = time()
	return s
end

-- Note un événement ; rend son identifiant (« maître du butin/début/numéro »).
Raid.Soiree = Soiree
function Raid.Noter (lettre, champs)
	local s = Soiree()
	s.n = s.n + 1
	local e = { lettre = lettre, id = s.ml .. "/" .. s.debut .. "/" .. s.n, t = time() }
	for k, v in pairs(champs or {}) do e[k] = v end
	s.evenements[#s.evenements + 1] = e
	return e.id
end

------------------------------------------------------------------------
-- les étapes
------------------------------------------------------------------------

local Rafraichir = function () if Raid.RafraichirButin then Raid.RafraichirButin() end end

local function Ensemble (liste) local t = {} for _, v in ipairs(liste) do t[v] = true end return t end
local function Compter (t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function EnCours (etat) return etat == "delai" or etat == "vote" end

-- l'attribution que vise « !objection n » : le numéro donné, ou la seule en cours
local function Visee (n, etat)
	if n then
		local a = Raid.attributions[n]
		return a and a.etat == etat and a or nil
	end
	local seule
	for _, a in ipairs(Raid.attributions) do
		if a.etat == etat then
			if seule then return nil end
			seule = a
		end
	end
	return seule
end

-- aux addons du raid (Comm.lua), s'il est chargé
local function Diffuser (...) if Raid.Diffuser then Raid.Diffuser(...) end end
Raid.DiffuserAttribution = function (a) Diffuser("R", a.n, a.etat, a.attributaire or "") end

local function Attribuer (a, nom, voie, comment)
	a.etat, a.attributaire = "attribue", nom
	Raid.DiffuserAttribution(a)
	a.evenementA = Raid.Noter("A", { tombe = a.evenementT, attributaire = nom, voie = voie })
	if Raid.ApresAttribution then Raid.ApresAttribution(a) end
	Raid.Annoncer(string.format("#%d %s attribué à %s%s.", a.n, a.lien, nom, comment or ""))
	Rafraichir()
end

Raid.Attribuer = Attribuer

local function FinDelai (a)
	if a.etat ~= "delai" then return end
	Attribuer(a, a.propose, "wish", " (pas d'objection)")
end

local function FinVote (a)
	if a.etat ~= "vote" then return end
	local pour, contre = 0, 0
	for _, v in pairs(a.votes) do if v == "pour" then pour = pour + 1 else contre = contre + 1 end end
	local votants = pour + contre
	local atteint = votants >= a.quorum
	Raid.Noter("V", { objection = a.evenementX, pour = pour, contre = contre, electeurs = a.nElecteurs, quorum = atteint and 1 or 0 })
	local bilan = string.format("%d pour, %d contre, %d votant%s sur %d, quorum %d", pour, contre, votants, votants > 1 and "s" or "", a.nElecteurs, a.quorum)
	if atteint and contre > pour then
		a.etat = "trancher"
		Raid.DiffuserAttribution(a)
		Raid.Annoncer(string.format("#%d %s : vote %s. La proposition est renversée : les officiers tranchent.", a.n, a.lien, bilan))
		Rafraichir()
	else
		Attribuer(a, a.propose, "wish", " : vote " .. bilan .. (atteint and "" or " (non atteint)") .. ", la proposition tient")
	end
end

-- Annonce un objet et lance le délai. o = { lien, id } ; rend l'attribution.
function Raid.Lancer (o)
	local actif, raison = Raid.Actif()
	if not actif then Msg(raison .. ".") return nil end
	local presents = Raid.Presents()
	local r = Raid.Proposer(o.id, presents)
	if not r then Msg("aucun instantané importé.") return nil end
	local s = Soiree()
	local a = { n = #Raid.attributions + 1, lien = o.lien, id = o.id, votes = {}, objecteurs = {} }
	Raid.attributions[a.n] = a
	-- tous les candidats en wishlist, présents ou non : aucun ne vote sur cet objet
	a.candidats = {}
	for _, c in ipairs(Raid.db.instantane.souhaits[o.id] or {}) do a.candidats[c.nom] = true end
	local noms = {}
	for nom in pairs(presents or {}) do noms[#noms + 1] = nom end
	table.sort(noms)
	a.evenementT = Raid.Noter("T", { boss = Raid.dernierBoss or "", item = o.id, presents = noms })
	local c1 = r.candidats[1]
	if not c1 then
		Raid.LancerSK(a, Raid.TexteAnnonce(o.lien, r))
		return a
	end
	a.propose, a.score = c1.nom, c1.score
	a.evenementO = Raid.Noter("O", { tombe = a.evenementT, candidat = c1.nom,
		scores = (function () local t = {} for _, c in ipairs(r.candidats) do t[#t + 1] = string.format("%s:%.1f", c.nom, c.score) end return t end)() })
	a.etat, a.fin = "delai", GetTime() + DELAI
	local texte = Raid.TexteAnnonce(o.lien, r, string.format(" Objection : « !objection %d » (%d min).", a.n, DELAI / 60))
	Raid.Annoncer("#" .. a.n .. " " .. texte)
	local candidats = {}
	for nom in pairs(a.candidats) do candidats[#candidats + 1] = nom end
	Diffuser("A", a.n, a.id, a.propose, DELAI, table.concat(candidats, ","))
	C_Timer.After(DELAI, function () FinDelai(a) end)
	Rafraichir()
	return a
end

local function Objecter (a, nom)
	a.objecteurs[#a.objecteurs + 1] = nom
	a.evenementX = Raid.Noter("X", { proposition = a.evenementO, auteur = nom })
	-- les électeurs : les présents qui ne sont pas candidats ; hors groupe (essais), tout le monde
	local presents = Raid.Presents()
	if presents then
		a.electeurs = {}
		for p in pairs(presents) do if not a.candidats[p] then a.electeurs[p] = true end end
		a.nElecteurs = Compter(a.electeurs)
	else
		a.electeurs, a.nElecteurs = nil, 1
	end
	a.quorum = math.max(1, math.ceil(a.nElecteurs * QUORUM))
	a.etat, a.fin = "vote", GetTime() + VOTE
	Diffuser("V", a.n, VOTE, a.quorum, a.nElecteurs, nom)
	Raid.Annoncer(string.format("#%d objection de %s. Vote %d min, non-candidats seulement : « !pour %d » (la proposition tient) ou « !contre %d ». Quorum : %d sur %d.",
		a.n, nom, VOTE / 60, a.n, a.n, a.quorum, a.nElecteurs))
	C_Timer.After(VOTE, function () FinVote(a) end)
	Rafraichir()
end

-- Une objection, un vote ou un « je le veux » (Suicide King), venu du canal raid ou de la fenêtre d'un joueur
-- (Comm.lua) : mot = « objection », « pour », « contre » ou « sk » ; n = le numéro de l'annonce, ou nil.
function Raid.Recevoir (mot, n, expediteur)
	local m = Raid.Identifier(expediteur, true)
	local nom = m and m.nom or Raid.Court(expediteur)
	if not nom then return end
	if mot == "sk" then
		local a = Visee(n, "sk")
		if a then a.interesses[nom] = true Rafraichir() end
		return
	end
	if mot == "objection" then
		local a = Visee(n, "delai")
		if a then Objecter(a, nom) end
		return
	end
	local a = Visee(n, "vote")
	if not a or a.candidats[nom] then return end
	if a.electeurs and not a.electeurs[nom] then return end
	a.votes[nom] = mot
	Rafraichir()
end

-- Un message du canal raid (ou de groupe) : « !objection n », « !pour n », « !contre n ».
function Raid.Entendre (message, expediteur)
	message, expediteur = Propre(message), Propre(expediteur)
	if not message or not expediteur then return end
	local mot, n = strtrim(message):lower():match("^!(%a+)%s*(%d*)$")
	if mot ~= "objection" and mot ~= "pour" and mot ~= "contre" and mot ~= "sk" then return end
	Raid.Recevoir(mot, tonumber(n), expediteur)
end

for _, e in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }) do
	Raid.Ecoute(e, function (message, expediteur) if #Raid.attributions > 0 then Raid.Entendre(message, expediteur) end end)
end

-- le dernier boss vaincu, noté avec l'objet tombé
Raid.Ecoute("ENCOUNTER_END", function (_, nom, _, _, reussi) if reussi == 1 then Raid.dernierBoss = Propre(nom) end end)

-- La décision des officiers après un vote qui renverse la proposition : à un candidat, en Suicide King ou au
-- désenchantement, avec un motif obligatoire.
function Raid.Decider (a, nom, voie, motif)
	if not Raid.PeutGerer() then Msg("décision " .. Raid.QuiPeut() .. ".") return false end
	if a.etat ~= "trancher" then Msg("rien à trancher pour #" .. a.n .. ".") return false end
	motif = strtrim(motif or "")
	if motif == "" then Msg("une décision demande un motif.") return false end
	Raid.Noter("D", { proposition = a.evenementO, attributaire = nom or "", officier = Raid.MonNom(), motif = motif })
	if voie == "wish" then
		Attribuer(a, nom, "wish", " sur décision des officiers : " .. motif)
	elseif voie == "sk" then
		Raid.LancerSK(a, a.lien .. " : décision des officiers (" .. motif .. "), Suicide King.")
	else
		Raid.Desenchanter(a, " sur décision des officiers : " .. motif)
	end
	return true
end

-- ce qu'affiche la fenêtre pour une attribution
function Raid.EtatAttribution (a)
	local reste = a.fin and math.max(0, math.floor(a.fin - GetTime())) or 0
	local chrono = string.format("%d:%02d", math.floor(reste / 60), reste % 60)
	if a.etat == "delai" then return "#" .. a.n .. " " .. a.propose .. " — objections encore " .. chrono end
	if a.etat == "vote" then
		local pour, contre = 0, 0
		for _, v in pairs(a.votes) do if v == "pour" then pour = pour + 1 else contre = contre + 1 end end
		return string.format("#%d vote %s : %d pour, %d contre (quorum %d)", a.n, chrono, pour, contre, a.quorum)
	end
	if a.etat == "trancher" then return "#" .. a.n .. " renversée : aux officiers de trancher" end
	local remise = a.remis and (a.remis == a.attributaire and " — remis" or (" — remis à " .. a.remis .. " !")) or ""
	if a.etat == "attribue" then return "#" .. a.n .. " attribué à " .. a.attributaire .. (remise ~= "" and remise or " — à remettre") end
	if a.etat == "sk" then
		local n = 0
		for _ in pairs(a.interesses) do n = n + 1 end
		return string.format("#%d Suicide King %s : %d intéressé%s", a.n, chrono, n, n > 1 and "s" or "")
	end
	if a.etat == "de" then return "#" .. a.n .. " désenchantement" .. (a.attributaire and (" : " .. a.attributaire) or "") .. remise end
	if a.etat == "banque" then return "#" .. a.n .. " pour la banque" end
	return ""
end

-- Après un rechargement en cours de soirée, les attributions se relisent dans le journal : les remises restent suivies.
-- Une annonce qui n'avait pas abouti (délai, vote, Suicide King en cours) est à trancher par les officiers.
Raid.Ecoute("PLAYER_LOGIN", function ()
	local s = Raid.db.soiree
	if not s or time() - (s.derniere or 0) > 6 * 3600 or #Raid.attributions > 0 then return end
	local par, i = {}, Raid.db.instantane
	for _, e in ipairs(s.evenements) do
		if e.lettre == "T" then
			local a = { n = #Raid.attributions + 1, id = e.item, lien = Raid.LienDe(e.item), votes = {}, objecteurs = {},
				candidats = {}, interesses = {}, evenementT = e.id, etat = "trancher", propose = "?" }
			for _, c in ipairs(i and i.souhaits[e.item] or {}) do a.candidats[c.nom] = true end
			Raid.attributions[a.n], par[e.id] = a, a
		elseif e.lettre == "O" and par[e.tombe] then
			local a = par[e.tombe]
			a.evenementO, a.propose, par[e.id] = e.id, e.candidat, a
		elseif e.lettre == "A" and par[e.tombe] then
			local a = par[e.tombe]
			a.etat = (e.voie == "wish" or e.voie == "sk") and "attribue" or e.voie
			a.attributaire = e.attributaire ~= "" and e.attributaire or nil
			a.evenementA, par[e.id] = e.id, a
		elseif e.lettre == "M" and par[e.attribution] then
			par[e.attribution].remis = e.destinataire
		elseif e.lettre == "K" and e.nature == "delai_proche" and par[e.attribution] then
			par[e.attribution].alerte = true
		end
	end
	local interrompues = {}
	for _, a in ipairs(Raid.attributions) do if a.etat == "trancher" then interrompues[#interrompues + 1] = "#" .. a.n end end
	if #Raid.attributions > 0 then
		Msg(string.format("soirée reprise : %d annonce%s relue%s dans le journal.", #Raid.attributions,
			#Raid.attributions > 1 and "s" or "", #Raid.attributions > 1 and "s" or ""))
	end
	if #interrompues > 0 then
		Msg("|cffffd100interrompues par le rechargement|r : " .. table.concat(interrompues, ", ") .. ", à trancher (/opus raid trancher n).")
	end
end)

Raid.Commande("trancher", "trancher <n>", "la décision des officiers pour l'annonce n° n (après un vote renversé ou un rechargement)", function (texte)
	local a = Raid.attributions[tonumber(texte) or 0]
	if not a then Msg("usage : /opus raid trancher <n> (les numéros : /opus raid objections)") return end
	if a.etat ~= "trancher" then Msg("rien à trancher pour #" .. a.n .. ".") return end
	Raid.OuvrirDecision(a)
end)

Raid.Commande("objections", "objections", "les annonces de la soirée et leur état", function ()
	if #Raid.attributions == 0 then Msg("aucune annonce ce soir.") return end
	for _, a in ipairs(Raid.attributions) do DEFAULT_CHAT_FRAME:AddMessage("  " .. a.lien .. " : " .. Raid.EtatAttribution(a)) end
end)
