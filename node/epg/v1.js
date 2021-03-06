// --------------------------------------------------------------------
//                                                                   --
// Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
//                                                                   --
// Project:       AVTV                                               --
// Filename:      v1.js                                              --
// Description:   EPG API V1                                         --
//                                                                   --
// -------------------------------------------------------------------- 

var async   = require('async')
var config  = require('config')
var solr    = require('solr')

var CMD_CHANNELS = "channels"
var CMD_PROGRAMS = "programs"
var CMD_VOD = "vod"
var CMD_SEARCH = "search"
var CMD_RECOMMEND = "recommend"
var CMD_RATE = "rate"

var MAX_LIST_RANGE = 10

function onError(err, res, next)
{
	if (err)
	{
		console.error("Error: " + err)
		res.send(500)
		next()
		return false
	}
	return true
}

function rawQuery(namespace, res, next, rclient, keyArr)
{
	var PATTERNS_ALLOW =
		[
			"^[^\\.]+\\." // something . something
		]

	// extract query key
	var keys = namespace + '.' + keyArr.join('.')

	// validates if the key is allowed
	var isAllowed = PATTERNS_ALLOW.some(function eachAllowed(allow)
	{
		return keys.match(allow)
	})
	if (!isAllowed)
	{
		res.send(403)
		next()
		return false
	}

	// request all keys in specified namespace
	return rclient.keys(keys + '*', function onKeys(err, resKeys)
	{
		if (err)
		{
			return onError(err, res, next)
		}
		if (resKeys.length === 0)
		{
			res.send(404)
			next()
			return
		}
		// request all key values
		rclient.mget(resKeys, function onMGet(err, resValues)
		{
			if (err)
			{
				return onError(err, res, next)
			}
			var json
			// shall result one value?
			if (resKeys.length === 1 && resKeys[0].length === keys.length)
			{
				// verify if the valus is redis list
				rclient.lrange(resKeys[0], 0, MAX_LIST_RANGE, function onMGet(err, resRangeValues){
					if (err)
					{
						json = resValues[0]
						if (!json) json = ""
						res.contentType = 'text/plain'
					}
					else
					{
						json = {
							meta: [resKeys[0]],
							data: resRangeValues
						}
					}
					res.send(json)
					next()
				})
			}
			else
			{
				// result multiple values
				var stripKey = keys.length // + 1
				// create json object { key = value }
				json = {}
				for (var i = 0; i < resKeys.length; i++)
				{
					var key = resKeys[i].substring(stripKey)
					if (key.substring(0, 1) == ".")
						key = key.substring(1)
					json[key] = resValues[i]
				}
			}
			if (json)
			{
				res.send(json)
				next()
			}
		})
		return true
	})
}

function channelsQuery(res, next, rclient, params, attr)
{
	if (params.length < 1)
	{
		res.send(403)
		next()
		return false
	}
	// extract provider
	var provider = params[0]
	var prefix = 'epg.' + provider + '.'
	switch (params.length)
	{
		case 1:
			// use redis sort to extract additional objects info
			attr = ["title", "thumbnail"].concat(attr)
			var args = [prefix + 'channels', 'by', 'nosort', 'get', '#']
			for (var i = 0; i < attr.length; i++)
			{
				args.push('get')
				args.push(prefix + '*.' + attr[i])
			}
			args.push(function onSortChannels(err, channelrows)
			{
				if (err)
				{
					return onError(err, res, next)
				}
				if (channelrows.length > 0)
				{
					var json = {meta: ["id"].concat(attr), data: []}
					var attrcount = attr.length + 1
					for (var i = 0; i < channelrows.length / attrcount; i++)
					{
						json.data.push(channelrows.slice(i * attrcount, (i + 1) * attrcount))
					}
					res.send(json)
				}
				else
				{
					res.send(404)
				}
				next()
			})

			return rclient.sort.apply(rclient, args)
		case 2:
			var channelId = params[1]
			attr = ["id", "title", "thumbnail"].concat(attr)
			prefix = prefix + channelId + '.'
			var args = []
			for (var i = 0; i < attr.length; i++)
			{
				args.push(prefix + attr[i])
			}
			args.push(function onMGet(err, resValues)
			{
				if (err)
				{
					return onError(err, res, next)
				}
				if (resValues[0] !== null)
				{
					var json = {}
					for (var i = 0; i < attr.length; i++)
					{
						json[attr[i]] = resValues[i]
					}
					res.send(json)
				}
				else
				{
					res.send(404)
				}
				next()
			})
			// request channel details
			return rclient.mget.apply(rclient, args)

		default:
			return rawQuery("epg", res, next, rclient, params)
	}
}

function programsByTime(res, next, rclient, provider, channelId, when, offset, count, attr)
{
	var luaGetPrograms =
		"local provider, channel, when, offset, count, attrindex\n" +
		"for arg = 1, #ARGV, 2 do\n" +
		"  if ARGV[arg] == 'provider' then\n" +
		"    provider = ARGV[arg + 1]\n" +
		"  elseif ARGV[arg] == 'channel' then\n" +
		"    channel = ARGV[arg + 1]\n" +
		"  elseif ARGV[arg] == 'when' then\n" +
		"    when = tonumber(ARGV[arg + 1])\n" +
		"  elseif ARGV[arg] == 'offset' then\n" +
		"    offset = tonumber(ARGV[arg + 1])\n" +
		"  elseif ARGV[arg] == 'count' then\n" +
		"    count = tonumber(ARGV[arg + 1])\n" +
		"  elseif ARGV[arg] == 'attr' then\n" +
		"    attrindex = arg + 1\n" +
		"  end\n" +
		"end\n" +
		"offset = offset or 0\n" +
		"count = count or 1\n" +
		"local channels\n" +
		"if channel then\n" +
		"  channels = {channel}\n" +
		"else\n" +
		"  channels = redis.call('lrange', 'epg.'..provider..'.channels', 0, -1)\n" +
		"end\n" +
		"local index\n" +
		"local programs = {}\n" +
		"for index = 1, #channels do\n" +
		"  local channel = channels[index]\n" +
		"  local starts = redis.call('sort', 'epg.'..provider..'.'..channel..'.programs')\n" +
		"  for i = 1, #starts - 1 do\n" +
		"    local start = tonumber(starts[i])\n" +
		"    local stop = tonumber(starts[i+1])\n" +
		"    if not when or (when >= start and when < stop) then\n" +
		"      local jfrom, jto = i, i\n" +
		"      if when then\n" +
		"        jfrom, jto = i + offset, i + offset + count - 1\n" +
		"      end\n" +
		"      if jfrom < 0 then jfrom = 0 end\n" +
		"      if jto > #starts then jto = #starts end\n" +
		"      for j = jfrom, jto do\n" +
		"        if j > 0 and j < #starts then\n" +
		"          local mgetattr = {}\n" +
		"          for a = attrindex, #ARGV do\n" +
		"            table.insert(mgetattr, 'epg.'..provider..'.'..channel..'.'..starts[j]..'.'..ARGV[a])\n" +
		"          end\n" +
		"          local program = redis.call('mget', unpack(mgetattr))\n" +
		"          table.insert(program, 1, starts[j + 1])\n" +
		"          table.insert(program, 1, starts[j])\n" +
		"          table.insert(program, 1, channel)\n" +
		"          table.insert(programs, program)\n" +
		"        end\n" +
		"      end\n" +
		"    end\n" +
		"  end\n" + 
		"end\n" + 
		"return programs\n";
	var args = [luaGetPrograms, 0, "provider", provider]
	if (channelId !== undefined)
	{
		args.push("channel")
		args.push(channelId)
	}
	if (when !== undefined)
	{
		args.push("when")
		args.push(when)
	}
	if (offset !== undefined)
	{
		args.push("offset")
		args.push(offset)
	}
	if (count !== undefined)
	{
		args.push("count")
		args.push(count)
	}
	args.push("attr")
	args = args.concat(attr)
	args.push(function onProgramsResult(err, programs){
			if (err)
			{
				return onError(err, res, next)
			}
			var json = {meta: ["channelid", "start", "stop"].concat(attr), data: []}
			var attrcount = attr.length + 2
			var countissues = 0
			var countall = 0
			for (var i = 0; i < programs.length; i++)
			{
				var programdata = programs[i]
				if (i > 0)
				{
					var prevprogramstart = programs[i-1][1]
					if (programdata[1] == prevprogramstart)
					{
						console.warn("Caution! Detected duplicate program starting at " + programdata[1] + " for channel " + programdata[0]);
						console.log(programdata)
						countissues++
						continue
					}
				}
				
				json.data.push(programdata)
				countall++
			}
			if (countissues > 0)
				console.log(countissues + " issues of " + countall + " programs detected")
			res.send(json)
		})
	rclient.eval.apply(rclient, args)
}

function programsQuery(res, next, rclient, params, attr, query)
{
	if (params.length < 1)
	{
		res.send(403)
		next()
		return false
	}
	// extract provider
	var provider = params[0]

	var when = query['when']
	var offset = query['offset'] || 0
	var count = query['count'] || 1

	if (params.length === 1)
	{
		return programsByTime(res, next, rclient, provider, undefined, when, offset, count, ["title"].concat(attr));
	}
	else if (params.length === 2)
	{
		var channelId = params[1]
		if (when)
			return programsByTime(res, next, rclient, provider, channelId, when, offset, count, ["title"].concat(attr));

		var prefix = 'epg.' + provider + '.' + channelId + '.'

		// use redis sort to extract additional objects info
		attr = ["stop", "title"].concat(attr)
		var args = [prefix + 'programs', 'get', '#']
		for (var i = 0; i < attr.length; i++)
		{
			args.push('get')
			args.push(prefix + '*.' + attr[i])
		}
		args.push(function onSortPrograms(err, programsrows)
		{
			if (err)
			{
				return onError(err, res, next)
			}
			var json = {meta: ["start"].concat(attr), data: []}
			var attrcount = attr.length + 1
			var countissues = 0
			var countall = 0
			for (var i = 0; i < programsrows.length / attrcount; i++)
			{
				var programinfo = programsrows.slice(i * attrcount, (i + 1) * attrcount)
				if (i > 0)
				{
					var prevprograminfo = programsrows.slice((i-1) * attrcount, i * attrcount)
					if (programinfo[0] == prevprograminfo[0])
					{
						console.warn("Caution! Detected duplicate program starting at " + programinfo[0] + " from " + prefix);
						console.log(programinfo)
						countissues++
					}
					else
					{
						json.data.push(programinfo)
						countall++
					}
				}
			}
			if (countissues > 0)
				console.log(countissues + " issues of " + countall + " programs detected")
			res.send(json)
		})
		return rclient.sort.apply(rclient, args)
	}
	else
	{
		return rawQuery("epg", res, next, rclient, params)
	}
}

function vodQuery(res, next, rclient, params, attr)
{
	if (params.length < 1)
	{
		res.send(403)
		next()
		return false
	}

	// extract provider
	var provider = params[0]

	var prefix = 'vod.' + provider + '.'

	switch (params.length)
	{
		// extract all vod groups
		case 1:
			// use redis sort to extract additional objects info
			attr = ["title", "parent"].concat(attr)
			var args = [prefix + 'groups', 'by', 'nosort', 'get', '#']
			for (var i = 0; i < attr.length; i++)
			{
				args.push('get')
				args.push(prefix + '*.' + attr[i])
			}
			args.push(function onSortVodGroups(err, vodgrouprows)
			{
				if (err)
				{
					return onError(err, res, next)
				}
				if (vodgrouprows.length > 0)
				{
					var json = {meta: ["id"].concat(attr), data: []}
					var attrcount = attr.length + 1
					for (var i = 0; i < vodgrouprows.length / attrcount; i++)
					{
						json.data.push(vodgrouprows.slice(i * attrcount, (i + 1) * attrcount))
					}
					res.send(json)
				}
				else
				{
					res.send(404)
				}
				return next()
			})
			return rclient.sort.apply(rclient, args)
		case 2:
			// extract all vod items in a group
			var vodgroupid = params[1]

			// all vod items
			if (vodgroupid === "*")
			{
				var args = [prefix + 'groups', 'by', 'nosort', 'get', '#']
				args.push(function onSortVodGroups(err, vodgrouprows)
				{
					if (err)
					{
						return onError(err, res, next)
					}
					if (vodgrouprows.length > 0)
					{
						var vodItemsCB = []
						var vodattr = ["title"].concat(attr)
						for (var i = 0; i < vodgrouprows.length; i++)
						{
							function cbgen(grpid)
							{
								return function(callback)
								{
									var vodprefix = 'vod.' + provider + '.' + grpid + '.'

									// use redis sort to extract additional objects info
									var args = [vodprefix + 'vods', 'by', 'nosort', 'get', '#']
									for (var j = 0; j < vodattr.length; j++)
									{
										args.push('get')
										args.push(vodprefix + '*.' + vodattr[j])
									}
									args.push(function (err, vodlist)
									{
										vodlist.group = grpid
										callback(err, vodlist)
									})
									rclient.sort.apply(rclient, args)
								}
							}
							vodItemsCB.push(cbgen(vodgrouprows[i]))
						}
						async.series(vodItemsCB, function(err, vodlists)
						{
							if (err)
							{
								return onError(err, res, next)
							}
							var json = {meta: ["id"].concat(vodattr).concat("parent"), data: []}
							for (var vl = 0; vl < vodlists.length; vl++)
							{
								var attrcount = vodattr.length + 1
								for (var i = 0; i < vodlists[vl].length / attrcount; i++)
								{
									var vod = vodlists[vl].slice(i * attrcount, (i + 1) * attrcount)
									vod.push(vodlists[vl].group)
									json.data.push(vod)
								}
							}
							res.send(json)
						})
						return true
					}
					else
					{
						res.send(404)
					}
					return false
				})
				return rclient.sort.apply(rclient, args)
			}
			else
			{
				prefix = 'vod.' + provider + '.' + vodgroupid + '.'
				// use redis sort to extract additional objects info
				attr = ["title"].concat(attr)
				var args = [prefix + 'vods', 'by', 'nosort', 'get', '#']
				for (var i = 0; i < attr.length; i++)
				{
					args.push('get')
					args.push(prefix + '*.' + attr[i])
				}
				args.push(function onSortVodItems(err, voditemsrows)
				{
					if (err)
					{
						return onError(err, res, next)
					}
					if (voditemsrows.length > 0)
					{
						var json = {meta: ["id"].concat(attr), data: []}
						var attrcount = attr.length + 1
						for (var i = 0; i < voditemsrows.length / attrcount; i++)
						{
							json.data.push(voditemsrows.slice(i * attrcount, (i + 1) * attrcount))
						}
						res.send(json)
					}
					else
					{
						res.send(404)
					}
					return next()
				})
				return rclient.sort.apply(rclient, args)
			}
		case 3:
			if (params[2] == "*") 
			{
				// this will make join(.) to add . at the end and make query like ict_1.*, instead ict_1*
				params[2] = ""
			}
	}
	return rawQuery("vod", res, next, rclient, params)
}

function searchQueryVOD(res, next, rclient, provider, text, attr)
{
	console.log("searchQueryVOD: searching `" + text + "' in " + provider)

	// connect to Solr
	var slrclient = solr.createClient({host: config.get("solr_host"), port: config.get("solr_port"), path: config.get("vod_solr_path")})

	// query text
	slrclient.query(text, {rows: config.get("vod_solr_rows")}, function(err, jsonText)
	{
		if (err)
		{
			return onError(err, res, next)
		}
		else
		{
			var vodItemsCB = []
			var resJson = JSON.parse(jsonText)
			for (var i = 0; i < resJson.response.docs.length; i++)
			{
				function cbgen(vodid, grpid)
				{
					return function(callback)
					{
						if (attr.length == 0)
						{
							// no need to fetch any attributes from redis
							callback(null, [vodid, grpid])
						}
						else
						{
							var vodprefix = 'vod.' + provider + '.' + grpid + '.' + vodid + '.'

							// use redis mget to extract multiple attributes by a vod item
							var args = []
							for (var j = 0; j < attr.length; j++)
							{
								args.push(vodprefix + attr[j])
							}
							args.push(function (err, voditem)
							{
								console.log(voditem)
								callback(err, [vodid, grpid].concat(voditem))
							})
							rclient.mget.apply(rclient, args)
						}
					}
				}
				vodItemsCB.push(cbgen(resJson.response.docs[i].id, resJson.response.docs[i].group_id))
			}
			var vodattr = ["id", "parent"].concat(attr)
			async.series(vodItemsCB, function(err, voditems)
			{
				if (err)
				{
					return onError(err, res, next)
				}
				var json = {meta: vodattr, data: []}
				for (var vi = 0; vi < voditems.length; vi++)
				{
					var attrcount = vodattr.length
					for (var i = 0; i < voditems[vi].length / attrcount; i++)
					{
						var vod = voditems[vi].slice(i * attrcount, (i + 1) * attrcount)
						json.data.push(vod)
					}
				}
				res.send(json)
			})
			return next()
		}
	})
}

function searchQuery(res, next, rclient, params, text, attr)
{
	if (params.length < 2)
	{
		res.send(403)
		return next()
	}

	var module = params[0]
	if (module == "vod")
		return searchQueryVOD(res, next, rclient, params[1], text, attr)

	res.send(403)
	return next()
}

function rateQuery(res, next, rclient, params)
{
	if (params.length < 4)
	{
		res.send(403)
		return next()
	}
	var key = 'rating' +'.' + params[0] +'.' + params[1] + '.' + params[2] + ','+ params[3]
	rclient.get(key, function (err,result) 
	{
		if(err)	
		{			
			console.log(err)
			return onError(err, res, next)
		}		
		else 
		{
			
			var json = {rating: result}
			res.send(json)
		}	
		next()
   
	})
}

function ratePost(res, next, rclient, params, rating)
{
	if (params.length < 4)
	{
		res.send(403)
		return next()
	}

	var key = 'rating' +'.' + params[0] +'.' + params[1] + '.' + params[2] + ','+ params[3]
	rclient.set(key, rating, function (err) 
	{
		if(err)	
		{			
			return onError(err, res, next)
		}		
		else 
		{
			var json = {status: 'success'}
			res.send(json)
		}	
		next()
   	})
}

function recommendQuery(res, next, rclient, params, max)
{
	if (params.length < 3)
	{
		res.send(403)
		return next()
	}
    var key = 'recommend' +'.' + params[0] + '.' + params[1] + '.' + params[2]
	rclient.lrange(key, 0, max - 1, function(err, reply)
	{
		if (err)
		{
			return onError(err, res, next)
		}
		else
		{
			res.json(reply)
			next()
		}
	})
}

function apiV1(pkg, rclient)
{
	return function respond(req, res, next)
	{
		
		var params = req.params[0]

		// notify http client with the character encoding type
		res.charSet('utf8')

		// strip last / if any
		if (params.charAt(params.length - 1) === '/')
		{
			params = params.substring(0, params.length - 1)
		}

		// strip to array
		params = params.split('/')

		// strip empty params
		for (var i = 0; i < params.length; i++)
		{
			if (params[i].length === 0)
			{
				params.splice(i, 1)
				i--
			}
		}

		// get command
		var cmd = params[0]
		params = params.slice(1)

		// get attr from query
		var attr = req.query['attr']
		if (attr !== undefined)
			attr = attr.split(',')
		else
			attr = []	
		switch (cmd)
		{
			case CMD_CHANNELS:
				return channelsQuery(res, next, rclient, params, attr)
			case CMD_PROGRAMS:
				return programsQuery(res, next, rclient, params, attr, req.query)
			case CMD_VOD:
				return vodQuery(res, next, rclient, params, attr)
			case CMD_SEARCH:
				var text = req.query['text']
				return searchQuery(res, next, rclient, params, text, attr)
			case CMD_RECOMMEND:
				var max = req.query['max']
				return recommendQuery(res, next, rclient, params, max)
			case CMD_RATE:

			    switch (req.method)	
			    {
				    case 'POST':
				    {	
					    var rating = req.params.rating;			    	
						return ratePost(res, next, rclient, params, rating)						
					}
					case 'GET':
					{
						return rateQuery(res, next, rclient, params)					
					}
				}
			default:
				res.send(404)
				next()
				break
		}
		return false
	}
}

module.exports = apiV1
