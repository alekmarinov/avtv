-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      programs.lua                                       --
-- Description:   Wilmaa programs provider                             --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local gzip   = require "luagzip"
local lom    = require "lxp.lom"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs, table =
      io, os, type, assert, ipairs, table
local print, pairs = print, pairs

module "avtv.provider.wilmaa.programs"

local DAYSECS = 24*60*60

local function day(offset)
	return os.date("%Y%m%d000000", os.time() + offset * DAYSECS)
end

-- updates Wilmaa programs for given channel list and call sink callback for each new program extracted
function update(channels, sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "wilmaa", os.date("%Y%m%d"))
	lfs.mkdir(dirdata)

	local dayspast = config.getnumber("epg.wilmaa.dayspast")
	local daysfuture = config.getnumber("epg.rayv.daysfuture")
	for day = -dayspast, daysfuture do
		local ok, file, xml, err
		local timestamp = os.time() + day * DAYSECS
		local programsfile = lfs.concatfilenames(dirdata, "programs-wilmaa-"..os.date("%Y%m%d", timestamp)..".xml")
		if not lfs.exists(programsfile) then
			local url = string.format(URL, os.date("%Y", timestamp), os.date("%m", timestamp), os.date("%d", timestamp))
			log.debug(_NAME..": downloading `"..url.."' to `"..programsfile.."'")
			local ok, code, headers = dw.downloadfile(url, programsfile, {proxy=config.get("epg.wilmaa.proxy")})
			if not ok then
				-- error downloading file
				return nil, code
			end
			if headers["content-encoding"] == "gzip" then
				local gzfile = programsfile..".gz"
				lfs.move(programsfile, gzfile)
				-- decompressed file
				log.debug(_NAME..": decompressing `"..gzfile.."' -> `"..programsfile.."'")
				file, err = gzip.open(gzfile)
				if not file then
					return nil, err
				end
				xml = file:read("*a")
				file:close()
				file, err = io.open(programsfile, "w")
				if not file then
					return nil, err
				end
				ok, err = file:write(xml)
				file:close()
				if not ok then
					return nil, err
				end
			end
		end
		if not xml then
			-- open xml file
			log.debug(_NAME..": opening `"..programsfile.."'")
			file = io.open(programsfile)
			xml = file:read("*a")
			file:close()
		end
		-- parse programs xml
		log.debug(_NAME..": parsing `"..programsfile.."'")
		local dom, err = lom.parse(xml)
		if not dom then
			return nil, err
		end
		for i, v in ipairs(dom) do
		end
	end
	return true
end

return _M
