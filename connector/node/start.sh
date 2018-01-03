#!/bin/sh
if ! test -e node_modules; then
    echo "Missing some node.js modules. I'll try to install them for you now."
    if ! test -n `which npm`; then
        echo "Missing node.js package manager (npm). Please check https://www.npmjs.com/get-npm for instructions on how to install it for your system."
        exit 1
    else
        npm install
    fi
fi

node index.js $*
