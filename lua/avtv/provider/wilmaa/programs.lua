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
local zip    = require "luazip"
local lom    = require "lxp.lom"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs, table, tonumber =
      io, os, type, assert, ipairs, table, tonumber
local print, pairs = print, pairs

module "avtv.provider.wilmaa.programs"

local DAYSECS = 24*60*60

local function day(offset)
	return os.date("%Y%m%d000000", os.time() + offset * DAYSECS)
end

local IMAGE_SIZE = "253_190"

-- updates Wilmaa programs for given channel list and call sink callback for each new program extracted
function update(channels, sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "wilmaa", os.date("%Y%m%d"))
	lfs.mkdir(dirdata)

	local dayspast = config.getnumber("epg.wilmaa.dayspast")
	local daysfuture = config.getnumber("epg.rayv.daysfuture")
	local urltempl = config.getstring("epg.wilmaa.url.programs")
	local dwopts = {proxy=config.get("epg.wilmaa.proxy")}
	for day = -dayspast, daysfuture do
		local ok, zfile, xmlfile, xml, err
		local timestamp = os.time() + day * DAYSECS
		local programsfile = lfs.concatfilenames(dirdata, "programs-wilmaa-"..os.date("%Y%m%d", timestamp)..".zip")
		if not lfs.exists(programsfile) then
			local url = string.format(urltempl, os.date("%Y", timestamp), os.date("%m", timestamp), os.date("%d", timestamp))
			log.debug(_NAME..": downloading `"..url.."' to `"..programsfile.."'")
			local ok, code, headers = dw.download(url, programsfile, dwopts)
			if not ok then
				-- error downloading file
				return nil, code
			end
		end

		log.debug(_NAME..": unzipping `"..programsfile.."'")
		zfile, err = zip.open(programsfile)
		if not zfile then
			return nil, err
		end
		local xmlfilename
		for file in zfile:files() do
			xmlfilename = file.filename
			xmlfile, err = zfile:open(file.filename)
			xml = xmlfile:read("*a")
			xmlfile:close()
			break
		end
		zfile:close()

		if not xmlfilename then
			return nil, "Empty zip file "..programsfile
		end

		-- parse programs xml
		log.debug(_NAME..": parsing `"..xmlfilename.."'")
		local dom, err = lom.parse(xml)
		if not dom then
			return nil, err
		end
		local sequence, seperator, imageurltempl, genre, subgenre, descurltempl
		local sequencemap, genremap, subgenremap
		for i, v in ipairs(dom) do
			local tag = v.tag and string.lower(v.tag)
			if tag == "sequence" then
				sequence = v[1]
			elseif tag == "seperator" then
				seperator = v[1]
			elseif tag == "imageurl" then
				imageurltempl = string.gsub(v[1], "%[SIZE%]", IMAGE_SIZE)
			elseif tag == "genre" then
				genre = v[1]
			elseif tag == "adlinkgenres" then
				subgenre = v[1]
			elseif tag == "desc" then
				descurltempl = v[1]
			elseif tag == "all" then
				for j, k in ipairs(v) do
					if k.tag and string.lower(k.tag) == "i" then
						sequencemap = sequencemap or string.explode(sequence, seperator)
						local programvalues = string.explode(k[1], seperator)
						for l, paramname in ipairs(sequencemap) do
							programvalues[paramname] = programvalues[l]
						end
						genremap = genremap or string.explode(genre, seperator)
						subgenremap = subgenremap or string.explode(subgenre, ",")
						local program = {
							id = programvalues.from,
							tele_id = programvalues.tele_id,
							stop = programvalues.to,
							title = programvalues.title,
							subtitle = programvalues.subtitle,
							 -- genre index is zero based
							genre = programvalues.genre and tonumber(programvalues.genre) and genremap[tonumber(programvalues.genre) + 1],
							subgenre = programvalues.subgenre and tonumber(programvalues.subgenre) and subgenremap[tonumber(programvalues.subgenre) + 1],
							image = programvalues.image
						}

						local channel = programvalues.channel_id
						local imageurl = string.gsub(imageurltempl, "%[ID%]", programvalues.image)
						local imagefile = lfs.concatfilenames(dirdata, programvalues.image..".jpg")
						if not lfs.exists(imagefile) then
							-- download program image
							log.debug(_NAME..": downloading `"..imageurl.."' to `"..imagefile.."'")
							ok, code = dw.download(imageurl, imagefile, dwopts)
							if not ok then
								log.warn(_NAME..": error downloading "..imageurl)
								program.image = nil
							end
						end

						if programvalues.desc_existing == "1" then
							-- download program details
							local descurl = string.gsub(descurltempl, "%[ID%]", programvalues.tele_id)
							log.debug(_NAME..": downloading `"..descurl.."'")
							xml, code = dw.download(descurl, nil, dwopts)
							if not xml then
								log.warn(_NAME..": error downloading "..descurl)
							else
								local ddom
								ddom, err = lom.parse(xml)
								if not ddom then
									log.warn(_NAME..": error parsing description of tele_id = "..programvalues.tele_id)
								else
									for l, m in ipairs(ddom) do
										if m.tag and string.lower(m.tag) == "desc" then
											program.description = m[1]
											break
										end
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
			end			
		end
		break -- FIXME: temporary
	end
	return true
end

return _M
