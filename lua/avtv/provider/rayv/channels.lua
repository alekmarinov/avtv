-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      channels.lua                                       --
-- Description:   RayV channels provider                             --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local gzip   = require "luagzip"
local lom    = require "lxp.lom"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs =
      io, os, type, assert, ipairs
local print, pairs = print, pairs

module "avtv.provider.rayv.channels"

local URL = "%s/Channels/DistributorChannels?DistributorKey=%s&ListType=All"

-- updates RayV channels and call sink callback for each new channel extracted
function update(sink)
	assert(type(sink) == "function", "sink function argument expected")
	local distributor = config.getstring("epg.rayv.distributor")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "rayv", os.date("%Y%m%d"))
	local dirstatic = config.getstring("epg.rayv.dir.static")
	lfs.mkdir(dirdata)
	lfs.mkdir(dirstatic)
	local channelsfile = lfs.concatfilenames(dirdata, "channels-rayv-"..distributor.."-"..os.date("%Y%m%d")..".xml")

	local ok, file, xml, err
	if not lfs.exists(channelsfile) then
		local url = string.format(URL, config.getstring("epg.rayv.baseurl"), distributor)
		log.debug(_NAME..": downloading `"..url.."' to `"..channelsfile.."'")
		local ok, code, headers = dw.download(url, channelsfile)
		if not ok then
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
	for i,v in ipairs(dom[1]) do
		if string.lower(v.tag) == "item" then
			local channel = {}
			local thumbnailurl, thumbnailwidth, thumbnailheight
			-- parse channel attributes
			for j, k in ipairs(v) do
				local tag = string.lower(k.tag)
				if tag == "guid" then
					channel.id = k[1]
				elseif tag == "title" then
					channel.title = k[1]
				elseif tag == "media:thumbnail" then
					thumbnailurl = string.trim(k.attr.url)
					thumbnailwidth = k.attr.width
					thumbnailheight = k.attr.height
				end
			end
			-- update channel thumbnail image
			local thumbext = thumbnailurl and lfs.ext(thumbnailurl)
			if not thumbext then
				log.warn(_NAME..": channel "..channel.id.." have invalid thumbnail image")
			else
				local thumbname = "logo"..thumbext
				local thumbfile = lfs.concatfilenames(dirstatic, channel.id, thumbname)
				lfs.mkdir(lfs.dirname(thumbfile))
				log.debug(_NAME..": downloading `"..thumbnailurl.."' to `"..thumbfile.."'")
				ok, err = dw.download(thumbnailurl, thumbfile)
				if not ok then
					log.warn(_NAME..": "..err)
				else
					channel.thumbnail = thumbname
				end
			end
			-- sink channel
			log.debug(_NAME..": extracted channel "..channel.id)
			if not sink(channel) then
				return nil, "interrupted"
			end
		end
	end
	return true
end

return _M
