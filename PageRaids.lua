-- PageRaids.lua : l'onglet « Raids », en trois vues.
--   Ce soir     la soirée de guilde (l'ouvrir, la fermer, son état), l'instantané du site, les annonces du soir et le
--               rapport à rendre au site ;
--   Ma liste    mes listes de souhaits (rangs, objets déjà reçus), mes compteurs et ma place au Suicide King ;
--   Historique  les soirées validées des paliers en cours et ce que chaque objet est devenu.
-- Ma liste et l'historique viennent du site, par le bridge (OpusBridgeFeed.raids, écrit à la connexion) ; à défaut,
-- ma liste est lue dans l'instantané importé. Les fenêtres du raid (butin, attributions, décision) restent à part :
-- elles surgissent en pleine soirée.
local _, Opus = ...
local Raid = Opus.Raid

local MAX_ANNONCES = 8              -- annonces montrées ici ; /opus raid objections pour toutes
local VUE_MAX = 480                 -- hauteur visible de Ma liste et de l'historique ; au-delà, la molette
local JOURS = { "dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam." }
local QUALITES = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

local vue = "soir"
local VUES = { { "soir", "Ce soir" }, { "liste", "Ma liste" }, { "historique", "Historique" } }
local defile = 0

local function Pluriel (n, mot) return n .. " " .. mot .. (n > 1 and "s" or "") end
local function Jour (t) local d = date("*t", t) return ("%s %d/%d"):format(JOURS[d.wday], d.day, d.month) end

------------------------------------------------------------------------
-- le flux du site (bridge)
------------------------------------------------------------------------

-- le bloc raids écrit par le bridge, et quand le site l'a produit ; nil sans bridge
function Raid.Flux ()
	local f = OpusBridgeFeed
	if type(f) ~= "table" or type(f.raids) ~= "table" or type(f.raids.paliers) ~= "table" then return nil end
	return f.raids, tonumber(f.raids.maj)
end

-- le lien d'un objet du flux : celui du jeu s'il est en cache, sinon son nom à la couleur de sa qualité
local Info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function Lien (o)
	local _, lien = Info(o.id)
	if lien then return lien end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, o.id) end
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[QUALITES[o.qualite or ""] or 1]
	local nom = "[" .. ((o.nom and o.nom ~= "") and o.nom or ("objet " .. o.id)) .. "]"
	return q and (q.hex .. nom .. "|r") or nom
end

-- sans bloc raids : le bridge manque, ou il est d'une version qui ne l'écrit pas encore
local function SansFlux (quoi)
	if type(OpusBridgeFeed) == "table" then
		return Opus.Gris(quoi .. " arrive" .. (quoi:find(" et ") and "nt" or "") .. " avec la dernière version du bridge : il se met à jour tout seul, puis reconnecte-toi.")
	end
	return Opus.Gris(quoi .. " arrive" .. (quoi:find(" et ") and "nt" or "") .. " ici avec le bridge : installe-le depuis opus-guild.eu/bridge (une ligne à coller), puis reconnecte-toi.")
end

local function Moi (nom) return nom and Raid.MonNom() and nom:lower() == Raid.MonNom():lower() end

local function Dernier (n)
	n = tonumber(n) or -1
	if n < 0 then return "jamais servi" end
	if n == 0 then return "servi à sa dernière soirée" end
	return "servi il y a " .. Pluriel(n, "soirée")
end

------------------------------------------------------------------------
-- Ma liste
------------------------------------------------------------------------

-- Ma liste avec le bridge : un bloc par perso (le perso joué d'abord), comme sur la planche. Son nom, le statut et le
-- rôle de sa liste en pastilles, ce qu'il a reçu ; quatre tuiles (soirées, prios perdues, dernier loot, Suicide King) ;
-- ses objets, avec leur rang, leur icône et « reçu le … ». Sans bridge, le texte de l'instantané (plus bas).
local function DernierCourt (n)
	n = tonumber(n) or -1
	if n < 0 then return "jamais" end
	if n == 0 then return "dernière soirée" end
	return "il y a " .. n
end

local function BlocListe (cadre, k)
	cadre.blocs = cadre.blocs or {}
	if cadre.blocs[k] then return cadre.blocs[k] end
	local x, largeur = cadre.contenu, cadre.largeur - 24
	local b = CreateFrame("Frame", nil, x)
	b:SetWidth(largeur)
	b.palier = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.palier:SetPoint("TOPLEFT", 0, 0)
	b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.statut = Raid.Pastille(b)
	b.role = Raid.Pastille(b)
	b.recus = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.tuiles = {}
	local lt = math.floor((largeur - 18) / 4)
	for i = 1, 4 do b.tuiles[i] = Raid.Tuile(b, lt) end
	b.objets = {}
	cadre.blocs[k] = b
	return b
end

local function ObjetListe (b, i)
	if b.objets[i] then return b.objets[i] end
	local l = CreateFrame("Frame", nil, b)
	l:SetSize(b:GetWidth(), 20)
	l.rang = l:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	l.rang:SetPoint("LEFT", 0, 0) l.rang:SetWidth(18) l.rang:SetJustifyH("CENTER")
	l.icone = Raid.Icone(l, 16)
	l.icone:SetPoint("LEFT", 24, 0)
	l.lien = CreateFrame("Button", nil, l)
	l.lien:SetSize(360, 18) l.lien:SetPoint("LEFT", 46, 0)
	l.lien.texte = l.lien:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.lien.texte:SetPoint("LEFT") l.lien.texte:SetJustifyH("LEFT") l.lien.texte:SetWordWrap(false)
	l.lien:SetScript("OnEnter", function (self) Raid.Infobulle(self, self.lienObjet, self.id) end)
	l.lien:SetScript("OnLeave", GameTooltip_Hide)
	l.etat = Raid.Pastille(l)
	l.etat:SetPoint("RIGHT", 0, 0)
	l.attente = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	l.attente:SetPoint("RIGHT", 0, 0)
	b.objets[i] = l
	return l
end

-- dessine les blocs ; rend la hauteur occupée, ou nil s'il n'y a rien à montrer
local function BlocsListe (cadre, flux)
	for _, b in ipairs(cadre.blocs or {}) do b:Hide() end
	local k, y = 0, -4
	for _, p in ipairs(flux.paliers) do
		local listes = {}
		for _, l in ipairs(type(p.listes) == "table" and p.listes or {}) do
			if Moi(l.perso) then table.insert(listes, 1, l) else listes[#listes + 1] = l end
		end
		for j, l in ipairs(listes) do
			k = k + 1
			local b = BlocListe(cadre, k)
			local h = 0
			b.palier:SetShown(j == 1)
			if j == 1 then b.palier:SetText(p.code .. " · " .. (p.nom or "")) h = 24 end
			b.nom:ClearAllPoints() b.nom:SetPoint("TOPLEFT", 0, -h)
			b.nom:SetText(l.perso)
			b.statut:ClearAllPoints() b.statut:SetPoint("LEFT", b.nom, "RIGHT", 8, 0)
			Raid.PoserPastille(b.statut, l.statut or "?", (l.statut or ""):find("valid") and "fait" or "neutre")
			b.role:ClearAllPoints() b.role:SetPoint("LEFT", b.statut, "RIGHT", 4, 0)
			Raid.PoserPastille(b.role, (l.role and l.role ~= "") and l.role or nil, "neutre")
			local recus = 0
			for _, o in ipairs(l.objets or {}) do if o.recu then recus = recus + 1 end end
			b.recus:ClearAllPoints() b.recus:SetPoint("TOPRIGHT", 0, -h - 2)
			b.recus:SetText(recus .. " sur " .. #(l.objets or {}) .. " reçu" .. (recus > 1 and "s" or ""))
			h = h + 22
			local sk = tonumber(l.sk) or 0
			local valeurs = {
				{ tostring(tonumber(l.presences) or 0), "soirées" }, { tostring(tonumber(l.perdues) or 0), "prios perdues" },
				{ DernierCourt(l.dernier), "dernier loot" }, { sk > 0 and (sk .. " / " .. (l.skTotal or "?")) or "—", "Suicide King" },
			}
			for i, t in ipairs(b.tuiles) do
				t:ClearAllPoints() t:SetPoint("TOPLEFT", (i - 1) * (t:GetWidth() + 6), -h)
				t:Poser(valeurs[i][1], valeurs[i][2])
			end
			h = h + 40
			for _, o in ipairs(b.objets) do o:Hide() end
			for i, o in ipairs(l.objets or {}) do
				local r = ObjetListe(b, i)
				r:ClearAllPoints() r:SetPoint("TOPLEFT", 0, -h)
				r.rang:SetText(o.rang)
				Raid.PoserIcone(r.icone, o.id, nil)
				local lien = Lien(o)
				r.lien.lienObjet, r.lien.id = lien, o.id
				r.lien.texte:SetText((lien:gsub("%[(.-)%]", "%1")))
				if o.recu then Raid.PoserPastille(r.etat, "reçu le " .. Jour(o.recu), "fait") r.attente:SetText("")
				else r.etat:Hide() r.attente:SetText("en attente") end
				r:Show()
				h = h + 20
			end
			b:ClearAllPoints() b:SetPoint("TOPLEFT", 8, y)
			b:SetHeight(h)
			b:Show()
			y = y - h - 16
		end
	end
	if k == 0 then return nil end
	return -y
end

-- le texte de la vue : mes listes, celle du perso joué d'abord
local function TexteListe ()
	local flux = Raid.Flux()
	local lignes = {}
	local function L (t) lignes[#lignes + 1] = t or " " end
	if flux then
		for _, p in ipairs(flux.paliers) do
			local listes = {}
			for _, l in ipairs(type(p.listes) == "table" and p.listes or {}) do
				if Moi(l.perso) then table.insert(listes, 1, l) else listes[#listes + 1] = l end
			end
			if #listes > 0 then
				L(Opus.Normal(p.code .. " · " .. (p.nom or "")))
				for _, l in ipairs(listes) do
					local recus = 0
					for _, o in ipairs(l.objets or {}) do if o.recu then recus = recus + 1 end end
					L(Opus.Blanc(l.perso) .. Opus.Gris(" · liste " .. (l.statut or "?") .. (l.role and l.role ~= "" and (", " .. l.role) or "")
						.. " · " .. #(l.objets or {}) .. " objets, " .. recus .. " reçu" .. (recus > 1 and "s" or "")))
					L(Opus.Gris(("%s · %s · %s · Suicide King : %s"):format(Pluriel(tonumber(l.presences) or 0, "soirée"),
						Pluriel(tonumber(l.perdues) or 0, "prio perdue"), Dernier(l.dernier),
						(tonumber(l.sk) or 0) > 0 and (l.sk .. (l.sk == 1 and "er" or "e") .. " sur " .. l.skTotal) or "pas encore dans la liste")))
					for _, o in ipairs(l.objets or {}) do
						L("   " .. Opus.Normal(o.rang .. ".") .. " " .. Lien(o) .. (o.recu and Opus.Vert("  reçu le " .. Jour(o.recu)) or ""))
					end
					L()
				end
			end
		end
		if #lignes == 0 then L(Opus.Gris("Pas de liste sur le site pour les paliers en cours. Les listes se font sur opus-guild.eu, page Raids.")) end
		return table.concat(lignes, "\n")
	end
	-- sans bridge : ce que dit l'instantané importé (le maître du butin et son second)
	local i, moi = Raid.db.instantane, Raid.MonNom()
	if i and i.joueurs[moi] then
		local souhaits = {}
		for id, candidats in pairs(i.souhaits) do
			for _, c in ipairs(candidats) do if c.nom == moi then souhaits[#souhaits + 1] = { id = id, rang = c.rang } end end
		end
		table.sort(souhaits, function (a, b) return a.rang < b.rang end)
		L(Opus.Normal(i.tier ~= "" and i.tier or "Palier") .. Opus.Gris(" · d'après l'instantané importé"))
		for _, s in ipairs(souhaits) do L("   " .. Opus.Normal(s.rang .. ".") .. " " .. Raid.LienDe(s.id)) end
		local sk = (Raid.db.soiree and Raid.db.soiree.sk) or i.sk or {}
		for k, nom in ipairs(sk) do if nom == moi then L(Opus.Gris("Suicide King : rang " .. k .. " sur " .. #sk)) end end
		L()
	end
	L(SansFlux("Ta liste, tes soirées et l'historique des attributions"))
	return table.concat(lignes, "\n")
end

------------------------------------------------------------------------
-- Historique
------------------------------------------------------------------------

local function TexteHistorique ()
	local flux = Raid.Flux()
	if not flux then return SansFlux("L'historique des soirées") end
	local lignes = {}
	local function L (t) lignes[#lignes + 1] = t or " " end
	local moi = Raid.MonNom()
	for _, p in ipairs(flux.paliers) do
		local soirees = type(p.soirees) == "table" and p.soirees or {}
		if #soirees > 0 then
			L(Opus.Normal(p.code .. " · " .. (p.nom or "")) .. Opus.Gris(" · " .. Pluriel(#soirees, "soirée") .. " validée" .. (#soirees > 1 and "s" or "")))
			for _, s in ipairs(soirees) do
				local present = false
				for _, n in ipairs(s.presents or {}) do if Moi(n) then present = true end end
				L(Opus.Blanc(Jour(s.debut) .. date(" à %H:%M", s.debut)) .. Opus.Gris(" · " .. (s.ml or "?") .. " · " .. #(s.presents or {}) .. " présents")
					.. (present and Opus.Vert(" · tu y étais") or ""))
				local attributions = s.attributions or {}
				if #attributions == 0 then L(Opus.Gris("   aucun objet attribué")) end
				for _, a in ipairs(attributions) do
					local pour = (a.pour and a.pour ~= "") and (Moi(a.pour) and Opus.Vert(a.pour) or Opus.Blanc(a.pour)) or Opus.Gris("la guilde")
					L("   " .. Lien(a) .. "  " .. pour .. Opus.Gris(" · " .. (a.comment or "") .. (a.motif and (" : « " .. a.motif .. " »") or "")))
				end
				L()
			end
		end
	end
	if #lignes == 0 then return Opus.Gris("Aucune soirée validée pour les paliers en cours.") end
	return table.concat(lignes, "\n")
end

------------------------------------------------------------------------
-- Ce soir
------------------------------------------------------------------------

-- l'état de la soirée de guilde, en une ligne (le bandeau de « Ce soir »)
local function EtatSoiree ()
	local o = Raid.db.ouverte
	local part, guilde, taille = Raid.PartGuilde()
	local compo = part and string.format(" · %d sur %d de la guilde", guilde, taille) or ""
	if not o then
		if not IsInGroup() then return "Soirée fermée" .. Opus.Gris(string.format(" · s'ouvre en raid, %d %% de la guilde", Raid.Seuil() * 100)) end
		if part and part < Raid.Seuil() then
			return Opus.Rouge("Pas un raid de guilde") .. Opus.Gris(compo .. string.format(" · il en faut %d %%", Raid.Seuil() * 100))
		end
		return "Raid de guilde" .. Opus.Gris(compo .. " · soirée pas encore ouverte, le butin ne bouge pas")
	end
	local actif, raison = Raid.Actif()
	if not actif then return Opus.Rouge("Soirée suspendue") .. Opus.Gris(" · " .. (raison or "")) end
	return Opus.Vert("Soirée ouverte à " .. date("%H:%M", o.debut)) .. Opus.Gris(" par " .. (o.par or "?") .. compo)
end

-- l'instantané que le bridge a apporté (le palier le plus récent qui en a un), pour un officier du butin
local function InstantaneDuFlux ()
	local flux = Raid.Flux()
	if not flux or type(flux.instantanes) ~= "table" then return nil end
	for _, p in ipairs(flux.paliers) do
		local texte = flux.instantanes[p.code]
		if type(texte) == "string" and texte ~= "" then return texte, p.code end
	end
	return nil
end

local function Chrono (a)
	local reste = math.max(0, math.floor((a.fin or 0) - GetTime()))
	return string.format("%d:%02d", math.floor(reste / 60), reste % 60)
end

-- Une annonce du soir : sa pastille (texte, sens, comme dans la fenêtre du butin), à qui, et par quelle voie.
local function EtatDuSoir (a)
	local dest = a.attributaire and a.attributaire ~= "" and a.attributaire or nil
	local voie = a.decision and "décision des officiers" or a.interesses and "Suicide King" or (a.objecteurs and #a.objecteurs > 0) and "vote"
		or a.etat == "de" and "désenchantement" or a.etat == "banque" and "personne" or "liste"
	if a.etat == "delai" then return "objections " .. Chrono(a), "cours", a.propose and ("proposé : " .. a.propose) or "", "liste" end
	if a.etat == "vote" then return "vote " .. Chrono(a), "cours", a.propose and ("proposé : " .. a.propose) or "", "vote" end
	if a.etat == "sk" then return "Suicide King " .. Chrono(a), "cours", "", "Suicide King" end
	if a.etat == "trancher" then return "à trancher", "afaire", "", "vote" end
	if a.etat == "banque" then return "banque", "neutre", Opus.Gris("banque"), voie end
	if a.remis then return "remis", "fait", dest or "?", voie end
	return "à remettre", "afaire", dest or "?", voie
end

local function LigneSoir (cadre, k)
	if cadre.lignesSoir[k] then return cadre.lignesSoir[k] end
	local l = CreateFrame("Frame", nil, cadre)
	l:SetSize(cadre.largeur - 20, 20)
	l.num = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	l.num:SetPoint("LEFT", 0, 0) l.num:SetWidth(22) l.num:SetJustifyH("RIGHT")
	l.icone = Raid.Icone(l, 16)
	l.icone:SetPoint("LEFT", 28, 0)
	l.objet = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.objet:SetPoint("LEFT", 50, 0) l.objet:SetWidth(200) l.objet:SetJustifyH("LEFT") l.objet:SetWordWrap(false)
	l.a = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l.a:SetPoint("LEFT", 256, 0) l.a:SetWidth(150) l.a:SetJustifyH("LEFT") l.a:SetWordWrap(false)
	l.voie = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	l.voie:SetPoint("LEFT", 412, 0) l.voie:SetWidth(130) l.voie:SetJustifyH("LEFT") l.voie:SetWordWrap(false)
	l.etat = Raid.Pastille(l)
	l.etat:SetPoint("LEFT", 548, 0)
	l.filet = l:CreateTexture(nil, "BACKGROUND")
	l.filet:SetHeight(1) l.filet:SetPoint("TOPLEFT") l.filet:SetPoint("TOPRIGHT") l.filet:SetColorTexture(1, 1, 1, 0.04)
	cadre.lignesSoir[k] = l
	return l
end

local function RafraichirSoir (cadre)
	local i, gere = Raid.db.instantane, Raid.PeutGerer()
	local o = Raid.db.ouverte

	-- le bandeau : la soirée, d'un coup d'œil
	local actif = o and Raid.Actif()
	cadre.temoin:SetColorTexture(o and (actif and 0.25 or 1) or 0.35, o and (actif and 1 or 0.35) or 0.33, o and (actif and 0.25 or 0.35) or 0.29)
	cadre.soiree:SetText(EtatSoiree())
	cadre.ouvrir:SetShown(not o)
	cadre.fermer:SetShown(o ~= nil)
	cadre.ouvrir:SetEnabled(gere and IsInGroup())
	cadre.ouvrir.raison = not gere and ("Ouvrir la soirée " .. Raid.QuiPeut() .. ".") or "Une soirée de guilde s'ouvre en raid (ou en groupe, pour l'essai en donjon)."
	cadre.fermer:SetEnabled(gere)
	cadre.fermer.raison = "Fermer la soirée " .. Raid.QuiPeut() .. "."
	local aRemettre = #Raid.ARemettre()
	cadre.butin:SetEnabled(gere)
	cadre.butin.raison = "La fenêtre du butin " .. Raid.QuiPeut() .. "."
	cadre.remises:SetShown(aRemettre > 0)
	cadre.remises:SetText("À remettre : " .. aRemettre)
	-- une seule action principale : ouvrir la soirée quand on peut, sinon la fenêtre du butin pendant la soirée
	cadre.ouvrir:SetGenre(cadre.ouvrir:IsEnabled() and "prim" or "sec")
	cadre.butin:SetGenre(o and gere and "prim" or "sec")
	local precedent
	for _, b in ipairs({ cadre.ouvrir, cadre.fermer, cadre.butin, cadre.remises }) do
		if b:IsShown() then
			b:ClearAllPoints()
			if precedent then b:SetPoint("RIGHT", precedent, "LEFT", -6, 0) else b:SetPoint("RIGHT", cadre.bandeau, "RIGHT", -8, 0) end
			precedent = b
		end
	end

	-- l'instantané, sur une ligne ; qui l'a importé, au survol de « Détail »
	if i then
		cadre.instantane:SetText(Opus.Blanc(i.id) .. "  " .. Opus.Gris(string.format("%s · %s · %s · %s",
			i.tier ~= "" and i.tier or "?", Pluriel(i.nJoueurs, "joueur"), Pluriel(i.nObjets, "objet"), date("%d/%m %H:%M", i.importe or i.date))))
	else
		cadre.instantane:SetText(Opus.Gris("Aucun instantané : importe-le du bridge, ou colle celui du site."))
	end
	cadre.importer:SetEnabled(gere)
	cadre.importer.raison = "L'import " .. Raid.QuiPeut() .. "."
	local texte = InstantaneDuFlux()
	local nouveau = gere and texte ~= nil and not (i and texte:find(i.id, 1, true))
	cadre.duBridge:SetEnabled(nouveau)
	cadre.duBridge:SetGenre(nouveau and "prim" or "sec")
	cadre.duBridge.raison = not texte and "Le bridge n'a pas apporté d'instantané (pas officier du butin, ou pas de palier ouvert)."
		or (i and texte:find(i.id, 1, true)) and "L'instantané du bridge est déjà importé." or ("L'import " .. Raid.QuiPeut() .. ".")
	cadre.detail:SetEnabled(i ~= nil)
	cadre.detail.raison = "Aucun instantané importé."

	-- le soir : un tableau, et son résumé dans le titre
	local debut = math.max(1, #Raid.attributions - MAX_ANNONCES + 1)
	local remis, banque, enCours, aFaire = 0, 0, 0, 0
	for _, l in ipairs(cadre.lignesSoir) do l:Hide() end
	local k = 0
	for n = debut, #Raid.attributions do
		local a = Raid.attributions[n]
		local etat, sens, qui, voie = EtatDuSoir(a)
		if sens == "fait" then remis = remis + 1 elseif a.etat == "banque" then banque = banque + 1
		elseif sens == "cours" then enCours = enCours + 1 elseif sens == "afaire" then aFaire = aFaire + 1 end
		k = k + 1
		local l = LigneSoir(cadre, k)
		l.num:SetText(a.n)
		Raid.PoserIcone(l.icone, a.id, a.lien)
		l.objet:SetText(((Raid.LienAJour(a.lien, a.id) or ""):gsub("%[(.-)%]", "%1")))
		l.a:SetText(qui)
		l.voie:SetText(voie)
		Raid.PoserPastille(l.etat, etat, sens)
		l:ClearAllPoints() l:SetPoint("TOPLEFT", 12, cadre.yAnnonces - (k - 1) * 20)
		l:Show()
	end
	local total = #Raid.attributions
	local resume = {}
	if total > 0 then resume[1] = Pluriel(total, "objet") end
	if enCours > 0 then resume[#resume + 1] = enCours .. " en cours" end
	if aFaire > 0 then resume[#resume + 1] = "|cffffcc33" .. aFaire .. " à faire|r" end
	if remis > 0 then resume[#resume + 1] = remis .. " remis" end
	if banque > 0 then resume[#resume + 1] = banque .. " à la banque" end
	cadre.resumeSoir:SetText(#resume > 0 and table.concat(resume, " · ") or "")
	cadre.vide:SetShown(k == 0)
	cadre.plusTot:SetShown(total > MAX_ANNONCES)
	cadre.plusTot:SetText(Opus.Gris(string.format("… et %d plus tôt (/opus raid objections)", total - MAX_ANNONCES)))
	local y = cadre.yAnnonces - math.max(1, k) * 20 - (total > MAX_ANNONCES and 16 or 0) - 14
	cadre.plusTot:SetPoint("TOPLEFT", 16, cadre.yAnnonces - k * 20 - 2)

	-- le rapport, en une ligne
	local s = Raid.db.soiree
	local n = s and #s.evenements or 0
	cadre.rapport:SetText(n > 0 and (Opus.Blanc(Pluriel(n, "événement")) .. Opus.Gris(" · soirée du " .. date("%d/%m %H:%M", s.debut)
		.. " · part au site par le bridge à la déconnexion")) or Opus.Gris("Rien à rendre au site pour l'instant."))
	cadre.exporter:SetEnabled(n > 0)
	cadre.exporter.raison = "Rien à exporter : aucun événement noté ce soir."
	cadre.titreRapport:SetPoint("TOPLEFT", 4, y)
	cadre.rapport:SetPoint("TOPLEFT", 16, y - 26)
	cadre.exporter:SetPoint("TOPRIGHT", -8, y - 20)
	return -y + 60
end

local function ConstruireSoir (cadre, largeur)
	cadre.largeur = largeur
	local function Section (texte, y)
		local s = cadre:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		s:SetPoint("TOPLEFT", 4, y) s:SetText(texte)
		return s
	end
	local function Texte (y, l)
		local t = cadre:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("TOPLEFT", 16, y) t:SetWidth(l or (largeur - 170)) t:SetJustifyH("LEFT") t:SetWordWrap(false)
		return t
	end
	local function Bulle (b, titre, texte)
		b.bulle = function (self)
			Raid.Ancrer(self)
			GameTooltip:AddLine(titre, 1, 1, 1)
			if not self:IsEnabled() and self.raison then GameTooltip:AddLine(self.raison, 1, 0.82, 0, true) end
			GameTooltip:AddLine(type(texte) == "function" and texte() or texte, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end

	-- le bandeau de la soirée : un témoin, l'état, les actions
	cadre.bandeau = CreateFrame("Frame", nil, cadre, "BackdropTemplate")
	cadre.bandeau:SetPoint("TOPLEFT", 4, -4) cadre.bandeau:SetPoint("TOPRIGHT", -4, -4) cadre.bandeau:SetHeight(36)
	cadre.bandeau:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	cadre.bandeau:SetBackdropBorderColor(1, 1, 1, 0.08)
	cadre.temoin = cadre.bandeau:CreateTexture(nil, "ARTWORK")
	cadre.temoin:SetSize(8, 8) cadre.temoin:SetPoint("LEFT", 12, 0)
	cadre.soiree = cadre.bandeau:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.soiree:SetPoint("LEFT", 28, 0) cadre.soiree:SetWidth(largeur - 360) cadre.soiree:SetJustifyH("LEFT") cadre.soiree:SetWordWrap(false)
	cadre.ouvrir = Raid.Bouton(cadre.bandeau, "Ouvrir la soirée", 120, function () Raid.OuvrirSoiree() end, "prim")
	Bulle(cadre.ouvrir, "Ouvrir la soirée de guilde", function () return string.format("En raid, par le maître du butin ou un officier, si %d %% du raid est de la guilde. Sans soirée ouverte, l'addon ne touche pas au butin.", Raid.Seuil() * 100) end)
	cadre.fermer = Raid.Bouton(cadre.bandeau, "Fermer la soirée", 120, function () Raid.FermerSoiree() end, "sec")
	Bulle(cadre.fermer, "Fermer la soirée", "Le rapport part au site par le bridge à la déconnexion.")
	cadre.butin = Raid.Bouton(cadre.bandeau, "Fenêtre du butin", 120, function () Raid.MontrerButin() end, "sec")
	Bulle(cadre.butin, "Fenêtre du butin", "Les objets du dernier corps ouvert, leur état et ce qu'il reste à faire.")
	cadre.remises = Raid.Bouton(cadre.bandeau, "À remettre", 110, function () Raid.Executer("remises") end, "sec")
	Bulle(cadre.remises, "À remettre", "Les objets attribués pas encore remis : ouvre un échange avec le gagnant, l'objet s'y pose tout seul.")

	Section("Instantané", -54)
	cadre.instantane = Texte(-78, largeur - 300)
	cadre.importer = Raid.Bouton(cadre, "Coller…", 76, function () Raid.OuvrirImport() end, "sec")
	cadre.importer:SetPoint("TOPRIGHT", -8, -72)
	Bulle(cadre.importer, "Coller l'instantané", "La chaîne « OLS1:I: » de la page Raids du site, avant la soirée.")
	cadre.duBridge = Raid.Bouton(cadre, "Du bridge", 86, function ()
		local texte = InstantaneDuFlux()
		if texte and Raid.ImporterInstantane(texte) then Opus.Rafraichir() end
	end, "sec")
	cadre.duBridge:SetPoint("RIGHT", cadre.importer, "LEFT", -6, 0)
	Bulle(cadre.duBridge, "Importer depuis le bridge", "L'instantané du palier en cours, apporté par le bridge à ta connexion (un rapport validé depuis demande un /reload, le bridge allumé).")
	cadre.detail = Raid.Bouton(cadre, "Détail", 66, function () Raid.Executer("etat") end, "sec")
	cadre.detail:SetPoint("RIGHT", cadre.duBridge, "LEFT", -6, 0)
	Bulle(cadre.detail, "Détail de l'instantané", function ()
		local i = Raid.db.instantane
		return i and string.format("%s, palier %s : %s, %s. Importé le %s par %s. Le détail complet part dans la discussion.", i.id, i.tier ~= "" and i.tier or "?",
			Pluriel(i.nJoueurs, "joueur"), Pluriel(i.nObjets, "objet"), date("%d/%m à %H:%M", i.importe or i.date), i.par or "?") or ""
	end)

	Section("Ce soir", -112)
	cadre.resumeSoir = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.resumeSoir:SetPoint("TOPLEFT", 70, -114)
	-- les en-têtes du tableau
	for _, t in ipairs({ { "#", 12, 22, "RIGHT" }, { "objet", 62 }, { "à", 268 }, { "par", 424 }, { "état", 560 } }) do
		local e = cadre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		e:SetPoint("TOPLEFT", t[2], -134) e:SetText(t[1])
		if t[3] then e:SetWidth(t[3]) e:SetJustifyH(t[4]) end
	end
	cadre.yAnnonces = -150
	cadre.lignesSoir = {}
	cadre.vide = Texte(cadre.yAnnonces - 2, largeur - 20)
	cadre.vide:SetText(Opus.Gris("Aucune annonce ce soir. Les soirées passées sont dans l'historique."))
	cadre.plusTot = Texte(0, largeur - 20)

	cadre.titreRapport = Section("Rapport", -260)
	cadre.rapport = Texte(-286, largeur - 140)
	cadre.exporter = Raid.Bouton(cadre, "Exporter…", 90, function () Raid.Exporter() end, "sec")
	cadre.exporter:SetPoint("TOPRIGHT", -8, -280)
	Bulle(cadre.exporter, "Exporter le rapport", "Avec le bridge, le rapport part tout seul au site à la déconnexion. Sans lui, à coller sur le site, page Raids, « Rapports » du palier. Rien ne compte en double.")
end

------------------------------------------------------------------------
-- la page
------------------------------------------------------------------------

-- Ma liste et l'historique : un texte qui défile, aux liens d'objets survolables
local function ConstruireTexte (cadre, largeur)
	cadre.largeur = largeur
	cadre.defile = CreateFrame("ScrollFrame", nil, cadre)
	cadre.defile:SetPoint("TOPLEFT") cadre.defile:SetWidth(largeur - 14) cadre.defile:SetHeight(VUE_MAX)
	local x = CreateFrame("Frame", nil, cadre.defile)
	x:SetWidth(largeur - 14) x:SetHeight(1)
	cadre.defile:SetScrollChild(x)
	x:SetHyperlinksEnabled(true)
	x:SetScript("OnHyperlinkEnter", function (self, lien)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		if pcall(GameTooltip.SetHyperlink, GameTooltip, lien) then GameTooltip:Show() else GameTooltip:Hide() end
	end)
	x:SetScript("OnHyperlinkLeave", function () GameTooltip:Hide() end)
	x:SetScript("OnHyperlinkClick", function (_, lien, texte, bouton) SetItemRef(lien, texte, bouton) end)
	cadre.texte = x:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cadre.texte:SetPoint("TOPLEFT", 4, -4) cadre.texte:SetWidth(largeur - 30) cadre.texte:SetJustifyH("LEFT") cadre.texte:SetSpacing(4)
	cadre.contenu = x
	cadre.ascenseur = Opus.Ascenseur(cadre, function (d) defile = d Opus.Rafraichir() end)
	cadre.ascenseur:SetPoint("TOPRIGHT", cadre.defile, "TOPRIGHT", 14, 0)
	cadre.ascenseur:SetPoint("BOTTOMRIGHT", cadre.defile, "BOTTOMRIGHT", 14, 0)
	cadre.ascenseur:Hide()
end

local function RafraichirTexte (cadre, texte)
	cadre.texte:SetText(texte)
	local total = cadre.texte:GetStringHeight() + 12
	local visible = math.min(total, VUE_MAX)
	cadre.contenu:SetHeight(total)
	cadre.defile:SetHeight(visible)
	cadre:SetHeight(visible)
	defile = math.max(0, math.min(defile, total - visible))
	cadre.defile:SetVerticalScroll(defile)
	cadre.ascenseur:Recaler(defile, total, visible)
	return visible + 8
end

local function Rafraichir (cadre)
	cadre.vues:Maj()
	local _, maj = Raid.Flux()
	cadre.fraicheur:SetText(maj and ("site : " .. Jour(maj) .. date(" %H:%M", maj)) or "")
	for _, k in ipairs({ "soir", "liste", "historique" }) do cadre[k]:SetShown(vue == k) end
	if vue == "liste" then
		local flux = Raid.Flux()
		local hauteur = flux and BlocsListe(cadre.liste, flux)
		if hauteur then
			-- les blocs, dans le même défilement que le texte (vidé)
			cadre.liste.texte:SetText("")
			local c = cadre.liste
			local visible = math.min(hauteur, VUE_MAX)
			c.contenu:SetHeight(hauteur) c.defile:SetHeight(visible) c:SetHeight(visible)
			defile = math.max(0, math.min(defile, hauteur - visible))
			c.defile:SetVerticalScroll(defile)
			c.ascenseur:Recaler(defile, hauteur, visible)
			return visible + 8
		end
		for _, b in ipairs(cadre.liste.blocs or {}) do b:Hide() end
		return RafraichirTexte(cadre.liste, TexteListe())
	end
	if vue == "historique" then return RafraichirTexte(cadre.historique, TexteHistorique()) end
	return RafraichirSoir(cadre.soir)
end

local function Construire (cadre, barre)
	local largeur = Opus.LARGEUR - 30
	cadre.vues = Opus.Onglets(barre, VUES, function () return vue end, function (v) vue = v defile = 0 Opus.Rafraichir() end)
	cadre.fraicheur = barre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cadre.fraicheur:SetPoint("RIGHT", 0, 0)
	for _, k in ipairs({ "soir", "liste", "historique" }) do
		cadre[k] = CreateFrame("Frame", nil, cadre)
		cadre[k]:SetPoint("TOPLEFT") cadre[k]:SetPoint("TOPRIGHT") cadre[k]:SetHeight(1)
	end
	ConstruireSoir(cadre.soir, largeur)
	ConstruireTexte(cadre.liste, largeur)
	ConstruireTexte(cadre.historique, largeur)
end

Opus.Page("raids", "Raids", Construire, Rafraichir, function (_, d) defile = math.max(0, defile - d * 60) end)

-- un objet arrivé dans le cache du jeu : son vrai lien remplace le nom
local attente
Raid.Ecoute("GET_ITEM_INFO_RECEIVED", function ()
	if attente or not Opus.db or Opus.db.page ~= "raids" or vue == "soir" then return end
	attente = C_Timer.NewTimer(0.5, function () attente = nil Opus.Rafraichir() end)
end)

-- les comptes à rebours, tant que l'onglet est ouvert et qu'une annonce court
C_Timer.NewTicker(1, function ()
	if not Opus.db or Opus.db.page ~= "raids" or vue ~= "soir" or not OpusFenetre or not OpusFenetre:IsShown() then return end
	for _, a in ipairs(Raid.attributions) do
		if a.etat == "delai" or a.etat == "vote" or a.etat == "sk" then Opus.Rafraichir() return end
	end
end)
