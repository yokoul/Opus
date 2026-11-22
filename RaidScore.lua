-- RaidScore.lua : la proposition calculée (WishVote) pour un objet, parmi les candidats présents
-- Score sur 100 = somme pondérée de quatre termes entre 0 et 1 :
--   prio perso   : le rang dans sa wishlist, 1 pour le rang 1, puis décroissant jusqu'au dernier rang possible
--                  ((taille - rang + 1) / taille, la taille des listes venant de l'instantané) ;
--   prios perdues, dernier loot, gain : les compteurs de l'instantané, déjà normalisés par le site, 1 = le plus
--                  méritant (beaucoup de prios perdues, pas de loot depuis longtemps, gros gain).
-- Les poids viennent de l'instantané (50, 25, 15, 10 au départ). En cas d'égalité : le meilleur rang, puis le plus
-- de prios perdues, et l'égalité est signalée : c'est au maître du butin de trancher.
local _, Opus = ...
local Raid = Opus.Raid

local function Arrondi (x) return math.floor(x * 10 + 0.5) / 10 end

-- la taille des listes : celle de l'instantané, sinon le plus grand rang qu'il contient
local function Taille (i)
	if i.taille then return i.taille end
	local t = 1
	for _, candidats in pairs(i.souhaits) do
		for _, c in ipairs(candidats) do if c.rang > t then t = c.rang end end
	end
	return t
end

-- Les noms présents (le raid, ou le groupe pour les essais), ou nil seul : tout le monde compte, pour essayer en solo.
function Raid.Presents ()
	if not IsInRaid() and not IsInGroup() then return nil end
	local presents = {}
	for _, m in ipairs(Raid.MembresDuRaid()) do presents[m.nom] = true end
	return presents
end

-- Rend { candidats = { { nom, rang, score, termes = { perso, perdues, dernier, gain } }, … } du meilleur au moins bon,
-- absents = { noms }, egalite = vrai si les deux premiers ont le même score }, ou nil s'il n'y a pas d'instantané.
function Raid.Proposer (itemID, presents)
	local i = Raid.db.instantane
	if not i then return nil end
	local p, taille = i.poids, Taille(i)
	local r = { candidats = {}, absents = {} }
	for _, c in ipairs(i.souhaits[itemID] or {}) do
		local j = i.joueurs[c.nom]
		if presents and not presents[c.nom] then
			r.absents[#r.absents + 1] = c.nom
		elseif j then
			local t = {
				perso = math.max(0, (taille - c.rang + 1) / taille),
				perdues = j.perdues, dernier = j.dernier, gain = j.gain,
			}
			local score = p.perso * t.perso + p.perdues * t.perdues + p.dernier * t.dernier + p.gain * t.gain
			r.candidats[#r.candidats + 1] = { nom = c.nom, rang = c.rang, score = Arrondi(score), termes = t, perso = j.perso, role = j.role }
		end
	end
	table.sort(r.candidats, function (a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.rang ~= b.rang then return a.rang < b.rang end
		if a.termes.perdues ~= b.termes.perdues then return a.termes.perdues > b.termes.perdues end
		return a.nom < b.nom
	end)
	local c1, c2 = r.candidats[1], r.candidats[2]
	r.egalite = c1 and c2 and c1.score == c2.score or false
	return r
end

-- « 87,5 » : les scores s'écrivent à la française
function Raid.Score (x) return (string.format("%.1f", x):gsub("%.", ",")) end
