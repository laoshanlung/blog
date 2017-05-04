+++
date = "2017-05-03T20:16:36+03:00"
title = "Set up rTorrent using Dokku"
tags = ['rtorrent', 'dokku', 'docker']
categories = ['Programming']
+++

Having a BitTorrent seedbox is convenient in many ways. Few days ago, I needed to download something (totally legal!) using BitTorrent, but I don't want to open my laptop 24/7 for seeding. Since I already have a dokku server up and running, I can just set up a BitTorrent seedbox using [rtorrent](https://github.com/rakshasa/rtorrent) and [ruTorrent](https://github.com/Novik/ruTorrent)

<!--more-->
The method is to use dokku's [image tag deployment](http://dokku.viewdocs.io/dokku/deployment/methods/images/) to set up a new app. But first I need to have a docker image for rTorrent and ruTorrent. Fortunately, there is one [Kerwood/Rtorrent-LXC](https://github.com/Kerwood/Rtorrent-LXC), so I am not going to repeat myselft.

First I need to create a new app
```
ssh dokku@tannguyen.org apps:create torrent
```

Then, I need to pull the **Rtorrent-LXC** image from docker hub into my local machine

```
docker pull kerwood/rtorrent-lxc
```

Then, retag it to follow dokku's conventions

```
docker tag kerwood/rtorrent-lxc dokku/torrent:v1
```

However, this image is stored in my local machine, I need to push it to the dokku server before I can do any deployment

```
docker save dokku/torrent:v1 | bzip2 | ssh root@tannguyen.org "bunzip2 | docker load"
```

With that I have the image loaded to my dokku server, now the actual deployment can happen

```
ssh dokku@tannguyen.org tags:deploy torrent v1
```

It will take some minutes, and after that everything is (almost) ready. There are few things I need to take care afterward

### Port mapping
The default port mapping is `http:80:5000` which means to map port 5000 of the container to port 80 in the nginx virtual host, but according to **Rtorrent-LXC**, it runs `rutorrent` on port 80. So I need to change the port mapping from 5000 to 80

```
ssh dokku@tannguyen.org config:set torrent DOKKU_PROXY_PORT_MAP=http:80:80
```

### Security
By default, the deployed app can be accessed by anyone. And I don't really want to allow that. There is a plugin to provide basic access authentication for dokku apps, [dokku-secure-apps](https://github.com/matto1990/dokku-secure-apps.git).

I need to install the plugin first, and it can only be done using a user with `sudo` permission. But I am going to use `root` because I can

```
ssh root@tannguyen.org dokku plugin:install https://github.com/matto1990/dokku-secure-apps.git secure-apps
```

The next step is to create an identity

```
ssh dokku@tannguyen.org secure:set torrent my-user super-duper-strong-password
ssh dokku@tannguyen.org secure:enable torrent
```

### Get the downloaded files
Downloaded files are stored within the docker container, I need to mount the download directory to a directory in the host in order to access the downloaded files. Dokku comes with a plugin [docker-options](https://github.com/dokku/dokku/blob/master/docs/advanced-usage/docker-options.md) to make it easy to specify docker options

```
ssh dokku@tannguyen.org docker-options:add torrent run "-v /home/dokku/torrent/downloads:/downloads"
ssh dokku@tannguyen.org docker-options:add torrent deploy "-v /home/dokku/torrent/downloads:/downloads"
```

Note that `/home/dokku/torrent/downloads` must be created beforehand and must be owned by `dokku:dokku`.

### Some problems
- Whenever I re-deploy the app, everything I have downloaded so far is gone. It's not a big problem because for this app, I don't think I will need to re-deploy it

- rTorrent occasionally crashes. And when it happens I need to go inside the docker container to start `rtorrent` again. I am not sure what causes it yet, only saw it once since the deployment.

### Happy torrenting!!!
