-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      programs.lua                                       --
-- Description:   RayV programs provider                             --
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

module "avtv.provider.rayv.programs"

local URL = "%s/Programs/SearchAll?channelList=%s&timeStartFrom=%s&timeStartTo=%s&timeEndFrom=%s&timeEndTo=%s"
local DAYSECS = 24*60*60

local function day(offset)
	return os.date("%Y%m%d000000", os.time() + offset * DAYSECS)
end

-- updates RayV programs for given channel list and call sink callback for each new program extracted
function update(channels, sink)
	assert(type(sink) == "function", "sink function argument expected")
	local distributor = config.getstring("epg.rayv.distributor")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "rayv", os.date("%Y%m%d"))
	lfs.mkdir(dirdata)
	local programsfile = lfs.concatfilenames(dirdata, "programs-rayv-"..distributor.."-"..os.date("%Y%m%d")..".xml")

	local startsfrom = day(-config.getnumber("epg.rayv.dayspast"))
	local startsto = day(config.getnumber("epg.rayv.daysfuture"))
	local endsfrom = day(-config.getnumber("epg.rayv.dayspast"))
	local endsto = day(config.getnumber("epg.rayv.daysfuture"))

	local ok, file, xml, err
	if not lfs.exists(programsfile) then
		local url = string.format(URL, config.getstring("epg.rayv.baseurl"), table.concat(channels, ","), startsfrom, startsto, endsfrom, endsto)
		log.debug(_NAME..": downloading `"..url.."' to `"..programsfile.."'")
		local ok, code, headers = dw.downloadfile(url, programsfile)
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
		if string.lower(v.tag) == "programme" then
			local program = {
				id = v.attr.start,
				stop = v.attr.stop,
			}
			local channel = v.attr.channel
			-- parse program attributes
			for j, k in ipairs(v) do
				local tag = string.lower(k.tag)
				if tag == "title" then
					program.title = k[1]
				elseif tag == "sub-title" then
					program.subtitle = k[1]
				elseif tag == "category" then
					program.category = program.category or {}
					table.insert(program.category, k[1])
				elseif tag == "desc" then
					program.description = k[1]
				elseif tag == "date" then
					program.date = k[1]
				elseif tag == "country" then
					program.country = program.country or {}
					table.insert(program.country, k[1])
				elseif tag == "subtitles" then
					program.subtitles = {}
					for l, m in ipairs(k) do
						local tag = string.lower(m.tag)
						if tag == "language" then
							program.subtitles.language = m[1]
						end
					end
				elseif tag == "credits" then
					program.credits = {}
					for l, m in ipairs(k) do
						local tag = string.lower(m.tag)
						if tag == "director" then
							program.credits.director = m[1]
						elseif tag == "actor" then
							program.credits.actor = program.credits.actor or {}
							table.insert(program.credits.actor, m[1])
						elseif tag == "writer" then
							program.credits.writer = m[1]
						elseif tag == "presenter" then
							program.credits.presenter = m[1]
						end
					end
				elseif tag == "video" then
					program.video = {}
					for l, m in ipairs(k) do
						local tag = string.lower(m.tag)
						if tag == "aspect" then
							program.video.aspect = m[1]
						end
					end
				end
			end
			-- sink program
			log.debug(_NAME..": extracted program "..channel.."/"..program.id)
			if not sink(channel, program) then
				return nil, "interrupted"
			end
		end
	end
	return true
end

return _M
