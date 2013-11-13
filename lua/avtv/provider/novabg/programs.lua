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

local channelupdater = {}

-- updates NovaTV channel
channelupdater.novatv = function (channel, sink)
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "novabg", os.date("%Y%m%d"))
	lfs.mkdir(dirdata)

	local dayfrom = -config.getnumber("epg.novabg.dayspast")
	local dayto = config.getnumber("epg.novabg.daysfuture")

	for day = dayfrom, dayto do
		local date = ymdofs(day)
		local url = string.format(config.getstring("epg.novabg.novatv.url.schedule"), unpack(date))
		local programsfile = lfs.concatfilenames(dirdata, "programs-"..dayofs(day, "%Y%m%d")..".html")

		local htmltext
		if not lfs.exists(programsfile) then
			log.debug(_NAME..": downloading `"..url.."' to `"..programsfile.."'")
			local ok, code = dw.download(url)
			if not ok then
				-- error downloading file
				return nil, code
			end
			htmltext = ok
		else
			local file, err = io.open(programsfile)
			htmltext = file:read("*a")
			file:close()
		end
		local hom = html.parse(htmltext)
		local taglist = hom{ tag = "div", id = "accordion" }
		local tagh3 = taglist[1].h3
		local tagdiv = taglist[1]{tag="div", class="current_show"}
		local prevhour
		for i, div in ipairs(tagdiv) do
			local program = {}
			local h3 = tagh3[i]

			-- set program title
			program.title = tostring(h3.a[1])
			local time = tostring(h3.span[1])
			local hour, min = unpack(string.explode(time, ":"))
			hour = tonumber(hour)
			min = tonumber(min)
			local pday = day
			if prevhour and prevhour > hour then
				date = ymdofs(day + 1)
			end
			prevhour = hour

			-- set program id
			program.id = os.time{year=date[1], month=date[2], day=date[3], hour=hour, min=min}

			local spans = div.span
			-- set program summary (short description)
			program.summary = string.trim(tostring(div.span[#spans])) -- take last span as short description
			local el = div.div
			local style
			if #el > 0 then
				style = el[1]("style")
				if style then
					string.gsub(style, "url%((.-)%)", function (url)
						-- extract program thumbnail
						local thumbfile = lfs.basename(url)
						thumbfile = lfs.concatfilenames(dirdata, thumbfile)
						-- set program thumbnail image
						program.thumbnail = thumbfile
						if not lfs.exists(thumbfile) then
							log.debug(_NAME..": downloading `"..url.."' to `"..thumbfile.."'")
							ok, code = dw.download(url, thumbfile)
							if not ok then
								log.warn(_NAME..": Error downloading thumbnail `"..url.."'. HTTP status "..code)
								program.thumbnail = nil
							end
						end
					end)
				end
			end

			if #div.a > 0 then
				local detailsurl = config.getstring("epg.novabg.novatv.url.main").."/"..div.a[1]("href")
				local detailsfile = lfs.concatfilenames(dirdata, lfs.basename(detailsurl:sub(1, detailsurl:len()-1))..".html")
				log.debug(_NAME..": downloading `"..detailsurl.."' to `"..detailsfile.."'")
				if not lfs.exists(detailsfile) then
					ok, code = dw.download(detailsurl, detailsfile)
					if not ok then
						log.warn(_NAME..": Error downloading details `"..detailsurl.."'. HTTP status "..code)
						detailsfile = nil
					end
				end
				if detailsfile then
					local file = io.open(detailsfile)
					htmltext = file:read("*a")
					file:close()
				end

				ok, err = pcall(function()
					hom = html.parse(htmltext)
					local divparent = hom{tag="div", class="inside"}[1]
					local flash = divparent{tag="object", id="flashHeader"}
					local videourl, imageurl
					if #flash > 0 then
						-- flash video found
						local flashparam = flash[1]{tag = "param", name = "flashvars"}[1]("value")
						
						local params = string.explode(flashparam, "&")
						videourl = string.explode(params[1], "=")[2]
						imageurl = string.explode(params[2], "=")[2]
					else
						local divhead = divparent{tag="div", class="news_head"}[1].div[1]
						style = divhead("style")
						if style then
							string.gsub(style, "url%((.-)%)", function (url) imageurl = url end)
						end
					end
					if videourl then
						-- set program video
						program.video = lfs.basename(videourl)
						local videofile = lfs.concatfilenames(dirdata, program.video)
						if not lfs.exists(videofile) then
							ok, code = dw.download(videourl, videofile)
							if not ok then
								log.warn(_NAME..": Error downloading video `"..videourl.."'. HTTP status "..code)
								program.video = nil
							end
						end
					end
					if imageurl then
						-- set program image
						program.image = lfs.basename(imageurl)
						local imagefile = lfs.concatfilenames(dirdata, program.image)
						if not lfs.exists(imagefile) then
							ok, code = dw.download(imageurl, imagefile)
							if not ok then
								log.warn(_NAME..": Error downloading image `"..imageurl.."'. HTTP status "..code)
								program.image = nil
							end
						end
					end

					local divdetails = divparent{tag="div", class="n-text"}[1]
					local paras = divdetails.p
					local description = {}
					for i, v in ipairs(paras) do
						table.insert(description, tostring(v))
					end
					-- set program description
					program.description = table.concat(description, "\n")
				end)
				if not ok then -- if error reading program details
					-- report warning
					log.warn(_NAME..": error parsing details for "..channel.."/"..program.id..": "..err)
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
