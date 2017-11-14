Slack          = require '../vendor/client'
mongoClient    = require '../modules/mongoClient'
InputHelper    = require '../helper/inputHelper'
timeHelper     = require '../helper/timeHelper'
Promise        = require 'promise'
{EventEmitter} = require 'events'
config         = require 'config'

class SlackClient extends EventEmitter

  @slack = null
  @mongo = null

  constructor: (mongo = null, token = null, slack) ->
    @token            = process.env.SLACK_TOKEN || config.get('slack.token')
    @token            = token || @token
    @autoReconnect    = true
    @autoMark         = true
    @users            = []
    @channels         = []
    @channelId        = process.env.CHANNEL_ID || config.get('slack.channelId')
    @slack            = slack

    # parse env vars that have to be arrays
    @disabledUsers    = if process.env.DISABLED_USERS then JSON.parse "[" + process.env.DISABLED_USERS + "]" else config.get 'slack.disabledUsers'
    @disabledChannels = if process.env.DISABLED_CHANNELS then JSON.parse "[" + process.env.DISABLED_CHANNELS + "]" else config.get 'slack.disabledChannels'

    if mongo? then @mongo = mongo

  connect: () ->
    # listen to Slack API events
    @slack.on 'presenceChange', @presenceChangeHandler
    @slack.on 'message', @messageHandler
    
    promise = new Promise (resolve, reject) =>
      # on open, push available users to array
      @slack.on 'open', =>
        for user, attrs of @slack.users when attrs.is_bot is false
          @users.push attrs

        console.log @slack.users
        resolve @slack

      @slack.on 'error', (error) ->
        reject error
      
      @slack.login()

  getUsers: () ->
    # ignore slackbot and disabled users
    users = @users.filter (user) =>
      return @disabledUsers.indexOf(user.id) is -1
    return users

  getUserIds: () ->
    users = @getUsers().map (user) ->
      return user.id

  getUser: (userId) ->
    # ignore disabled users
    if @disabledUsers.indexOf(userId) isnt -1
      return null

    filteredUsers = (user for user in @users when user.id is userId)
    filteredUsers[0]

  setUserPresence: (userId, presence) =>
    (user.presence = presence) for user in @users when user.id is userId

  allowUserFeedbackMessage: (userId) ->
    user = @getUser userId
    user.allowFeedbackMessage = true

  disallowUserFeedbackMessage: (userId) ->
    user = @getUser userId
    user.allowFeedbackMessage = false

  isUserFeedbackMessageAllowed: (userId) ->
    user = @getUser userId
    typeof user isnt 'undefined' && typeof user.allowFeedbackMessage isnt 'undefined' && user.allowFeedbackMessage

  getfeedbackRequestsCount: (userId) ->
    user = @getUser userId
    if (typeof user isnt 'undefined' && typeof user.feedbackRequestsCount isnt 'undefined' && user.feedbackRequestsCount)
      return user.feedbackRequestsCount
    return 0

  setfeedbackRequestsCount: (userId, count) ->
    user = @getUser userId
    user.feedbackRequestsCount = count

  presenceChangeHandler: (data, presence) =>
    # when presence changes, set internally and send event
    data =
      userId: data.id
      status: presence

    @setUserPresence data.userId, presence

    @emit 'presence', data

  messageHandler: (message) =>
    # if user is bot, return
    if !message? || (@getUser message.user) is undefined
      return false

    # ignore channel that oskar is broadcasting to (otherwise he'd react to every single message in there)
    if (@channelId && @channelId is message.channel)
      return false

    # disable messages from disabled channels
    if @disabledChannels.indexOf(message.channel) isnt -1
      return false

    # send message event
    message.type = 'input'
    @emit 'message', message
    return true

  # post message to slack
  postMessage: (userId, message, cb) =>
    # if channels object already exists
    if (userId in @channels)
      return @slack.postMessage @channels[userId].channel.id, message, () ->
        cb()
    # otherwise open new one
    @slack.openDM userId, (res) =>
      @channels[userId] = res
      @slack.postMessage res.channel.id, message, () ->
        if (cb)
          cb arguments...

  postMessageToChannel: (channelId, message, cb) ->
    @slack.postMessage channelId, message, () ->
      if (cb)
        cb arguments...

module.exports = SlackClient
