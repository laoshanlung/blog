+++
date = "2017-03-08T21:55:22+02:00"
title = "Build a simple chat web app using Faye, Express and Vue - Part 2"
tags = ['nodejs', 'express', 'javascript']
categories = ['Programming']
+++

Previously, I had the basic API server up and running. In this part I am going to continue with the authentication and authorization (via Github). The purpose is to have a simple login system where the users need to log in (via Github) before they can send messages.

<!--more-->
## User table
First thing first, since I have new data entity in my application, I need to store it somewhere. I am using a very simple migration system to manage the database schema. Adding a new migration is done by creating a file name `002-users.sql`. There is nothing special about the `users` table

```
-- Up
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  login_type TEXT NOT NULL,
  login_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  profile_url TEXT NOT NULL,
  avatar_url TEXT NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE messages ADD COLUMN user_id INTEGER REFERENCES users(id);
CREATE UNIQUE INDEX unique_user ON users(login_type, login_id);

-- Down
ALTER TABLE messages DROP COLUMN user_id;
DROP TABLE users;
```

I also need to add a new method `upsertUser` to `service` to abstract away the "complex" sql queries to upsert users. This table is used to store data retrieved from Github when someone logs in.

## Authentication
I am using [PassportJS](http://passportjs.org/) to talk to Github OAuth server. Using the example found in the git repository of [passport-github2](https://github.com/cfsghost/passport-github) and adding some stuff, I have the following `auth.js` router.

```
const passport = require('passport'),
      GitHubStrategy = require('passport-github2'),
      config = require('../config'),
      express = require('express'),
      router = express.Router(),
      service = require('../service'),
      jwt = require('jsonwebtoken');

passport.use(new GitHubStrategy({
    clientID: config.get('auth.github.id'),
    clientSecret: config.get('auth.github.secret'),
    callbackURL: `${config.get('api.url')}/auth/github/callback`
  },
  function(accessToken, refreshToken, profile, done) {
    const json = profile._json;

    const data = {
      loginType: 'github',
      loginId: json.login,
      avatarUrl: json.avatar_url,
      profileUrl: json.html_url,
      displayName: json.name
    };

    service.upsertUser(data).asCallback(done);
  }
));

router.get('/github', passport.authenticate('github'));

const failureRedirect = `${config.get('web.url')}/login`;
const successRedirect = `${config.get('web.url')}`;
router.get('/github/callback',
  passport.authenticate('github', { failureRedirect, session: false }),
  function(req, res) {
    const token = jwt.sign({
      user: req.user
    }, config.get('auth.secret'), { expiresIn: '48h' });

    res.cookie('token', token, { maxAge: 48 * 3600 * 1000, httpOnly: true });
    res.redirect(successRedirect);
  }
);

module.exports = router;
```

There are 2 parts, the first one is to let `passportjs` know how to handle `github` OAuth by setting the appropriate authentication strategy, the strategy has a set of options to configure the client ID/secret/callback for the OAuth service (pretty standard stuff) and a function to deal with the result. In this function, people usually check if the user has already created an account in the system using their external credentials (Github in this case) or not. If they have already had an account, update the account. Otherwise, create a new one. This function basically converts an external identity to an internal one.

The second part is to set up 2 routes, the first one is `/github` which is for the user to call when they need to authenticate themselves. The second one is `/github/callback` is the url to be called by Github OAuth server in order to send the result back. This url must match the one specified in Github OAuth settings.

If the user fails to authenticate, I just redirect them to the login url so that they can log in again. If everything is ok, I construct a JSON Web Token and store it in a cookie. This is to allow the subsequent requests to access the protected API.

In order to use the JSON web token, I also need to add a middleware to express to decrypt it. Fortunately, there is one [express-jwt](https://github.com/auth0/express-jwt)

```
app.use(jwt({
  secret: config.get('auth.secret'),
  requestProperty: 'token',
  credentialsRequired: false,
  getToken: function(req) {
    return req.cookies.token;
  }
}));
```

After this, the token can be accessed via `req.token` and it contains whatever I have signed using `jsonwebtoken` module after the user logged in.

Now that I have everything ready, I need to have a way to protect the API from unauthenticated requests. However, there are some API that I still want everyone to be able to access as well. In `express`, one can just add a middleware (which is basically a function) to intercept the current request.

```
function authenticated() {
  return (req, res, next) => {
    const {
      token
    } = req;

    if (token && token.user && token.user.id) return next();

    // from part 1
    res.jsonError({
      code: 403,
      message: 'Unauthenticated access',
      data: null
    }, 403);
  };
}
```

The usage is simple, put this middleware in front of the API that needs to be protected. For example

```
router.post('/', authenticated(), (req, res) => {
  service.createMessage(req.body.content).then(res.jsonData, res.jsonError);
});
```

With this I have the basic authentication part ready. The next step is to control what resources the user can access a.k.a authorization.

## Authorization
In this simple app, there are only 2 roles, `anonymous` and `user` that need to work with the API. An user can only delete/update their own messages. There are several ways of doing authorization, it can be done in the code or at database level (I will have another post about this later). For this chat app, I am going to do it in the code. I am using the same pattern as in the authentication process by defining a middleware to intercept the request.

```
function checkAuthor() {
  return (req, res, next) => {
    const {
      id
    } = Object.assign({}, req.query, req.args, req.params);

    const {
      token
    } = req;

    service.getMessageById(id).then((message) => {
      if (!message) return res.jsonError({
        code: 400,
        message: 'Message not found',
        data: {
          id
        }
      });

      // assuming that we always have the user because of authenticated middleware
      if (message.userId !== token.user.id) return res.jsonError({
        code: 403,
        message: 'Unauthorized access',
        data: {
          id
        }
      });

      next();
    }).catch((error) => {
      res.jsonError({
        code: 400,
        message: 'Failed to check access',
        data: null
      });
    });
  };
}
```

And use it in the end points that need to be protected. However, this middleware is not efficient because it needs to call `service.getMessageById`, which issues a sql query, everytime a request comes in. There are ways to optimize it but that is outside the scope of this post.

```
router.delete('/:id(\\d+)', authenticated(), checkAuthor(), (req, res) => {
  service.deleteMessage(parseInt(req.params.id, 10)).then(res.jsonData, res.jsonError);
});
```

With all that in place, I have an ok-ish API server with all the basic stuff such as authentication, authorization and data persistence. In the next part, I am going to implement the pub/sub messaging server and integrate it to the API server.

The code for this part can be found at [https://github.com/laoshanlung/simple-chat-api](https://github.com/laoshanlung/simple-chat-api/tree/part-2).
