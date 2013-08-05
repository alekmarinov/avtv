-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      update.lua                                         --
-- Description:   Command updating EPG databased                     --
--                                                                   --
-----------------------------------------------------------------------

local config   = require "lrun.util.config"
local log      = require "avtv.log"
local epg = {
	rayv     =
	{
		channels = require "avtv.provider.rayv.channels",
		programs = require "avtv.provider.rayv.programs",
	},
	wilmaa     =
	{
		channels = require "avtv.provider.wilmaa.channels",
		programs = require "avtv.provider.wilmaa.programs",
	}
}

local _G, table, unpack, setmetatable, os =
      _G, table, unpack, setmetatable, os

local print, pairs, type = print, pairs, type

module "avtv.command.update"

_NAME = "update"
_DESCRIPTION = "Updates EPG database with providers data"
_HELP =
[[
UPDATE [provider {' ' provider}]
  Update EPG data for the specified providers given as command arguments

]]

local function time(n, f)
	local timestart = os.time()
	local res = {f()}
	local timetotal = os.time() - timestart
	log.info(_NAME..": "..n.." - "..timetotal.." secs")	
	return unpack(res)
end

local function updateprovider(provider)
	local channels = {}
	local ok, err = time("epg."..provider..".channels.update", function ()
		return epg[provider].channels.update(function (channel) 
			table.insert(channels, channel)
			return true
		end)
	end)
	if not ok then
		return nil, err
	end
	-- insert channels to DB
	_G._rdb.epg[provider].channels(channels)

	for i = 1, #channels do
		channels[i] = channels[i].id
	end
	return time("epg."..provider..".programs.update", function () 
		return epg[provider].programs.update(channels, function (channel, program) 
			_G._rdb.epg[provider][channel](program)
			return true
		end)
	end)
end

return setmetatable(_M, { __call = function (this, ...)
	local query = ...
	if query == "--help" then
		-- display help
		print(_HELP)
		return true
	else
		if query then
			return updateprovider(query)
		else
			for provider in pairs(epg) do
				return updateprovider(provider)
			end
		end
	end
end})
