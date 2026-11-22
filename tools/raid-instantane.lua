-- Fabrique un instantané d'essai, signé comme le fera le site : lua tools/instantane.lua > tools/instantane-essai.txt
-- Des membres de la guilde (deux Basara, deux Kibrom) et un nom qui n'existe pas (Kibrom Stoneheart) ; objets fictifs.

local function Adler32 (s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return string.format("%08x", b * 65536 + a)
end

local r = {
	"E;essai-1;T1;" .. os.time() .. ";0;12",
	"P;50;25;15;10",
	"J;Basara Nore;tank;0.5;1;0;main",
	"J;Basara Auberdine;dps;0;0.4;0.2;reroll",
	"J;Kibrom Felheart;heal;0;0.2;0.4;main",
	"J;Kibrom Stoneheart;heal;1;1;0;main",
	"J;Kibrom Wildheart;dps;0.2;0.6;0.1;reroll",
	"W;19019;Basara Nore:1,Kibrom Felheart:3",
	"W;18814;Kibrom Felheart:1,Kibrom Stoneheart:1,Basara Auberdine:2",
	"S;Kibrom Stoneheart,Basara Auberdine,Kibrom Felheart,Kibrom Wildheart,Basara Nore",
	"Z;Basara Auberdine",
}
local corps = "OLS1:I:" .. table.concat(r, "~")
print(corps .. "~#" .. Adler32(corps))
