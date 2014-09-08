-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      update.lua                                         --
-- Description:   Command updating EPG databased                     --
--                                                                   --
-----------------------------------------------------------------------

local table    = require "lrun.util.table"
local log      = require "avtv.log"
local config   = require "avtv.config"

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
	},
	novabg =
	{
		channels = require "avtv.provider.novabg.channels",
		programs = require "avtv.provider.novabg.programs",
	},
	bulsat_com =
	{
		channels = require "avtv.provider.bulsat_com.channels",
		programs = require "avtv.provider.bulsat_com.programs",
	},
	bulsat =
	{
		channels = require "avtv.provider.bulsat.epg",
		programs = require "avtv.provider.bulsat.epg"
	},
	zattoo =
	{
		channels = require "avtv.provider.zattoo.epg",
		programs = require "avtv.provider.zattoo.epg"
	}
}

local _G, unpack, setmetatable, os =
      _G, unpack, setmetatable, os

local print, pairs, ipairs, type = print, pairs, ipairs, type

module "avtv.command.update"

_NAME = "update"
_DESCRIPTION = "Updates EPG database with providers data"
_HELP =
[[
UPDATE [provider {' ' provider}]
  Update EPG data for the specified providers given as command arguments.
  Available providers: ]]..table.concat(table.keys(epg, true), ", ")..[[
]]

local function time(n, f)
	local timestart = os.time()
	local res = {f()}
	local timetotal = os.time() - timestart
	log.info(_NAME..": "..n.." - "..timetotal.." secs")	
	return unpack(res)
end

local function updateprovider(provider)
	log.info(_NAME..": updating "..provider)
	local channelsexpire = config.getnumber("epg.channels.expire")
	local programsexpire = config.getnumber("epg.programs.expire")
	local channelids = {__expire = channelsexpire}
	if not epg[provider] then
		return nil, "no such EPG provider `"..provider.."'"
	end
	local ok, err = time("epg."..provider..".channels.update", function ()
		return epg[provider].channels.update(function (channel)
			if channelsexpire > 0 then
				channel.__expire = channelsexpire
			end
			_G._rdb.epg[provider](channel)
			table.insert(channelids, channel.id)
			return true
		end)
	end)
	if not ok then
		return nil, err
	end
	-- insert channels to DB
	_G._rdb.epg[provider].__delete("channels")
	_G._rdb.epg[provider].__rpush("channels", channelids)

	log.info(_NAME..": "..table.getn(channelids).." channels inserted in "..provider.." provider")

	local channelprograms = {}
	local nprograms = 0
	ok, err = time("epg."..provider..".programs.update", function () 

		local ok, err = epg[provider].programs.update(channelids, function (channelid, program) 
			if programsexpire > 0 then
				program.__expire = programsexpire
			end
			nprograms = nprograms + 1
			channelprograms[channelid] = channelprograms[channelid] or {__expire = programsexpire}

			-- check for duplicated program id
			for i, prg in ipairs(channelprograms[channelid]) do
				if prg.id == program.id then
					log.warn(_NAME..": duplicate program id = "..prg.id.." in channel "..provider.."/"..channelid)
					table.remove(channelprograms[channelid], i)
					break
				end
			end
			table.insert(channelprograms[channelid], program)
			return true
		end)

		log.debug(_NAME..": importing "..nprograms.." programs")
		for channelid, programs in pairs(channelprograms) do
			for _, program in ipairs(programs) do
				_G._rdb.epg[provider][channelid](program)
			end
		end

		return ok, err
	end)
	if not ok then
		return nil, err
	end
	log.info(_NAME..": "..nprograms.." programs inserted in "..provider.." provider")
	for channelid, programs in pairs(channelprograms) do
		_G._rdb.epg[provider][channelid].__delete("programs")
		local programsid = {}
		for _, prg in ipairs(programs) do
			table.insert(programsid, prg.id)
		end
		_G._rdb.epg[provider][channelid].__rpush("programs", programsid)
	end
	log.info(_NAME..": updating "..provider.." completed")
	return true
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
			local ok, err
			for provider in pairs(epg) do
				ok, err = updateprovider(provider)
				if not ok then
					return nil, err
				end
			end
			return true
		end
	end
end})
