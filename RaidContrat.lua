-- RaidContrat.lua : les chaînes échangées avec le site Opus (instantané à l'aller, rapport au retour)
-- Le format est décrit dans docs/contrat-butin.md du dépôt Opus : préfixe « OLS1:I: » ou « OLS1:R: », enregistrements
-- séparés par « ~ », champs par « ; », listes par « , », et à la fin « ~# » suivi de la somme Adler-32 en hexadécimal
-- de tout ce qui précède. Une chaîne abîmée au collage est refusée en entier : rien n'est appliqué à moitié.
local _, Opus = ...
local Raid = Opus.Raid

local VERSION = "OLS1"
local FS, RS, LS = ";", "~", ","
Raid.contrat = { version = VERSION, FS = FS, RS = RS, LS = LS }

-- Adler-32, sans opérations sur les bits : deux sommes modulo 65521
function Raid.Adler32 (s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return string.format("%08x", b * 65536 + a)
end

-- signe une chaîne : ce que le site fait de son côté, et ce que fera le rapport
function Raid.Signer (corps)
	return corps .. RS .. "#" .. Raid.Adler32(corps)
end

-- Ouvre une chaîne collée : vérifie la version, le sens (« I » ou « R ») et la somme, rend la liste des
-- enregistrements, chacun en liste de champs. Les retours à la ligne et les espaces ajoutés au collage sont ignorés.
function Raid.Ouvrir (texte, sens)
	if type(texte) ~= "string" then return nil, "rien à lire" end
	texte = strtrim((texte:gsub("[\r\n\t]", "")))
	if texte == "" then return nil, "rien à lire" end
	local version, s = texte:match("^(OLS%d+):(%u):")
	if not version then return nil, "ce n'est pas une chaîne du site Opus" end
	if version ~= VERSION then return nil, "chaîne au format " .. version .. ", cet addon lit " .. VERSION .. " : mets à jour Opus" end
	if s ~= sens then return nil, s == "R" and "c'est un rapport, pas un instantané" or "ce n'est pas un instantané" end
	local corps, somme = texte:match("^(.*)~#(%x+)$")
	if not corps then return nil, "la chaîne est incomplète (somme de contrôle absente) : recopie-la en entier" end
	if somme:lower() ~= Raid.Adler32(corps) then return nil, "la chaîne est abîmée (somme de contrôle fausse) : recopie-la en entier" end
	local enregistrements = {}
	corps = corps:sub(#VERSION + 4)        -- « OLS1:I: » retiré
	for r in (corps .. RS):gmatch("(.-)" .. RS) do
		if r ~= "" then enregistrements[#enregistrements + 1] = { strsplit(FS, r) } end
	end
	return enregistrements
end

-- une liste « a,b,c » (vide si le champ est vide)
function Raid.Liste (champ)
	local t = {}
	if champ and champ ~= "" then
		for brut in (champ .. LS):gmatch("(.-)" .. LS) do
			local v = strtrim(brut)
			if v ~= "" then t[#t + 1] = v end
		end
	end
	return t
end
