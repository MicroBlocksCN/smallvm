#!/bin/sh

print_help() {
    echo "Usage: ./ssh-serial.sh [REMOTE-IP] [REMOTE-USERNAME] [REMOTE-PORTNAME]"
    echo
    echo "Examples:"
    echo "./ssh-serial.sh 192.168.1.124 pi /dev/pts/1"
    echo "./ssh-serial.sh myserver.com user /dev/ttyUSB0"
    echo
    exit 0
}

if test $# -eq 0; then print_help; fi

if ! [ -x "$(command -v socat)" ]; then
    echo "Please install socat to run this utility."
    echo "In Debian-based system you can do so by running:"
    echo
    echo "sudo apt-get install socat"
    echo
    exit 0
fi

ip=$1
user=$2
port=$3

ssh -fNCo "ExitOnForwardFailure yes" -L 54333:localhost:54321 $user@$ip "nc -l localhost 54321 <$port >$port"
success=$?
socat pty,link=$HOME/remotepts,wait-slave tcp:localhost:54333 &
success="$success,$?"

if [ $success = "0,0" ]; then
    echo "Port bridge over SSH to $ip created."
    echo "Connect to the remote port by specifying $HOME/remotepts as your serial port in MicroBlocks."
else
    echo "Failed to create bridge over SSH to $ip.  Please make sure that:"
    echo
    echo "  * The netcat utility is installed in the remote system"
    echo "  * SSH has been enabled in the remote system"
    echo "  * Port $port exists in the remote system"
    echo "  * User $user exists in the remote system"
    echo "  * The IP for the remote system is actually $ip"
fi
