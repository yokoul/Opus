-- Groupe.lua : le groupe qu'on monte (le donjon visé, et ceux qui ont accepté une proposition, Invitation.lua) ; il n'est
-- plus affiché : les cartes d'envie invitent elles-mêmes, et le donjon visé règle « En ligne à ta portée »
-- Les donjons et leurs tranches de niveau viennent de l'addon Dungeon Journal s'il est installé (sa table
-- ForeverDungeonJournal_NS.DB, avec ses noms traduits) ; sans lui, la tranche est son propre niveau à ±3.
local _, Opus = ...

local ECART = 3
-- Sur Forever (annonce de novembre 2026), si les monstres d'un donjon sont gris pour un joueur, plus personne du groupe
-- ne gagne d'XP : on prévient dès 13 niveaux d'écart (au-dessus du maximum du donjon, ou entre membres sans donjon).
Opus.ECART_GRIS = 13
Opus.groupe = { donjon = nil, places = {} }     -- places[i] = nom du membre ; 1 tank, 2 soin, 3-5 dégâts
Opus.PLACES = { "tank", "soin", "degats", "degats", "degats" }

-- les donjons connus : { cle, nom, min, max }, du plus bas au plus haut
function Opus.Donjons ()
	local ns = _G.ForeverDungeonJournal_NS
	local liste = {}
	if ns and type(ns.DB) == "table" then
		for cle, d in pairs(ns.DB) do
			local niv = type(d) == "table" and type(d.level) == "string" and d.level or ""
			local a, b = niv:match("^(%d+)%s*%-%s*(%d+)$")
			if not a then a = niv:match("^(%d+)%+$") b = a and 60 end
			if a then
				local ok, nom = pcall(ns.LocalizeDungeonName or function (x) return x end, cle)
				liste[#liste + 1] = { cle = cle, nom = ok and nom or cle, min = tonumber(a), max = tonumber(b) }
			end
		end
	end
	table.sort(liste, function (x, y) if x.min ~= y.min then return x.min < y.min end return x.nom < y.nom end)
	return liste
end

-- la tranche de niveau visée : celle du donjon choisi, sinon son niveau à ±3
function Opus.Tranche ()
	local d = Opus.groupe.donjon
	if d then return d.min, d.max, d.nom end
	local n = UnitLevel("player")
	return math.max(1, n - ECART), n + ECART, nil
end

function Opus.DansLeGroupe (nom)
	for i = 1, #Opus.PLACES do if Opus.groupe.places[i] == nom then return i end end
	return nil
end

-- place un membre à une place de ses rôles, le principal d'abord ; un rôle inconnu va d'abord en dégâts (le plus
-- courant), pour laisser tank et soin à ceux qui le sont, puis à n'importe quelle place libre
function Opus.AjouterAuGroupe (m)
	if Opus.DansLeGroupe(m.nom) then return end
	local roles = Opus.RolesDe(Opus.db.spes[m.nom])
	local role = roles[1]
	local libre
	for _, voulu in ipairs(#roles > 0 and roles or { "degats" }) do
		for i, r in ipairs(Opus.PLACES) do
			if not libre and not Opus.groupe.places[i] and r == voulu then libre = i end
		end
	end
	if not libre and not role then
		for i = 1, #Opus.PLACES do if not Opus.groupe.places[i] then libre = i break end end
	end
	if not libre then Opus.Msg(role and "plus de place pour ce rôle dans le groupe." or "le groupe est complet.") return end
	Opus.groupe.places[libre] = m.nom
	if Opus.Rafraichir then Opus.Rafraichir() end
end

-- ce joueur ferait-il perdre l'XP au groupe ? (un donjon choisi : son niveau au-dessus de son maximum ; sinon : face au
-- plus bas du groupe)
function Opus.RisqueGris (niveau)
	local d = Opus.groupe.donjon
	if d then return niveau - d.max >= Opus.ECART_GRIS end
	local plusBas
	for i = 1, #Opus.PLACES do
		local m = Opus.groupe.places[i] and Opus.TrouverMembre(Opus.groupe.places[i])
		if m then plusBas = math.min(plusBas or m.niveau, m.niveau) end
	end
	return plusBas ~= nil and niveau - plusBas >= Opus.ECART_GRIS
end

-- changer de donjon : les membres déjà placés qui ont l'addon en sont prévenus
function Opus.ChoisirDonjon (d)
	local avant = Opus.groupe.donjon
	Opus.groupe.donjon = d
	if (avant and avant.cle) ~= (d and d.cle) and Opus.AnnoncerDonjon then Opus.AnnoncerDonjon() end
	if Opus.Rafraichir then Opus.Rafraichir() end
end

-- ouvre la ligne de discussion avec un texte déjà écrit (« /g … ») : on le relit, le retouche et l'envoie soi-même
function Opus.PreRemplir (texte)
	if not texte or texte == "" then return end
	local ouvrir = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
	if ouvrir then ouvrir(texte) end
end
