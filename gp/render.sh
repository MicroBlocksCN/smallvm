#!/bin/sh
(cd /home/git/smallvm/gp; ./gp-linux64bit runtime/lib/* ../ide/* renderScript.gp - --jsonFile /tmp/json)
