local dw = require "lrun.net.www.download.luasocket"
local gzip = require "luagzip"

local xmlchannels = "http://md2.rayv-inc.com/V1/API/Channels/DistributorChannels?DistributorKey=vtx&ListType=All"
local filename = "channels.xml"

local ok, code, headers = dw.downloadfile(xmlchannels, filename)
if headers["content-encoding"] == "gzip" then
	print("decompressing...")
	local file = gzip.open(filename)
	print(file:read())
	file:close()
end
