-- Registre.lua : les prêts de la guilde et les remises d'objets sortis de la banque, visibles de toute la guilde
-- Un prêt va dans un sens ou dans l'autre : un joueur a avancé de l'or à la guilde (« la guilde lui doit »), ou la guilde
-- a prêté à un joueur (« il doit à la guilde »). Ses remboursements s'y ajoutent ; l'addon en propose d'après la banque
-- (dépôt d'un débiteur, retrait d'un créancier, or envoyé à un créancier) et un officier les confirme. Un dépôt relié à
-- un prêt ou à un remboursement ne compte pas comme cotisation (Cotisation.lua).
-- Une remise : un objet retiré de la banque puis donné par courrier ou par échange, à un joueur ou à un autre de ses
-- personnages. L'addon la note toute seule quand l'objet envoyé correspond à un de ses retraits récents.
-- Chaque enregistrement porte un identifiant et une date de modification : la version la plus récente l'emporte, une
-- suppression en garde la trace. Prêts et remboursements : chef et officiers ; une remise : son auteur, ou un officier.
-- Messages : « B » (un enregistrement), « b » (demande de rattrapage à la connexion).
local _, Opus = ...
local Msg = Opus.Msg

local FS = Opus.FS
local CONSERVATION = 400 * 86400       -- les remises et les prêts soldés, en secondes
local ATTENTE = 14 * 24                -- en heures : un retrait non remis reste « en attente » deux semaines
local RATTRAPAGE_MAX = 200

local function Registre ()
	local guilde = GetGuildInfo("player")
	if not guilde then return nil end
	Opus.db.registre = Opus.db.registre or {}
	local r = Opus.db.registre[guilde] or {}
	Opus.db.registre[guilde] = r
	return r
end

-- une opération de la banque, telle qu'un prêt, un remboursement ou une remise y renvoie ; deux relevés peuvent la
-- dater à une heure près (Banque.lua), d'où la comparaison avec marge
function Opus.SignatureOp (e)
	return table.concat({ e.q, e.t, e.c or e.n or 0, e.nom }, ":")
end

-- un ensemble de signatures : Ajouter(s, n) puis Trouver(e) → ce qui a été ajouté pour cette opération (n cumulés)
local function Ensemble ()
	local index = {}
	local ens = {}
	function ens.Ajouter (sig, n)
		local q, t, x, nom = sig:match("^([^:]+):(%d+):(%d+):(.+)$")
		if not q then return end
		local cle = q .. ":" .. x .. ":" .. nom
		index[cle] = index[cle] or {}
		table.insert(index[cle], { t = tonumber(t), n = n or 1 })
	end
	function ens.Trouver (e)
		local total = 0
		for _, v in ipairs(index[e.q .. ":" .. (e.c or e.n or 0) .. ":" .. e.nom] or {}) do
			if math.abs(v.t - e.t) <= 1 then total = total + v.n end
		end
		return total
	end
	return ens
end

-- même joueur (ses personnages ensemble)
local function MemeJoueur (a, b) return a and b and (a == b or Opus.Joueur(a) == Opus.Joueur(b)) end

-- un nom tapé (destinataire d'un courrier, d'un échange, saisie) : le membre du roster, prénom seul compris
function Opus.MembreDe (nom)
	if not nom or nom == "" then return nil end
	nom = Opus.Court(strtrim(nom))
	local m = Opus.TrouverMembre(nom)
	if m then return m end
	local bas = nom:lower()
	for _, x in ipairs(Opus.Membres()) do
		if x.nom:lower() == bas or Opus.EstMembre(x.nom, nom) then return x end
	end
	return nil
end

------------------------------------------------------------------------
-- lecture
------------------------------------------------------------------------

-- les opérations de la banque reliées à un prêt ou un remboursement : liees.Trouver(e) > 0
function Opus.OperationsLiees ()
	local liees = Ensemble()
	for _, r in pairs(Registre() or {}) do
		if not r.x and r.ev and r.k ~= "remise" then liees.Ajouter(r.ev) end
	end
	return liees
end

-- les prêts : { r, rembs, rendu, reste } ; ouverts d'abord, puis les plus récents
function Opus.Prets ()
	local reg, prets, par = Registre() or {}, {}, {}
	for id, r in pairs(reg) do
		if r.k == "pret" and not r.x then
			local p = { r = r, rembs = {}, rendu = 0 }
			par[id] = p
			prets[#prets + 1] = p
		end
	end
	for _, r in pairs(reg) do
		local p = r.k == "remb" and not r.x and par[r.pret]
		if p then
			p.rembs[#p.rembs + 1] = r
			p.rendu = p.rendu + r.c
		end
	end
	for _, p in ipairs(prets) do
		p.reste = math.max(0, p.r.c - p.rendu)
		table.sort(p.rembs, function (a, b) return a.d > b.d end)
	end
	table.sort(prets, function (a, b)
		if (a.reste > 0) ~= (b.reste > 0) then return a.reste > 0 end
		return a.r.d > b.r.d
	end)
	return prets
end

-- ce que la guilde doit, et ce qu'on lui doit (cuivre, nombre de prêts ouverts)
function Opus.BilanPrets ()
	local doit, du, nDoit, nDu = 0, 0, 0, 0
	for _, p in ipairs(Opus.Prets()) do
		if p.reste > 0 then
			if p.r.sens == "g" then doit, nDoit = doit + p.reste, nDoit + 1 else du, nDu = du + p.reste, nDu + 1 end
		end
	end
	return doit, nDoit, du, nDu
end

-- les opérations de la banque qui ressemblent à un remboursement de ce prêt : dépôts du débiteur, retraits du créancier
function Opus.Propositions (p)
	if p.reste <= 0 then return {} end
	local q = p.r.sens == "g" and "or-" or "or+"
	local depuis, liees, liste = math.floor(p.r.d / 3600) - 1, Opus.OperationsLiees(), {}
	for _, e in ipairs(Opus.db.banque.evenements) do
		if e.q == q and e.t >= depuis and MemeJoueur(e.nom, p.r.qui) and liees.Trouver(e) == 0 then
			liste[#liste + 1] = e
		end
	end
	table.sort(liste, function (a, b) return a.t > b.t end)
	return liste
end

-- les remises, les plus récentes d'abord
function Opus.Remises ()
	local liste = {}
	for _, r in pairs(Registre() or {}) do
		if r.k == "remise" and not r.x then liste[#liste + 1] = r end
	end
	table.sort(liste, function (a, b) return a.d > b.d end)
	return liste
end

-- ses retraits d'objets récents pas encore remis : { e, reste }
function Opus.RetraitsEnAttente ()
	local moi, depuis, remis = Opus.MonNom(), math.floor(time() / 3600) - ATTENTE, Ensemble()
	for _, r in pairs(Registre() or {}) do
		if r.k == "remise" and not r.x and r.ev then remis.Ajouter(r.ev, r.n) end
	end
	local liste = {}
	for _, e in ipairs(Opus.db.banque.evenements) do
		if e.q == "obj-" and e.t >= depuis and MemeJoueur(e.nom, moi) then
			local reste = e.n - remis.Trouver(e)
			if reste > 0 then liste[#liste + 1] = { e = e, reste = reste } end
		end
	end
	table.sort(liste, function (a, b) return a.e.t < b.e.t end)
	return liste
end

------------------------------------------------------------------------
-- partage : un enregistrement par message
------------------------------------------------------------------------

local function Mot (s, max) return Opus.MotMsg(s or "", max or 48) end

local function Encoder (r)
	local champs = { "B", r.id, r.t, Mot(r.par), r.x and 1 or 0, r.k }
	local reste
	if r.k == "pret" then reste = { r.sens, Mot(r.qui), r.c, r.d, r.ev or "", Mot(r.motif, 60) }
	elseif r.k == "remb" then reste = { r.pret, r.c, r.d, r.ev or "", Mot(r.note, 60) }
	else reste = { Mot(r.de), Mot(r.a), r.id_ or "", r.n, r.via, r.d, r.ev or "", Mot(r.o, 50) } end
	for _, v in ipairs(reste) do champs[#champs + 1] = v end
	return Opus.CoupeMsg(table.concat(champs, FS), Opus.MAX_MSG)
end

local function Partager (r) if IsInGuild() then Opus.Envoyer(Encoder(r)) end end

local VIAS = { courrier = true, echange = true, main = true, garde = true }

local function Decoder (c)
	local id, t, par, x, k = c[2], tonumber(c[3]), c[4], c[5] == "1", c[6]
	if not id or not id:match("^%x+$") or #id > 16 or not t or t > time() + 86400 or not par or par == "" then return nil end
	local r = { id = id, t = t, par = par, x = x or nil, k = k }
	local function Entier (v) v = tonumber(v) return v and v >= 0 and v < 2^40 and math.floor(v) or nil end
	if k == "pret" then
		r.sens, r.qui, r.c, r.d, r.ev, r.motif = c[7], c[8], Entier(c[9]), Entier(c[10]), c[11], c[12]
		if (r.sens ~= "g" and r.sens ~= "j") or not r.qui or r.qui == "" or not r.c or r.c <= 0 or not r.d then return nil end
	elseif k == "remb" then
		r.pret, r.c, r.d, r.ev, r.note = c[7], Entier(c[8]), Entier(c[9]), c[10], c[11]
		if not r.pret or r.pret == "" or not r.c or r.c <= 0 or not r.d then return nil end
	elseif k == "remise" then
		r.de, r.a, r.id_, r.n, r.via, r.d, r.ev, r.o = c[7], c[8], Entier(c[9]), Entier(c[10]), c[11], Entier(c[12]), c[13], c[14]
		if not r.de or r.de == "" or not r.a or r.a == "" or not r.n or r.n <= 0 or not VIAS[r.via] or not r.d then return nil end
	else
		return nil
	end
	if r.ev == "" then r.ev = nil end
	if r.motif == "" then r.motif = nil end
	if r.note == "" then r.note = nil end
	return r
end

-- l'auteur peut-il écrire cet enregistrement ? (et remplacer l'ancien, s'il y en a un)
local function Permis (r, ancien)
	local auteur = Opus.TrouverMembre(r.par)
	if not auteur then return false end
	if Opus.PeutConfigurer(auteur.grade) then return true end
	return r.k == "remise" and r.de == r.par and (not ancien or ancien.de == r.par)
end

local function Retenir (r)
	local reg = Registre()
	if not reg then return false end
	local ancien = reg[r.id]
	if ancien and (ancien.t >= r.t or ancien.k ~= r.k) then return false end
	if not Permis(r, ancien) then return false end
	reg[r.id] = r
	return true
end

-- enregistre une saisie locale, puis la partage
local function Ecrire (r)
	r.id = r.id or Opus.NouvelId()
	r.t, r.par = time(), Opus.MonNom()
	local reg = Registre()
	if not reg then return nil end
	reg[r.id] = r
	Partager(r)
	if Opus.Rafraichir then Opus.Rafraichir() end
	return r
end

Opus.recepteurs.B = function (_, champs, _, canal)
	if canal ~= "GUILD" then return end
	local r = Decoder(champs)
	if r and Retenir(r) and Opus.Rafraichir then Opus.Rafraichir() end
end

------------------------------------------------------------------------
-- le solde de la banque (« O ») : lu par qui ouvre la banque, partagé aux autres
------------------------------------------------------------------------

local function PartagerSolde ()
	local s = Opus.db.banque.solde
	if s and IsInGuild() then Opus.Envoyer(table.concat({ "O", s.c, s.t }, FS)) end
end

-- retient le solde s'il est plus récent ; lu = relevé à la banque par ce joueur, à partager s'il a changé
function Opus.RetenirSolde (c, t, lu)
	local s = Opus.db.banque.solde
	if s and s.t >= t then return false end
	local change = not s or s.c ~= c
	Opus.db.banque.solde = { c = c, t = t }
	if lu and change then PartagerSolde() end
	return true
end

Opus.recepteurs.O = function (_, champs, _, canal)
	local c, t = tonumber(champs[2]), tonumber(champs[3])
	if canal ~= "GUILD" or not c or c < 0 or not t or t > time() + 86400 then return end
	if Opus.RetenirSolde(c, t) and Opus.Rafraichir then Opus.Rafraichir() end
end

-- rattrapage : on renvoie ce qui est plus récent que le plus récent du demandeur (et le solde connu)
Opus.recepteurs.b = function (_, champs, _, canal)
	if canal ~= "GUILD" then return end
	if Opus.db.banque.solde then Opus.Repondre(champs[3] and champs[3] .. "o", "GUILD", PartagerSolde) end
	local depuis, rid = tonumber(champs[2]) or 0, champs[3]
	local choix = {}
	for _, r in pairs(Registre() or {}) do
		if r.t > depuis - 3600 then choix[#choix + 1] = r end
	end
	if #choix == 0 then return end
	table.sort(choix, function (a, b) return a.t > b.t end)
	while #choix > RATTRAPAGE_MAX do table.remove(choix) end
	Opus.Repondre(rid, "GUILD", function () for _, r in ipairs(choix) do Partager(r) end end)
end

local function Purger ()
	local reg = Registre()
	if not reg then return end
	local limite = time() - CONSERVATION
	local prets = {}
	for _, p in ipairs(Opus.Prets()) do prets[p.r.id] = p end
	for id, r in pairs(reg) do
		local vieux = r.t < limite
		if r.k == "pret" then vieux = vieux and (r.x or prets[id].reste == 0)
		elseif r.k == "remb" then vieux = vieux and (not reg[r.pret] or reg[r.pret].t < limite) end
		if vieux then reg[id] = nil end
	end
end

local connecte = false
Opus.Ecoute("PLAYER_ENTERING_WORLD", function ()
	if connecte then return end
	connecte = true
	C_Timer.After(50, function ()
		if not IsInGuild() or not Opus.db then return end
		Purger()
		local plusRecent = 0
		for _, r in pairs(Registre() or {}) do plusRecent = math.max(plusRecent, r.t) end
		Opus.Envoyer(table.concat({ "b", plusRecent, Opus.NouvelId() }, FS))
	end)
end)

------------------------------------------------------------------------
-- écrire : prêts et remboursements (chef et officiers)
------------------------------------------------------------------------

-- « 83 », « 83,5 », « 83 po 50 pa », « 12 pa » → cuivre
function Opus.LireOr (texte)
	texte = (texte or ""):lower():gsub(",", ".")
	local po, pa, pc = texte:match("([%d%.]+)%s*po"), texte:match("(%d+)%s*pa"), texte:match("(%d+)%s*pc")
	if not po and not pa and not pc then po = texte:match("^%s*([%d%.]+)%s*$") end
	local cuivre = math.floor((tonumber(po) or 0) * 10000 + (tonumber(pa) or 0) * 100 + (tonumber(pc) or 0) + 0.5)
	return cuivre > 0 and cuivre or nil
end

-- un dépôt (ou retrait) récent de ce joueur du même montant : celui qui a fait le prêt, à relier
local function OperationDuPret (sens, qui, c)
	local q, depuis, liees = sens == "g" and "or+" or "or-", math.floor(time() / 3600) - 30 * 24, Opus.OperationsLiees()
	local trouve
	for _, e in ipairs(Opus.db.banque.evenements) do
		if e.q == q and e.c == c and e.t >= depuis and MemeJoueur(e.nom, qui) and liees.Trouver(e) == 0 then
			if not trouve or e.t > trouve.t then trouve = e end
		end
	end
	return trouve
end

function Opus.NouveauPret (sens, qui, c, motif)
	if not Opus.PeutConfigurer() then Msg("seuls le chef et les officiers notent les prêts.") return end
	local m = Opus.MembreDe(qui)
	if not m then Msg(("« %s » n'est pas dans la guilde."):format(qui or "")) return end
	local e = OperationDuPret(sens, m.nom, c)
	local r = Ecrire({ k = "pret", sens = sens, qui = m.nom, c = c, d = e and e.t * 3600 or time(), ev = e and Opus.SignatureOp(e), motif = motif })
	if r then
		Msg(("prêt noté : %s %s %s%s."):format(sens == "g" and "la guilde doit" or m.nom .. " doit", Opus.OrDetail(c),
			sens == "g" and "à " .. m.nom or "à la guilde", e and " (relié à son " .. (sens == "g" and "dépôt" or "retrait") .. " à la banque)" or ""))
	end
	return r
end

-- un remboursement, saisi ou tiré d'une opération de la banque (e)
function Opus.Rembourser (p, c, note, e)
	if not Opus.PeutConfigurer() then Msg("seuls le chef et les officiers notent les remboursements.") return end
	c = math.min(c, p.reste)
	if c <= 0 then return end
	local r = Ecrire({ k = "remb", pret = p.r.id, c = c, d = e and e.t * 3600 or time(), ev = e and Opus.SignatureOp(e), note = note })
	if r then
		local reste = p.reste - c
		Msg(("remboursement de %s noté pour %s ; %s"):format(Opus.OrDetail(c), p.r.qui, reste > 0 and ("reste " .. Opus.OrDetail(reste) .. ".") or "prêt soldé."))
	end
	return r
end

function Opus.Supprimer (r)
	local reg = Registre()
	if not reg or not reg[r.id] then return end
	if not Opus.PeutConfigurer() and not (r.k == "remise" and r.de == Opus.MonNom()) then return end
	local copie = Opus.Copie(r)
	copie.x = true
	Ecrire(copie)
end

------------------------------------------------------------------------
-- écrire : remises
------------------------------------------------------------------------

-- remet n objets d'un retrait en attente (a = attente : { e, reste }) à un destinataire
function Opus.Remettre (a, dest, n, via)
	n = math.min(n, a.reste)
	if n <= 0 then return end
	local m = Opus.MembreDe(dest)
	return Ecrire({ k = "remise", de = Opus.MonNom(), a = m and m.nom or Opus.Court(dest), id_ = a.e.id, o = a.e.o, n = n, via = via,
		d = time(), ev = Opus.SignatureOp(a.e) })
end

-- des objets donnés (courrier ou échange) : ce qui vient de ses retraits récents devient une remise
local function Donnes (dest, objets, via)
	if not dest or dest == "" or #objets == 0 then return end
	local attente, notes = Opus.RetraitsEnAttente(), {}
	for _, o in ipairs(objets) do
		local n = o.n
		for _, a in ipairs(attente) do
			if n <= 0 then break end
			if a.e.id == o.id and a.reste > 0 then
				local k = math.min(n, a.reste)
				if Opus.Remettre(a, dest, k, via) then
					a.reste, n = a.reste - k, n - k
					notes[#notes + 1] = k .. " × " .. (a.e.o or o.nom or "?")
				end
			end
		end
	end
	if #notes > 0 then
		local m = Opus.MembreDe(dest)
		Msg(("remise notée : %s à %s."):format(table.concat(notes, ", "), m and m.nom or dest))
	end
end

-- de l'or donné à un créancier de la guilde : on propose d'en faire un remboursement
StaticPopupDialogs["OPUS_REMBOURSEMENT"] = {
	text = "%s",
	button1 = YES, button2 = NO,
	OnAccept = function (_, d) Opus.Rembourser(d.p, d.c, d.via == "echange" and "par échange" or "par courrier") end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

local function OrDonne (dest, cuivre, via)
	if not cuivre or cuivre <= 0 or not Opus.PeutConfigurer() then return end
	local m = Opus.MembreDe(dest)
	if not m then return end
	for _, p in ipairs(Opus.Prets()) do
		if p.r.sens == "g" and p.reste > 0 and MemeJoueur(p.r.qui, m.nom) then
			local c = math.min(cuivre, p.reste)
			local texte = ("Tu as donné %s à |cffffd100%s|r, à qui la guilde doit encore %s.\nLe noter comme remboursement de son prêt ?")
				:format(Opus.OrDetail(cuivre), m.nom, Opus.OrDetail(p.reste))
			StaticPopup_Show("OPUS_REMBOURSEMENT", texte, nil, { p = p, c = c, via = via })
			return
		end
	end
end

local function IdDe (lien) return lien and tonumber(lien:match("item:(%d+)")) end

-- le courrier : ce qui est joint au moment de l'envoi, retenu jusqu'à la confirmation du serveur
local courrier
if SendMail then
	hooksecurefunc("SendMail", function (dest)
		local objets = {}
		for i = 1, ATTACHMENTS_MAX_SEND or 12 do
			local nom, _, _, n = GetSendMailItem(i)
			local id = IdDe(GetSendMailItemLink and GetSendMailItemLink(i))
			if nom and id then objets[#objets + 1] = { id = id, nom = nom, n = n or 1 } end
		end
		courrier = { dest = dest, objets = objets, or_ = GetSendMailMoney and GetSendMailMoney() or 0 }
	end)
end
Opus.Ecoute("MAIL_SEND_SUCCESS", function ()
	local c = courrier
	courrier = nil
	if not c or not Opus.db or not IsInGuild() then return end
	Donnes(c.dest, c.objets, "courrier")
	OrDonne(c.dest, c.or_, "courrier")
end)
Opus.Ecoute("MAIL_FAILED", function () courrier = nil end)

-- l'échange : ce qu'on donne est relevé à chaque acceptation, et compté quand le jeu annonce l'échange terminé
local echange
Opus.Ecoute("TRADE_SHOW", function () echange = nil end)
Opus.Ecoute("TRADE_ACCEPT_UPDATE", function (moi)
	if moi ~= 1 and moi ~= true then return end
	local objets = {}
	for i = 1, MAX_TRADABLE_ITEMS or 6 do
		local nom, _, n = GetTradePlayerItemInfo(i)
		local id = IdDe(GetTradePlayerItemLink(i))
		if nom and id then objets[#objets + 1] = { id = id, nom = nom, n = n or 1 } end
	end
	local dest = TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText() or UnitName("NPC")
	echange = { dest = dest, objets = objets, or_ = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0 }
end)
Opus.Ecoute("UI_INFO_MESSAGE", function (_, message)
	if message ~= ERR_TRADE_COMPLETE or not echange then return end
	local e = echange
	echange = nil
	if not Opus.db or not IsInGuild() then return end
	Donnes(e.dest, e.objets, "echange")
	OrDonne(e.dest, e.or_, "echange")
end)
