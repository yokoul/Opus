-- Invitation.lua : proposer une place dans un groupe de guilde à un membre qui a l'addon, et sa réponse
-- La proposition part sur le canal de guilde des addons (« J ») avec le nom du destinataire : seul lui affiche une fenêtre
-- (« Je viens ! » ou « Pas cette fois »), et sa réponse (« R ») revient à celui qui forme le groupe. Une acceptation le
-- place dans le groupe, et une fenêtre propose de l'inviter : l'invitation passe par /invite dans un bouton sécurisé,
-- parce qu'inviter directement est restreint pour un addon. Rien ne s'ouvre en combat : la fenêtre attend la fin.
local _, Opus = ...

local FS = ";"
local DUREE = 90                  -- secondes avant qu'une proposition sans réponse ne se ferme
local NOMS_ROLES = { tank = "tank", soin = "soigneur", degats = "dégâts" }
local envoyees = {}               -- [rid] = { cible, role } : nos propositions en attente

local function Texte (s) return s and (tostring(s):gsub(";", ","):gsub("~", "-")) or "" end

-- la place qu'on propose : parmi ses rôles, celui qui manque au groupe (tank et soin d'abord), sinon son rôle principal ;
-- sans rôle connu, le premier rôle qui manque
function Opus.RolePropose (m)
	local s = Opus.db.spes[m.nom]
	local roles = Opus.RolesDe(s)
	for i, r in ipairs(Opus.PLACES) do
		if not Opus.groupe.places[i] and Opus.PeutTenir(s, r) then return r end
	end
	if roles[1] then return roles[1] end
	for i, r in ipairs(Opus.PLACES) do if not Opus.groupe.places[i] then return r end end
	return "degats"
end

-- le message tout prêt pour un chuchotement
function Opus.MessageProposition (m)
	local _, _, donjon = Opus.Tranche()
	return ("Coucou ! On monte un groupe de guilde pour %s : ça te tenterait, en %s ?"):format(donjon or "un donjon", NOMS_ROLES[Opus.RolePropose(m)])
end

local function Places ()
	local n = 0
	for i = 1, #Opus.PLACES do if Opus.groupe.places[i] then n = n + 1 end end
	return n
end

function Opus.Proposer (m)
	local min, max, donjon = Opus.Tranche()
	local rid = ("%04x%04x"):format(math.random(0, 65535), math.random(0, 65535))
	local role = Opus.RolePropose(m)
	envoyees[rid] = { cible = m.nom, role = role }
	Opus.EnvoyerVite(table.concat({ "J", rid, Texte(m.nom), Texte(donjon or ""), min, max, role, Places(), Texte(Opus.MonNom()),
		Opus.RisqueGris(m.niveau) and "gris" or "" }, FS))
	Opus.Msg(("proposition envoyée à %s (%s)."):format(m.nom, NOMS_ROLES[role]))
end

------------------------------------------------------------------------
-- les fenêtres : celle qui propose (chez le destinataire), celle qui annonce la réponse (chez le chef de groupe)
------------------------------------------------------------------------

local enAttente = {}              -- fenêtres à montrer à la fin du combat

local function Fenetre (nom)
	local f = CreateFrame("Frame", nom, UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HideButtonBar(f)
	f:SetSize(380, 170)
	f:SetPoint("TOP", 0, -140)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPortraitToAsset("Interface\\AddOns\\Opus\\Media\\Embleme")
	f.texte = f.Inset:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.texte:SetPoint("TOPLEFT", 12, -12) f.texte:SetPoint("TOPRIGHT", -12, -12)
	f.texte:SetJustifyH("LEFT") f.texte:SetSpacing(3)
	f:Hide()
	return f
end

local function Montrer (f)
	if InCombatLockdown() then enAttente[#enAttente + 1] = f return end
	f:Show()
	PlaySound(SOUNDKIT.READY_CHECK)
	if FlashClientIcon then FlashClientIcon() end
end
Opus.Ecoute("PLAYER_REGEN_ENABLED", function ()
	for _, f in ipairs(enAttente) do Montrer(f) end
	enAttente = {}
end)

-- chez le destinataire
local proposition
local function Repondre (oui)
	local p = proposition and proposition.p
	if not p then return end
	Opus.EnvoyerVite(table.concat({ "R", p.rid, oui and "oui" or "non" }, FS))
	if p.minuteur then p.minuteur:Cancel() end
	proposition:Hide()
end

Opus.RepondreProposition = Repondre

local function Proposition (p)
	if not proposition then
		proposition = Fenetre("OpusProposition")
		proposition:SetTitle("Groupe de guilde")
		local oui = Opus.Bouton(proposition.Inset, "Je viens !", 150, function () Repondre(true) end)
		oui:SetPoint("BOTTOMRIGHT", -12, 10)
		local non = Opus.Bouton(proposition.Inset, "Pas cette fois", 150, function () Repondre(false) end)
		non:SetPoint("RIGHT", oui, "LEFT", -8, 0)
		proposition.CloseButton:SetScript("OnClick", function () Repondre(false) end)
	end
	proposition.p = p
	local demandeur = Opus.TrouverMembre(p.de)
	proposition.texte:SetText(("%s te propose une place dans son groupe :\n%s\n%s, places prises : %d / 5"):format(
		demandeur and (Opus.Couleur(demandeur.classe) .. p.de .. "|r") or p.de,
		Opus.Normal((p.donjon ~= "" and p.donjon or "Donjon") .. ("  (niv. %d-%d)"):format(p.min, p.max)),
		"En " .. Opus.Blanc(NOMS_ROLES[p.role] or p.role), p.places)
		.. (p.gris and ("\n" .. Opus.Rouge("Attention : trop haut pour ce donjon, le groupe ne gagnerait plus d'XP.")) or ""))
	if p.minuteur then p.minuteur:Cancel() end
	p.minuteur = C_Timer.NewTimer(DUREE, function () if proposition.p == p then proposition:Hide() end end)
	Montrer(proposition)
end

-- chez le chef de groupe
local reponse
local function Reponse (nom, role)
	if not reponse then
		reponse = Fenetre("OpusReponse")
		reponse:SetTitle("Groupe de guilde")
		reponse.inviter = Opus.BoutonSecurise(reponse.Inset, 150, function ()
			GameTooltip:SetText("Inviter")
			GameTooltip:AddLine("Envoie l'invitation de groupe (/invite).", 1, 1, 1, true)
		end)
		reponse.inviter:SetSize(150, 24)
		reponse.inviter:SetText("Inviter")
		reponse.inviter:SetPoint("BOTTOMRIGHT", -12, 10)
		reponse.inviter:HookScript("PostClick", function () reponse:Hide() end)
		local plusTard = Opus.Bouton(reponse.Inset, "Plus tard", 120, function () reponse:Hide() end)
		plusTard:SetPoint("RIGHT", reponse.inviter, "LEFT", -8, 0)
	end
	if InCombatLockdown() then
		C_Timer.After(1, function () Reponse(nom, role) end)
		return
	end
	local m = Opus.TrouverMembre(nom)
	reponse.texte:SetText(("%s accepte de venir, en %s.\nIl est placé dans ton groupe (onglet Roster)."):format(
		m and (Opus.Couleur(m.classe) .. nom .. "|r") or nom, Opus.Blanc(NOMS_ROLES[role] or role)))
	reponse.inviter:SetAttribute("type", "macro")
	reponse.inviter:SetAttribute("macrotext", "/invite " .. nom)
	Montrer(reponse)
end

------------------------------------------------------------------------
-- changement de donjon (« D ») : prévenir les membres déjà placés
------------------------------------------------------------------------

function Opus.AnnoncerDonjon ()
	local moi, cibles = Opus.MonNom(), {}
	for i = 1, #Opus.PLACES do
		local nom = Opus.groupe.places[i]
		if nom and nom ~= moi and Opus.AAddon(nom) then cibles[#cibles + 1] = Texte(nom):gsub(",", " ") end
	end
	if #cibles == 0 then return end
	local min, max, donjon = Opus.Tranche()
	Opus.EnvoyerVite(table.concat({ "D", Texte(donjon or ""), min, max, Texte(moi), table.concat(cibles, ",") }, FS))
	Opus.Msg("changement de donjon annoncé au groupe.")
end

local changement
function Opus.RecevoirDonjon (champs, expediteur)
	local donjon, min, max, de, cibles = champs[2], tonumber(champs[3]), tonumber(champs[4]), champs[5], champs[6] or ""
	if not min or not Opus.EstMembre(de, expediteur) then return end
	local pourMoi = false
	for nom in cibles:gmatch("[^,]+") do if nom == Opus.MonNom() then pourMoi = true end end
	if not pourMoi then return end
	if not changement then
		changement = Fenetre("OpusChangement")
		changement:SetTitle("Groupe de guilde")
		local ok = Opus.Bouton(changement.Inset, "D'accord", 150, function () changement:Hide() end)
		ok:SetPoint("BOTTOMRIGHT", -12, 10)
	end
	local trop = UnitLevel("player") - max >= Opus.ECART_GRIS
	changement.texte:SetText(("%s change de donjon :\n%s"):format(de, Opus.Normal((donjon ~= "" and donjon or "autour de son niveau") .. ("  (niv. %d-%d)"):format(min, max)))
		.. (trop and ("\n" .. Opus.Rouge("Attention : tu es trop haut pour ce donjon, le groupe ne gagnerait plus d'XP.")) or ""))
	Montrer(changement)
end

------------------------------------------------------------------------
-- réception (Partage.lua passe les messages « J » et « R »)
------------------------------------------------------------------------

function Opus.RecevoirProposition (champs, expediteur)
	local rid, cible, donjon, min, max, role, places, de = champs[2], champs[3], champs[4], tonumber(champs[5]), tonumber(champs[6]), champs[7], tonumber(champs[8]), champs[9]
	if not rid or cible ~= Opus.MonNom() or not min or not max then return end
	if not Opus.EstMembre(de, expediteur) then return end
	Proposition({ rid = rid, de = de, donjon = donjon or "", min = min, max = max, role = role, places = places or 1, gris = champs[10] == "gris" })
end

function Opus.RecevoirReponse (champs, expediteur)
	local rid, oui = champs[2], champs[3] == "oui"
	local e = rid and envoyees[rid]
	if not e or not Opus.EstMembre(e.cible, expediteur) then return end
	envoyees[rid] = nil
	if oui then
		local m = Opus.TrouverMembre(e.cible)
		if m then Opus.AjouterAuGroupe(m) end
		Reponse(e.cible, e.role)
	else
		Opus.Msg(e.cible .. " ne vient pas cette fois.")
	end
end
