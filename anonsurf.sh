#!/bin/bash

### BEGIN INIT INFO
# Provides:          anonsurf
# Required-Start:
# Required-Stop:
# Should-Start:
# Default-Start:
# Default-Stop:
# Short-Description: Transparent Proxy through TOR.
### END INIT INFO
#
# Devs:
# Lorenzo 'Palinuro' Faletra <palinuro@parrotsec.org>
# Lisetta 'Sheireen' Ferrero <sheireen@autistiche.org>
# Francesco 'Mibofra' Bonanno <mibofra@parrotsec.org>
#
# Extended:
# Daniel 'Sawyer' Garcia <dagaba13@gmail.com>
#
# Port to Ubuntu:
# https://github.com/moonchitta
#
# Port from Ubuntu to WSL2 Ubuntu:
# Marcel 'Paranoik' Pewny
#
# anonsurf is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# You can get a copy of the license at www.gnu.org/licenses
#
# anonsurf is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Parrot Security OS. If not, see <http://www.gnu.org/licenses/>.


export BLUE='\033[1;94m'
export GREEN='\033[1;92m'
export RED='\033[1;91m'
export RESETCOLOR='\033[1;00m'


# Destinations you don't want routed through Tor
TOR_EXCLUDE="192.168.0.0/16 172.16.0.0/12 10.0.0.0/8"

# The UID Tor runs as
# change it if, starting tor, the command 'ps -e | grep tor' returns a different UID
TOR_UID="tor"
TOR_PID="/var/run/tor/tor.pid"

# Tor's TransPort
TOR_PORT="9040"


function notify {
	if [ -e /usr/bin/notify-send ]; then
		/usr/bin/notify-send "AnonSurf" "$1"
	fi
}
export notify


function init {
	echo -e -n "$BLUE[$GREEN*$BLUE] anonsurf-ubuntu will only work on ubuntu\n"
	echo -e -n "$BLUE[$GREEN*$BLUE] killing dangerous applications\n"
	sudo killall -q chrome dropbox iceweasel skype icedove thunderbird firefox firefox-esr chromium xchat hexchat transmission steam firejail
	echo -e -n "$BLUE[$GREEN*$BLUE] Dangerous applications killed\n"
	notify "Dangerous applications killed"

	echo -e -n "$BLUE[$GREEN*$BLUE] cleaning some dangerous cache elements\n"
	bleachbit -c adobe_reader.cache chromium.cache chromium.current_session chromium.history elinks.history emesene.cache epiphany.cache firefox.url_history flash.cache flash.cookies google_chrome.cache google_chrome.history  links2.history opera.cache opera.search_history opera.url_history &> /dev/null
	echo -e -n "$BLUE[$GREEN*$BLUE] Cache cleaned\n"
	notify "Cache cleaned"
}


function ip {

	MYIP=`wget -qO- https://ipinfo.io/ip`
	echo -e "\nMy ip is:\n"
	echo $MYIP
	echo -e "\n"
	notify "My IP is:\n\n$MYIP"
}


function start {
	# Make sure only root can run this script
	ME=$(whoami | tr [:lower:] [:upper:])
	if [ $(id -u) -ne 0 ]; then
		echo -e -e "\n$GREEN[$RED!$GREEN] $RED $ME R U DRUNK?? This script must be run as root$RESETCOLOR\n" >&2
		exit 1
	fi
	echo -e "\n$GREEN[$BLUE i$GREEN ]$BLUE Changin torrc file for anonsurf\n"
	if [ -e /etc/tor/torrc ]; then
 		mv /etc/tor/torrc /etc/tor/torrc.orig
	fi
	if [ -e /etc/anonsurf/torrc ]; then
 		cp /etc/anonsurf/torrc /etc/tor/torrc
	fi

	echo -e "\n$GREEN[$BLUE i$GREEN ]$BLUE Starting anonymous mode:$RESETCOLOR\n"

	echo -e "\n$GREEN*$BLUE Stop tor if its running\n"
	service tor stop

	if [ ! -e $TOR_PID ]; then
		echo -e " $RED*$BLUE Tor is not running! $GREEN starting it $BLUE for you" >&2
		service tor start
		sleep 20
	fi

	TOR_UID=$(<"$TOR_PID")
	echo -e -n "\n $GREEN*$BLUE Tor is running with PID: $TOR_UID\n"

	if ! [ -f /etc/network/iptables.rules ]; then
		/sbin/iptables-save > /etc/network/iptables.rules
		echo -e "\n $GREEN*$BLUE Saved iptables rules\n"
	fi

	/sbin/iptables -F
	/sbin/iptables -t nat -F

	mv /etc/resolv.conf /etc/resolv.conf.bak
	echo -e 'nameserver 127.0.0.1' > /etc/resolv.conf
	echo -e " $GREEN*$BLUE Modified resolv.conf to use Tor\n"

	# disable ipv6
	echo -e " $GREEN*$BLUE Disabling IPv6 for security reasons\n"
	/sbin/sysctl -w net.ipv6.conf.all.disable_ipv6=1
	/sbin/sysctl -w net.ipv6.conf.default.disable_ipv6=1

	# set iptables nat
	echo -e " $GREEN*$BLUE Configuring iptables rules to route all traffic through tor\n"
	/sbin/iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -j RETURN

	#set dns redirect
	echo -e " $GREEN*$BLUE Redirecting DNS traffic through tor\n"
	/sbin/iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 53
	/sbin/iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 53
	/sbin/iptables -t nat -A OUTPUT -p udp -m owner --uid-owner $TOR_UID -m udp --dport 53 -j REDIRECT --to-ports 53

	#resolve .onion domains mapping 10.192.0.0/10 address space
	/sbin/iptables -t nat -A OUTPUT -p tcp -d 10.192.0.0/10 -j REDIRECT --to-ports $TOR_PORT
	/sbin/iptables -t nat -A OUTPUT -p udp -d 10.192.0.0/10 -j REDIRECT --to-ports $TOR_PORT

	#exclude local addresses
	for NET in $TOR_EXCLUDE 127.0.0.0/9 127.128.0.0/10; do
		/sbin/iptables -t nat -A OUTPUT -d $NET -j RETURN
		/sbin/iptables -A OUTPUT -d "$NET" -j ACCEPT
	done

	#redirect all other output through TOR
	/sbin/iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TOR_PORT
	/sbin/iptables -t nat -A OUTPUT -p udp -j REDIRECT --to-ports $TOR_PORT
	/sbin/iptables -t nat -A OUTPUT -p icmp -j REDIRECT --to-ports $TOR_PORT

	#accept already established connections
	/sbin/iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

	#allow only tor output
	echo -e " $GREEN*$BLUE Allowing only tor to browse in clearnet\n"
	/sbin/iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
	/sbin/iptables -A OUTPUT -j REJECT

	echo -e "$GREEN *$BLUE All traffic was redirected throught Tor\n"
	echo -e "$GREEN[$BLUE i$GREEN ]$BLUE You are under AnonSurf tunnel$RESETCOLOR\n"
	notify "Global Anonymous Proxy Activated"
	sleep 1
	notify "Dance like no one's watching. Encrypt like everyone is :)"

}


function stop {
	# Make sure only root can run our script
	ME=$(whoami | tr [:lower:] [:upper:])

	if [ $(id -u) -ne 0 ]; then
		echo -e "\n$GREEN[$RED!$GREEN] $RED $ME R U DRUNK?? This script must be run as root$RESETCOLOR\n" >&2
		exit 1
	fi

	echo -e "\n$GREEN[$BLUE i$GREEN ]$BLUE Stopping anonymous mode:$RESETCOLOR\n"

	/sbin/iptables -F
	/sbin/iptables -t nat -F
	echo -e "\n $GREEN*$BLUE Deleted all iptables rules"

	if [ -f /etc/network/iptables.rules ]; then
		/sbin/iptables-restore < /etc/network/iptables.rules
		rm /etc/network/iptables.rules
		echo -e "\n $GREEN*$BLUE Iptables rules restored"
	fi
	echo -e -n "\n $GREEN*$BLUE Restore DNS service\n"
	rm /etc/resolv.conf || true
	if ! [ -f /etc/resolv.conf.bak ]; then
		ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
	else
		cp /etc/resolv.conf.bak /etc/resolv.conf || true
	fi

	# re-enable ipv6
	/sbin/sysctl -w net.ipv6.conf.all.disable_ipv6=0
	/sbin/sysctl -w net.ipv6.conf.default.disable_ipv6=0

	/usr/sbin/service tor stop
	sleep 6
	echo -e -n " $GREEN*$BLUE Restoring torrc to original\n"
	if [ -e /etc/tor/torrc.orig ]; then
 		rm /etc/tor/torrc
 		mv /etc/tor/torrc.orig /etc/tor/torrc
	fi
	sleep 1

	echo -e " $GREEN*$BLUE Anonymous mode stopped\n"
	notify "Global Anonymous Proxy Closed - Stop dancing :("

}


function change {
	exitnode-selector
	sleep 10
	echo -e " $GREEN*$BLUE Tor daemon reloaded and forced to change nodes\n"
	notify "Identity changed - let's dance again!"
	sleep 1
}


function status {
	/usr/sbin/service tor status
	cat /tmp/anonsurf-tor.log || cat /var/log/tor/log
}

case "$1" in
	start)
	read -p "To start anonsurf needs to kill dangerous applications and clean some application caches. Want to continue? [Y/n]: " response
		response=${response:-Y}
		if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
		then
				start
		else
			echo "AnonSurf can't start without killing dangerous applications and cleaning some application caches. Goodbye!"

		fi

	;;
	stop)

	read -p "To stop anonsurf needs to kill dangerous applications and clean some application caches. Want to continue? [Y/n]: " response
		response=${response:-Y}
		if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
		then
				stop
		else
			echo "AnonSurf can't stop without killing dangerous applications and cleaning some application caches."

		fi
	;;
	changeid|change-id|change)
		change
	;;
	status)
		status
	;;
	myip|ip)
		ip
	;;
	restart)
		$0 stop
		sleep 1
		$0 start
	;;
   *)
echo -e "
Parrot AnonSurf Module (v 2.11)
	Developed by Lorenzo \"Palinuro\" Faletra <palinuro@parrotsec.org>
		     Lisetta \"Sheireen\" Ferrero <sheireen@parrotsec.org>
		     Francesco \"Mibofra\" Bonanno <mibofra@parrotsec.org>
		and a huge amount of Caffeine + some GNU/GPL v3 stuff
	Extended by Daniel \"Sawyer\" Garcia <dagaba13@gmail.com>
	WSL2 (Ubuntu) Port by Marcel \"Paranoik\" Pewny <mpewny@protonmail.com>

	Usage:
	$RED┌──[$GREEN$USER$YELLOW@$BLUE`hostname`$RED]─[$GREEN$PWD$RED]
	$RED└──╼ \$$GREEN"" anonsurf $RED{$GREEN""start$RED|$GREEN""stop$RED|$GREEN""restart$RED|$GREEN""change$RED""$RED|$GREEN""status$RED""}

	$RED start$BLUE -$GREEN Start system-wide TOR tunnel
	$RED stop$BLUE -$GREEN Stop anonsurf and return to clearnet
	$RED restart$BLUE -$GREEN Combines \"stop\" and \"start\" options
	$RED changeid$BLUE -$GREEN Restart TOR to change identity
	$RED status$BLUE -$GREEN Check if AnonSurf is working properly
	$RED myip$BLUE -$GREEN Check your ip and verify your tor connection
$RESETCOLOR
Dance like no one's watching. Encrypt like everyone is.
" >&2

exit 1
;;
esac

echo -e $RESETCOLOR
exit 0
