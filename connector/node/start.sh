#!/bin/sh
if ! test -e node_modules; then
    echo "Missing some node.js modules. I'll try to install them for you now."
    if ! test -n `which npm`; then
        echo "Missing node.js package manager (npm). Please check https://www.npmjs.com/get-npm for instructions on how to install it for your system."
        exit 1
    else
        npm install
        curl -OL https://github.com/zaaack/node-systray/raw/master/traybin/tray_darwin
        curl -OL https://github.com/zaaack/node-systray/raw/master/traybin/tray_darwin_release
        mv tray_darwin* node_modules/systray/traybin
        chmod +x node_modules/systray/traybin/*darwin*
    fi
fi

node index.js $*
