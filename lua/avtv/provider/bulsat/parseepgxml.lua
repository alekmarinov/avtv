-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      parseepgxml.lua                                    --
-- Description:   Parse XML protocol from Bulsat EPG provider        --
--                                                                   --
-----------------------------------------------------------------------

local lom      = require "lxp.lom"
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

module "avtv.provider.bulsat.parseepgxml"

function _M.parsechannels(xml)
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

	local dom, err = lom.parse(xml)
	if not dom then
		return nil, err
	end
	local image = images.new("bulsat", images.MOD_CHANNEL)
	local channels = {}
	local skipchannels = {}
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
					channel.id = epgutils.normchannelid(m[1])
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
					local imagefile = epgutils.downloadtempimage(m[1])
					if imagefile then
						channel.thumbnail, channel.thumbnail_base64 = image:addchannellogo(channel.id, imagefile)
					end
				elseif istag(m, "logo_selected") then
					-- download selected logo
					local imagefile = epgutils.downloadtempimage(m[1])
					if imagefile then
						channel.thumbnail_selected, channel.thumbnail_selected_base64 = image:addchannellogo(channel.id, imagefile, images.LOGO_SELECTED)
					end
				elseif istag(m, "logo_favorite") then
					-- download favorite logo
					local imagefile = epgutils.downloadtempimage(m[1])
					if imagefile then
						channel.thumbnail_favorite, channel.thumbnail_favorite_base64 = image:addchannellogo(channel.id, imagefile, images.LOGO_FAVORITE)
					end
				elseif istag(m, "logo_epg") then
					-- download epg logo
					local imagefile = epgutils.downloadtempimage(m[1])
					if imagefile then
						local imageformats = string.explode(config.getstring("epg.bulsat.image.formats"), ",")
						for _, format in ipairs(imageformats) do
							local resolution = config.getstring("epg.bulsat.image."..format)
							channel["program_image_"..format], channel["program_image_"..format.."_base64"] = image:addchannellogo(channel.id, imagefile, images.PROGRAM_IMAGE, resolution)
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
	end
	image:close()
	return channels, skipchannels
end

function _M.parseprograms(xml, channels, skipchannels)
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
		timestamp = timestamp - offset
		local formated = os.date("%Y%m%d%H%M%S", timestamp)
		--log.debug(_NAME..": mktime "..timespec.." -> "..formated.." with offset "..offset)
		return formated
	end
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
			local channelid = epgutils.normchannelid(k.attr.channel)
			if not channels[channelid] then
				if not skipchannels[channelid] then
					epgutils.logerror("missing channel "..channelid.." for program on "..program.id)
				end
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
							local imagefile = epgutils.downloadtempimage(o.attr.src)
							if imagefile then
								local imagename = lfs.basename(o.attr.src)
								imagename = URL.unescape(imagename)

								local imageformats = string.explode(config.getstring("epg.bulsat.image.formats"), ",")
								for _, format in ipairs(imageformats) do
									local resolution = config.getstring("epg.bulsat.image."..format)
									program["image_"..format], program["image_"..format.."_base64"] = image:addprogramimage(channelid, imagefile, imagename, resolution)
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
