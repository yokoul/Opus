-- RaidSuicideKing.lua : les objets hors wishlist (ou sans candidat présent), et ceux dont personne ne veut
-- Annonce « Suicide King » : pendant le temps réglé, les intéressés se déclarent (« Je le veux » dans leur fenêtre, ou
-- « !sk n » dans le canal raid) ; les autres peuvent passer (« Passer », « !passe n »). Quand tous les présents ont
-- répondu, le tour finit sans attendre. L'intéressé présent le plus haut dans la liste gagne et passe en bas ; les autres
-- gardent leur ordre. Un intéressé absent de la liste passe après tous ceux qui y sont (puis le premier déclaré).
-- Sans instantané, l'annonce est un Suicide King direct : la liste de la soirée s'il y en a une, sinon le premier déclaré.
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

-- debut : le début de l'annonce détaillée ; garder : l'annoncer même en annonces courtes (une décision des officiers)
function Raid.LancerSK (a, debut, garder)
	local duree = Raid.Duree("sk")
	a.etat, a.fin, a.interesses, a.duree = "sk", GetTime() + duree, {}, duree
	if Raid.Detaillees() or garder then
		Raid.Annoncer(string.format("#%d %s. Intéressés : « !sk %d », sinon « !passe %d » (%s), le plus haut dans la liste Suicide King gagne.",
			a.n, (debut or a.lien):gsub("%.$", ""), a.n, a.n, Raid.TexteDuree(duree)))
	else
		Raid.Annoncer(string.format("#%d %s : Suicide King (%s), « !sk %d » ou « !passe %d ».", a.n, a.lien, Raid.TexteDuree(duree), a.n, a.n))
	end
	if Raid.Diffuser then Raid.Diffuser("S", a.n, a.id, duree, Raid.ChaineObjet and Raid.ChaineObjet(a.lien) or "") end
	C_Timer.After(duree, function () Raid.FinSK(a) end)
	Rafraichir()
end

-- La liste Suicide King de la soirée (ou de l'instantané avant la première attribution), du haut vers le bas.
function Raid.ListeSK ()
	local s = Raid.db.soiree
	return s and s.sk or (Raid.db.instantane and Raid.db.instantane.sk) or {}
end

-- Les intéressés présents, du mieux placé au moins bien placé : le premier gagnerait si le tour finissait maintenant.
function Raid.ClassementSK (a, liste)
	local presents = Raid.Presents()
	local pos = Positions(liste or Raid.ListeSK())
	local candidats = {}
	for nom in pairs(a.interesses or {}) do
		if not presents or presents[nom] then candidats[#candidats + 1] = nom end
	end
	-- hors de la liste (ou sans liste) : le premier déclaré passe devant
	local ordre = a.ordre or {}
	table.sort(candidats, function (x, y)
		local px, py = pos[x] or math.huge, pos[y] or math.huge
		if px ~= py then return px < py end
		local ox, oy = ordre[x] or math.huge, ordre[y] or math.huge
		if ox ~= oy then return ox < oy end
		return x < y
	end)
	return candidats, pos
end

-- Chaque présent a dit « Je le veux » ou « Passer » (les figurants de l'essai ne comptent pas) : le tour peut finir.
function Raid.ToutLeMondeARepondu (a)
	local presents = Raid.Presents()
	if not presents then return false end
	local n = 0
	for nom in pairs(presents) do
		if not Raid.Figurant(nom) then
			n = n + 1
			if not a.interesses[nom] and not (a.passes and a.passes[nom]) then return false end
		end
	end
	return n > 0
end

function Raid.FinSK (a)
	if a.etat ~= "sk" then return end
	local s = Raid.Soiree()
	local candidats, pos = Raid.ClassementSK(a, s.sk)
	if #candidats == 0 then Raid.Desenchanter(a, " (personne en Suicide King)") return end
	local gagnant = candidats[1]
	local rang = pos[gagnant]
	-- le gagnant passe en bas de la liste
	if rang then table.remove(s.sk, rang) end
	s.sk[#s.sk + 1] = gagnant
	Raid.Attribuer(a, gagnant, "sk", string.format(" (Suicide King, %s sur %d intéressé%s)",
		rang and ("rang " .. rang) or "hors liste", #candidats, #candidats > 1 and "s" or ""))
end

-- Le désenchanteur : celui que le maître du butin a choisi (fenêtre du butin), s'il est là ; sinon le premier présent
-- de la liste de l'instantané (« Z ») ; nil : personne, l'objet part à la banque.
function Raid.Desenchanteur ()
	local presents = Raid.Presents()
	local choisi = Raid.db.reglages.desenchanteur
	if choisi and choisi ~= "" and (not presents or presents[choisi]) then return choisi end
	local i = Raid.db.instantane
	for _, nom in ipairs(i and i.de or {}) do
		if not presents or presents[nom] then return nom end
	end
end

-- Au désenchantement : le désenchanteur, sinon la banque. comment : ajouté à l'annonce.
function Raid.Desenchanter (a, comment)
	local qui = Raid.Desenchanteur()
	a.etat, a.attributaire = qui and "de" or "banque", qui
	a.evenementA = Raid.Noter("A", { tombe = a.evenementT, attributaire = qui or "", voie = a.etat })
	if qui and Raid.ApresAttribution then Raid.ApresAttribution(a) end
	if Raid.DiffuserAttribution then Raid.DiffuserAttribution(a) end
	if Raid.Detaillees() or a.decision then
		Raid.Annoncer(string.format("#%d %s%s : %s.", a.n, a.lien, comment or "",
			qui and ("désenchantement par " .. qui) or "aucun désenchanteur présent, pour la banque"))
	else
		Raid.Annoncer(string.format("#%d %s » %s.", a.n, a.lien, qui and ("désenchantement (" .. qui .. ")") or "banque"))
	end
	Rafraichir()
end

Raid.Commande("sk", "sk", "la liste Suicide King de la soirée (ou de l'instantané), du haut vers le bas", function ()
	local s = Raid.db.soiree
	local liste = s and s.sk or (Raid.db.instantane and Raid.db.instantane.sk) or {}
	if #liste == 0 then Msg("liste Suicide King vide.") return end
	Msg("liste Suicide King" .. (s and " de la soirée" or "") .. " :")
	for k, nom in ipairs(liste) do DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s", k, nom)) end
end)
