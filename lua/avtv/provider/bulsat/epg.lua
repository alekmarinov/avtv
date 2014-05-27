-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2014,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      channels.lua                                       --
-- Description:   Bulsat channels provider                             --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local html   = require "lrun.parse.html"
local lom    = require "lxp.lom"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs, tostring, tonumber, table =
      io, os, type, assert, ipairs, tostring, tonumber, table

local print, pairs = print, pairs

module "avtv.provider.bulsat.channels"

local function downloadxml()
	local epgurl = config.getstring("epg.bulsat.url")
	log.debug(_NAME..": downloading `"..epgurl.."'")
	local ok, code, headers = dw.download(epgurl)
	if not ok then
		-- error downloading url
		return nil, code.." while downloading "..epgurl
	end
	return ok
end

local function parsexml(xml)
	local function istag(tag, name)
		return type(tag) == "table" and string.lower(tag.tag) == name
	end
	local function mktime(timespec)
		local timestamp = os.time{year=tonumber(timespec:sub(1, 4)), month=tonumber(timespec:sub(5, 6)), day=tonumber(timespec:sub(7, 8)), hour=tonumber(timespec:sub(9, 10)), min=tonumber(timespec:sub(11, 12)), sec=tonumber(timespec:sub(13, 14))}
		local mul = 1
		if timespec:sub(16, 16) == "-" then
			mul = -1
		end
		local offset = mul * (60 * 60 * tonumber(timespec:sub(17, 18)) + 60 * tonumber(timespec:sub(19, 20)))
		timestamp = timestamp - offset
		local formated = os.date("%Y%m%d%H%M%S", timestamp)
		log.debug(_NAME..": mktime "..timespec.." -> "..formated.." with offset "..offset)
		return formated
	end
	local function downloadlogo(channelid, url)
		local ext = lfs.ext(url)
		local thumbname = "logo"..ext
		local dirstatic = config.getstring("epg.bulsat.dir.static")
		local thumbfile = lfs.concatfilenames(dirstatic, channelid, thumbname)
		lfs.mkdir(lfs.dirname(thumbfile))
		log.debug(_NAME..": downloading `"..url.."' to `"..thumbfile.."'")
		ok, err = dw.download(url, thumbfile)
		if not ok then
			log.warn(_NAME..": "..err)
		else
			return thumbname
		end 
	end
	local dom, err = lom.parse(xml)
	if not dom then
		return nil, err
	end
	local channels = {}
	local programsmap = {}
	for j, k in ipairs(dom) do
		if istag(k, "tv") then
			local channel = {}
			for l, m in ipairs(k) do
				if istag(m, "channel") then
					channel.channel = tonumber(m[1])
				elseif istag(m, "epg_id") then
					channel.epg_id = tonumber(m[1])
				elseif istag(m, "epg_name") then
					channel.id = m[1]
				elseif istag(m, "title") then
					channel.title = m[1]
				elseif istag(m, "genre") then
					channel.genre = m[1]
				elseif istag(m, "quality") then
					channel.quality = m[1]
				elseif istag(m, "audio") then
					channel.audio = m[1]
				elseif istag(m, "logo") then
					-- download logo
					channel.thumbnail = downloadlogo(channel.id, m[1])
				elseif istag(m, "logo_selected") then
					-- download selected logo
					channel.thumbnail_selected = downloadlogo(channel.id, m[1])
				elseif istag(m, "sources") then
					channel.streams = {{url = m[1]}}
				elseif istag(m, "has_dvr") then
					channel.has_dvr = m[1]
				elseif istag(m, "ndvr") then
					channel.ndvr = m[1]
				elseif istag(m, "pg") then
					channel.pg = m[1]
				elseif istag(m, "programme") then
					local program = {
						id = mktime(m.attr.start),
						stop = mktime(m.attr.stop),
					}
					programsmap[m.attr.channel] = programsmap[m.attr.channel] or {}
					table.insert(programsmap[m.attr.channel], program)

					for n, o in ipairs(m) do
						if istag(o, "title") then
							program.title = o[1]
						elseif istag(o, "language") then
							program.language = o.attr.lang
						end
					end
				end
			end
			table.insert(channels, channel)
		end
	end
	return channels, programsmap
end

local _channels, _programsmap

-- updates Bulsat channels or programs and call sink callback for each new channel extracted
function update(channelids, sink)
	if not _channels then
		local xml, err = downloadxml()
		if not xml then
			return nil, err
		end
		_channels, _programsmap = parsexml(xml)
		if not _channels then
			return nil, _programsmap
		end
	end
	if not sink then
		sink = channelids
		assert(type(sink) == "function", "sink function argument expected")
		-- sink channels
		for _, channel in ipairs(_channels) do
			if not sink(channel) then
				return nil, "interrupted"
			end
		end
	else
		assert(type(sink) == "function", "sink function argument expected")
		-- sink programs
		for _, channelid in ipairs(channelids) do
			if _programsmap[channelid] then
				for _, program in ipairs(_programsmap[channelid]) do
					if not sink(channelid, program) then
						return nil, "interrupted"
					end
				end
			else
				log.warn(_NAME..": No programs for channel id "..channelid)
			end
		end
	end
	return true
end

return _M
