// --------------------------------------------------------------------
//                                                                   --
// Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
//                                                                   --
// Project:       AVTV                                               --
// Filename:      v1.js                                              --
// Description:   EPG API V1                                         --
//                                                                   --
// -------------------------------------------------------------------- 

var async = require("async")

var CMD_CHANNELS = "channels"
var CMD_PROGRAMS = "programs"
var CMD_VOD = "vod"

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

function programsQuery(res, next, rclient, params, attr, linkinfo)
{
	if (params.length < 2)
	{
		res.send(403)
		next()
		return false
	}

	if (params.length === 2)
	{
		// extract provider and channelId
		var provider = params[0]
		var channelId = params[1]

		if (linkinfo[provider])
		{
			var chnlink = linkinfo[provider][channelId]
			if (chnlink)
			{
				console.log("Linking " + provider + "/" + channelId + " to " + chnlink[0] + "/" + chnlink[1])
				provider = chnlink[0]
				channelId = chnlink[1]
			}
		}

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
		// extract all vod items in a group
		case 2:
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
									console.log(args)
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
							var json = {meta: ["id"].concat(vodattr).concat("group"), data: []}
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
				return programsQuery(res, next, rclient, params, attr, pkg.epg.link)
			case CMD_VOD:
				return vodQuery(res, next, rclient, params, attr)
			default:
				res.send(404)
				next()
				break
		}
		return false
	}
}

module.exports = apiV1
