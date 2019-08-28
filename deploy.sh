#!/bin/bash
HOST=tannguyen.org
hugo
ssh dokku@${HOST} apps:create blog
ssh dokku@${HOST} domains:add blog tannguyen.org
ssh dokku@${HOST} config:set --no-restart blog DOKKU_LETSENCRYPT_EMAIL=tan.qh.nguyen@gmail.com
ssh dokku@${HOST} letsencrypt blog
touch public/.static
cp -fv .dokku/* public
tar c public | ssh dokku@${HOST} tar:in blog
