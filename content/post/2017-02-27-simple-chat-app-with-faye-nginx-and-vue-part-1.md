+++
date = "2017-02-27T15:28:49+02:00"
title = "Build a simple chat web app using Faye, Express and Vue - Part 1"
tags = ['nodejs', 'express', 'javascript']
categories = ['Programming']
+++
I have been keeping my eyes on [Vuejs](https://vuejs.org/) for quite some time, and I finally decided to build something with it. I am going to build a simple chat web app using Faye, Express and Vue. I have been using Faye and Express for several years, Vue is the new guy here.

<!--more-->

The structure of the app is straightforward, there are 3 main components communicating with each other to serve the requests.

- The API server to handle data persistence, authentication and authorization (through Github or other OAuth services).
- The pub/sub messaging server to push messages to the client side in real-time (through websocket, evensource or long-polling).
- The static file server to show the actual user interface.

In the first part, I am going to start with setting up the API server and a simple data persistence layer:

- API server is implemented using [Express](http://expressjs.com/)
- Data persistence is done via [sqlite3](https://github.com/kriasoft/node-sqlite)

## API server
I love to work with Express because it only takes several minutes to get the server up and running. It provides a thin layer on top of the native http module in Nodejs but still allows a wide range of customization to be done easily.

I will go with REST because I don't see any point in doing something fancy like GraphQL for this trival app. At its simplest form, the API server looks like this
```
// app.js
const express = require('express'),
      bodyParser = require('body-parser'),
      cookieParser = require('cookie-parser'),
      config = require('./config');

const allowCors = (req, res, next) => {
  res.header('Access-Control-Allow-Origin', config.get('web.url'));
  res.header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS, PUT, DELETE');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.header('Access-Control-Allow-Credentials', true);

  next();
};

const app = express();
app.use(allowCors);
app.disable('x-powered-by');
app.enable('trust proxy');
app.use(cookieParser());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

app.use('/messages', require('./routes/messages'));
```

It's pretty straightforward, there are 2 things worth mentioning, the `config` and the use of `router`

### Config module
I am using `nconf` to build a hierarchy of configuration for my projects. The idea is simple, first it loads a global configuration file (`config.yml` in my case). Then it tries to load the environment specific configuration file, it's can be `development`, `production`, `staging`, `testing` or `ci` (for continuous integration setup).

For security purposes, I don't store any passwords, API keys in git repository (and you should too). Instead, I set them in environment variables during the deployment process and `nconf` automatically picks them up and overwrites the existing configuration.

For example, when I set the database connection variable to the environment variable called `psql__host`, I can get it by calling `config.get('psql.host')`.

```
// config/index.js
const _ = require('lodash'),
      yaml = require('js-yaml');

let nconf = require('nconf');

const env = process.env.NODE_ENV || 'development';

module.exports = nconf.env({
  separator: '__',
  lowerCase: true,
  logicalSeparator: '.'
}).file('env-configs', {
  file: `${__dirname}/config.${env}.yml`,
  format: {
    parse: yaml.safeLoad,
    stringify: yaml.safeDump
  },
  logicalSeparator: '.'
}).file('default-configs', {
  file: `${__dirname}/config.yml`,
  format: {
    parse: yaml.safeLoad,
    stringify: yaml.safeDump
  },
  logicalSeparator: '.'
});
```

### Router
The concept of router in Express is simple, you divide your application into smaller independent "routers" and compose them in the main Express app instance. I usually put the files in sub folders corresponding to their path. For example:

- `GET    /api/1/messages`   -> `/project/routes/api/1/messages/list.js`
- `GET    /api/1/messages/1` -> `/project/routes/api/1/messages/read.js`
- `POST   /api/1/messages`   -> `/project/routes/api/1/messages/create.js`
- `PUT    /api/1/messages`   -> `/project/routes/api/1/messages/update.js`
- `DELETE /api/1/messages/1` -> `/project/routes/api/1/messages/delete.js`

Then with a simple recursive function I can loop through all the files and construct the end points accordingly. It can also takes care of API versoning and other middleware setup.

However, in this small project, I just go with a simple router file containing 4 end points for interacting with `messages` resource. There is no end point to get one message because I am not going to support that in the UI.

```
// routes/messages.js
const express = require('express'),
      router = express.Router();

router.get('/', (req, res) => {
  // list
});

router.post('/', (req, res) => {
  // create
});

router.put('/:id', (req, res) => {
  // update
});

router.delete('/:id', (req, res) => {
  // delete
});

module.exports = router;
```

When composing it with the main app

```
app.use('/messages', require('./messages'));
```

I have the following routes
```
GET    /messages
POST   /messages
PUT    /messages/1
DELETE /messages/1
```

## Data persistence
For the purposes of this simple app, I don't need anything fancier than sqlite3 and a bunch of functions, sql queries to store and retrieve data.

```
// sqlite.js
const sqlite = require('sqlite'),
      Promise = require('bluebird');

module.exports = {
  getMessages(limit = 50) {},
  createMessage(content) {},
  deleteMessage(id) {},
  updateMessage(id, content) {},

  // must call this before everything else
  up() {
    return sqlite.open(`${__dirname}/chat.sqlite`, {Promise}).then(() => {
      return sqlite.migrate({
        migrationsPath: `${__dirname}/migrations`
      });
    });
  }
};
```

I skip all the SQL queries on purpose to present a clearer view of the module. Notice that there is an `up` function that must be called before starting the application to run migration files.

```
// start.js
const app = require('./src/app'),
      service = require('./src/service'),
      config = require('./src/config');

const port = config.get('express.port');
const host = config.get('express.host');

service.up().then(() => {
  app.listen(port, host, () => {
    console.log(`API server is running at ${host}:${port}`);
  });
}).catch((e) => {
  console.error('Failed to start application', e);
});
```

And the migration

```
-- Up
CREATE TABLE messages (
  id INTEGER PRIMARY KEY,
  content TEXT NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Down
DROP TABLE messages;
```

With this I have the first part of the application ready. The source code can be found here [https://github.com/tanqhnguyen/simple-chat-api](https://github.com/tanqhnguyen/simple-chat-api/tree/part-1).

In the next part, I am going to write about the authentication and authorization process using [Passport](http://passportjs.org/).
