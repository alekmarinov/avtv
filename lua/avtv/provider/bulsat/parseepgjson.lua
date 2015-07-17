-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      parseepgxml.lua                                    --
-- Description:   Parse XML protocol from Bulsat EPG provider        --
--                                                                   --
-----------------------------------------------------------------------

local json     = require "json"  
local lfs      = require "lrun.util.lfs"
local string   = require "lrun.util.string"
local config   = require "avtv.config"
local log      = require "avtv.log"
local images   = require "avtv.images"
local URL      = require "socket.url"
local epgutils = require "avtv.provider.bulsat.epgutils"

local os, type, ipairs, tostring, tonumber, table =
      os, type, ipairs, tostring, tonumber, table

local HOURSECS = 60 * 60
local DAYSECS = 24 * HOURSECS

module "avtv.provider.bulsat.parseepgjson"

function _M.parsechannels(jsontext)
	local function istag(tag, name)
		return type(tag) == "table" and string.lower(tag.tag) == name
	end
	local function checkduplicates(channels, channel)
		for i, ch in ipairs(channels) do
			if ch.id == channel.id then
				epgutils.logerror("channel ("..epgutils.channeltostring(ch)..") is duplicated by ("..epgutils.channeltostring(channel)..")" )
				return true
			end
		end
	end

	local dom, err = json.decode(jsontext)
	if not dom then
		return nil, err
	end
	if dom.login_error then
		return nil, "Login error"
	end
	local image = images.new("bulsat", images.MOD_CHANNEL)
	local channels = {}
	local skipchannels = {}
	for _, channeljson in ipairs(dom) do
		local channel = 
		{
			ndvr = 0,
			streams = 
			{
				{ type = "live", url = nil },
				{ type = "ndvr", url = nil }
			}
		}
		channel.channel = tonumber(channeljson.channel)
		channel.epg_id = tonumber(channeljson.epg_id)
		channel.id = epgutils.normchannelid(channeljson.epg_name)
		channel.title = channeljson.title
		channel.genre = channeljson.genre
		channel.quality = channeljson.quality
		channel.audio = channeljson.audio

		-- download logo
		local imagefile = epgutils.downloadtempimage(channeljson.logo)
		if imagefile then
			channel.thumbnail, channel.thumbnail_base64 = image:addchannellogo(channel.id, imagefile)
		end
		-- download selected logo
		local imagefile = epgutils.downloadtempimage(channeljson.logo_selected)
		if imagefile then
			channel.thumbnail_selected, channel.thumbnail_selected_base64 = image:addchannellogo(channel.id, imagefile, images.LOGO_SELECTED)
		end
		-- download favorite logo
		local imagefile = epgutils.downloadtempimage(channeljson.logo_favorite)
		if imagefile then
			channel.thumbnail_favorite, channel.thumbnail_favorite_base64 = image:addchannellogo(channel.id, imagefile, images.LOGO_FAVORITE)
		end
		-- download epg logo
		local imagefile = epgutils.downloadtempimage(channeljson.logo_epg)
		if imagefile then
			local imageformats = string.explode(config.getstring("epg.bulsat.image.formats"), ",")
			for _, format in ipairs(imageformats) do
				local resolution = config.getstring("epg.bulsat.image."..format)
				channel["program_image_"..format], channel["program_image_"..format.."_base64"] = image:addchannellogo(channel.id, imagefile, images.PROGRAM_IMAGE, resolution)
			end
		end
		channel.streams[1].url = channeljson.sources
		channel.ndvr = tonumber(channeljson.has_dvr) or 0
		channel.recordable = tonumber(channeljson.can_record) or 0
		channel.streams[2].url = channeljson.ndvr
		channel.pg = channeljson.pg
		channel.radio = channeljson.radio == "true"

		local skipchannelswithoutstream = "yes" == config.getstring("epg.bulsat.skip_channels_without_stream")

		if not (channel.id and channel.title) then
			epgutils.logerror("skipping channel without id or title ("..epgutils.channeltostring(channel)..")")
		elseif skipchannelswithoutstream and not channel.streams[1].url then
			log.warn(_NAME..": skipping channel without stream ("..epgutils.channeltostring(channel)..")")
			skipchannels[channel.id] = true
		elseif not checkduplicates(channels, channel) then
			channels[channel.id] = channel
			table.insert(channels, channel)
		end
	end
	image:close()
	return channels, skipchannels
end

function _M.parseprograms(jsontext, channels, skipchannels)

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

	local dom, err = json.decode(jsontext)
	if not dom then
		return nil, err
	end

	local image = images.new("bulsat", images.MOD_PROGRAM)
	local programsmap = {}
	local dayspast = config.getnumber("epg.bulsat.dayspast")
	local daysfuture = config.getnumber("epg.bulsat.daysfuture")
	local timestamppast = os.time() - dayspast * DAYSECS
	local timestampfuture = os.time() + daysfuture * DAYSECS

	for _, channel in ipairs(channels) do
		if not dom[channel.id] then
			if not skipchannels[channel.id] then
				log.warn(_NAME..": missing channel "..channel.id.." in programs data")
			end
		else
			for _, programjson in ipairs(dom[channel.id].programme) do
				local program = {
					id = mktime(programjson.start),
					stop = mktime(programjson.stop),
				}
				if mktimestamp(program.id) > timestamppast and mktimestamp(program.stop) < timestampfuture then
					programsmap[channel.id] = programsmap[channel.id] or {}
					table.insert(programsmap[channel.id], program)

					program.title = string.gsub(programjson.title, "@EXTENDED@.*", "")
					program.description = programjson.desc
					string.gsub(programjson.title, "@EXTENDED@(.*)", function(ext)
						if string.len(program.description or "") == 0 then
							programjson.title = ext
						end
					end)

					program.date = programjson.date
					program.audio = programjson.audio

					if type(programjson.category) == "table" and #programjson.category > 0 then
						program.categories = {}
						for _, c in ipairs(programjson.category) do
							table.insert(program.categories, c)
						end
					end

					program.episode_num = programjson.episode

					if string.len(programjson.image or "") > 0 then
						local imagefile = epgutils.downloadtempimage(programjson.image)
						if imagefile then
							local imagename = lfs.basename(programjson.image)
							imagename = URL.unescape(imagename)

							local imageformats = string.explode(config.getstring("epg.bulsat.image.formats"), ",")
							for _, format in ipairs(imageformats) do
								local resolution = config.getstring("epg.bulsat.image."..format)
								program["image_"..format], program["image_"..format.."_base64"] = image:addprogramimage(channelid, imagefile, imagename, resolution)
							end
						end
					end
				end
			end
		end
	end

	image:close()

	-- generate fake EPG data
	local noepgdata = config.getstring("epg.bulsat.no_epg_data")
	for _, channel in ipairs(channels) do
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
				-- image = channels[channelid].thumbnail?
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
				-- image = channels[channelid].thumbnail?
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
				-- image = channels[channelid].thumbnail?
			}
			table.insert(stack, program)
			datetime = datetime - HOURSECS
		end

		--[[
		-- causes invalid program
		if programtime then
			local starttime = programtime
			local stoptime = os.date("%Y%m%d%H0000", datetime)
			local program = {
				id = starttime,
				stop = stoptime,
				title = noepgdata
				-- FIXME: replace with channel image placeholder
				-- image = channels[channelid].thumbnail?
			}
			table.insert(stack, program)
		end
		]]
		for _, prg in ipairs(stack) do
			table.insert(programs, prg)
		end
	end
	return programsmap
end

return _M
