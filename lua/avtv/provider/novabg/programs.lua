-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      programs.lua                                       --
-- Description:   NovaBG programs provider                           --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local html   = require "lrun.parse.html"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"
local gzip   = require "luagzip"

local io, os, type, assert, ipairs, table, tonumber, tostring, unpack, pcall =
      io, os, type, assert, ipairs, table, tonumber, tostring, unpack, pcall
local print, pairs = print, pairs

module "avtv.provider.novabg.programs"

local DAYSECS = 24*60*60

local function dayofs(offset, frm)
	return os.date(frm, os.time() + offset * DAYSECS)
end

local function ymdofs(day)
	return { tonumber(dayofs(day, "%Y")), tonumber(dayofs(day, "%m")), tonumber(dayofs(day, "%d")) }
end

-- format program date time
local function formatprogramtime(ts)
	return os.date("%Y%m%d%H%M%S", tonumber(ts))
end

local channelupdater = {}

-- FIXME: pattern for searching video url of program zdraveiblgariya
local videos = {
	zdraveiblgariya = "http://str.by.host.bg/novatv/na_svetlo/na_svetlo-%s-%s-%s.flv"
}

-- updates NovaTV channel
channelupdater.novatv = function (channel, sink)
	local function dumpprogram(program)
		local dmp = {}
		for i,v in pairs(program) do
			table.insert(dmp, i.."="..tostring(v))
		end
		return table.concat(dmp, "\n")
	end
	local function dumpdate(d)
		return d[1].."-"..d[2].."-"..d[3]
	end
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "novabg", os.date("%Y%m%d"))
	local dirstatic = config.getstring("epg.novabg.dir.static")
	lfs.mkdir(dirdata)
	lfs.mkdir(dirstatic)

	local dayfrom = -config.getnumber("epg.novabg.dayspast")
	local dayto = config.getnumber("epg.novabg.daysfuture")

	local lastprogram
	for day = dayfrom, dayto do
		local date = ymdofs(day)
		local url = string.format(config.getstring("epg.novabg.novatv.url.schedule"), unpack(date))
		local programsfile = lfs.concatfilenames(dirdata, "programs-"..dayofs(day, "%Y%m%d")..".html")

		local ok, err, code, file, htmltext
		if not lfs.exists(programsfile) then
			log.debug(_NAME..": downloading `"..url.."' to `"..programsfile.."'")
			ok, code = dw.download(url, programsfile)
			if not ok then
				-- error downloading file
				return nil, code
			end
		end
		file, err = io.open(programsfile)
		htmltext = file:read("*a")
		file:close()

		-- fix for some html pages incorrectly start with empty space
		htmltext = string.trimleft(htmltext)
		local hom = html.parse(htmltext)
		local taglist = hom{ tag = "li", class = "programme" }

		local prevhour
		local incday = 0
		log.debug(_NAME..": Parsing programs for "..dumpdate(date))
		for _, tagprogramme in ipairs(taglist) do
			local program = {}

			local tagtime = tagprogramme{ tag = "div", class = "programme_time" }
			local tagtitle = tagprogramme{ tag = "a", class = "programme_title" }
			local taginfo = tagprogramme{ tag = "span", class = "programme_info_box" }

			-- set program title
			program.title = tostring(tagtitle[1])

			-- parse program time and compute program date
			local time = tostring(tagtime[1])
			local hour, min = unpack(string.explode(time, ":"))

			hour = tonumber(hour)
			min = tonumber(min)
			local pday = day
			if prevhour and prevhour > hour then
				incday = incday + 1
				log.debug(_NAME..": Moving to next day "..(day + incday))
			end
			date = ymdofs(day + incday)
			prevhour = hour

			-- set program id
			-- since Nova provides time for timezone in BG we substract 2 hours to adjust to greenwich
			-- also we provide info that DST is in effect since it is also provided by Nova
			program.id = formatprogramtime(os.time{year=date[1], month=date[2], day=date[3], hour=hour-3, min=min, isdst=true})
			log.debug(_NAME..": parsing program "..program.id)

			-- set program summary (short description)
			program.summary = taginfo[1] and tostring(taginfo[1])

			-- extract program details
			local detailsurl = tagtitle[1]("href")
			if string.starts(detailsurl, "/") then
				detailsurl = config.getstring("epg.novabg.novatv.url.main")..detailsurl
				if string.ends(detailsurl, "/") then
					detailsurl = detailsurl:sub(1, -2)
				end
				local detailsfile = lfs.concatfilenames(dirdata, lfs.basename(detailsurl)..".html")
				if not lfs.exists(detailsfile) then
					log.debug(_NAME..": downloading `"..detailsurl.."' to `"..detailsfile.."'")
					ok, code = dw.download(detailsurl, detailsfile)
					if not ok then
						log.warn(_NAME..": Error downloading details `"..detailsurl.."'. "..code)
						detailsfile = nil
					end
				end
				if detailsfile then
					file, err = io.open(detailsfile)
					htmltext = file:read("*a")
					file:close()

					-- fix for some html pages incorrectly start with empty space
					htmltext = string.trimleft(htmltext)
					hom = html.parse(htmltext)

					local tagdescr = hom{ tag = "div", itemprop="description"}
					tagdescr = tagdescr[1] and tagdescr[1].p or tagdescr.p

					if not tagdescr then
						tagdescr = hom{ tag = "div", class="show_description"}
						tagdescr = tagdescr[1] and tagdescr[1].p
						if not tagdescr then
							log.warn(_NAME..": Error parsing description from `"..detailsfile.."'. Can't find <div itemprop='description' or <div class='show_description'!")
						end
					else
						-- extract program description
						local descrarr = {}
						for _, ptag in ipairs(tagdescr) do
							if ptag("class") == nil then
								table.insert(descrarr, tostring(ptag))
							end
						end
						program.description = table.concat(descrarr, "\n")

						-- extract program thumbnail
						local thumbtag = hom{ tag = "meta", itemprop="thumbnail"}
						local imgsrc = thumbtag[1]("content")
						if string.starts(imgsrc, "http://") then
							local imgfile = lfs.basename(imgsrc)
							-- set program image
							program.image = imgfile
							-- download thumbnail file
							imgfile = lfs.concatfilenames(dirstatic, channel, imgfile)
							lfs.mkdir(lfs.dirname(imgfile))
							if not lfs.exists(imgfile) then
								log.debug(_NAME..": downloading `"..imgsrc.."' to `"..imgfile.."'")
								ok, code = dw.download(imgsrc, imgfile)
								if not ok then
									log.warn(_NAME..": Error downloading image `"..imgsrc.."'. "..code)
									program.image = nil
								end
							end
						end

						-- extract program video
						local vidtag = hom{ tag = "meta", itemprop="contentURL"}
						local vidurl = vidtag[1]("content")
						if vidurl and string.starts(tostring(vidurl), "http://") then
							program.video = lfs.basename(vidurl)
						end
					end
				end
			end

			if incday > 0 and hour > 6 then
				break
			end

			-- sink program
			if lastprogram then
				lastprogram.stop = program.id
				assert(lastprogram.id < lastprogram.stop, "Stop time can't be lower than start time in program "..dumpprogram(lastprogram))
				log.debug(_NAME..": extracted program "..channel.."/"..lastprogram.id.."-"..lastprogram.stop.." \""..lastprogram.title.."\"")
			-- assert(program.id ~= lastprogram.id, "Updating two programs with the same program id is not allowed:\n"..dumpprogram(lastprogram))
				if not sink(channel, lastprogram) then
					return nil, "interrupted"
				end
			end
			lastprogram = program
		end
	end
	-- extract program video
	if config.getnumber("epg.novabg.novatv.video.enable") == 1 then
		local vidnames = string.explode(config.getstring("epg.novabg.novatv.video.names"), ",")
		log.debug(_NAME..": start downloading "..table.getn(vidnames).." videos")
		local vidfilepattern = config.getstring("epg.novabg.novatv.video.pattern")
		local vidurlpattern = config.getstring("epg.novabg.novatv.video.url")
		for _, vidname in ipairs(vidnames) do
			local programname, programfile, programfile2 = unpack(string.explode(vidname, "/"))
			if not programfile2 then
				programfile2 = programfile
			end
			-- probe url for yesterday and today
			for d = -1, 0 do
				local y, m, d = unpack(ymdofs(d))
				local localfilename = string.format(vidfilepattern, programname, y, m, d)
				local remotefilename = string.format(vidfilepattern, programfile2, y, m, d)
				local vidurl = string.format(vidurlpattern, programfile, remotefilename)
				local filepath = lfs.concatfilenames(dirstatic, channel, localfilename)
				if not lfs.exists(filepath) then
					ok, code = dw.download(vidurl, filepath)
					if not ok then
						log.warn(_NAME..": Error downloading video `"..vidurl.."'. "..code)
						lfs.delete(filepath)
					end
				end
			end
		end
	end
	return true
end

-- updates NovaBG programs for given channel list and call sink callback for each new program extracted
function update(channels, sink)
	assert(type(sink) == "function", "sink function argument expected")

	for _, channel in ipairs(channels) do
		if not channelupdater[channel] then
			log.error(_NAME..": Channel "..channel.." is not supported")
		else
			local ok, err = channelupdater[channel](channel, sink)
			if not ok then
				return nil, err
			end
		end
	end
	return true
end

return _M
