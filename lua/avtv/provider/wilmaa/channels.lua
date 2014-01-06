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

local io, os, type, assert, ipairs, table, require, tonumber =
      io, os, type, assert, ipairs, table, require, tonumber
local print, pairs = print, pairs

module "avtv.provider.wilmaa.channels"

-- updates RayV channels and call sink callback for each new channel extracted
function update(sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "wilmaa", os.date("%Y%m%d"))
	local dirstatic = config.getstring("epg.wilmaa.dir.static")
	lfs.mkdir(dirdata)
	lfs.mkdir(dirstatic)
	local channelsfile = lfs.concatfilenames(dirdata, "channels-wilmaa-"..os.date("%Y%m%d")..".xml")

	local ok, file, xml, err
	if not lfs.exists(channelsfile) then
		local url = config.getstring("epg.wilmaa.url.channels")
		log.debug(_NAME..": downloading `"..url.."' to `"..channelsfile.."'")

		local dwmethod = config.get("epg.wilmaa.download.method")
		if dwmethod ~= "luasocket" then
			dw = require("lrun.net.www.download."..dwmethod)
		end

		local ok, code, headers = dw.download(url, channelsfile, {proxy=config.get("epg.wilmaa.proxy")})
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
	local thumburl, thumbsize
	for i, v in ipairs(dom) do
		if v.tag and string.lower(v.tag) == "defaults" then
			for q, p in ipairs(v) do
				if p.tag and string.lower(p.tag) == "logos" then
					for j, k in ipairs(p) do
						if k.tag and string.lower(k.tag) == "baseurl" then
							thumburl = k[1]
						elseif k.tag and string.lower(k.tag) == "sizes" then
							local size = 0
							for l, m in ipairs(k) do
								if m.tag and string.lower(m.tag) == "size" then
									local wxh = tonumber(m.attr.width) * tonumber(m.attr.height)
									if wxh > size then
										thumbsize = m[1]
										size = wxh
									end
								end
							end
						end
					end
					if thumbsize then
						thumburl = string.gsub(thumburl, "{SIZE}", thumbsize)
					else
						log.warn(_NAME..": Unable to find logo/size tag. Channel urls will not be downloaded")
						thumburl = nil
					end
				end
			end
		elseif v.tag and string.lower(v.tag) == "channels" then
			local tempchannels = {}
			for j, k in ipairs(v) do
				if k.tag and string.lower(k.tag) == "channel" then
					local channel = {}
					local ishd = false
					for l, m in ipairs(k) do
						local tag = m.tag and string.lower(m.tag)
						if tag == "label" then
							for n, o in ipairs(m) do
								local tag = o.tag and string.lower(o.tag)
								if tag == "channelgroupid" then
									channel.id = o[1]
								elseif tag == "name" then
									channel.title = o[1]
								end
							end
						elseif tag == "settings" then
							for n, o in ipairs(m) do
								if o.tag and string.lower(o.tag) == "hd" then
									ishd = o[1] == "true"
								end
							end
						elseif tag == "streams" then
							for n, o in ipairs(m) do
								if o.tag and string.lower(o.tag) == "stream" then
									for p, q in ipairs(o) do
										if q.tag and string.lower(q.tag) == "url" then
											channel.streams = channel.streams or {}
											table.insert(channel.streams, {
												language = q.attr.lang,
												dvr = q.attr.dvr,
												url = q[1],
												hd = ishd and 1 or 0
											})
										end
									end									
								end
							end
						end
					end
					-- update channel thumbnail image
					if thumburl then
						local thumbname = "logo"..lfs.ext(thumburl)
						local thumbfile = lfs.concatfilenames(dirstatic, channel.id, thumbname)
						lfs.mkdir(lfs.dirname(thumbfile))
						local thumbnailurl = string.gsub(thumburl, "{CHANNEL_ID}", channel.id)
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

					table.insert(tempchannels, channel)
				end
			end
			-- union channels and their streams
			log.debug(_NAME..": unioning channels list")
			local channelsmap = {}
			local newchannels = {}
			for i = 1, #tempchannels do
				local channel = tempchannels[i]
				if not channelsmap[channel.id] then
					table.insert(newchannels, channel)
					channelsmap[channel.id] = channel
				else
					channel = channelsmap[channel.id]
				end
				for j = i + 1, #tempchannels do
					if channel.id == tempchannels[j].id then
						for _, tempstream in ipairs(tempchannels[j].streams or {}) do
							local isnewstream = true
							for _, stream in ipairs(channel.streams or {}) do
								if stream.url == tempstream.url then
									isnewstream = false
								end
							end
							if isnewstream then
								table.insert(channel.streams, tempstream)
							end
						end
					end
				end
			end

			log.debug(_NAME..": inserting channels "..table.getn(newchannels).." channels")
			for _, channel in ipairs(newchannels) do
				if not sink(channel) then
					return nil, "sink interrupted"
				end
			end
		end
	end
	return true
end

return _M
