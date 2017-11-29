###################################################################
# Setup the tests
###################################################################
should      = require 'should'
sinon       = require 'sinon'
config      = require 'config'
Slack       = require '../src/vendor/client'
SlackClient = require '../src/modules/slackClient'
slackClient = null
connect     = null

###################################################################
# Slack client
###################################################################

describe 'SlackClient', ->

  before ->
    slack = new Slack('tokens4feels')
    slackLogin = sinon.stub slack, 'login', () ->
      slack.users = 
        user1: 
          id: 1
          is_bot: false
          name: 'Mr Mc Mr'
          first_name: 'Mc'
          last_name: 'Mr'
        user2:
          id: 2
          is_bot: true
          name: 'Barbar de Rarrar'
          first_name: 'Barbar'
          last_name: 'de Rarrar'
      slack.emit('open')
    slackClient = new SlackClient(null, 'whatever', slack)

  it 'should connect to the slack client', (done) ->
    slackClient.connect().then (res) ->
      res.should.have.property 'users'
      res.should.have.property 'autoReconnect'
      res.should.have.property 'autoMark'
      done()

###################################################################
# Slack client users
###################################################################

  describe 'SlackClientUsers', ->

    users            = null
    userIds          = null
    disabledUsers    = null
    disabledChannels = null

    before ->
      slackClient.connect().then ->
        users            = slackClient.getUsers()
        userIds          = slackClient.getUserIds()
        console.log userIds
        disabledUsers    = config.get 'slack.disabledUsers'
        disabledChannels = config.get 'slack.disabledChannels'

    describe 'PublicMethods', ->

      it 'should not contain IDs of disabled users', ->
        if disabledUsers.length
          disabledUsers.forEach (userId) ->
            users.indexOf(userId).should.be.equal(-1)

      it 'should get a user', ->
        user = slackClient.getUser 1
        console.log user
        user.name.should.be.type 'string'
        user.first_name.should.equal 'Mc'

    describe 'PublicMethodsFeedbackMessage', ->

      it 'should enable user feedback message', ->
        userId = userIds[0]
        slackClient.allowUserFeedbackMessage(userId)
        user = slackClient.getUser(userId)
        user.allowFeedbackMessage.should.be.equal(true)

      it 'should disable user feedback message', ->
        userId = userIds[0]
        slackClient.disallowUserFeedbackMessage(userId)
        user = slackClient.getUser(userId)
        user.allowFeedbackMessage.should.be.equal(false)

      it 'should return false if user feedback message is not yet allowed', ->
        userId = userIds[0]
        allowed = slackClient.isUserFeedbackMessageAllowed(userId)
        allowed.should.be.equal(false)

      it 'should return true if user feedback message is allowed after setting it', ->
        userId = userIds[0]
        slackClient.allowUserFeedbackMessage(userId)
        allowed = slackClient.isUserFeedbackMessageAllowed(userId)
        allowed.should.be.equal(true)

    describe 'PublicMethodsRequestsCount', ->

      it 'should return the number of times oskar has asked this user for feedback', ->
        userId = userIds[0]
        number = slackClient.getfeedbackRequestsCount(userId)
        number.should.be.equal(0)

      it 'should set the number of times oskar has asked this user for feedback', ->
        userId = userIds[0]
        slackClient.setfeedbackRequestsCount(userId, 1)
        number = slackClient.getfeedbackRequestsCount(userId)
        number.should.be.equal(1)

    describe 'EventHandlers', ->

      it 'should send a presence event when user changes presence', ->
        data =
          id: userIds[0]

        spy = sinon.spy()
        slackClient.on('presence', spy);
        slackClient.presenceChangeHandler data, 'away'

        spy.called.should.be.equal(true);
        spy.args[0][0].userId.should.be.equal(userIds[0])
        spy.args[0][0].status.should.be.equal('away')

      it 'should set the user status when user changes presence', ->
        data =
          id: userIds[0]

        slackClient.presenceChangeHandler data, 'active'
        user = slackClient.getUser data.id
        user.presence.should.be.equal 'active'

    describe 'MessageHandler', ->

      it 'should return false when message handler if user is slackbot', ->
        message =
          userId: 'USLACKBOT'
        response = slackClient.messageHandler(message)
        response.should.be.equal(false)

      it 'should return false when message handler is called with a disabled channel', ->
        if disabledChannels.length
          message =
            user: userIds[0]
            channel: disabledChannels[0]
        response = slackClient.messageHandler(message)
        response.should.be.equal(false)

      it 'should return false when message handler is called with a message from broadcast channel', ->
        message =
          user: userIds[0]
          channel: 'broadcastChannel'
        response = slackClient.messageHandler(message)
        response.should.be.equal(false)

      it 'should trigger a message event when message handler is called with a user and text that asks for user status', ->
        message =
          user: userIds[0]
          text: 'How is <@#{userIds[1]}>?'

        spy = sinon.spy()
        slackClient.on 'message', spy

        slackClient.messageHandler message
        spy.called.should.be.equal true
        spy.args[0][0].text.should.be.equal 'How is <@#{userIds[1]}>?'

      it 'should trigger a message event when message handler is called with a user and text that asks for channel status', ->
        message =
          user: userIds[0]
          text: 'How is everyone?'

        spy = sinon.spy()
        slackClient.on 'message', spy

        slackClient.messageHandler message
        spy.called.should.be.equal true
        spy.args[0][0].text.should.be.equal 'How is everyone?'
