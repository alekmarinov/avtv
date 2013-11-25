local html   = require "lrun.parse.html"

programsfile = "programs.htm"

local file, err = io.open(programsfile)
htmltext = file:read("*a")
file:close()
local hom = html.parse(htmltext)
local taglist = hom{ tag = "li", class = "programme" }

for _, programme in ipairs(taglist) do
	local timetag = programme{ tag = "div", class = "programme_time" }
	local titletag = programme{ tag = "a", class = "programme_title" }
	local descrtag = programme{ tag = "span", class = "programme_info_box" }

	print("time: ", timetag[1], titletag[1]("href"), timetag[1], "title: ", titletag[1], "descr: ", descrtag[1], titletag[1]("href"))
end

detailsfile = "details.htm"
local file, err = io.open(detailsfile)
htmltext = file:read("*a")
file:close()

local hom = html.parse(htmltext)
local tagdescr = hom{ tag = "div", class="show_description" }
tagdescr = tagdescr[1]
local imgsrc = tagdescr.img[1]("src")
local descrtags = tagdescr{ tag = "p" }
local descrarr = {}
for i, descr in ipairs(descrtags) do
	if descr("class") == nil then
		table.insert(descrarr, tostring(descr))
	end
end
print(table.concat(descrarr, "\n"))
