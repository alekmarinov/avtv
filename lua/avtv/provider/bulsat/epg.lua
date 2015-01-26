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
local images  = require "avtv.images"
local logging = require "logging"
local URL     = require "socket.url"
local gzip    = require "luagzip"
local unicode = require "unicode"

local io, os, type, assert, ipairs, tostring, tonumber, table, math =
      io, os, type, assert, ipairs, tostring, tonumber, table, math

local print, pairs = print, pairs

local HOURSECS = 60 * 60
local DAYSECS = 24 * HOURSECS

module "avtv.provider.bulsat.epg"

local function mktempfile(ext)
	local tmpfile = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"), string.format("tmp_%08x", math.random(99999999)))
	if ext then
		tmpfile = tmpfile..ext
	end
	return tmpfile
end

local function downloadxml(url)
	local tmpfile = mktempfile()
	log.debug(_NAME..": downloading `"..url.."' to `"..tmpfile.."'")
	lfs.mkdir(lfs.dirname(tmpfile))
	local ok, code, headers = dw.download(url, tmpfile)
	if not ok then
		-- error downloading url
		return nil, code.." while downloading "..url
	end
	local xml
	if headers["content-encoding"] == "gzip" then
		local gzfile = tmpfile..".gz"
		lfs.move(tmpfile, gzfile)
		-- decompressed file
		log.debug(_NAME..": decompressing `"..gzfile.."' -> `"..tmpfile.."'")
		local file, err = gzip.open(gzfile)
		if not file then
			return nil, err
		end
		xml = file:read("*a")
		file:close()
	else
		local file, err = io.open(tmpfile)
		if not file then
			return nil, err
		end
		xml = file:read("*a")
		file:close()
	end
	lfs.delete(tmpfile)
	return xml
end

-- cyrilic to latin
local cyr = {"а", "б", "в", "г", "д", "е", "ж", "з", "и", "й", "к", "л", "м", "н", "о", "п", "р", "с", "т", "у", "ф", "х", "ц", "ч", "ш", "щ", "ъ", "ь", "ю", "я",
"А", "Б", "В", "Г", "Д", "Е", "Ж", "З", "И", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ъ", "Ь", "Ю", "Я"}
local lat = {"a", "b", "v", "g", "d", "e", "j", "z", "i", "j", "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "f", "h", "c", "c", "s", "t", "u", "_", "u", "a", 
"A", "B", "V", "G", "D", "E", "J", "Z", "I", "J", "K", "L", "M", "N", "O", "P", "R", "S", "T", "U", "F", "H", "C", "C", "S", "T", "U", "_", "U", "A"}

for i, c in ipairs(cyr) do
	cyr[c] = i
end

local function normchannelid(id)
	id = tostring(id)
	id = string.gsub(id, "%.", "_")

	local newid = ""
	for ci = 1, unicode.len(id) do
		local c = unicode.sub(id, ci, ci)
		if cyr[c] then
			newid = newid..lat[cyr[c]]
		else
			newid = newid..c
		end
	end
	return newid
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

local function downloadtempimage(url)
	local tmpfile = mktempfile(lfs.ext(url))
	lfs.mkdir(lfs.dirname(tmpfile))
	log.debug(_NAME..": downloading `"..url.."' to `"..tmpfile.."'")
	local ok, err = dw.download(url, tmpfile)
	if not ok then
		logerror(url.."->"..err)
		return nil, err
	else
		return tmpfile
	end 
end

local function parsechannelsxml(xml)
	local function istag(tag, name)
		return type(tag) == "table" and string.lower(tag.tag) == name
	end
	--[[
	local function downloadimage(channel, url, suffix)
		local channelid = channel.id
		if not channelid then
			log.warn(_NAME..": Can't download the logo of channel without id: "..channeltostring(channel))
			return nil
		end
		local ext = lfs.ext(url)
		if suffix then
			suffix = "_"..suffix
		else
			suffix = ""
		end
		local thumbname = "logo"..suffix..ext
		local dirstatic = config.getstring("epg.bulsat.dir.static")
		local thumbfile = lfs.concatfilenames(dirstatic, channelid, thumbname)
		lfs.mkdir(lfs.dirname(thumbfile))
		log.debug(_NAME..": downloading `"..url.."' to `"..thumbfile.."'")
		ok, err = dw.download(url, thumbfile)
		if not ok then
			logerror(url.."->"..err)
		else
			return thumbname
		end 
	end
	]]
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
	local image = images.new("bulsat", images.MOD_CHANNEL)
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
					channel.id = normchannelid(m[1])
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
					local imagefile = downloadtempimage(m[1])
					if imagefile then
						channel.thumbnail = image:addchannellogo(channel.id, imagefile)
					end
				elseif istag(m, "logo_selected") then
					-- download selected logo
					local imagefile = downloadtempimage(m[1])
					if imagefile then
						channel.thumbnail_selected = image:addchannellogo(channel.id, imagefile, images.LOGO_SELECTED)
					end
				elseif istag(m, "logo_favorite") then
					-- download favorite logo
					local imagefile = downloadtempimage(m[1])
					if imagefile then
						channel.thumbnail_favorite = image:addchannellogo(channel.id, imagefile, images.LOGO_FAVORITE)
					end
				elseif istag(m, "logo_epg") then
					-- download epg logo
					local imagefile = downloadtempimage(m[1])
					if imagefile then
						local imageformats = string.explode(config.getstring("epg.bulsat.image.formats"), ",")
						for _, format in ipairs(imageformats) do
							local resolution = config.getstring("epg.bulsat.image."..format)
							channel["program_image_"..format] = image:addchannellogo(channel.id, imagefile, images.PROGRAM_IMAGE, resolution)
						end
					end
				elseif istag(m, "sources") then
					channel.streams[1].url = m[1]
				elseif istag(m, "has_dvr") then
					if not tonumber(m[1]) then
						log.warn(_NAME..": unexpected has_dvr value `"..(m[1] or "").."' for channel id "..channel.id)
					end
					channel.ndvr = tonumber(m[1]) or 0
				elseif istag(m, "can_record") then
					if not tonumber(m[1]) then
						log.warn(_NAME..": unexpected can_record value `"..(m[1] or "").."' for channel id "..channel.id)
					end
					channel.recordable = tonumber(m[1]) or 0
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
	image:close()
	return channels
end

local _channels, _programsmap

local function parseprogramsxml(xml, channels)
	local function istag(tag, name)
		return type(tag) == "table" and string.lower(tag.tag) == name
	end
	local function mktimestamp(timestamp)
		return os.time{year=tonumber(timestamp:sub(1, 4)), month=tonumber(timestamp:sub(5, 6)), day=tonumber(timestamp:sub(7, 8)), hour=tonumber(timestamp:sub(9, 10)), min=tonumber(timestamp:sub(11, 12)), sec=tonumber(timestamp:sub(13, 14))}
	end
	local function mktime(timespec)
		-- if no need to format date time if comming in GMT
		-- local formated = timespec:sub(1, 4)..timespec:sub(5, 6)..timespec:sub(7, 8)..timespec:sub(9, 10)..timespec:sub(11, 12)..timespec:sub(13, 14)
		-- return formated

		local timestamp = mktimestamp(timespec)
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
	--[[
	local function downloadimage(channelid, url)
		local thumbname = lfs.basename(url)
		thumbname = URL.unescape(thumbname)
		local dirstatic = config.getstring("epg.bulsat.dir.static")
		local thumbfile = lfs.concatfilenames(dirstatic, channelid, thumbname)
		if not lfs.exists(thumbfile) then
			lfs.mkdir(lfs.dirname(thumbfile))
			log.debug(_NAME..": downloading `"..url.."' to `"..thumbfile.."'")
			ok, err = dw.download(url, thumbfile)
			if not ok then
				logerror(url.."->"..err)
				return nil, err
			end 
		end
		return thumbname
	end
	]]
	local dom, err = lom.parse(xml)
	if not dom then
		return nil, err
	end
	local image = images.new("bulsat", images.MOD_PROGRAM)
	local programsmap = {}
	local dayspast = config.getnumber("epg.bulsat.dayspast")
	local daysfuture = config.getnumber("epg.bulsat.daysfuture")
	local timestamppast = os.time() - dayspast * DAYSECS
	local timestampfuture = os.time() + daysfuture * DAYSECS
	for j, k in ipairs(dom) do
		if istag(k, "programme") then
			local program = {
				id = mktime(k.attr.start),
				stop = mktime(k.attr.stop),
			}
			local channelid = normchannelid(k.attr.channel)
			if not channels[channelid] then
				logerror("missing channel "..channelid.." for program on "..program.id)
			else
				if mktimestamp(program.id) > timestamppast and mktimestamp(program.stop) < timestampfuture then
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
							-- program.image = downloadimage(channelid, o.attr.src)
							local imagefile = downloadtempimage(o.attr.src)
							if imagefile then
								local imagename = lfs.basename(o.attr.src)
								imagename = URL.unescape(imagename)

								local imageformats = string.explode(config.getstring("epg.bulsat.image.formats"), ",")
								for _, format in ipairs(imageformats) do
									local resolution = config.getstring("epg.bulsat.image."..format)
									program["image_"..format] = image:addprogramimage(channelid, imagefile, imagename, resolution)
								end
							end
						elseif istag(o, "audio") then
							-- FIXME: handle audio tag
						end
					end
				end
			end
		end
	end
	image:close()

	-- generate fake EPG data
	local noepgdata = config.getstring("epg.bulsat.no_epg_data")
	for _, channel in ipairs(_channels) do
		local channelid = channel.id
		programsmap[channelid] = programsmap[channelid] or {}
		local programs = programsmap[channelid]

		log.info(_NAME..": Generating fake EPG data for channel "..channelid.." for days since "..dayspast.." up to "..daysfuture)
		local daystotal = daysfuture + dayspast
		local firstday = os.date("%Y%m%d", os.time() - dayspast * DAYSECS)
		local lastday = os.date("%Y%m%d", os.time() + daysfuture * DAYSECS)
		local firstdatetime = os.time{year=tonumber(string.sub(firstday, 1, 4)),month=tonumber(string.sub(firstday, 5, 6)), day=tonumber(string.sub(firstday, 7, 8)), hour=0, min=0, sec=0}
		local lastdatetime = os.time{year=tonumber(string.sub(lastday, 1, 4)),month=tonumber(string.sub(lastday, 5, 6)), day=tonumber(string.sub(lastday, 7, 8)), hour=0, min=0, sec=0}
		local firstprogramtime = lastdatetime
		local lastprogramtime = firstdatetime

		-- fill up to the first program
		local programtime
		if programs[1] then
			programtime = programs[1].id
			firstprogramtime = os.time{year=tonumber(string.sub(programtime, 1, 4)),month=tonumber(string.sub(programtime, 5, 6)), day=tonumber(string.sub(programtime, 7, 8)), hour=0, min=0, sec=0}
		end

		local stack = {}
		local datetime = firstdatetime 
		while datetime + HOURSECS < firstprogramtime do
			local starttime = os.date("%Y%m%d%H0000", datetime)
			local stoptime = os.date("%Y%m%d%H0000", datetime + HOURSECS)
			local program = {
				id = starttime,
				stop = stoptime,
				title = noepgdata
				-- FIXME: replace with channel image placeholder
				-- image = _channels[channelid].thumbnail?
			}
			table.insert(stack, 1, program)

			datetime = datetime + HOURSECS
		end
		if programtime then
			local starttime = os.date("%Y%m%d%H0000", datetime)
			local stoptime = programtime
			local program = {
				id = starttime,
				stop = stoptime,
				title = noepgdata
				-- FIXME: replace with channel image placeholder
				-- image = _channels[channelid].thumbnail?
			}
			table.insert(stack, program)
		end
		for _, prg in ipairs(stack) do
			table.insert(programs, 1, prg)
		end

		-- fill up from last program to the end
		stack = {}
		local programtime
		if programs[#programs] then
			programtime = programs[#programs].stop
			lastprogramtime = os.time{year=tonumber(string.sub(programtime, 1, 4)),month=tonumber(string.sub(programtime, 5, 6)), day=tonumber(string.sub(programtime, 7, 8)), hour=0, min=0, sec=0}
		end

		local datetime = lastdatetime 
		while datetime - HOURSECS > lastprogramtime do
			local starttime = os.date("%Y%m%d%H0000", datetime)
			local stoptime = os.date("%Y%m%d%H0000", datetime + HOURSECS)
			local program = {
				id = starttime,
				stop = stoptime,
				title = noepgdata
				-- FIXME: replace with channel image placeholder
				-- image = _channels[channelid].thumbnail?
			}
			table.insert(stack, program)
			datetime = datetime - HOURSECS
		end

		if programtime then
			local starttime = programtime
			local stoptime = os.date("%Y%m%d%H0000", datetime)
			local program = {
				id = starttime,
				stop = stoptime,
				title = noepgdata
				-- FIXME: replace with channel image placeholder
				-- image = _channels[channelid].thumbnail?
			}
			table.insert(stack, program)
		end
		for _, prg in ipairs(stack) do
			table.insert(programs, prg)
		end
	end
	return programsmap
end

-- detect image placehoder as the max frequent image name in channel programs
-- unused
function channelplaceholders(channels, programsmap)
	for _, channel in ipairs(channels) do
		local imagestats = {}
		for _, program in ipairs(programsmap[channel.id]) do
			if program.image then
				imagestats[program.image] = (imagestats[program.image] or 0) + 1
			end
		end
		local imageplaceholder = nil
		local maxcount = 0
		for imagename, count in pairs(imagestats) do
			if count > maxcount then
				maxcount = count
				imageplaceholder = imagename
			end
		end
		if maxcount < #programsmap[channel.id] / 2 then
			-- avoid using placeholder if image frequency is less than the half of all programs
			imageplaceholder = nil
		end
		-- image placehoder detected as thmaximum frequent image name
		if imageplaceholder then
			-- set channel program placehoder
			channel.program_image = imageplaceholder
			for _, program in ipairs(programsmap[channel.id]) do
				if program.image == imageplaceholder then
					-- remove program image if equal to the channel placeholder
					program.image = nil
				end
			end
		end
	end
end

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

		-- channelplaceholders(_channels, _programsmap)
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
