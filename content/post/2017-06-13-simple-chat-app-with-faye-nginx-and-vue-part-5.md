+++
date = "2017-06-13T20:45:40+03:00"
title = "Build a simple chat web app using Faye, Express and Vue - Part 5"
tags = ['dokku']
categories = ['Programming']
+++

In the previous part, I implemented the UI using Vue. In this part, I am going to write about the deployment process using `dokku`. This simple chat app is split into 3 separate services `api`, `faye` and `web`. Each service can be deployed separately without affecting other running services.

<!--more-->
## Deploy api service
Let's look at the final `deploy.sh` script first

```bash
#!/bin/bash
ssh dokku@tannguyen.org apps:create simple-chat-api
tar --exclude='src/chat.sqlite' -cv src package.json start.js -C .dokku CHECKS | ssh dokku@tannguyen.org tar:in simple-chat-api
```

First, I need to create the dokku app named `simple-chat-api`. Then, I can simply do a tar deployment. The tar part is quite tricky. I usually put dokku specific files (`CHECKS` for example) into `.dokku` folder. So, my tar command needs consists of 2 parts

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

I can do the same for `faye` service but I will do something else to demonstrate a different way to allow cross-domain communication. The [nginx config](https://github.com/tanqhnguyen/simple-chat-faye/blob/master/.dokku/nginx.conf.sigil) has there 4 extra headers added to allow cross-domain communication

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

## Final thought
With this final part, I have a very simple chat app with complete deployment process. The only missing piece is a continous integration service to automatically deploy the application.

I am pretty happy with Vue so far, it offers a nice and fast way to build user interface. However, I think that I will not use it for production yet because it's still quite new which makes it hard to build a team around it.
