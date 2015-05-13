-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      channels.lua                                       --
-- Description:   NovaBG channels provider                           --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs  =
      io, os, type, assert, ipairs

module "avtv.provider.novabg.channels"

-- updates NovaBG channels and call sink callback for each new channel
function update(sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "novabg", os.date("%Y%m%d"))
	local dirstatic = config.getstring("epg.novabg.dir.static")

	local channels = string.explode(config.getstring("epg.novabg.channels"), ",")
	for _, id in ipairs(channels) do
		local logourl = config.getstring("epg.novabg."..id..".logourl")
		local thumbname = lfs.basename(logourl)
		local channel =
		{
			id = id,
			title = config.getstring("epg.novabg."..id..".title"),
			thumbnail = "logo"..lfs.ext(logourl)
		}

		local thumbfile = lfs.concatfilenames(dirstatic, id, channel.thumbnail)
		lfs.mkdir(lfs.dirname(thumbfile))
		if not lfs.exists(thumbfile) then
			local ok, code = dw.download(logourl, thumbfile)
			if not ok then
				log.warn(_NAME..": Error downloading logo from `"..logourl.."'. HTTP status "..code)
			end
		end
		-- sink channel
		log.debug(_NAME..": extracted channel "..channel.id)
		if not sink(channel) then
			return nil, "interrupted"
		end
	end
	return true
end

return _M
