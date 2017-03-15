+++
date = "2017-03-15T20:54:07+02:00"
title = "Let's build an API framework - Part 1"
tags = ['nodejs', 'javascript', 'expressjs']
categories = ['Programming']
+++

Today, I am going to take a break from the simple chat app series because I want to build something else for a change. During my work, I usually have to work with APIs a lot from integrating with existing APIs to building a new one for internal or external uses. I have tried a lot of different frameworks and even built one for my master's thesis.

<!--more-->

For the project that I am working one, I came up with an idea on how to build an API on top of the famous [Express](https://expressjs.com/) framework. It is actually not new because I have used a similar concept for a project I did 4 or 5 years ago, and I bet somebody somewhere has already created a similar (or exactly the same) one. This is (yet) another series on how I build a simple API framework on top of other existing frameworks such as Express. There are 3 parts, the first part (this post) is for the design of the framework. The next 2 parts are for the implementation.

## Basic requirements for an API framework
During my short time of working with APIs (and building them). I can see there are several basic needs for an API framework to make it easier and faster to build an API.

- Authentication. Be able to ask "Who is it?"
- Authorization. Be able to ask "What can it do?"
- Validation. Be able to validate the requests
- Extensibility. Adding more stuff must be easy and fast
- Testability. Writting unit tests does not cost a whole day setting up
- Consistency. The response format must be consistent

With all those in mind, I am going to implement a very simple API framework (let's call it `ohmyapi`) on top of Express. The framework is not necessarily REST-compliant but it follows a lot of REST principles.

## Routes
Although the framework is said to be built on top of Express, it should have an abstraction layer so that it can switch to use another web framework (Hapi, Koa you name it). The abstraction layer can just be the files that define how end points are constructed. Let's call those files "routes". Each end point corresponds to one file. For example

```
GET /api/v1/posts -> /project-name/api/v1/posts/list.js
POST /api/v1/posts -> /project-name/api/v1/posts/create.js
```

Each file defines a set of options to let the framework know how to construct a particular path. For example

```
// /project-name/api/v1/posts/list.js
module.exports = {
  method: 'get',
  path: '/',
  handler: function() {}
}
```

The final API is the path to the file and whatever defined in `path`.

- If the file path is `v1/posts/list.js` and there is no `path` specified, the final API path is `/v1/posts/list`.
- If the file path is `v1/posts/list.js` and the route set `path` to `/`, the final API path is `/v1/posts`

There are also options to specify the `prefix` and where to look for routes during the initialization.

```
const Api = require('ohmyapi');

const api = new Api({
  routes: __dirname + '/api',
  prefix: '/api'
});
```

## Arguments and context
There are 2 objects that will be passed around the routes and other related functions `args` and `context`. The idea is that

- `args` contains the input sent to the server. It is a combination of the query string and body data or URL params. For example in Express, it is the combination of `req.query`, `req.body` and `req.params` (let's skip file uploading for now)

- `context` is the data about the current request such as cookies, session, current path or other data added during the execution

## Validation
The validation process is there to make sure that only valid arguments are passed to the routes, and it is not the responsibility of the routes to validate the input, they just need to do the computation and return the result.

Input validation varies from string matching to make sure that an email does not exist in the database. The validation rules are defined in the route itself.

```
module.exports = {
  method: 'post',
  path: '/members',
  handler: function(args, ctx) {},
  args: {
    name: {
      string: true,
      required: true
    },
    age: {
      number: {
        onlyInteger: true,
        gte: 1, // greater than or equal
        lte: 100, // less than or equal
        message: 'Age must be between 1 and 100'
      },
      required: true
    },
    gender: {
      oneOf: {
        values: ['male', 'female'],
        message: 'Sorry, best I can do is 2'
      }
    }
  }
}
```

The validation process happens right after receiving the request, and it makes sure that `args` (passed to `handler` or other functions) contains valid data.

## Authentication
The authentication happens in a simple function provided when initializing the framework. This function returns the identity of the current request or `null` to indicate that the request is anonymous.

```
const Api = require('ohmyapi'),
      jwt = require('jsonwebtoken');

const api = new Api({
  authenticate: function(args, context) {
    // for example, get the user from the web token
    jwt.verify(context.cookies.token, cert, function(err, decoded) {
      if (err) return cb(err);
      callback(null, decoded.user);
    });
    // or the Promise version
    return new Promise(function(resolve, reject) {
      jwt.verify(context.cookies.token, cert, function(err, decoded) {
        if (err) return reject(err);
        resolve(decoded.user);
      });
    });
  }
});
```

Then the route can specify whether it needs authentication or not. It's quite often that I want an API to be public.

```
module.exports = {
  method: 'get',
  path: '/members',
  handler: function() {},
  authenticated: true
}
```

## Authorization
This process comes right after the authentication. There are many ways to do authorization such as role-based access control list. But for `ohmyapi`, I am going to use a much simpler approach. Each route has its own authorization functions, and those functions verify the request to make sure that it has sufficient permissions to access the route.

```
module.exports = {
  method: 'get',
  path: '/members',
  handler: function() {},
  authenticated: true,
  authorize: function(args, ctx) {},
  // or an array of functions, if any of them returns false,
  // the request fails
  authorize: [
    isMember,
    shouldBelongToSomeGroup
  ]
}
```

This approach is simple but very powerful as it allow granular control of the routes.

In the next 2 parts, I am going to implement an API framework following the above design.
