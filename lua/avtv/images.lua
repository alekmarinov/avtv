-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  AVIQ Bulgaria Ltd                       --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      images.lua                                         --
-- Description:   Manage storage of the static images                --
--                                                                   --
----------------------------------------------------------------------- 

local table    = require "lrun.util.table"
local lfs      = require "lrun.util.lfs"
local string   = require "lrun.util.string"
local log      = require "avtv.log"
local config   = require "avtv.config"

local setmetatable, os =
      setmetatable, os

local print, pairs, type, assert = print, pairs, type, assert

module "avtv.images"

MOD_CHANNEL = "channel"
MOD_PROGRAM = "program"
MOD_VOD = "vod"

LOGO_SELECTED = "selected"
LOGO_FAVORITE = "favorite"

local function mklogoname(imagefile, modifier)
	local ext = lfs.ext(imagefile)
	if modifier then
		modifier = "_"..modifier
	else
		modifier = ""
	end
	return "logo"..modifier..ext
end

local function islogoname(imagefile)
	local imagename = lfs.stripext(lfs.basename(imagefile))
	return imagename == "logo" or imagename == "logo_"..LOGO_SELECTED or imagename == "logo_"..LOGO_FAVORITE
end

 -- e.g., epg.bulsat.dir.static
local function getdirstatic(provider, modulename)
	local prefix = modulename
	if MOD_CHANNEL == modulename or MOD_PROGRAM == modulename then
		prefix = "epg"
	end
	return config.getstring(prefix.."."..provider..".dir.static")
end

local function collectimages(dirstatic, modulename)
	assert(modulename == MOD_CHANNEL or modulename == MOD_PROGRAM or modulename == MOD_VOD)

	local images = {}
	if MOD_CHANNEL == modulename or MOD_PROGRAM == modulename then
		for dirname in lfs.dir(dirstatic, "directory") do
			local dirpath = lfs.concatfilenames(dirstatic, dirname)

			for imagefile in lfs.dir(dirpath, "file") do
				local imagepath = lfs.concatfilenames(dirpath, imagefile)
				images[imagepath] = (islogoname(imagefile) and MOD_CHANNEL == modulename) or (not islogoname(imagefile) and MOD_PROGRAM == modulename)
				if images[imagepath] then
					log.debug(_NAME..": "..imagepath.." collected for deletion")
				else
					log.debug(_NAME..": "..imagepath.." skipped for deletion")
				end
			end
		end
	elseif MOD_VOD == modulename then
		for resolution in lfs.dir(dirstatic, "directory") do
			local dirpath = lfs.concatfilenames(dirstatic, resolution)
			for imagefile in lfs.dir(dirpath, "file") do
				local imagepath = lfs.concatfilenames(dirpath, imagefile)
				images[imagepath] = true
				log.debug(_NAME..": "..imagepath.." collected for deletion")
			end
		end
	end
	return images
end

local function deleteimages(imageset)
	for imagefile, isdel in pairs(imageset) do
		if isdel then
			log.info(_NAME..": deleting "..imagefile)
			os.remove(imagefile)
		end
	end
end

local function deleteemptydirs(dirpath)
	for dirname in lfs.dir(dirpath) do
		local delete = true
		local dircondidate = lfs.concatfilenames(dirpath, dirname)
		for trydir in lfs.dir(dircondidate) do
			delete = false
			break
		end
		if delete then
			lfs.delete(dircondidate)
		end
	end
end

local function rename(filename1, filename2)
	os.remove(filename2)
	return os.rename(filename1, filename2)
end

-- add new channel logo
function _M:addchannellogo(channelid, imagepath, modifier)
	assert(not modifier or modifier == LOGO_SELECTED or modifier == LOGO_FAVORITE)

	local imagename = mklogoname(imagepath, modifier)
	local localpath = lfs.concatfilenames(self.dirstatic, channelid, imagename)
	if self.deleteimageset[localpath] then
		log.debug(_NAME..": undelete "..localpath)
		self.deleteimageset[localpath] = nil
	end
	log.debug(_NAME..": rename "..imagepath.." to "..localpath)
	lfs.mkdir(lfs.dirname(localpath))
	local ok, err = rename(imagepath, localpath) 
	if not ok then
		return nil, err
	end
	return imagename
end

-- add new program image
function _M:addprogramimage(channelid, imagepath, imagename)
	local localpath = lfs.concatfilenames(self.dirstatic, channelid, imagename)
	if self.deleteimageset[localpath] then
		log.debug(_NAME..": undelete "..localpath)
		self.deleteimageset[localpath] = nil
	end
	log.debug(_NAME..": rename "..imagepath.." to "..localpath)
	lfs.mkdir(lfs.dirname(localpath))
	local ok, err = rename(imagepath, localpath) 
	if not ok then
		return nil, err
	end
	return imagename
end

-- FIXME: handle image resolution
function _M:addvodimage(vodid, imagepath, resolution)
	assert(self.modulename == MOD_VOD)
	local ext = lfs.ext(imagepath)
	local imagename = vodid..ext
	local localpath = lfs.concatfilenames(self.dirstatic, resolution, imagename)
	if self.deleteimageset[localpath] then
		log.debug(_NAME..": undelete "..localpath)
		self.deleteimageset[localpath] = nil
	end
	log.debug(_NAME..": rename "..imagepath.." to "..localpath)
	lfs.mkdir(lfs.dirname(localpath))
	local ok, err = rename(imagepath, localpath) 
	if not ok then
		return nil, err
	end
	return imagename
end

-- closes the image manager
function _M:close()
	-- delete the unused images
	deleteimages(self.deleteimageset)
	deleteemptydirs(self.dirstatic)
	self.deleteimageset = nil
	self.modulename = nil
end

-- opens the images for specified provider and module ("program", "channel", "vod")
function new(provider, modulename)
	local o = setmetatable({}, {__index = _M})
	assert(modulename == MOD_CHANNEL or modulename == MOD_PROGRAM or modulename == MOD_VOD)

	o.provider = provider
	o.modulename = modulename
	o.dirstatic = getdirstatic(provider, modulename)

	-- collect all existing images
	o.deleteimageset = collectimages(o.dirstatic, modulename)
	return o
end

return _M
