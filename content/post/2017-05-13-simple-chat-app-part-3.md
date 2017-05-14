+++
date = "2017-05-13T21:55:22+02:00"
title = "Build a simple chat web app using Faye, Express and Vue - Part 3"
tags = ['nodejs', 'express', 'javascript', 'faye']
categories = ['Programming']
+++

In the previous part, I added the basic authentication and authorization to the API service. In this part, I am going to implement the pub/sub messaging service using [Faye](https://faye.jcoglan.com/) and integrate it with the API service.

<!--more-->
## Pub/sub messaging system
If you are not familiar with publish-subscribe design pattern, you might want to do some reading before continue reading. I am gonna give a brief explanation about pub/sub design pattern. The idea behind this design pattern is to eliminate direct dependencies between services. In this design pattern, services communicate with each other through channels instead of direct calls. There can be one or multiple channels to which services will listen for incoming messages or send messages. When a service wants to notify another service about an event, it sends a message to the appropriate channel to which the targeted service is listening. The targeted service then receives the message and does something with it.

Faye implements the simplest form of pub/sub. There are many other pub/sub libraries in nodejs world such as [Socket.io](https://socket.io/) or [SockJS](https://github.com/sockjs). There are also paid services such as [PubNub](https://www.pubnub.com/).

Setting up a faye server takes just few minutes

```javascript
// faye/src/server.js
const http = require('http'),
      faye = require('faye'),
      config = require('./config');

const bayeux = new faye.NodeAdapter({
  mount: config.get('faye.mount'),
  timeout: config.get('faye.timeout')
});

// Handle non-Bayeux requests
const server = http.createServer(function(request, response) {
  response.writeHead(200, {'Content-Type': 'text/plain'});
  response.end('Hello stranger');
});

bayeux.attach(server);

module.exports = server;
```

But I probably don't want to allow everyone to push messages to my pub/sub server. Instead I want to make it read-only from the UI point of view, and only allow the API service to push messages. Faye's [extensions](https://faye.jcoglan.com/node/extensions.html) are designed for this purpose

```javascript
// faye/src/server.js
const serverAuth = {
  incoming: function(message, callback) {
    if (message.channel !== '/meta/subscribe') return callback(message);
    const subscription = message.subscription,
          msgToken     = message.ext && message.ext.secret;

    const secret = config.get('faye.secret');
    if (secret !== msgToken) message.error = 'Invalid subscription auth token';
    callback(message);
  }
};
bayeux.addExtension(serverAuth);
```

## API integration
Because I am going to deploy the pub/sub and the API service separately, the API service will need to use [server side clients](https://faye.jcoglan.com/node/clients.html) to talk to Faye server.

```javascript
// api/src/faye.js
const faye = require('faye'),
      deflate = require('permessage-deflate'),
      config = require('./config');

const client = new faye.Client(config.get('faye.url'));
client.addWebsocketExtension(deflate);

module.exports = client;
```

This is enough if I don't have the secret key set up on the other side. Since I have it, I need to add another extension to insert the secret key to every message pushed to pub/sub channels from the API service.

```javascript
// api/src/faye.js
const clientAuth = {
  outgoing: function(message, callback) {
    if (message.channel !== '/meta/subscribe') return callback(message);
    message.ext = message.ext || {};
    message.ext.secret = config.get('faye.secret');
    callback(message);
  }
};

client.addExtension(clientAuth);
```

Now that I have the faye client ready, next step is to actually use it. When creating a message, I send an event to `/messages` channel to notify the UI that there is a new message.

```javascript
// api/src/service.js
createMessage(content, userId) {
  if (!content) return Promise.reject('Missing content');

  content = xssFilters.inHTMLData(content);

  faye.publish('/messages', {
    event: 'createMessage',
    payload: {content, userId}
  });

  return sqlite.run(`
    INSERT INTO messages(content, userId) VALUES (?, ?)
  `, [content, userId]).then((stm) => {
    return sqlite.get(`
      SELECT * FROM messages WHERE id = ?
    `, [stm.lastID]);
  }).then(changeAllKeysToCamelCase);
}
```

Then when someone deletes a message, I also send an event to tell the UI to delete the message.

```javascript
// api/src/service.js
deleteMessage(id) {
  faye.publish('/messages', {
    event: 'deleteMessage',
    payload: {id}
  });

  return sqlite.run(`
    DELETE FROM messages WHERE id = ?
  `, [id]).then((stm) => {
    return {id};
  });
}
```

Finally, when updating a message

```javascript
// api/src/service.js
updateMessage(id, content) {
  if (!content) return Promise.reject('Missing content');

  content = xssFilters.inHTMLData(content);

  faye.publish('/messages', {
    event: 'updateMessage',
    payload: {id, content}
  });

  return sqlite.run(`
    UPDATE messages
    SET content = ?
    WHERE id = ?
  `, [content, id]).then((stm) => {
    return sqlite.get(`
      SELECT * FROM messages WHERE id = ?
    `, [id]);
  }).then(changeAllKeysToCamelCase);
}
```

And that's everything, a secured pub/sub messaging server and an API integration. That's all it needs to build the backend for a simple chat app. You can find the source code

- For the API service at [https://github.com/tanqhnguyen/simple-chat-api/tree/part-3](https://github.com/tanqhnguyen/simple-chat-api/tree/part-3)
- For the Faye service at [https://github.com/tanqhnguyen/simple-chat-faye/tree/part-3](https://github.com/tanqhnguyen/simple-chat-faye/tree/part-3)

Next, the final piece of the app, the UI. I am going to implement the UI for this simple chat app using [Vue](https://vuejs.org/).
