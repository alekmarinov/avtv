-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      channels.lua                                       --
-- Description:   Wilmaa channels provider                             --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local lom    = require "lxp.lom"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs =
      io, os, type, assert, ipairs
local print, pairs = print, pairs

module "avtv.provider.wilmaa.channels"

-- updates RayV channels and call sink callback for each new channel extracted
function update(sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "wilmaa", os.date("%Y%m%d"))
	lfs.mkdir(dirdata)
	local channelsfile = lfs.concatfilenames(dirdata, "channels-wilmaa-"..os.date("%Y%m%d")..".xml")

	local ok, file, xml, err
	if not lfs.exists(channelsfile) then
		local url = config.getstring("epg.wilmaa.url.channels")
		log.debug(_NAME..": downloading `"..url.."' to `"..channelsfile.."'")
		local ok, code, headers = dw.downloadfile(url, channelsfile, {proxy=config.get("epg.wilmaa.proxy")})
		if not ok then
			lfs.delete(channelsfile)
			-- error downloading file
			return nil, code
		end
		if headers["content-encoding"] == "gzip" then
			local gzfile = channelsfile..".gz"
			lfs.move(channelsfile, gzfile)
			-- decompressed file
			log.debug(_NAME..": decompressing `"..gzfile.."' -> `"..channelsfile.."'")
			file, err = gzip.open(gzfile)
			if not file then
				return nil, err
			end
			xml = file:read("*a")
			file:close()
			file, err = io.open(channelsfile, "w")
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
		log.debug(_NAME..": opening `"..channelsfile.."'")
		file = io.open(channelsfile)
		xml = file:read("*a")
		file:close()
	end
	-- parse channels xml
	log.debug(_NAME..": parsing `"..channelsfile.."'")
	local dom, err = lom.parse(xml)
	if not dom then
		return nil, err
	end
	for i, v in ipairs(dom) do
		local tag = string.lower(v.tag)
		if v.tag == "channels" then
			for j, k in ipairs(v) do
				tag = string.lower(k.tag)
				if tag == "channel" then
					local channel = {
						id = k.attr.id
					}
				end
			end
		end
	end
	return true
end

return _M
