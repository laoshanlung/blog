+++
date = "2017-02-08T11:52:29+02:00"
title = "Set up Hugo, Dokku and Travis"
tags = ['hugo', 'dokku', 'travis']
categories = ['Programming']
+++

Setting up your own blog has never been easier. With less than an hour, one can have a blog up and running even without any Ops experience like myself

<!--more-->

In this post, I am going to write about the process of setting up my blog using Hugo, Dokku and Travis

The goal is to have an automatic workflow where I can write my posts in peace and just push everything to `master` when it's finished.

### Hugo
[Hugo](https://gohugo.io/) is a static website generator. It can be used for building all kind of static websites such as blog, personal home page etc...

It's written in Go but you don't need to have any Go knowledge in order to use it. It's designed to be as easy to use as possible. I am not going to explain how to use Hugo, its website has everything documented.

### Dokku
After writting a blog post, Hugo will generate a static HTML page for it and I will need to deploy the static pages to somewhere.

Since the task is simple, set up a nginx (or whatever static file server) and put all the files generated by Hugo there, I will choose [Dokku](http://dokku.viewdocs.io/dokku/). There are other tools out there but they are more focusing on large deployment.

Dokku is a tool to manage and deploy Docker containers. Installing Dokku is simple

```bash
wget https://raw.githubusercontent.com/dokku/dokku/v0.8.0/bootstrap.sh
sudo DOKKU_TAG=v0.8.0 bash bootstrap.sh
```

After that, I need to go to the web installer (usually the domain name or the server IP address). Just follow the instructions and everything will be fine.

Using Dokku is also simple, I need to

- Specify the app configuration so that Dokku knows how to deploy the app. It can be as simple as adding a file to the project or it can be as complex as writing custom `Dockerfile` to install dependencies.

- Push the code to Dokku server (it can be either Git push or normal tar deployment). In this setup, I am going to use tar deployment because it's simpler and easier to set up

### Travis
The final piece is a continuous integration service which will automatically deploy the `master` branch to Dokku server. I choose [Travis](https://travis-ci.org/) because it's free and has ok-ish integration with Github.

With Travis, all I have to do is to sign up using my Github account and choose which repository I want it to manage. Then I also need to add several configurations for the deployment

#### Build the project
Travis supports custom build process using `.travis.yml` file. This file defines the build configuration for Travis to know how to build the container for running the project and what to do afterward.

```
language: go

go:
  - 1.7.x

install:
  - go get -v github.com/spf13/hugo

script:
  - hugo
```

This is the basic process for building the blog. Since I am using Hugo which requires Go, I set the language for the container to Go. In `install` step, I simply ask Travis to install Hugo for me. And after that, generate the static HTML files by running `hugo`

#### Connect to Dokku
Now that I have all the static files, I need to talk to my Dokku server to publish them. With the following actions (set in `.travis.yml` file), I am granting the permission to Travis to connect to my Dokku server

```
after_success:
  - eval "$(ssh-agent -s)"
  - chmod 600 .travis/deploy_key.pem
  - ssh-add .travis/deploy_key.pem
  - mv -fv .travis/ssh_config ~/.ssh/config
  - ssh dokku@tannguyen.org apps:create tannguyen.org
```

The first 3 commands are to prepare the private key for Travis container to connect to my Dokku server.

But first thing first, I need to have a pair of public/private key. I use the following command to generate a new public/private key pair with the name `deploy_key` in my `~/.ssh` folder

```
ssh-keygen -t rsa -b 2048 -v
```

After running the command, there are 2 keys `deploy_key` (private) and `deploy_key.pub` (public). I need to add the public key to Dokku server so that any server with the private key can access it.

```
cat ~/.ssh/deploy_key.pub | ssh root@tannguyen.org "sudo sshcommand acl-add dokku Travis"
```

As for the private key, I need to encrypt it and add it to my project for security reasons. Fortunately, Travis comes with a tool for encrypting stuff.

```
gem install travis
travis login
cp ~/.ssh/deploy_key ./.travis/deploy_key.pem
travis encrypt-file ./.travis/deploy_key.pem
rm ./.travis/deploy_key.pem
```

Now that I have the encrypted version of the private key, I need to tell Travis to decrypt it before it can use it. There is a `before_install` hook to do that. After `travis encrypt-file` command, Travis creates 2 environment variables for your project (check the settings tab), it will use those variables to encrypt the file later.

```
before_install:
  - openssl aes-256-cbc -K $encrypted_b2a3a07f2f2c_key -iv $encrypted_b2a3a07f2f2c_iv -in .travis/deploy_key.pem.enc -out .travis/deploy_key.pem -d
```

The 4th command `mv -fv .travis/ssh_config ~/.ssh/config` is just to get rid of the confirmation message when the container connects to an unknown host.

```
The authenticity of host '_ (_)' can't be established.
ECDSA key fingerprint is _.
Are you sure you want to continue connecting (yes/no)?
```

The content of `ssh_config`

```
Host tannguyen.org
StrictHostKeyChecking no
User dokku
PasswordAuthentication no
CheckHostIP no
BatchMode yes
```

The 5th one `ssh dokku@tannguyen.org apps:create tannguyen.org` is to create a new Dokku app. In this case, I am going to deploy my blog to the main domain, so I use the full domain name. In order to deploy it to subdomain (blog.tannguyen.org for example), I just need to change to `ssh dokku@tannguyen.org apps:create blog`

#### Deploy to Dokku
![deploy-all-the-code](/images/deploy-all-the-code.jpg)

The final step is to tell Travis to deploy the `public` folder which is generated by Hugo in `script` hook. Continue from the above `after_success` hook, I need to add 2 more commands

```
after_success:
  - touch public/.static
  - tar c public | ssh dokku@tannguyen.org tar:in tannguyen.org
```

The idea is to deploy only the public folder since it's what I want to serve (my blog). And I am going to use `tar` deployment instead of git deployment because of its simplicity to set up.

Dokku comes with a nginx buildpack. A buildpack is basically a set of commands to build the container. Dokku usually detect the buildpack to use by itself (for Node, Ruby, Python etc... application), but for static sites, it needs to look for `.static` file. And that is what the first command does, it creates a `.static` file in `public folder`

The next command is to pack the public folder into a tar file and push it to Dokku server. If I want to use git, it would be something like this

```
git remote add dokku dokku@tannguyen.org:tannguyen.org
git add public -f
git commit -m "Travis build"
git push dokku master -f
```

And with that I have a fully automatic deployment process. Now I just need to focus on blogging and let Travis handle the deployment.

The source code for my blog can be found [here](https://github.com/laoshanlung/blog). There are some extra stuff such as syntax highlighting and custom nginx config. I will cover them in another post.