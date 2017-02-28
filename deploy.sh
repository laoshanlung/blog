#!/bin/bash
ssh dokku@tannguyen.org apps:create tannguyen.org
touch public/.static
cp -fv .dokku/* public
tar c public | ssh dokku@tannguyen.org tar:in tannguyen.org
