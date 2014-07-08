local ltn12  = require "ltn12"
local http   = require "socket.http"
local dw     = require "lrun.net.www.download.luasocket"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"

local print, tostring, table, pairs = print, tostring, table, pairs

local Zapi = {}
setfenv(1, Zapi)

-- print(downloadjson("http://www.google.com"))
local function downloadjson(epgurl)
	print("downloading `"..epgurl.."'")
	local ok, code, headers = dw.download(epgurl)
	if not ok then
		-- error downloading url
		return nil, code.." while downloading "..epgurl
	end
	return ok
end

APPID = "a48d93cd-0247-4225-8063-301d540f3553"
ZUUID = "c7fb5bb2-c201-4b3a-9b76-7c25d5090cad"
function new(baseurl)

    local reqparams = {
        "app_tid="..APPID,
        "uuid"..ZUUID,
        "lang=en",
        "format=json",
        "live_thumbs=256x144,640x360",
        "program_thumbs=256x144,640x360",
	}
	local reqbody = table.concat(reqparams, "&amp;")
    local respbody = {} -- for the response body

    local result, respcode, respheaders, respstatus = http.request {
        method = "POST",
        url = baseurl.."/zapi/session/hello",
        source = ltn12.source.string(reqbody),
        headers = {
            ["content-type"] = "text/plain",
            ["content-length"] = tostring(#reqbody)
        },
        sink = ltn12.sink.table(respbody)
    }
    -- get body as string by concatenating table filled by sink
    respbody = table.concat(respbody)
    print("result = ", result)
    print("respcode = ", respcode)
    print("headers...")
    for i,v in pairs(respheaders) do
    	print(i,v)
    end
    print("respstatus=", respstatus)

end

return Zapi
