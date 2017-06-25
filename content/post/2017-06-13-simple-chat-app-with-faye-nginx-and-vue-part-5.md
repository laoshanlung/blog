+++
date = "2017-06-13T20:45:40+03:00"
title = "Build a simple chat web app using Faye, Express and Vue - Part 5"
tags = ['dokku']
categories = ['Programming']
+++

In the previous part, I implemented the UI using Vue. In this part, I am going to write about the deployment process using `dokku`. This simple chat app is split into 3 separate services `api`, `faye` and `web`. Each service can be deployed independently without affecting other running services.

<!--more-->
Let's look at the final result first. The application is deployed to [http://simple-chat.tannguyen.org](http://simple-chat.tannguyen.org/#/) which contains the production version (built and minified JS code) of the web UI. This UI connects to the API server at [http://simple-chat-api.tannguyen.org](http://simple-chat-api.tannguyen.org) which contains the code for `api` service. And finally, `faye` service is deployed to [ws://simple-chat-faye.tannguyen.org](ws://simple-chat-faye.tannguyen.org)

This kind of setup seems to be too complicated for this tiny application. However, as the application gets bigger, this setup really shines. Imagine that when your application grows bigger, you will probably have more independent services, let say 10 of them. Once you make new changes to the UI, you probably don't want to deploy the UI code together with all 9 other services which are exactly the same as they were before. With the current state of technology, deploying 9 more services to one server is nothing. But when you have 100 servers, this becomes a huge problem because you are unnecessarily deploying all of your services to all of your servers every time you change one line of code in any of your services. This setup also makes it easier to scale one particular service. Since each service is implemented as an isolated component, I can easily monitor and scale services that are under extensive use.

## Deploy api service
Let's look at the final `deploy.sh` script first

```bash
#!/bin/bash
ssh dokku@tannguyen.org apps:create simple-chat-api
tar --exclude='src/chat.sqlite' -cv src package.json start.js -C .dokku CHECKS | ssh dokku@tannguyen.org tar:in simple-chat-api
```

First, I need to create the dokku app named `simple-chat-api`. Then, I can simply do a tar deployment. The tar part is quite tricky. I usually put dokku specific files (`CHECKS` for example) into `.dokku` folder. So, my tar command consists of 2 parts

- First part gets all the necessary files and folders in the root directory (src, package.json and start.js). Since I am using sqlite, I also want to exclude it
- Second part changes the working directory to `.dokku` and appends `CHECKS` file to the tar content

Finally, the tar content is pushed to the dokku server and dokku will take care the rest.

## Deploy faye service
The `deploy.sh` script for `faye` service is almost the same as that of `api` service

```bash
#!/bin/bash
ssh dokku@tannguyen.org apps:create simple-chat-faye
tar -cv src package.json start.js -C .dokku CHECKS nginx.conf.sigil | ssh dokku@tannguyen.org tar:in simple-chat-faye
```

The difference here is the new `nginx.conf.sigil` file. This file basically overwrites the default nginx config that dokku uses. The reason for this setup is to allow cross-domain communication.

In `api` service, I handle this at the code level using this middleware for express.

```javascript
app.use(require('cors')({
  origin: config.get('web.url'),
  credentials: true
}));
```

I can do the same for `faye` service but I will do something else to demonstrate a different way to allow cross-domain communication. The [nginx config](https://github.com/tanqhnguyen/simple-chat-faye/blob/master/.dokku/nginx.conf.sigil) has these 4 extra headers added to allow cross-domain communication

```
add_header 'Access-Control-Allow-Origin' 'http://simple-chat.tannguyen.org';
add_header 'Access-Control-Allow-Credentials' 'true';
add_header 'Access-Control-Allow-Methods' 'GET, POST, DELETE, PUT, OPTIONS';
add_header 'Access-Control-Allow-Headers' '*';
```

This approach is powerful but not practical because now I have to hard-code the web UI domain in the nginx config template. With the approach in `api` service, everything is centralized in one config file which makes it easier to manage and maintain.

## Deploy web service
This process is similar to the other 2 services with 2 extra steps

```
#!/bin/bash
ssh dokku@tannguyen.org apps:create simple-chat
NODE_ENV=production npm run build
touch dist/.static
tar c dist | ssh dokku@tannguyen.org tar:in simple-chat
```

First step is to build the production files using webpack. Second step is to tag this deployment as `static` by creating an empty file named `.static` to let dokku know that it should use [nginx-buildpack](https://github.com/dokku/buildpack-nginx) to build `web` app.

## Final thoughts
With this simple chat app, I have demonstrated how to develop and deploy a project using Nodejs (express, faye), Vue and Dokku. I am using this same kind of structure at work and for my hobby projects. I am pretty happy with it and don't have any problem so far.

I have a positive impression about Vue as a front-end development framework. It's very simple to get into, the learning curve is not as big as I thought. I will definitely use it for my next hobby project, and if possible try to use it at work.
