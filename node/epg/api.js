// --------------------------------------------------------------------
//                                                                   --
// Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
//                                                                   --
// Project:       AVTV                                               --
// Filename:      api.js                                             --
// Description:   EPG API WebService in NodeJS                       --
//                                                                   --
// -------------------------------------------------------------------- 

var redis = require("redis")
var restify = require("restify")
var apiV1 = require("./v1")


// snippet taken from http://catapulty.tumblr.com/post/8303749793/heroku-and-node-js-how-to-get-the-client-ip-address
function getClientIp(req) {
  var ipAddress
  // The request may be forwarded from local web server.
  var forwardedIpsStr = req.header('x-forwarded-for')
  if (forwardedIpsStr) {
    // 'x-forwarded-for' header may return multiple IP addresses in
    // the format: "client IP, proxy 1 IP, proxy 2 IP" so take the
    // the first one
    var forwardedIps = forwardedIpsStr.split(',')
    ipAddress = forwardedIps[0];
  }
  if (!ipAddress) {
    // If request was not forwarded
    ipAddress = req.connection.remoteAddress
  }
  return ipAddress
}


var server = restify.createServer(
{
	name: 'AVTV',
})

server.use(restify.gzipResponse())
server.use(restify.queryParser())
server.get(/v1\/(.*)/, apiV1(redis.createClient()))
server.get(/\/static\/*.*/, restify.serveStatic({
  directory: './node/epg'
}))
server.get("/shutdown", function(req, res, next) 
{
	if (getClientIp(req) == "127.0.0.1")
	{
		console.log("Shutting down...")
		process.exit(0)
		return true
	}
	else
	{
		res.send(404);
   		return next();
	}
})

server.listen(9090, function()
{
  console.log('%s listening at %s', server.name, server.url)
})
