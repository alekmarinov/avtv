-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      config.lua                                         --
-- Description:   AVTV configuration module                          --
--                                                                   --
-----------------------------------------------------------------------

local config = require "lrun.util.config"
local _G, type, assert = _G, type, assert

module "avtv.config"

function get(key)
	return config.get(_G._conf, key)
end

function getstring(key)
	local value = get(key)
	assert(type(value) == "string", "string config `"..key.."' expected, got "..type(value))
	return value
end

function getnumber(key)
	local value = config.getnumber(_G._conf, key)
	assert(type(value) == "number", "number config `"..key.."' expected, got "..type(value))
	return value
end
