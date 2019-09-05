+++
date = "2019-09-05T11:52:29+02:00"
title = "One year hiatus and a new home for my blog"
tags = []
categories = ['Programming']
+++

It has been (maybe more than) a year since my last post. One year ago, I decided that I should start doing something else other than sitting in front of my laptop building random stuff. It's not only unhealthy but also slowly killing my motivation to build things. And I am glad that I did it. I spent my free time collecting and playing board games, my collection has grown from few games to more than 100 games now. I guess too much of something is not good and it's time to get back to building random stuff. Anyway, if you happen to live in Helsinki area and need a gaming partner, hit me up.

<!--more-->

First thing I did when I got back was to migrate my blog to a new home. I have been a faithful customer of [DigitalOcean](https://www.digitalocean.com/) for more than 5 years, and it's time to move on. Not that there is anything wrong with DigitalOcean, on the contrary, they have been great so far. But I just want to experience something else.

At work, we are using [Hetzner](https://www.hetzner.com/) (I still can't spell their name correctly on one try), so I am curious and check out their cloud offering. And to my surprise, with half of what I was paying for DigitalOcean, I can get a slightly better cloud server (10TB more SSD space and 1GB more). Since I am not reviewing and advertising Hetzner, I will stop my rambling non-sense here.

With all the server setup (and paid for), now it's time to move my blog to a new home. Since I use a very simple [setup](/2017/02/set-up-hugo-dokku-and-travis/), moving everything over should be a piece of cake. Well, it's true, the only problem I had was the SSH key I generated for the old server, it took me a while to remember where I store it. But hey, I can just copy the one in the old server from whatever `~/.ssh` folder it is. Did that and voilà everything is ready. Or at least I thought it was...

It turns out that my hugo version is too out of date, I have to update it and with the update comes a bunch of code changes. It took a while to figure out all the changes but I finally did it. And this blog now is hosted by Hetzner