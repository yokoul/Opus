-- RaidSuicideKing.lua : les objets hors wishlist (ou sans candidat présent), et ceux dont personne ne veut
-- Annonce « Suicide King » : pendant une minute, les intéressés se déclarent (« Je le veux » dans leur fenêtre, ou
-- « !sk n » dans le canal raid). L'intéressé présent le plus haut dans la liste gagne et passe en bas ; les autres
-- gardent leur ordre. Un intéressé absent de la liste passe après tous ceux qui y sont (puis par ordre alphabétique).
-- Personne : désenchantement par le premier désenchanteur présent (instantané, « Z »), sinon la banque.
-- La liste de la soirée part de l'instantané et bouge à chaque gain ; le site la recalcule depuis le rapport.
local _, Opus = ...
local Raid = Opus.Raid
local Msg = Raid.Msg

-- le temps pour se déclarer : Raid.Duree("sk") (réglable)

local function Rafraichir () if Raid.RafraichirButin then Raid.RafraichirButin() end end

-- La position de chacun dans la liste de la soirée (1 = en haut).
local function Positions (liste)
	local pos = {}
	for k, nom in ipairs(liste) do pos[nom] = k end
	return pos
end

function Raid.LancerSK (a, debut)
	local duree = Raid.Duree("sk")
	a.etat, a.fin, a.interesses = "sk", GetTime() + duree, {}
	Raid.Annoncer(string.format("#%d %s. Intéressés : « !sk %d » (%s), le plus haut dans la liste Suicide King gagne.",
		a.n, (debut or a.lien):gsub("%.$", ""), a.n, Raid.TexteDuree(duree)))
	if Raid.Diffuser then Raid.Diffuser("S", a.n, a.id, duree) end
	C_Timer.After(duree, function () Raid.FinSK(a) end)
	Rafraichir()
end

function Raid.FinSK (a)
	if a.etat ~= "sk" then return end
	local s = Raid.Soiree()
	local presents = Raid.Presents()
	local pos = Positions(s.sk)
	local candidats = {}
	for nom in pairs(a.interesses) do
		if not presents or presents[nom] then candidats[#candidats + 1] = nom end
	end
	if #candidats == 0 then Raid.Desenchanter(a, " (personne en Suicide King)") return end
	table.sort(candidats, function (x, y)
		local px, py = pos[x] or math.huge, pos[y] or math.huge
		if px ~= py then return px < py end
		return x < y
	end)
	local gagnant = candidats[1]
	local rang = pos[gagnant]
	-- le gagnant passe en bas de la liste
	if rang then table.remove(s.sk, rang) end
	s.sk[#s.sk + 1] = gagnant
	Raid.Attribuer(a, gagnant, "sk", string.format(" (Suicide King, %s sur %d intéressé%s)",
		rang and ("rang " .. rang) or "hors liste", #candidats, #candidats > 1 and "s" or ""))
end

-- Au désenchantement : le premier désenchanteur présent ; sinon, la banque. comment : ajouté à l'annonce.
function Raid.Desenchanter (a, comment)
	local i = Raid.db.instantane
	local presents = Raid.Presents()
	local qui
	for _, nom in ipairs(i and i.de or {}) do
		if not presents or presents[nom] then qui = nom break end
	end
	a.etat, a.attributaire = qui and "de" or "banque", qui
	a.evenementA = Raid.Noter("A", { tombe = a.evenementT, attributaire = qui or "", voie = a.etat })
	if qui and Raid.ApresAttribution then Raid.ApresAttribution(a) end
	if Raid.DiffuserAttribution then Raid.DiffuserAttribution(a) end
	Raid.Annoncer(string.format("#%d %s%s : %s.", a.n, a.lien, comment or "",
		qui and ("désenchantement par " .. qui) or "aucun désenchanteur présent, pour la banque"))
	Rafraichir()
end

Raid.Commande("sk", "sk", "la liste Suicide King de la soirée (ou de l'instantané), du haut vers le bas", function ()
	local s = Raid.db.soiree
	local liste = s and s.sk or (Raid.db.instantane and Raid.db.instantane.sk) or {}
	if #liste == 0 then Msg("liste Suicide King vide.") return end
	Msg("liste Suicide King" .. (s and " de la soirée" or "") .. " :")
	for k, nom in ipairs(liste) do DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s", k, nom)) end
end)
