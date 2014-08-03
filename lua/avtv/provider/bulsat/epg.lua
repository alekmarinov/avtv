-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2014,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      epg.lua                                            --
-- Description:   Bulsat EPG provider                                --
--                                                                   --
-----------------------------------------------------------------------

local dw      = require "lrun.net.www.download.luasocket"
local html    = require "lrun.parse.html"
local lom     = require "lxp.lom"
local lfs     = require "lrun.util.lfs"
local string  = require "lrun.util.string"
local config  = require "avtv.config"
local log     = require "avtv.log"
local logging = require "logging"

local io, os, type, assert, ipairs, tostring, tonumber, table =
      io, os, type, assert, ipairs, tostring, tonumber, table

local print, pairs = print, pairs

module "avtv.provider.bulsat.epg"

local function downloadxml(epgurl)
	log.debug(_NAME..": downloading `"..epgurl.."'")
	local ok, code, headers = dw.download(epgurl)
	if not ok then
		-- error downloading url
		return nil, code.." while downloading "..epgurl
	end
	return ok
end

--[[
-- create id from string
local function mkid(channel)
	return "channel_"..channel.channel
	local id = ""
	local idchars = "abcdefghijklmnopqrstuvwxyz0123456789_"
	for i = 1, string.len(text) do
		local c = string.sub(text, i, i)
		if string.find(idchars, string.lower(c), 1, true)  then
			id = id..c
		else
			id = id.."_"
		end
	end
	return id
end
]]

local errormessages = {}
local function logerror(errmsg)
	table.insert(errormessages, _NAME..": "..errmsg)
end

local function sendlogerrors()
	if #errormessages > 0 then
		local logmsgs = {}
		for i, errmsg in ipairs(errormessages) do
			table.insert(logmsgs, logging.prepareLogMsg(nil, os.date(), logging.ERROR, errmsg))
		end
		log.error(_NAME..": update errors:\n"..table.concat(logmsgs, "\n"))
	end
end

local function channeltostring(channel)
	local function mkstring(t)
		if type(t) == "table" then
			if #t > 0 then
				local tabval = {}
				for i, v in ipairs(t) do
					table.insert(tabval, mkstring(v))
				end
				return "{"..table.concat(tabval, ",").."}"
			else
				local tabval = {}
				for i, v in pairs(t) do
					table.insert(tabval, i.."="..mkstring(v))
				end
				return "{"..table.concat(tabval, ",").."}"
			end
		end
		return tostring(t)
	end
	local channelinfo = ""
	for i, v in pairs(channel) do
		if string.len(channelinfo) > 0 then
			channelinfo = channelinfo..", "
		end
		channelinfo = channelinfo..i.."="..mkstring(v)
	end
	return channelinfo
end

local function parsechannelsxml(xml)
	local function istag(tag, name)
		return type(tag) == "table" and string.lower(tag.tag) == name
	end
	local function downloadlogo(channel, url)
		local channelid = channel.id
		if not channelid then
			log.warn(_NAME..": Can't download the logo of channel without id: "..channeltostring(channel))
			return nil
		end
		local ext = lfs.ext(url)
		local thumbname = "logo"..ext
		local dirstatic = config.getstring("epg.bulsat.dir.static")
		local thumbfile = lfs.concatfilenames(dirstatic, tostring(channelid), thumbname)
		lfs.mkdir(lfs.dirname(thumbfile))
		log.debug(_NAME..": downloading `"..url.."' to `"..thumbfile.."'")
		ok, err = dw.download(url, thumbfile)
		if not ok then
			logerror(url.."->"..err)
		else
			return thumbname
		end 
	end
	local function checkduplicates(channels, channel)
		for i, ch in ipairs(channels) do
			if ch.id == channel.id then
				logerror("channel ("..channeltostring(ch)..") is duplicated by ("..channeltostring(channel)..")" )
				return true
			end
		end
	end

	local dom, err = lom.parse(xml)
	if not dom then
		return nil, err
	end
	local channels = {}
	for j, k in ipairs(dom) do
		if istag(k, "tv") then
			local channel = {
				ndvr = 0,
				streams = {
					{ type = "live", url = nil },
					{ type = "ndvr", url = nil }
				}
			}
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
					channel.thumbnail = downloadlogo(channel, m[1])
				elseif istag(m, "logo_selected") then
					-- download selected logo
					-- channel.thumbnail_selected = downloadlogo(channel, m[1])
				elseif istag(m, "sources") then
					channel.streams[1].url = m[1]
				elseif istag(m, "has_dvr") then
					if not tonumber(m[1]) then
						log.warn(_NAME..": unexpected has_dvr value `"..(m[1] or "").."' for channel id "..channel.id)
					end
					channel.ndvr = tonumber(m[1]) or 0
				elseif istag(m, "ndvr") then
					channel.streams[2].url = m[1]
				elseif istag(m, "pg") then
					channel.pg = m[1]
				end
			end

			if not (channel.id and channel.title) then
				logerror("skipping channel without id or title ("..channeltostring(channel)..")")
			end
			if not checkduplicates(channels, channel) then
				channels[channel.id] = channel
				table.insert(channels, channel)
			end
		end
	end
	return channels
end

local function parseprogramsxml(xml, channels)
	local function istag(tag, name)
		return type(tag) == "table" and string.lower(tag.tag) == name
	end
	local function mktime(timespec)
		-- if no need to format date time if comming in GMT
		-- local formated = timespec:sub(1, 4)..timespec:sub(5, 6)..timespec:sub(7, 8)..timespec:sub(9, 10)..timespec:sub(11, 12)..timespec:sub(13, 14)
		-- return formated

		local timestamp = os.time{year=tonumber(timespec:sub(1, 4)), month=tonumber(timespec:sub(5, 6)), day=tonumber(timespec:sub(7, 8)), hour=tonumber(timespec:sub(9, 10)), min=tonumber(timespec:sub(11, 12)), sec=tonumber(timespec:sub(13, 14))}
		local mul = 1
		if timespec:sub(16, 16) == "-" then
			mul = -1
		end
		local offset = mul * (60 * 60 * tonumber(timespec:sub(17, 18)) + 60 * tonumber(timespec:sub(19, 20)))
		-- timestamp = timestamp - 2 * offset
		local formated = os.date("%Y%m%d%H%M%S", timestamp)
		--log.debug(_NAME..": mktime "..timespec.." -> "..formated.." with offset "..offset)
		return formated
	end
	local function downloadlogo(channel, url)
		local channelid = channel.id
		if not channelid then
			return nil
		end
		local ext = lfs.ext(url)
		local thumbname = "logo"..ext
		local dirstatic = config.getstring("epg.bulsat.dir.static")
		local thumbfile = lfs.concatfilenames(dirstatic, tostring(channelid), thumbname)
		lfs.mkdir(lfs.dirname(thumbfile))
		log.debug(_NAME..": downloading `"..url.."' to `"..thumbfile.."'")
		ok, err = dw.download(url, thumbfile)
		if not ok then
			logerror(url.."->"..err)
		else
			return thumbname
		end 
	end
	local dom, err = lom.parse(xml)
	if not dom then
		return nil, err
	end
	local programsmap = {}
	for j, k in ipairs(dom) do
		if istag(k, "programme") then
			local program = {
				id = mktime(k.attr.start),
				stop = mktime(k.attr.stop),
			}
			local channelid = k.attr.channel
			if not channels[channelid] then
				logerror("missing channel "..channelid.." for program on "..program.id)
			else
				programsmap[channelid] = programsmap[channelid] or {}
				table.insert(programsmap[channelid], program)

				for n, o in ipairs(k) do
					if istag(o, "title") then
						program.title = o[1]
					elseif istag(o, "desc") then
						program.description = o[1]
					elseif istag(o, "date") then
						program.date = o[1]
					elseif istag(o, "language") then
						program.language = o.attr.lang
					elseif istag(o, "category") then
						program.categories = program.categories or {}
						table.insert(program.categories, o[1])
					elseif istag(o, "episode-num") then
						program.episode_num=o[1]
					elseif istag(o, "image") then
						-- FIXME: handle program images
					elseif istag(o, "audio") then
						-- FIXME: handle audio tag
					end
				end
			end
		end
	end
	return programsmap
end

local _channels, _programsmap

-- updates Bulsat channels or programs and call sink callback for each new channel or program extracted
function update(channelids, sink)
	if not _channels then
		local channelsurl = config.getstring("epg.bulsat.url.channels")
		local xml, err = downloadxml(channelsurl)
		if not xml then
			logerror(channelsurl.."->"..err)
			sendlogerrors()
			return nil, err
		end
		_channels, err = parsechannelsxml(xml)
		if not _channels then
			logerror(err)
			sendlogerrors()
			return nil, err
		end
		local programsurl = config.getstring("epg.bulsat.url.programs")
		local xml, err = downloadxml(programsurl)
		if not xml then
			logerror(programsurl.."->"..err)
			sendlogerrors()
			return nil, err
		end
		_programsmap, err = parseprogramsxml(xml, _channels)
		if not _programsmap then
			logerror(err)
			sendlogerrors()
			return nil, err
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
				log.info(_NAME..": Updating "..table.getn(_programsmap[channelid]).." programs in channel id "..channelid)
				for _, program in ipairs(_programsmap[channelid]) do
					if not sink(channelid, program) then
						return nil, "interrupted"
					end
				end
			else
				log.warn(_NAME..": No programs for channel id "..channelid)
			end
		end
		sendlogerrors()
	end
	return true
end

return _M
