-- Shared/Index.lua
-- Laeuft auf Server UND Client, und zwar vor Server/Index.lua bzw. Client/Index.lua.

DeathBox = DeathBox or {}
DeathBox.VERSION = "0.1.0"

Package.Require("Config.lua")
Package.Require("Cards.lua")
