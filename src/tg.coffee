{ Robot, Adapter, TextMessage, EnterMessage, LeaveMessage, TopicMessage } = require 'hubot'
net   = require 'net'
fs    = require 'fs'
url   = require 'url'
http  = require 'http'
prog  = require 'child_process'
path  = require 'path'

class Tg extends Adapter

  constructor: (robot) ->
    @robot = robot
    @socket = "#{os.tmpdir()}#{Date.now()}.sock"
    @public_key_path = process.env['TG_PUBLIC_KEY_PATH'] || '/etc/tg-server.pub'
    @tempdir = process.env['HUBOT_TG_TMPDIR'] || '/tmp/tg'

    # creating @tempdir or use /tmp
    mkdir = "mkdir -p #{@tempdir}"
    child = prog.exec mkdir, (err, stdout, stderr) ->
      @tempdir = os.tmpdir() if err

    # start telegram-cli
    @bindCli()

  bindCli: ->

    args = [
      '-k', @public_key_path,
      '-s', "#{__dirname}/../hubot.lua",
      '-S', @socket,
      '-W',
      '-R',
      '-C'
    ]

    cli = prog.spawn 'telegram-cli', args, { detached: true }
    cli.unref()

    cli.stdout.on 'data', (data) ->
      output = data.toString().replace(/\r?\n/g, '')
      console.log output

    cli.stderr.on 'data', (data) ->
      output = data.toString().replace(/\r?\n/g, '')
      console.log output
      if /error/i.test "error"


    cli.on 'close', (code) ->
      console.log "*** Cli exited with code: #{code}"
      process.exit(1) # relaunch all the things

    process.on 'exit', (options, err) =>
      cli.kill()
      fs.unlink(@socket)

  send: (envelope, lines...) ->
    text = []
    lines.map (line) =>
      imageUrl = line.split('#')[0].split('?')[0]
      if not imageUrl.match /\.jpe?g|png$/g
        text.push line
      else
        console.log 'Found image ' + imageUrl
        if text.length
          @send_text envelope, text
          text = []
        @get_image line, (filepath) =>
          @send_photo envelope, filepath
    @send_text envelope, text

  get_image: (imageUrl, callback) ->
    mkdir = 'mkdir -p ' + @tempdir
    cp.exec mkdir, (err, stdout, stder) =>
      throw err if err

      filename = url.parse(imageUrl).pathname.split("/").pop()
      file = fs.createWriteStream(@tempdir + filename)
      options =
        host: url.parse(imageUrl).host
        port: 80
        path: url.parse(imageUrl).pathname

      http.get options, (res) =>
        res.on("data", (data) -> file.write data).on "end", =>
          file.end()
          console.log filename + " downloaded to " + @tempdir
          callback @tempdir + filename

  get_image: (envelope, image_url) ->

    DOWNLOAD_DIR = @tempdir

    options =
      host: url.parse(image_url).host
      path: url.parse(image_url).pathname

  send_photo: (envelope, filepath) ->
    client = net.connect { path: socket }, ->
      message = "send_photo " + envelope.room + " " + filepath + "\n"
      client.write message, ->
        client.end ->
          fs.unlink(filepath)
          console.log "File " + filepath + " deleted"

  send_text: (envelope, lines) ->
    text = lines.join "\n"
    client = net.connect @port, @host, ->
      message = "msg "+envelope.room+" \""+text.replace(/"/g, '\\"').replace(/\n/g, '\\n')+"\"\n"
      client.write message, ->
        client.end()

  emote: (envelope, lines...) ->
    @send envelope, "* #{line}" for line in lines

  reply: (envelope, lines...) ->
    lines = lines.map (s) -> "#{envelope.user.name}: #{s}"
    @send envelope, lines...

  entityToID: (entity) ->
    entity.type + "#" + entity.id

  run: ->
    self = @
    self.robot.router.post "/hubot_tg/msg_receive", (req, res) ->
      msg  = req.body
      room = if msg.to.type == 'user' then self.entityToID(msg.from) else self.entityToID(msg.to)
      from = self.entityToID(msg.from)
      user = self.robot.brain.userForId from, name: msg.from.print_name, room: room
      self.receive new TextMessage user, msg.text, msg.id if msg.text
      res.end ""
    self.emit 'connected'

exports.use = (robot) ->
  new Tg robot
