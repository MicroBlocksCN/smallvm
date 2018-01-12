#!/bin/sh
unzip ../build/ublocks-linux.zip
sudo cp -rf ublocks /usr/local
sudo cp ublocksd /usr/local/ublocks
rm -rf ublocks

# Run the connector when our (mainstream) desktop environment starts
# Since the daemon kills and restarts itself when it's invoked, the 
# tray icon will show up even if we had the daemon already running
sudo cp ublocks.desktop /etc/xdg/autostart/

# Run the connector even if we do not run a mainstream desktop environment
# Files under profile.d need to have the sh extension
sudo ln -s /usr/local/ublocks/ublocksd /etc/profile.d/ublocksd.sh
