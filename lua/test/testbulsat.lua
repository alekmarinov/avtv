local html = require "lrun.parse.html"
local dw   = require "lrun.net.www.download.luasocket"

baseurl = "http://www.bulsat.com"

programsfile = "bulsat.htm"
file, err = io.open(programsfile)
htmltext = file:read("*a")
file:close()
local hom = html.parse(htmltext)

if false then -- test channels

	local function getchannellogo(url)
		local htmltext = assert(dw.download(url))
		local hom = html.parse(htmltext)
		local logourl = tostring(hom{ tag = "ul", id = "tvnav" }[1]{class="tab first"}[1].img[1]("src"))
		return  baseurl.."/"..logourl
	end

	local taglist = hom{ tag = "ul", id = "tvnav" }[1].li[3].div[2]{tag="a"}

	local channelids = {}
	for i,v in pairs(taglist) do
		local title = tostring(v)
		title = string.gsub(title, ",.*", "")
		local channelurl = v("href")
		local id
		string.gsub(channelurl, "go=(.*)", function (_id)
			id = _id
		end)
		local logourl = getchannellogo(channelurl)
		print(id, title, logourl)
	end

end

-- test programs
local programs = hom{ tag="div", class="prgdetails" }
for i, prg in ipairs(programs) do
	local title = tostring(prg.h2[1])
	local datetime = tostring(prg.p[1])
	local description = tostring(prg.p[2])
	print(datetime, title, description)
end
