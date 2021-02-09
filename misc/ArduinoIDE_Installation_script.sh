#! /bin/bash
if [[ $EUID != 0 ]] ; then
  echo This must be run as root!
  exit 1
fi
 
if [ "$1" = "" ] 
then
    echo "Run the script with command sudo ./ArduinoIDE_Installation_script.sh \$USER"
else
    echo "******* Add User to dialout,tty, uucp, plugdev groups *******"
    sudo adduser $1 dialout
    sudo adduser $1 uucp
    sudo usermod -a -G tty $1
    sudo usermod -a -G dialout $1
    sudo usermod -a -G uucp $1
    sudo groupadd plugdev
    sudo usermod -a -G plugdev $1
 
    echo "******* Removing modem manager *******"
    #Only for Ubuntu
    sudo apt-get remove modemmanager
 
    #Only for Suse
    sudo zypper remove modemmanager
   
    #Red Hat/Fedora/CentOS
    sudo yum remove modemmanager
 
    echo "******* Setting up udev rules *******"
    echo "Serial port rules"
    
	sudo echo "KERNEL=\"ttyUSB[0-9]*\", TAG+=\"udev-acl\", TAG+=\"uaccess\", OWNER=\"$1\"
KERNEL=\"ttyACM[0-9]*\", TAG+=\"udev-acl\", TAG+=\"uaccess\", OWNER=\"$1\"" > /etc/udev/rules.d/90-extraacl.rules
    
	echo "Adding Arduino M0/M0 Pro Rules"    
	sudo echo "	
ACTION!=\"add|change\", GOTO=\"openocd_rules_end\"
SUBSYSTEM!=\"usb|tty|hidraw\", GOTO=\"openocd_rules_end\"

#Please keep this list sorted by VID:PID

#CMSIS-DAP compatible adapters
ATTRS{product}==\"*CMSIS-DAP*\", MODE=\"664\", GROUP=\"plugdev\"

LABEL=\"openocd_rules_end\"" > /etc/udev/rules.d/98-openocd.rules

	echo "Adding AVRISP Rules"
	sudo echo "SUBSYSTEM!=\"usb_device\", ACTION!=\"add\", GOTO=\"avrisp_end\"

# Atmel Corp. JTAG ICE mkII
ATTR{idVendor}==\"03eb\", ATTRS{idProduct}==\"2103\", MODE=\"660\", GROUP=\"dialout\"
# Atmel Corp. AVRISP mkII
ATTR{idVendor}==\"03eb\", ATTRS{idProduct}==\"2104\", MODE=\"660\", GROUP=\"dialout\"
# Atmel Corp. Dragon
ATTR{idVendor}==\"03eb\", ATTRS{idProduct}==\"2107\", MODE=\"660\", GROUP=\"dialout\"

LABEL=\"avrisp_end\"" > /etc/udev/rules.d/avrisp.rules
    
 
    echo "Restarting udev"
    sudo service udev restart
    sudo udevadm control --reload-rules
    sudo udevadm trigger 
    
    
    echo "*********** Please Reboot your system ************"
fi
