#!/bin/bash
hugo
ssh dokku@tannguyen.org apps:create blog
ssh dokku@tannguyen.org domains:add blog tannguyen.org
ssh dokku@tannguyen.org letsencrypt blog
touch public/.static
cp -fv .dokku/* public
tar c public | ssh dokku@tannguyen.org tar:in blog
