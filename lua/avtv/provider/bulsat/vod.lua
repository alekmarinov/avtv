-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      vod.lua                                            --
-- Description:   Bulsat VOD provider                                --
--                                                                   --
-----------------------------------------------------------------------

local dw      = require "lrun.net.www.download.luasocket"
local lom     = require "lxp.lom"
local lfs     = require "lrun.util.lfs"
local string  = require "lrun.util.string"
local table   = require "lrun.util.table"
local config  = require "avtv.config"
local log     = require "avtv.log"
local images  = require "avtv.images"
local logging = require "logging"
local URL     = require "socket.url"
local gzip    = require "luagzip"

local io, os, type, assert, ipairs, tostring, tonumber, math =
      io, os, type, assert, ipairs, tostring, tonumber, math 

local print, pairs = print, pairs

module "avtv.provider.bulsat.vod"

local errormessages = {}
local function logerror(errmsg)
	table.insert(errormessages, _NAME..": "..errmsg)
end

local function sendlogerrors(errmsg)
	if errmsg then
		logerror(errmsg)
	end
	if #errormessages > 0 then
		local logmsgs = {}
		for i, errmsg in ipairs(errormessages) do
			table.insert(logmsgs, logging.prepareLogMsg(nil, os.date(), logging.ERROR, errmsg))
		end
		log.error(_NAME..": update errors:\n"..table.concat(logmsgs, "\n"))
	end
end

local function downloadxml(url)
	local tmpfile = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"), string.format("tmp_%08x", math.random(99999999)))
	log.debug(_NAME..": downloading `"..url.."' to `"..tmpfile.."'")
	lfs.mkdir(lfs.dirname(tmpfile))
	local ok, code, headers = dw.download(url, tmpfile)
	if not ok then
		-- error downloading url
		os.remove(tmpfile)
		return nil, code.." while downloading "..url
	end
	local xml
	if headers["content-encoding"] == "gzip" then
		local gzfile = tmpfile..".gz"
		lfs.move(tmpfile, gzfile)
		-- decompressed file
		log.debug(_NAME..": decompressing `"..gzfile.."' -> `"..tmpfile.."'")
		local file, err = gzip.open(gzfile)
		if not file then
			return nil, err
		end
		xml = file:read("*a")
		file:close()
		lfs.delete(gzfile)
	else
		local file, err = io.open(tmpfile)
		if not file then
			return nil, err
		end
		xml = file:read("*a")
		file:close()
		lfs.delete(tmpfile)
	end
	return xml
end

local function istag(tag, name)
	return type(tag) == "table" and string.lower(tag.tag) == name
end

local function printvodgroups(vodgroups)
	local n = 0
	for _, g in ipairs(vodgroups) do
		n = n + table.getn(g.vods or {})
		print(g.id, g.title, g.parent, table.getn(g.vods or {}))
		--[[
		print(g.id.."--------------------------------------")
		local str = {}
		table.serialize(g, function (s) table.insert(str, s) end, " ")
		print(table.concat(str))
		]]
	end
	return n
end

local function normalizecountry(country)
	if not country then
		return nil
	end
	if string.find(country, ",", 1, true) then
		local countries = string.explode(country, ",")
		local formatcountries = {}
		for _, c in ipairs(countries) do
			table.insert(formatcountries, string.trim(c))
		end
		country = table.concat(formatcountries, ", ")
	end
	return country
end

local function normalizedate(date)
	if not date then
		return nil
	end
	if string.match(date, "%d%d%d%d%-.-") then
		date = string.sub(date, 1, 4)
	end
	return date
end

local function parsevodgroupsxml(dom, parentgroup, vodgroups)
	vodgroups = vodgroups or {}
	for j, k in ipairs(dom) do
		if istag(k, "vodgroup") then
			local group = {}
			if parentgroup then
				group.parent = parentgroup.id
			end
			for l, m in ipairs(k) do
				if istag(m, "id") then
					group.id = m[1]
				elseif istag(m, "title") then
					group.title = m[1]
				elseif istag(m, "title_org") then
					group.original_title = m[1]
				elseif istag(m, "short_description") then
					group.short_description = m[1]
				elseif istag(m, "release") then
					group.release = normalizedate(m[1]) -- e.g. 2014-01-07
				elseif istag(m, "rating") then
					group.imdb_rating = m[1] -- 710, for 7.1 IMDB rating
				elseif istag(m, "country") then
					group.country = normalizecountry(m[1])
				elseif istag(m, "country_id") then
					group.country_id = m[1]
				end
			end
			table.insert(vodgroups, group)
			parsevodgroupsxml(k, group, vodgroups)
		end
	end
	return vodgroups
end

local function mktempfile(ext)
	local tmpfile = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"), string.format("tmp_%08x", math.random(99999999)))
	if ext then
		tmpfile = tmpfile..ext
	end
	return tmpfile
end

local function downloadtempimage(url)
	local tmpfile, err = assert(mktempfile(lfs.ext(url)))
	lfs.mkdir(lfs.dirname(tmpfile))
	log.debug(_NAME..": downloading `"..url.."' to `"..tmpfile.."'")
	local ok, err = dw.download(url, tmpfile)
	if not ok then
		os.remove(tmpfile)
		logerror(url.."->"..err)
		return nil, err
	else
		return tmpfile
	end 
end

local function parsevoddetails(dom, vod, image)
	local posterurl
	for j, k in ipairs(dom) do
		if istag(k, "id") then
			vod.id = k[1]
		elseif istag(k, "title") then
			vod.title = k[1]
		elseif istag(k, "title_org") then
			vod.original_title = k[1]
		elseif istag(k, "poster") then
			posterurl = k[1]
		elseif istag(k, "short_description") then
			vod.short_description = k[1]
		elseif istag(k, "description") then
			vod.description = k[1]
		elseif istag(k, "valid_from") then
			vod.valid_from = k[1]
		elseif istag(k, "release") then
			vod.release = normalizedate(k[1])
		elseif istag(k, "duration") then
			vod.duration = k[1]
		elseif istag(k, "imdb_id") then
			vod.imdb_id = k[1]
		elseif istag(k, "rating") then
			vod.imdb_rating = k[1]
		elseif istag(k, "audio_lang") then
			vod.audio_lang = k[1]
		elseif istag(k, "subtitles") then
			vod.subtitles = k[1]
		elseif istag(k, "trailer_link") then
			vod.youtube_trailer_url = k[1]
		elseif istag(k, "country") then
			vod.country = normalizecountry(k[1])
		elseif istag(k, "country_id") then
			vod.country_id = k[1]
		elseif istag(k, "pg_id") then
			vod.pg_id = k[1]
		elseif istag(k, "pg") then
			vod.pg = k[1]
		elseif istag(k, "genre_id") then
			vod.genre_id = k[1]
		elseif istag(k, "genre") then
			vod.genre = k[1]
		elseif istag(k, "genres_all") then
			vod.genres_all = k[1]
		elseif istag(k, "actors") then
			vod.cast = {}
			for l, m in ipairs(k) do
				if istag(m, "actor") then
					local actor = {}
					local castas
					for o, p in ipairs(m) do
						if istag(p, "name") then
							actor.name = p[1]
						elseif istag(p, "name_org") then
							actor.original_name = p[1]
						elseif istag(p, "cast_as") then
							castas = p[1]
						elseif istag(p, "important") then
							actor.important = string.lower(p[1])
						elseif istag(p, "person_poster") then
							actor.person_poster = p[1]
						elseif istag(p, "character") then
							actor.character = p[1]
						end
					end
					if not castas then
						local name = actor.name or "unknown"
						local vodid = vod.id or "unknown"
						logerror("Tag actor with name="..name.." has no tag castas in vod id = "..vodid)
					else
						vod.cast[castas] = vod.cast[castas] or {}
						table.insert(vod.cast[castas], actor)
					end
				end
			end
			for _, actor in ipairs(vod.cast.actor or {}) do
				if vod.actors then
					vod.actors = vod.actors..","
				else
					vod.actors = ""
				end
				vod.actors = vod.actors..actor.name
			end
			if vod.cast.director then
				vod.director = vod.cast.director.name
			end
		elseif istag(k, "source") then
			vod.source = k[1]
		end
	end
	-- generate vod item thumbnails
	if not posterurl then
		logerror("VOD "..vod.id.." have no poster url")
		return nil, err
	end
	local posterimage = downloadtempimage(posterurl)
	if not posterimage then
		return nil, "Can't download vod "..vod.id.." from "..posterurl
	end
	local posterformats = string.explode(config.getstring("vod.bulsat.poster.formats"), ",")
	for _, format in ipairs(posterformats) do
		local resolution = config.getstring("vod.bulsat.poster."..format)
		vod["poster_"..format], vod["poster_"..format.."_base64"] = image:addvodimage(vod.id, posterimage, resolution)
	end
	os.remove(posterimage)
	return true
end

-- unused
local function loadvod(vodid)
	local vodurl = string.format(config.getstring("vod.bulsat.url.details"), vodgroupid) 
	local xml, err = downloadxml(vodurl)
	if not xml then
		logerror(vodurl.."->"..err)
		return nil, err
	end
	local dom, err = lom.parse(xml)
	if not dom then
		logerror(err)
		return nil, err
	end
	local vod = {id = vodid}
	-- ...
	return vod
end

local function loadvodgroupdetails(image, vodgroup, vods, npage)
	local vodurl
	if not npage then
		vodurl = string.format(config.getstring("vod.bulsat.url.details"), vodgroup.id) 
	else
		vodurl = string.format(config.getstring("vod.bulsat.url.pages"), vodgroup.id, npage) 
	end
	local xml, err = downloadxml(vodurl)
	if not xml then
		logerror(vodurl.."->"..err)
		return nil, err
	end
	local dom, err = lom.parse(xml)
	if not dom then
		logerror(err)
		return nil, err
	end
	local newvods = {}
	for j, k in ipairs(dom) do
		if istag(k, "vodgroup") then
			local group = {}
			for l, m in ipairs(k) do
				if istag(m, "id") then
					group.id = m[1]
				elseif istag(m, "title") then
					group.title = m[1]
				elseif istag(m, "title_org") then
					group.original_title = m[1]
				elseif istag(m, "short_description") then
					group.short_description = m[1]
				elseif istag(m, "description") then
					group.description = m[1]
				elseif istag(m, "valid_from") then
					group.valid_from = m[1]
				elseif istag(m, "release") then
					group.release = m[1] -- e.g. 2014-01-07
				elseif istag(m, "imdb_id") then
					group.imdb_id = m[1]
				elseif istag(m, "rating") then
					group.imdb_rating = m[1] -- 710, for 7.1 IMDB rating
				elseif istag(m, "trailer_link") then
					group.youtube_trailer_url = m[1]
				elseif istag(m, "country") then
					group.country = m[1]
				elseif istag(m, "country_id") then
					group.country_id = m[1]
				elseif istag(m, "pg_id") then
					group.pg_id = m[1]
				elseif istag(m, "pg") then
					group.pg = m[1]
				elseif istag(m, "genre_id") then
					group.genre_id = m[1]
				elseif istag(m, "genre") then
					group.genre = m[1]
				end
			end
			if group.id == vodgroup.id then
				-- merge group to vodgroup
				table.fastcopy(group, vodgroup)
				break
			end
		elseif istag(k, "vod") then
			local vod = {}
			if parsevoddetails(k, vod, image) then
				table.insert(newvods, vod)
			end
		end
	end
	vods = vods or {}
	for _, v in ipairs(newvods) do
		table.insert(vods, v)
	end
	if #newvods > 1 then
		-- load next page
		loadvodgroupdetails(image, vodgroup, vods, (npage or 1) + 1)
	end
	return vods
end


local function isvodgroupempty(vodgroup, vodgroupsmap)
	if #vodgroupsmap[vodgroup] > 0 then
		return false
	end

	for group, list in pairs(vodgroupsmap) do
		if group.parent == vodgroup.id then
			if not isvodgroupempty(group, vodgroupsmap) then
				return false
			end
		end
	end

	return true
end

-- updates Bulsat VOD and call sink callback for each new voditem extracted
function update(sink)
	local vodurl = config.getstring("vod.bulsat.url.groups")
	local xml, err = downloadxml(vodurl)
	if not xml then
		sendlogerrors(vodurl.."->"..err)
		return nil, err
	end
	local dom, err = lom.parse(xml)
	if not dom then
		sendlogerrors(err)
		return nil, err
	end
	local vodgroups, err = parsevodgroupsxml(dom)
	if not vodgroups then
		sendlogerrors(err)
		return nil, err
	end

	local image = images.new("bulsat", images.MOD_VOD, ".jpg")
	local vodgroupsmap = {}
	local vodgroupsrefine = {}
	for _, vodgroup in ipairs(vodgroups) do
		vodgroupsmap[vodgroup] = loadvodgroupdetails(image, vodgroup)
		table.insert(vodgroupsrefine, vodgroup)
	end
	for _, vodgroup in ipairs(vodgroupsrefine) do
		if not isvodgroupempty(vodgroup, vodgroupsmap) then
			local vodlist = vodgroupsmap[vodgroup]
			sink(vodgroup, vodlist, {"title", "description", "short_description", "genre", "country", "actors", "director"})
		end
	end
	image:close()
	return true
end

return _M
