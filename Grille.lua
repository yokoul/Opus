-- Grille.lua : les droits que l'addon sait lire, et le préréglage de la guilde Opus (« Guilde Opus — Grades et droits »)
-- La grille active est celle de la guilde du joueur (Config.lua) ; ce préréglage n'en est que le point de départ chez Opus.
-- Sur Forever, la case « Est officier » (n° 22) regroupe canaux d'officiers, notes publiques et
-- d'officiers, message du jour et infos de guilde : la grille les accorde à Magister et Architecte seuls.
local _, Opus = ...

-- numéros des droits (C_GuildInfo.GuildControlGetRankFlags)
Opus.DROITS = {
	{ id = 1,  cle = "ecouter",    nom = "Écouter la guilde" },
	{ id = 2,  cle = "parler",     nom = "Parler en guilde" },
	{ id = 22, cle = "officier",   nom = "Est officier (canaux, notes, MdJ, infos)" },
	{ id = 7,  cle = "inviter",    nom = "Inviter" },
	{ id = 5,  cle = "promouvoir", nom = "Promouvoir" },
	{ id = 6,  cle = "retrograder", nom = "Rétrograder" },
	{ id = 8,  cle = "exclure",    nom = "Exclure" },
	{ id = 15, cle = "reparer",    nom = "Réparations" },
	{ id = 16, cle = "retraitOr",  nom = "Retrait d'or" },
}

local ONGLETS_OPUS = { "Chantier", "Matériaux", "Réserve" }

-- onglet : { voir, déposer, retraits par jour }
local function O (voir, deposer, retraits) return { voir = voir, deposer = deposer, retraits = retraits } end

-- grades dans l'ordre du jeu (1 = Magister, non modifiable)
local GRADES_OPUS = {
	{ nom = "Magister",    role = "Maître de guilde", desc = "Tous les droits, non modifiables." },
	{ nom = "Architecte",  role = "Officiers", desc = "Recrutent, promeuvent et rétrogradent ; canaux et notes d'officiers, message du jour. Seuls à voir la Réserve.",
	  officier = true, inviter = true, promouvoir = true, retrograder = true, exclure = true,
	  reparer = true, or_ = 10, onglets = { O(true, true, 10), O(true, true, 10), O(true, true, 0) } },
	{ nom = "Compagnon",   role = "Raiders titulaires", voie = "Tour", desc = "Le cœur du raid : réparations guilde, peuvent inviter.",
	  inviter = true, reparer = true, or_ = 5,
	  onglets = { O(true, true, 5), O(true, true, 5), O(false, true, 0) } },
	{ nom = "Itinérant",   role = "Raiders en rotation", voie = "Tour", desc = "Raident selon les places : réparations guilde.",
	  reparer = true, or_ = 5,
	  onglets = { O(true, true, 5), O(true, true, 2), O(false, true, 0) } },
	{ nom = "Sédentaire",  role = "Membres hors raid", voie = "Atelier", desc = "Les métiers et la vie de guilde : peuvent inviter, puisent dans les Matériaux.",
	  inviter = true, or_ = 0,
	  onglets = { O(true, true, 0), O(true, true, 5), O(false, true, 0) } },
	{ nom = "Aspirant",    role = "Raiders à l'essai", voie = "Tour", essai = "raid", desc = "Essai raid, puis Itinérant ou Compagnon : réparations guilde, petit accès au Chantier.",
	  reparer = true, or_ = 3,
	  onglets = { O(true, true, 3), O(true, true, 0), O(false, true, 0) } },
	{ nom = "Pierre brute", role = "Alts / rerolls", desc = "Les personnages secondaires : déposent, ne retirent rien.",
	  or_ = 0,
	  onglets = { O(true, true, 0), O(true, true, 0), O(false, true, 0) } },
	{ nom = "Apprenti",    role = "Nouvelles recrues", voie = "Atelier", essai = "guilde", desc = "Essai guilde, puis Sédentaire : déposent dans la banque sans la voir.",
	  or_ = 0,
	  onglets = { O(false, true, 0), O(false, true, 0), O(false, true, 0) } },
}

-- les sorties d'essai, par grade (le premier est la cible par défaut)
local SORTIES_OPUS = {
	Apprenti = { "Sédentaire" },
	Aspirant = { "Itinérant", "Compagnon" },
}

-- Avant l'ouverture des raids (9 décembre 2026, minuit à Paris), la feuille coupe les réparations et les retraits d'or
-- sauf pour le Magister : la caisse finance d'abord le premier onglet.
local RESTRICTION_OPUS = {
	fin = 1796770800,
	texte = "réparations et retraits d'or coupés, sauf Magister, jusqu'à l'ouverture des raids le 9 décembre",
}

-- le préréglage Opus, dans la forme d'une configuration de guilde (Config.lua) : sorties par numéro de grade
function Opus.PreReglageOpus ()
	local index = {}
	for i, g in ipairs(GRADES_OPUS) do index[g.nom] = i end
	local grades = {}
	for i, g in ipairs(GRADES_OPUS) do
		local c = CopyTable and CopyTable(g) or Opus.Copie(g)
		c.sorties = {}
		for _, s in ipairs(SORTIES_OPUS[g.nom] or {}) do c.sorties[#c.sorties + 1] = index[s] end
		grades[i] = c
	end
	return { version = 0, grades = grades, onglets = { ONGLETS_OPUS[1], ONGLETS_OPUS[2], ONGLETS_OPUS[3] }, restriction = RESTRICTION_OPUS }
end
