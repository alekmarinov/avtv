-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      epg.lua                                            --
-- Description:   Bulsat EPG provider                                --
--                                                                   --
-----------------------------------------------------------------------

local config   = require "avtv.config"
local log      = require "avtv.log"
local epgxml   = require "avtv.provider.bulsat.parseepgxml"
local epgjson   = require "avtv.provider.bulsat.parseepgjson"
local epgutils = require "avtv.provider.bulsat.epgutils"

local type, assert, ipairs, table, pairs =
      type, assert, ipairs, table, pairs

local io = io
module "avtv.provider.bulsat.epg"

local _channels, _programsmap

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
		local genresurl = config.getstring("epg.bulsat.url.genres")
		local channelsurl = config.getstring("epg.bulsat.url.channels")
		local content, err = epgutils.downloadurl(channelsurl, {method = "GET", headers = {STBDEVEL = "INTELIBO"}})
		if not content then
			epgutils.logerror(channelsurl.."->"..err)
			epgutils.sendlogerrors()
			return nil, err
		end
		local skipchannelsorerr
		local contentformat = config.getstring("epg.bulsat.url.format")
		if contentformat == "xml" then
			_channels, skipchannelsorerr = epgxml.parsechannels(content)
		else
			assert(contentformat == "json", "content format "..contentformat.." is not supported")
			_channels, skipchannelsorerr = epgjson.parsechannels(content)
		end
		if not _channels then
			epgutils.logerror(skipchannelsorerr)
			epgutils.sendlogerrors()
			return nil, skipchannelsorerr
		end

		local programsurl = config.getstring("epg.bulsat.url.programs")
		local content, err = epgutils.downloadurl(programsurl, {method = "POST", headers = {STBDEVEL = "INTELIBO"}, postbody = "epg=1month"})
		if not content then
			epgutils.logerror(programsurl.."->"..err)
			epgutils.sendlogerrors()
			return nil, err
		end

		-- debug
		local file = io.open("programs.json", "w")
		file:write(content)
		file:close()

		if contentformat == "xml" then
			_programsmap, err = epgxml.parseprograms(content, _channels, skipchannelsorerr)
		else
			assert(contentformat == "json", "content format "..contentformat.." is not supported")
			_programsmap, err = epgjson.parseprograms(content, _channels, skipchannelsorerr)
		end
		if not _programsmap then
			epgutils.logerror(err)
			epgutils.sendlogerrors()
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
		epgutils.sendlogerrors()
	end
	return true
end

return _M
