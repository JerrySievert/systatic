log       = console.log
fs        = require('fs')
path      = require('path')
jade      = require(path.join(__dirname, 'plugins', 'jade_template'))
servitude = require('servitude')
bricks    = require('bricks')
exec      = require('child_process').exec
u         = require('underscore')

# hopefully use servitude
less      = require('less')
coffee    = require('coffee-script')

exports.config = config = ()->
  return @configData if @configData?
  @configData = require(path.resolve(path.join('.', 'config.json')))

exports.inProject = (dirname)->
  return true if path.existsSync(path.join(dirname, 'config.json'))
  false

exports.clone = (dirname, template)->
  templatePath = path.join(__dirname, '..', 'templates', template)
  log "Generating project #{dirname}"
  exec "cp -R #{templatePath} #{dirname}", (error, stdout, stderr)->
    log error

getPlugin = (value, appserver)->
  switch value
    when "servitude" then servitude
    when "filehandler" then appserver.plugins.filehandler
    else appserver.plugins.filehandler

assetRoute = (appserver, asset)->
  c = config()
  basedir = c.sourceDir || 'src'
  appserver.addRoute(c[asset].route, getPlugin(c[asset].plugin, appserver), basedir: path.join(basedir, c[asset].baseDir))

exports.startServer = (port, ipaddr, logfile)->
  c = config()
  basedir = c.sourceDir || 'src'

  appserver = new bricks.appserver()
  appserver.addRoute("/$", jade, basedir: basedir, name: 'index')
  assetRoute(appserver, 'stylesheets')
  assetRoute(appserver, 'javascripts')
  assetRoute(appserver, 'images')
  # TODO: crap. cannot extract directories from regexp.
  appserver.addRoute(".+", jade, basedir: basedir, stylesheetspath: '/stylesheets/', javascriptspath: '/javascripts/')

  fourohfour = (request, response, options) ->
    request.url = "/404"
    response.statusCode 404
    jade.plugin request, response, options

  appserver.addRoute(".+", fourohfour)

  if logfile
    try
      appserver.addRoute(".+", appserver.plugins.loghandler, section: 'final', filename: logfile)
    catch error
      log "Error opening logfile, continuing without logfile"

  server = appserver.createServer()

  try
    server.listen(port, ipaddr)
  catch error
    log "Error starting server, unable to bind to #{ipaddr}:#{port}"


exports.test = (port, ipaddr, logfile)->
  c = config()
  builddir = c.buildDir || 'build'
  
  appserver = new bricks.appserver()
  

  appserver.addRoute("/$", appserver.plugins.redirect, routes: [{ path: "/$", url: "/index.html" }])
  appserver.addRoute(".+", appserver.plugins.filehandler, basedir: builddir)

  fourohfour = (request, response, options) ->
    request.url = "/404.html"
    appserver.plugins.filehandler.plugin request, response, options

  appserver.addRoute(".+", fourohfour, basedir: builddir)

  server = appserver.createServer()

  try
    server.listen(port, ipaddr)
  catch error
    log "Error starting server, unable to bind to #{ipaddr}:#{port}"


# Compiles and compacts all assets into a minimal set of files
exports.build = ()->
  c = config()
  basedir = c.sourceDir || 'src'
  basedir = path.resolve(basedir)

  builddir = c.buildDir || 'build'

  try
    fs.mkdirSync(builddir)
    fs.mkdirSync("#{builddir}/derp")
    fs.mkdirSync("#{builddir}/stylesheets")
    fs.mkdirSync("#{builddir}/javascripts")
  catch e

  builddir = path.resolve(builddir)

  ignores = c.ignore || []


  assets = {css: {}, js: {}}
  walkSync basedir, /\.jade$/, (filenames)->
    return if filenames.length == 0
    filenames.forEach (fullname)->
      filename = fullname.replace(basedir, '').replace(/\//, '')
      for ignore in ignores
        return if filename.match(ignore)
      outputfile = path.join(builddir, filename.replace(/\.jade$/, '.html'))
      randomname = (Math.random() * 0x100000000 + 1).toString(36)
      #randomname = filename.replace(/.jade$/, '')
      jade.compile(randomname, fullname, outputfile, assets) #, true)


  cssbasedir = c.stylesheets.baseDir || 'stylesheets'
  cssbuilddir = path.resolve(path.join(builddir, cssbasedir))
  cssbasedir = path.resolve(path.join(basedir, cssbasedir))

  parser = new less.Parser
    paths: [cssbasedir], # Specify search paths for @import directives
    #filename: 'style.less' # Specify a filename, for better error messages

  cssdata = {}

  # first compile up all less files
  walkSync cssbasedir, /\.less$/, (filenames)->
    return if filenames.length == 0
    filenames.forEach (fullname)->
      filename = fullname.replace(cssbasedir, '').replace(/\//, '')
      filedata = fs.readFileSync(fullname, 'utf8')
      parser.parse filedata, (e, tree)->
        cssdata[filename] = tree.toCSS(compress: true)

  # get all of the regular css files
  walkSync cssbasedir, /\.css$/, (filenames)->
    return if filenames.length == 0
    filenames.forEach (fullname)->
      filename = fullname.replace(cssbasedir, '').replace(/\//, '')
      cssdata[filename] = fs.readFileSync(fullname, 'utf8')
  

  u.forEach assets.css, (files, outputname)->
    outputname = path.join(cssbuilddir, "#{outputname}.css")
    buffer = ''
    u.forEach files, (i, assetkey)->
      unless cssdata[assetkey]?
        console.log "Unknown asset #{assetkey}"
        return
      buffer += cssdata[assetkey]
    # write buffer to outputname
    fs.writeFileSync(outputname, buffer, 'utf8')


  # Do all the same things for javascript
  jsbasedir = c.javascripts.baseDir || 'javascripts'
  jsbuilddir = path.resolve(path.join(builddir, jsbasedir))
  jsbasedir = path.resolve(path.join(basedir, jsbasedir))

  jsdata = {}

  # first compile up all coffee files
  walkSync jsbasedir, /\.coffee$/, (filenames)->
    return if filenames.length == 0
    filenames.forEach (fullname)->
      filename = fullname.replace(jsbasedir, '').replace(/\//, '')
      filedata = fs.readFileSync(fullname, 'utf8')
      jsdata[filename] = coffee.compile(filedata)

  # get all of the regular js files
  walkSync jsbasedir, /\.js$/, (filenames)->
    return if filenames.length == 0
    filenames.forEach (fullname)->
      filename = fullname.replace(jsbasedir, '').replace(/\//, '')
      jsdata[filename] = fs.readFileSync(fullname, 'utf8')
  

  u.forEach assets.js, (files, outputname)->
    outputname = path.join(jsbuilddir, "#{outputname}.js")
    buffer = ''
    u.forEach files, (i, assetkey)->
      unless jsdata[assetkey]?
        console.log "Unknown asset #{assetkey}"
        return
      buffer += jsdata[assetkey]
    # write buffer to outputname
    fs.writeFileSync(outputname, buffer, 'utf8')
  console.log "Done"


# Copies all built files to a remote source, like S3
exports.deploy = ()->
  log "== Not yet implemented"

exports.clean = ()->
  c = config()
  builddir = c.buildDir || 'build'
  if builddir == '.' || builddir.match(/^\//) || builddir == '~' || builddir == ''
    return log('No.')
  exec "rm -rf #{builddir}", (error, stdout, stderr)->
    log error


# Walks directories and finds files matching the given filter
walkSync = (start, filter, cb)->
  filter = /./ unless filter?
  if fs.statSync(start).isDirectory()
    collection = fs.readdirSync(start).reduce((acc, name)->
      if fs.statSync(path.join(start, name)).isDirectory()
        acc.dirs.push(name)
      else
        if name.match(filter)
          acc.names.push(path.join(start, name))
      acc
    names: []
    dirs: []
    )
    cb(collection.names)
    for dir in collection.dirs
      walkSync(path.join(start, dir), filter, cb)
  else
    throw new Error("#{start} is not a directory")
