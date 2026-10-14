-- Server/Instances.lua
-- Vergibt nanos-Dimensionen. Jede Instanz (Hub-Bereich oder Tisch) bekommt eine eigene Nummer.
-- Spieler in verschiedenen Dimensionen sehen sich nicht und bekommen keine Daten voneinander.

DeathBox.Instances = {
	used = {},
}

local Instances = DeathBox.Instances

-- Naechste freie Dimension ab first
function Instances.Acquire(first)
	local dimension = first
	while (Instances.used[dimension]) do
		dimension = dimension + 1
	end
	Instances.used[dimension] = true
	return dimension
end

function Instances.Release(dimension)
	Instances.used[dimension] = nil
end
