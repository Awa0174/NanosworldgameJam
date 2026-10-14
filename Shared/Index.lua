-- Shared/Index.lua
-- Laeuft auf Server UND Client, und zwar vor Server/Index.lua bzw. Client/Index.lua.

DeathBox = DeathBox or {}
DeathBox.VERSION = "0.12.0"

Package.Require("Config.lua")
Package.Require("Assets.lua")
Package.Require("Layout.lua")
Package.Require("Text.lua")
Package.Require("Cards.lua")
