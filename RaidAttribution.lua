-- RaidAttribution.lua : d'une annonce à l'attribution, avec le délai, l'objection et le vote (WishVote)
-- Tout passe par le canal raid, sans que les joueurs aient besoin de l'addon :
--   « !objection n [motif] » pendant les 3 minutes après l'annonce n° n (n facultatif s'il n'y a qu'une annonce en
--   cours) ; une objection ouvre un vote de 2 minutes entre les candidats présents : « !vote n k » (k, le numéro du
--   candidat dans l'annonce du vote, ou son nom). Seuls votent les présents qui ne sont pas candidats, officiers
--   compris, une voix chacun ; le dernier vote compte. Quorum : la moitié des électeurs. Quorum atteint : le vote
--   s'applique, une égalité en tête passe aux officiers ; sans quorum, la proposition tient. Les officiers peuvent
--   trancher à tout moment (pour le raid et le progress), toujours avec un motif.
-- Seul le client qui a annoncé compte : c'est celui du maître du butin. Chaque étape est notée pour le rapport.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

local QUORUM = 0.5                  -- part des électeurs qui doivent voter
-- le délai d'objection et la durée du vote : Raid.Duree("objection"), Raid.Duree("vote") (réglables)
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
	-- une soirée de guilde (pas un essai hors groupe) : son rapport part au site par le bridge
	if Raid.db.ouverte and (IsInRaid() or IsInGroup()) then s.guilde = true end
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
Raid.DiffuserAttribution = function (a) Diffuser("R", a.n, a.etat, a.attributaire or "", a.id or "") end

local function Attribuer (a, nom, voie, comment)
	a.etat, a.attributaire = "attribue", nom
	Raid.DiffuserAttribution(a)
	a.evenementA = Raid.Noter("A", { tombe = a.evenementT, attributaire = nom, voie = voie })
	if Raid.ApresAttribution then Raid.ApresAttribution(a) end
	-- courte : le gagnant ; le comment (vote, Suicide King…) en détaillé, ou toujours pour une décision des officiers
	if Raid.Detaillees() or a.decision then Raid.Annoncer(string.format("#%d %s attribué à %s%s.", a.n, a.lien, nom, comment or ""))
	else Raid.Annoncer(string.format("#%d %s » %s.", a.n, a.lien, nom)) end
	Rafraichir()
end

Raid.Attribuer = Attribuer

local function FinDelai (a, comment)
	if a.etat ~= "delai" then return end
	Attribuer(a, a.propose, "wish", comment or " (pas d'objection)")
end

-- Sans instantané : l'objet donné directement à un présent, par le maître du butin. Noté au rapport comme une
-- attribution (T puis A), avec le motif dans l'annonce ; le don depuis le corps suit, comme pour les autres.
function Raid.DonnerDirect (o, nom)
	local actif, raison = Raid.Actif()
	if not actif then Msg(raison .. ".") return nil end
	if not Raid.PeutGerer() then Msg("attribution " .. Raid.QuiPeut() .. ".") return nil end
	if o.attribution then return o.attribution end
	Soiree()
	local a = { n = #Raid.attributions + 1, lien = o.lien, id = o.id, source = o.source, votes = {}, objecteurs = {}, candidats = {} }
	Raid.attributions[a.n] = a
	local noms = {}
	for p in pairs(Raid.Presents() or {}) do noms[#noms + 1] = p end
	table.sort(noms)
	a.evenementT = Raid.Noter("T", { boss = Raid.dernierBoss or "", item = o.id, presents = noms })
	a.decision = true
	Attribuer(a, nom, "wish", " (donné par le maître du butin, sans liste ce soir)")
	o.attribution = a
	return a
end

-- Le maître du butin abrège un tour : le délai sans objection attribue tout de suite au proposé, le Suicide King
-- classe les déclarés du moment. Le minuteur d'origine, plus tard, ne trouve plus rien à faire.
function Raid.CloreTour (a)
	if not Raid.PeutGerer() then Msg("clore " .. Raid.QuiPeut() .. ".") return false end
	if a.etat == "delai" then FinDelai(a, " (pas d'objection, délai clos par le maître du butin)") return true end
	if a.etat == "sk" then Raid.FinSK(a) return true end
	return false
end

-- Les voix de chaque candidat du vote, dans l'ordre de l'annonce : { { nom, voix }, … }, le nombre de votants, et les
-- candidats en tête (plusieurs : égalité).
function Raid.Decompte (a)
	local voix, votants = {}, 0
	for _, nom in pairs(a.votes or {}) do voix[nom] = (voix[nom] or 0) + 1 votants = votants + 1 end
	local liste, haut, tete = {}, 0, {}
	for _, nom in ipairs(a.choix or {}) do
		local v = voix[nom] or 0
		liste[#liste + 1] = { nom = nom, voix = v }
		if v > haut then haut, tete = v, { nom } elseif v == haut and v > 0 then tete[#tete + 1] = nom end
	end
	return liste, votants, tete
end

-- « Essai Lame 6 – Légende Urbaine 3 » : les candidats qui ont des voix, du plus au moins
local function Bilan (liste)
	local t = {}
	for _, c in ipairs(liste) do if c.voix > 0 then t[#t + 1] = c end end
	table.sort(t, function (x, y) return x.voix > y.voix end)
	for k, c in ipairs(t) do t[k] = c.nom .. " " .. c.voix end
	return #t > 0 and table.concat(t, " – ") or "aucune voix"
end

local function FinVote (a)
	if a.etat ~= "vote" then return end
	local liste, votants, tete = Raid.Decompte(a)
	local atteint = votants >= a.quorum
	local gagnant = atteint and #tete == 1 and tete[1] or ""
	local pour = 0
	for _, c in ipairs(liste) do if c.nom == a.propose then pour = c.voix end end
	local detail = {}
	for _, c in ipairs(liste) do detail[#detail + 1] = c.nom .. ":" .. c.voix end
	Raid.Noter("V", { objection = a.evenementX, pour = pour, contre = votants - pour, electeurs = a.nElecteurs, quorum = atteint and 1 or 0,
		gagnant = gagnant, detail = detail })
	local bilan = Bilan(liste)
	local qui = a.objecteurs[1] and (" · objection de " .. a.objecteurs[1]) or ""
	if not atteint then
		Attribuer(a, a.propose, "wish", string.format(" · vote %s, quorum non atteint (%d sur %d)%s : la proposition tient", bilan, votants, a.quorum, qui))
	elseif gagnant == "" then
		a.etat = "trancher"
		Raid.DiffuserAttribution(a)
		Raid.Annoncer(string.format("#%d %s : vote %s, égalité entre %s : les officiers tranchent.", a.n, a.lien, bilan, table.concat(tete, " et ")))
		Rafraichir()
		if Raid.OuvrirDecision then Raid.OuvrirDecision(a) end
	else
		Attribuer(a, gagnant, "wish", string.format(" · vote %s · quorum atteint%s", bilan, qui))
	end
end

-- Un objet que personne de présent n'a en liste, envoyé droit au désenchantement par le maître du butin : ni annonce,
-- ni délai, ni Suicide King. Il est noté au rapport comme les autres (T puis A « de »). Rend l'attribution.
function Raid.DesenchanterObjet (o)
	local actif, raison = Raid.Actif()
	if not actif then Msg(raison .. ".") return nil end
	if not Raid.PeutGerer() then Msg("désenchantement " .. Raid.QuiPeut() .. ".") return nil end
	local presents = Raid.Presents()
	local r = Raid.Proposer(o.id, presents)
	if r and #r.candidats > 0 then Msg(o.lien .. " est en liste chez " .. r.candidats[1].nom .. " : annonce-le.") return nil end
	Soiree()
	local a = { n = #Raid.attributions + 1, lien = o.lien, id = o.id, source = o.source, votes = {}, objecteurs = {}, candidats = {} }
	Raid.attributions[a.n] = a
	local noms = {}
	for nom in pairs(presents or {}) do noms[#noms + 1] = nom end
	table.sort(noms)
	a.evenementT = Raid.Noter("T", { boss = Raid.dernierBoss or "", item = o.id, presents = noms })
	Raid.Desenchanter(a, " (hors liste)")
	return a
end

-- Annonce un objet et lance le délai. o = { lien, id } ; rend l'attribution.
function Raid.Lancer (o)
	local actif, raison = Raid.Actif()
	if not actif then Msg(raison .. ".") return nil end
	local presents = Raid.Presents()
	local r = Raid.Proposer(o.id, presents)
	-- sans instantané (pas de listes sur ce poste) : le Suicide King, directement
	if not r then
		Soiree()
		local a = { n = #Raid.attributions + 1, lien = o.lien, id = o.id, source = o.source, votes = {}, objecteurs = {}, candidats = {} }
		Raid.attributions[a.n] = a
		local noms = {}
		for nom in pairs(presents or {}) do noms[#noms + 1] = nom end
		table.sort(noms)
		a.evenementT = Raid.Noter("T", { boss = Raid.dernierBoss or "", item = o.id, presents = noms })
		Raid.LancerSK(a, o.lien .. " (sans liste ce soir)")
		return a
	end
	local s = Soiree()
	-- source : le corps d'où vient l'objet (son GUID), pour le reconnaître quand on le rouvre
	local a = { n = #Raid.attributions + 1, lien = o.lien, id = o.id, source = o.source, votes = {}, objecteurs = {} }
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
	local delai = Raid.Duree("objection")
	a.etat, a.fin, a.duree = "delai", GetTime() + delai, delai
	local texte = Raid.Detaillees() and Raid.TexteAnnonce(o.lien, r, string.format(" Objection : « !objection %d » (%s).", a.n, Raid.TexteDuree(delai)))
		or string.format("%s » %s%s. Objection : « !objection %d » (%s).", o.lien, c1.nom, r.egalite and " (ex aequo)" or "", a.n, Raid.TexteDuree(delai))
	Raid.Annoncer("#" .. a.n .. " " .. texte)
	local candidats = {}
	for nom in pairs(a.candidats) do candidats[#candidats + 1] = nom end
	Diffuser("A", a.n, a.id, a.propose, delai, table.concat(candidats, ","))
	C_Timer.After(delai, function () FinDelai(a) end)
	Rafraichir()
	return a
end

local function Objecter (a, nom, motif)
	a.objecteurs[#a.objecteurs + 1] = nom
	motif = strtrim((motif or ""):gsub("[;~]", " ")):sub(1, 80)
	a.motif = motif ~= "" and motif or nil
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
	-- le vote se fait entre les candidats présents, dans l'ordre du calcul
	a.choix = {}
	local r = Raid.Proposer(a.id, presents)
	for _, c in ipairs(r and r.candidats or {}) do a.choix[#a.choix + 1] = c.nom end
	local vote = Raid.Duree("vote")
	a.etat, a.fin, a.votes, a.duree = "vote", GetTime() + vote, {}, vote
	Diffuser("V", a.n, vote, a.quorum, a.nElecteurs, nom, table.concat(a.choix, ","), a.motif or "")
	local numeros = {}
	for k, c in ipairs(a.choix) do numeros[k] = k .. " " .. c end
	local motifTexte = a.motif and (" (« " .. a.motif .. " »)") or ""
	if Raid.Detaillees() then
		Raid.Annoncer(string.format("#%d objection de %s%s. Vote %s entre les candidats, « !vote %d <numéro> » : %s. Votent les non-candidats, quorum %d sur %d.",
			a.n, nom, motifTexte, Raid.TexteDuree(vote), a.n, table.concat(numeros, ", "), a.quorum, a.nElecteurs))
	else
		Raid.Annoncer(string.format("#%d objection de %s%s. Vote (%s) : « !vote %d <numéro> », %s.",
			a.n, nom, motifTexte, Raid.TexteDuree(vote), a.n, table.concat(numeros, ", ")))
	end
	C_Timer.After(vote, function () FinVote(a) end)
	Rafraichir()
	-- chez celui qui a annoncé : la fiche s'ouvre sur l'objection, pour suivre le vote (et y voter)
	if Raid.OuvrirFiche then Raid.OuvrirFiche(a) end
end

-- « Je le laisse » : un candidat renonce, pendant le délai ou le vote. Le proposé qui le laisse à un candidat présent
-- le lui donne ; sinon il sort des candidats du vote (s'il n'en reste qu'un, l'objet est à lui), ou, pendant le délai,
-- la proposition passe au suivant du calcul.
local function Laisser (a, nom, choix)
	if a.etat ~= "delai" and a.etat ~= "vote" then return end
	local presents = Raid.Presents()
	local r = Raid.Proposer(a.id, presents)
	local suivants = {}
	for _, c in ipairs(r and r.candidats or {}) do if c.nom ~= nom then suivants[#suivants + 1] = c.nom end end
	local pour = strtrim(tostring(choix or ""))
	local valide = false
	for _, c in ipairs(suivants) do if c:lower() == pour:lower() then pour, valide = c, true end end
	if a.etat == "vote" then
		local reste = {}
		for _, c in ipairs(a.choix) do if c ~= nom then reste[#reste + 1] = c end end
		if #reste == #a.choix then return end           -- il n'était pas candidat du vote
		for votant, c in pairs(a.votes) do if c == nom then a.votes[votant] = nil end end
		if valide then Attribuer(a, pour, "wish", " (laissé par " .. nom .. ")") return end
		a.choix = reste
		if #reste == 1 then Attribuer(a, reste[1], "wish", " (" .. nom .. " le laisse)") return end
		Diffuser("V", a.n, math.max(1, math.floor(a.fin - GetTime())), a.quorum, a.nElecteurs, a.objecteurs[1] or "", table.concat(a.choix, ","), a.motif or "")
		Raid.Annoncer(string.format("#%d %s le laisse : vote entre %s.", a.n, nom, table.concat(a.choix, ", ")))
		Rafraichir()
		return
	end
	if nom ~= a.propose then return end
	if valide then Attribuer(a, pour, "wish", " (laissé par " .. nom .. ")") return end
	if #suivants == 0 then Raid.LancerSK(a, a.lien .. " : " .. nom .. " le laisse, Suicide King.", true) return end
	Attribuer(a, suivants[1], "wish", " (" .. nom .. " le laisse au suivant)")
end

-- Une objection, un vote ou un « je le veux » (Suicide King), venu du canal raid ou de la fenêtre d'un joueur
-- (Comm.lua) : mot = « objection », « vote », « pour », « sk » ou « passe » ; n = le numéro de l'annonce, ou nil.
function Raid.Recevoir (mot, n, expediteur, choix)
	local m = Raid.Identifier(expediteur, true)
	local nom = m and m.nom or Raid.Court(expediteur)
	if not nom then return end
	if mot == "sk" or mot == "passe" then
		local a = Visee(n, "sk")
		if not a then return end
		a.passes = a.passes or {}
		if mot == "sk" then
			a.interesses[nom], a.passes[nom] = true, nil
			-- l'ordre des déclarations départage ceux que la liste ne classe pas
			a.ordre = a.ordre or {}
			if not a.ordre[nom] then a.nOrdre = (a.nOrdre or 0) + 1 a.ordre[nom] = a.nOrdre end
		else a.passes[nom], a.interesses[nom] = true, nil end
		-- les déclarés, du mieux placé au moins bien : chacun voit qui est en tête (un envoi par seconde au plus)
		if not a.classementPrevu then
			a.classementPrevu = true
			C_Timer.After(1, function ()
				a.classementPrevu = nil
				if a.etat == "sk" then Diffuser("K", a.n, table.concat((Raid.ClassementSK(a)), ",")) end
			end)
		end
		Rafraichir()
		-- tout le monde a répondu (je le veux ou je passe) : inutile d'attendre la fin du temps
		if Raid.ToutLeMondeARepondu(a) then Raid.FinSK(a) end
		return
	end
	if mot == "objection" then
		local a = Visee(n, "delai")
		if a then Objecter(a, nom, choix) end
		return
	end
	if mot == "laisse" then
		local a = (n and Raid.attributions[n]) or Visee(nil, "delai") or Visee(nil, "vote")
		if a then Laisser(a, nom, choix) end
		return
	end
	local a = Visee(n, "vote")
	if not a or a.candidats[nom] then return end
	if a.electeurs and not a.electeurs[nom] then return end
	-- « !pour n » (ancienne forme) : la proposition ; sinon le numéro du candidat dans l'annonce, ou son nom
	local pour
	if mot == "pour" then pour = a.propose
	elseif mot == "vote" then
		local k, bas = tonumber(choix), strtrim(tostring(choix or "")):lower()
		if k then pour = a.choix[k]
		elseif bas ~= "" then
			for _, c in ipairs(a.choix) do
				local cb = c:lower()
				if cb == bas or cb:match("^%S+") == bas then
					if pour then pour = nil break end   -- deux candidats du même prénom : ambigu
					pour = c
				end
			end
		end
	end
	if not pour then return end
	a.votes[nom] = pour
	Rafraichir()
end

-- Un message du canal raid (ou de groupe) : « !objection n [motif] », « !vote n k », « !sk n », « !passe n » (et « !pour n »).
function Raid.Entendre (message, expediteur)
	message, expediteur = Propre(message), Propre(expediteur)
	if not message or not expediteur then return end
	local mot, n, reste = strtrim(message):match("^!(%a+)%s*(%d*)%s*(.-)$")
	mot = mot and mot:lower()
	if mot ~= "objection" and mot ~= "vote" and mot ~= "pour" and mot ~= "sk" and mot ~= "passe" and mot ~= "laisse" then return end
	-- « !vote 2 » : le candidat n° 2 du seul vote en cours
	if mot == "vote" and reste == "" then n, reste = nil, n end
	Raid.Recevoir(mot, tonumber(n), expediteur, reste)
end

for _, e in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }) do
	Raid.Ecoute(e, function (message, expediteur) if #Raid.attributions > 0 then Raid.Entendre(message, expediteur) end end)
end

-- le dernier boss vaincu, noté avec l'objet tombé
Raid.Ecoute("ENCOUNTER_END", function (_, nom, _, _, reussi) if reussi == 1 then Raid.dernierBoss = Propre(nom) end end)

-- La décision des officiers, pour le raid et le progress, à tout moment avant l'attribution (pendant le délai, le vote,
-- ou après une égalité) : à un candidat, en Suicide King ou au désenchantement, avec un motif obligatoire.
local DECIDABLE = { delai = true, vote = true, trancher = true }
Raid.Decidable = function (a) return a and DECIDABLE[a.etat] or false end
function Raid.Decider (a, nom, voie, motif)
	if not Raid.PeutGerer() then Msg("décision " .. Raid.QuiPeut() .. ".") return false end
	if not DECIDABLE[a.etat] then Msg("rien à trancher pour #" .. a.n .. ".") return false end
	motif = strtrim(motif or "")
	if motif == "" then Msg("une décision demande un motif.") return false end
	Raid.Noter("D", { proposition = a.evenementO, attributaire = nom or "", officier = Raid.MonNom(), motif = motif })
	a.decision = true               -- une décision s'annonce toujours avec son motif
	if voie == "wish" then
		Attribuer(a, nom, "wish", " sur décision des officiers : " .. motif)
	elseif voie == "sk" then
		Raid.LancerSK(a, a.lien .. " : décision des officiers (" .. motif .. "), Suicide King.", true)
	else
		Raid.Desenchanter(a, " sur décision des officiers : " .. motif)
	end
	return true
end

-- Un joueur qui recharge (ou arrive) demande où en est la soirée : on lui renvoie l'état des annonces récentes et en
-- cours, comme au moment de les faire (A, V, S, K, R). Les clients qui les ont déjà ignorent ce qu'ils connaissent.
-- Une seule reprise à la fois, les messages espacés.
local renvoi = false
function Raid.RenvoyerEtat ()
	if renvoi or #Raid.attributions == 0 or not Raid.PeutGerer() then return end
	renvoi = true
	local file = {}
	local premier = math.max(1, #Raid.attributions - 9)
	for n, a in ipairs(Raid.attributions) do
		local actif = a.etat == "delai" or a.etat == "vote" or a.etat == "sk" or a.etat == "trancher"
		if not actif and n >= premier then
			-- déjà tranché : le résultat seul (avec l'objet, pour qui ne connaissait pas l'annonce)
			file[#file + 1] = { "R", a.n, a.etat, a.attributaire or "", a.id or "" }
		elseif actif then
			local reste = a.fin and math.max(1, math.floor(a.fin - GetTime())) or 1
			local candidats = {}
			for nom in pairs(a.candidats or {}) do candidats[#candidats + 1] = nom end
			if a.propose and a.propose ~= "?" then
				file[#file + 1] = { "A", a.n, a.id, a.propose, a.etat == "delai" and reste or 1, table.concat(candidats, ",") }
			else
				file[#file + 1] = { "S", a.n, a.id, a.etat == "sk" and reste or 1 }
			end
			if a.etat == "vote" then
				file[#file + 1] = { "V", a.n, reste, a.quorum or 1, a.nElecteurs or 1, a.objecteurs[1] or "", table.concat(a.choix or {}, ","), a.motif or "" }
			elseif a.etat == "sk" then
				file[#file + 1] = { "K", a.n, table.concat((Raid.ClassementSK(a)), ",") }
			end
			if a.etat == "trancher" then file[#file + 1] = { "R", a.n, a.etat, a.attributaire or "", a.id or "" } end
		end
	end
	for k, m in ipairs(file) do
		C_Timer.After(k * 0.3, function () Diffuser(unpack(m)) end)
	end
	C_Timer.After(#file * 0.3 + 5, function () renvoi = false end)
end

-- ce qu'affiche la fenêtre pour une attribution
function Raid.EtatAttribution (a)
	local reste = a.fin and math.max(0, math.floor(a.fin - GetTime())) or 0
	local chrono = string.format("%d:%02d", math.floor(reste / 60), reste % 60)
	if a.etat == "delai" then return "#" .. a.n .. " " .. a.propose .. " — objections encore " .. chrono end
	if a.etat == "vote" then
		local _, votants, tete = Raid.Decompte(a)
		return string.format("#%d vote %s : %d votant%s, quorum %d%s", a.n, chrono, votants, votants > 1 and "s" or "", a.quorum,
			#tete == 1 and (" · en tête : " .. tete[1]) or #tete > 1 and " · égalité en tête" or "")
	end
	if a.etat == "trancher" then return "#" .. a.n .. " : aux officiers de trancher" end
	local remise = a.remis and (a.remis == a.attributaire and " — remis" or (" — remis à " .. a.remis .. " !")) or ""
	if a.etat == "attribue" then return "#" .. a.n .. " attribué à " .. a.attributaire .. (remise ~= "" and remise or " — à remettre") end
	if a.etat == "sk" then
		local n = 0
		for _ in pairs(a.interesses) do n = n + 1 end
		local tete = Raid.ClassementSK and Raid.ClassementSK(a)[1]
		return string.format("#%d Suicide King %s : %d intéressé%s%s", a.n, chrono, n, n > 1 and "s" or "", tete and (" · en tête : " .. tete) or "")
	end
	if a.etat == "de" then return "#" .. a.n .. " désenchantement" .. (a.attributaire and (" : " .. a.attributaire) or "") .. remise end
	if a.etat == "banque" then return "#" .. a.n .. " pour la banque" end
	return ""
end

-- À la déconnexion (et à chaque rechargement), les attributions de la soirée sont gardées telles quelles, avec l'heure
-- de fin de chaque tour en cours ; elles reprennent au retour.
local FINS = { delai = function (a) FinDelai(a) end, vote = function (a) FinVote(a) end, sk = function (a) Raid.FinSK(a) end }
Raid.Ecoute("PLAYER_LOGOUT", function ()
	local s = Raid.db.soiree
	if not s or #Raid.attributions == 0 then return end
	for _, a in ipairs(Raid.attributions) do
		a.finT = a.fin and (time() + math.floor(a.fin - GetTime() + 0.5)) or nil
		a.classementPrevu = nil
	end
	s.attributionsGardees = Raid.attributions
end)

-- Au retour : les tours en cours reprennent avec le temps qui leur restait ; un tour fini pendant l'absence se termine
-- comme il l'aurait fait (le délai sans objection attribue, le vote compte ses voix, le Suicide King classe).
local function Reprendre (s)
	Raid.attributions = s.attributionsGardees
	s.attributionsGardees = nil
	local reprises, finies = 0, 0
	for _, a in ipairs(Raid.attributions) do
		local fin = FINS[a.etat]
		if fin then
			local reste = (a.finT or 0) - time()
			if reste > 1 then
				a.fin = GetTime() + reste
				C_Timer.After(reste, function () fin(a) end)
				reprises = reprises + 1
			else
				-- le groupe se relit d'abord (présents, électeurs)
				C_Timer.After(3, function () fin(a) end)
				finies = finies + 1
			end
		end
	end
	Msg(string.format("soirée reprise : %d annonce%s, %d tour%s en cours repris, %d terminé%s pendant le rechargement.",
		#Raid.attributions, #Raid.attributions > 1 and "s" or "", reprises, reprises > 1 and "s" or "", finies, finies > 1 and "s" or ""))
	-- les joueurs se recalent sur l'état repris
	C_Timer.After(5, function () if IsInGroup() and Raid.RenvoyerEtat then Raid.RenvoyerEtat() end end)
	Rafraichir()
end

-- Après un rechargement en cours de soirée, les attributions reprennent (ci-dessus) ; sans elles (une version d'avant),
-- elles se relisent dans le journal : les remises restent suivies, et une annonce qui n'avait pas abouti est à trancher.
Raid.Ecoute("PLAYER_LOGIN", function ()
	local s = Raid.db.soiree
	if not s or time() - (s.derniere or 0) > 6 * 3600 or #Raid.attributions > 0 then return end
	-- une soirée fermée ne revient pas : rien à reprendre
	if not Raid.db.ouverte then s.attributionsGardees = nil return end
	if s.attributionsGardees and #s.attributionsGardees > 0 then Reprendre(s) return end
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
