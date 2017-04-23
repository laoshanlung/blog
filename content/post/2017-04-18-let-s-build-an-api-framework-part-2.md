+++
date = "2017-04-18T20:54:07+02:00"
title = "Let's build an API framework - Part 2"
tags = ['nodejs', 'javascript', 'express']
categories = ['Programming']
+++

This is the second and final part of "Let's build an API framework". In the previous part, I wrote about the general design and requirements for the API framework that I am going to build. In this part, I am going to implement it. The actual implementation might be slightly different from the design but the ideas stay the same.

<!--more-->

## Modular structure
This framework aims to provide a very thin abstract layer on top of existing frameworks and libraries. It does not reinvent the wheel. The framework consists of several layers but all of them are implemented separately and can be easily replaced.

- Route is the foundation of the framework. It provides an abstract syntax to define how an API should work.
- Engine is the execution part that takes the defined routes and build a complete web server using existing frameworks or libraries such as Express and Hapi.

The execution part is then divided into 5 phases

- Filter. This phase takes the raw input (usually a combination of querystring, body data and specific params set in the URL) and picks those that are defined in the route.
- Authentication. This phase identifies the request to establish an identity for the request so that it can be used later on to determine the permissions.
- Authorization. Based on the identity of the request, a set of permissions are assigned to the request in order to control which resources the request can access.
- Validation. In this phase, the filtered input from the first phase is validated using the rules defined in the route. This includes data type validation and other custom validation logic.
- Execution. This is the final phase, it takes the filtered and validated input and runs the main logic handler function defined in the route.

The first 4 phases are totally customizable by simply switching the implementation. The execution phase, on the other hand, is fixed.

## Main module
The main `ohmyapi` module makes use of builder pattern to build the final API app/server

```javascript
const ohmyapi = require('ohmyapi');

const app = ohmyapi(__dirname + '/routes/api')
            .engine('express', {
              prefix: '/api'
            })
            .filter('default')
            .authenticate(function(args, context) {

            })
            .authorize({
              isAdmin: function(args, context) {},
              isMod: function(args, context) {},
              isAllowedToDeleteSomething: function(args, context) {}
            })
            .validate('default')
            .init();
```

The actual magic happens in `Builder` class ([source code](https://github.com/tanqhnguyen/ohmyapi/blob/master/src/Builder.js)), it basically loads all the routes from the provided path and initialize the routes using the provided options. During this initialization, each phase can be customized by calling the appropriate method.

## Route
Route is the smallest unit in the framework, it represents an API. It has only one job which is to execute the main logic provided by the user (through `handle` function in the route file). It doesn't have any implementation for filtering, authentication, authorization and validation. Instead, those are passed to routes by the `Builder`. This kind of dependency injection is one way to make modules/components independent.

`Route` has a method called `run` which does all the phases mentioned above. There are other methods in the class as well but they mostly do initialization works, but you can take a look at the [source code](https://github.com/tanqhnguyen/ohmyapi/blob/master/src/Route.js) here for deeper understading how `Route` works

Here is what the `run` method looks like

```javascript
class Route {
  run(input, ctx) {
    const {
      args,
      handle,
      validate,
      filter,
      authenticate,
      authorize
    } = this;

    return Promise.try(() => {
      if (!filter) return input;
      return filter(input, args, ctx);
    }).then((filteredInput) => {
      input = filteredInput;
    }).then(() => {
      if (!authenticate) return true;
      return authenticate(input, ctx);
    }).then((result) => {
      if (!result) throw new Unauthenticated;
      if (!authorize) return true;
      return authorize(input, ctx);
    }).then((result) => {
      if (!result) throw new Unauthorized;
    }).then(() => {
      if (validate) return validate(input, args, ctx);
      return null;
    }).then((errors) => {
      if (errors) throw new InvalidInput(errors);
      return handle(input, ctx);
    });
  }
}
```

There is one thing to notice, all the phases can be either asynchronous or synchronous. But they must return `Promise` to do asynchronous stuff. Let's go through each phase.

### Filter
The first phase is to filter the input in order to make sure that the route always receives what it expects (from `args` option). The route receives a `filter` function passed to it from `Builder`. A filter is a simple function which takes the input and returns the parsed values. The main reason for the filtering step is that when a `GET` request is sent to the server, all of its querystring values are considered strings, even numbers and booleans. For example, with this request

```
GET /api/users?limit=10&role=member&verified=true
```

The input is

```
{
  limit: '10',
  role: 'member',
  verified: 'true'
}
```

But what I need is

```
{
  limit: 10,
  role: 'member',
  verified: true
}
```

The [default implementation](https://github.com/tanqhnguyen/ohmyapi/blob/master/src/filters/default.js) for filtering is a combination of using [auto-parse](https://github.com/greenpioneersolutions/auto-parse) and an option `default` in `args` to convert arguments to their correct type and set default values if possible.

### Authentication
Authentication happens next. If the route has `authenticate` set to `true` or a function, the authentication phase is triggered. Otherwise, it assumes that the route is for public access. If it's `true`, the global authenticate function, which is set during the initialization of the framework by the `Builder`, is used. If it's a function, the function is used instead.

The authenticate function is expected to return a truthly or falsy value to indicate if the request is authenticated or not. At first, I was thinking if I should return an object or null to indicate the authentication result. And then store the result in `context` so that the remaining phases can get the current "user" from `context.user`. However, applications tend to use different name/concept for that. Therefore, expecting truthly/falsy value is more appropriate in this case. And the current identity can always be set separately during this phase. For example,

```javascript
const app = ohmyapi(__dirname + '/routes/api')
            .authenticate(function(args, context) {
              return fetchUserForArgs(args).then((user) => {
                context.user = user ? user : null;
                return context.user;
              });
            });
```

### Authorization
Next is the authorization phase. The route can set its authorization function via `authorize` option, and this option accepts 3 values

- A string to refer to a predefined authorization function during the initialization.
- A function to do custom authorization logic.
- An array of strings and/or functions to combine multiple authorization functions. The final result is `true` if at least one function returns true, and `false` otherwise.

Skipping the `authorize` option or set it to a falsy value will ignore the authorization phase.

This phase is a bit more complicated compared to other phases as it involves multiple functions. All the hard works happen in the [Builder](https://github.com/tanqhnguyen/ohmyapi/blob/master/src/Builder.js#L99) so that `Route` can just call `authorize` with the current input and context. The logic is straightforward, `Builder` combines 3 different types of `authorize` option into 1 array of functions which will be executed by using `Promise.map`. Then, check the result for truthly values.

### Validation
Next phase is to validate the input. The route has an option called `args` which specifies the data types and validation rules for its arguments. The format of `args` depends on the implementation of the validation function. By default, `ohmyapi` uses [validatejs](https://validatejs.org/) to do the validation. However, `validatejs` is set as a peer dependency which makes it more flexible for adding custom validators. The [default implementation](https://github.com/tanqhnguyen/ohmyapi/blob/master/src/validators/default.js) adds 2 more validators

- `default` is used as a dummy validator that does nothing but to provide a default value for filtering phase
- `boolean` is for validating boolean values (true/false)

The validation function is expected to return `null` when everything is ok or an object containing the errors for each invalid attribute. For example,

```javascript
{
  content: [
    'Must be set'
  ],
  age: [
    'Must be greater than 0'
  ]
}
```

### Execution
The final step is to call `handle` function specified in the route file. This step is straightforward, just call the function with the (filtered) input and context.

## Engine
The idea of having an engine is to separate the execution part from the API definition syntax. Instead of using the specific web application framework (for example, express) to build an API, building an API is split into 2 parts. First define the API in a separate file using an abstract syntax and then build the application server using the web application framework of choice.

An engine needs to do 3 things

- Extract the input from the request.
- Build a context object. The context object must have a certain set of values and is shared through the whole execution process.
- Execute the `run` function of the route instance.

An engine is simply a function which receives a list of routes that it needs to process and an optional `options` object containing specific setttings for the framework/library used.

`ohmyapi` comes with [express engine](https://github.com/tanqhnguyen/ohmyapi) which extracts the input from the request by doing

```javascript
function getInput(req) {
  return Object.assign({}, req.query, req.body, req.params);
}
```

and builds the context with the following values

```javascript
function buildContext(req) {
  return {
    cookies: _.cloneDeep(req.cookies),
    params: _.cloneDeep(req.params),
    query: _.cloneDeep(req.query),
    body: _.cloneDeep(req.body),
    path: req.originalUrl,
    headers: _.cloneDeep(req.headers),
    session: req.session,
    method: req.method.toLowerCase()
  };
};
```

The process of building the actual usable API is done via a simple `forEach` loop

```javascript
routes.forEach((route) => {
  const path = route.getPath(),
        method = route.getMethod(),
        args = route.getArgs();

  app[method](`${prefix}${path}`, function(req, res) {
    let input = getInput(req);
    const context = buildContext(req);

    return route.run(input, context).then((result) => {
      res.json(success(result));
    })
    .catch((error) => {
      const status = error.status || 400;
      res.status(status).json(failure(error));
    });
  });
});
```

With all that said and done, I have a dead simple API framework that can help me build a prototype in minutes. The source code can be found here [https://github.com/tanqhnguyen/ohmyapi](https://github.com/tanqhnguyen/ohmyapi). I will probably need to write a proper documentation for it.
