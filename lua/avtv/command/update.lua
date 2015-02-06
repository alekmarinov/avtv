-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      update.lua                                         --
-- Description:   Command updating EPG databased                     --
--                                                                   --
-----------------------------------------------------------------------

local redis    = require "lrun.db.redis"
local solr     = require "lrun.db.solr"
local table    = require "lrun.util.table"
local string   = require "lrun.util.string"
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
	},
	smartxmedia =
	{
		channels = require "avtv.provider.smartxmedia.epg",
		programs = require "avtv.provider.smartxmedia.epg"
	}
}

local vod = {
	bulsat = require "avtv.provider.bulsat.vod"
}

local _G, unpack, setmetatable, os, pairs, ipairs, type, assert =
      _G, unpack, setmetatable, os, pairs, ipairs, type, assert

-- debug
local print, tostring  = print, tostring

module "avtv.command.update"

_NAME = "update"
_DESCRIPTION = "Updates EPG database with providers data"
_HELP =
[[
UPDATE [ [(vod|epg):]provider {' ' [(vod|epg):]provider}]
  Update EPG/VOD data for the specified providers given as command arguments.
  Available EPG providers: ]]..table.concat(table.keys(epg, true), ", ")..[[
  
  Available VOD providers: ]]..table.concat(table.keys(vod, true), ", ")..[[
]]

local function time(n, f)
	local timestart = os.time()
	local res = {f()}
	local timetotal = os.time() - timestart
	log.info(_NAME..": "..n.." - "..timetotal.." secs")	
	return unpack(res)
end

local function checkprovider(provider, modname)
	assert(type(provider) == "string")
	if not modname then
		if not epg[provider] and not vod[provider] then
			return nil, "no such EPG or VOD provider `"..provider.."'"
		end
	elseif modname == "epg" then
		if not epg[provider] then
			return nil, "no such EPG provider `"..provider.."'"
		end
	elseif modname == "vod" then
		if not vod[provider] then
			return nil, "no such VOD provider `"..provider.."'"
		end
	else
		return nil, "no such module `"..modname.."'"
	end
	return true
end

local function getredisdb()
	return assert(redis.connect{
	    host = config.get("db.redis.host"),
	    port = config.get("db.redis.port")
	})
end

local function getsolrdb()
	return solr.new{
		host = config.get("db.solr.host"),
		port = config.get("db.solr.port"),
		collection = config.get("db.solr.collection")
	}
end

local function updateprovider(provider)
	log.info(_NAME..": updating "..provider)
	local providerparts = string.explode(provider, ":")
	local modname
	if #providerparts > 1 then
		modname = providerparts[1]
		provider = providerparts[2]
	end

	local ok, err = checkprovider(provider, modname)
	if not ok then
		return nil, err
	end

	if not modname or modname == "epg" then
		local rdb = getredisdb()
		local channelsexpire = config.getnumber("epg.channels.expire")
		local programsexpire = config.getnumber("epg.programs.expire")
		local channelids = {__expire = channelsexpire}
		ok, err = time("epg."..provider..".channels.update", function ()
			return epg[provider].channels.update(function (channel)
				if channelsexpire > 0 then
					channel.__expire = channelsexpire
				end
				rdb.epg[provider](channel)
				table.insert(channelids, channel.id)
				return true
			end)
		end)
		if not ok then
			return nil, err
		end
		-- insert channels to DB
		rdb.epg[provider].__delete("channels")
		rdb.epg[provider].__rpush("channels", channelids)

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
					rdb.epg[provider][channelid](program)
				end
			end

			return ok, err
		end)
		if not ok then
			return nil, err
		end
		log.info(_NAME..": "..nprograms.." programs inserted in "..provider.." provider")
		for channelid, programs in pairs(channelprograms) do
			rdb.epg[provider][channelid].__delete("programs")
			local programsid = {}
			for _, prg in ipairs(programs) do
				table.insert(programsid, prg.id)
			end
			rdb.epg[provider][channelid].__rpush("programs", programsid)
		end
		rdb:disconnect()
	end

	if not modname or modname == "vod" then
		local rdb = getredisdb()
		local slr = getsolrdb()

		local vodexpiregroups = config.getnumber("vod.expire.groups")
		local vodexpireitems  = config.getnumber("vod.expire.items")
		local vodgroupids = {__expire = vodexpiregroups}

		ok, err = time("vod."..provider..".update", function ()
			ok, err = vod[provider].update(function (vodgroup, vodlist, searchfields)

				if slr and #vodlist > 0 then
					-- posting VOD items to Solr
					local slritems = {}
					for _, item in ipairs(vodlist) do
						local newitem = { id = item.id, group_id = vodgroup.id }
						for _, name in ipairs(searchfields) do
							local value = item[name]
							if type(value) == "string" then
								newitem[name] = value
							end
						end
						table.insert(slritems, newitem)
					end
					log.info("Post "..#slritems.." items to solr at "..slr.host..":"..slr.port)
					slr:post(slritems)
				end

				if vodexpiregroups > 0 then
					vodgroup.__expire = vodexpiregroups
				end
				rdb.vod[provider](vodgroup)
				table.insert(vodgroupids, vodgroup.id)
				local voditemids = {__expire = vodexpireitems}
				for _, voditem in ipairs(vodlist) do
					if vodexpireitems > 0 then
						voditem.__expire = vodexpireitems
					end
					rdb.vod[provider][vodgroup.id](voditem)
					table.insert(voditemids, voditem.id)
				end
				rdb.vod[provider][vodgroup.id].__delete("vods")
				if #voditemids > 0 then
					rdb.vod[provider][vodgroup.id].__rpush("vods", voditemids)
				end
				return true
			end)
			if not ok then
				return nil, er
			end
			-- FIXME: delete unnecessary VOD items from Solr

			rdb.vod[provider].__delete("groups")
			rdb.vod[provider].__rpush("groups", vodgroupids)
			return true
		end)
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

