#! /bin/bash

function validateSubDomain() {
  local subDomain=$1
  if [[ ! $subDomain =~ ^[A-Za-z0-9]+$ ]]; then
    echo "[Error] Subdomain not valid format"
    exit 1
  fi
}

function validateIp() {
  local ip=$1
  local octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
  local ip4="^$octet\\.$octet\\.$octet\\.$octet$"
  if [[ ! $ip =~ $ip4 ]]; then
    echo "[Error] IP not valid format"
    exit 1
  fi
}

function main() {
  CFG_FILE=/etc/qdns.conf

  if [ ! -f "$CFG_FILE" ]; then
    echo "[Error] Config file not found in /etc/qdns.conf"
    exit 1
  fi

  CFG_CONTENT=$(cat $CFG_FILE | sed -r '/[^=]+=[^=]+/!d' | sed -r 's/\s+=\s/=/g')
  eval "$CFG_CONTENT"

  while true; do
    clear
    echo "================================================================"
    echo "||                     DNS MANAGE SCRIPT                      ||"
    echo "================================================================"
    local PS3='Please enter your choice: '
    local forwardZones="$(listForwardZone)"
    local forwardOptions
    read -r -a forwardOptions <<<"$forwardZones"
    local opt
    select opt in "${forwardOptions[@]}" "New Zone" "Quit"; do
      case $opt in
      "New Zone")
        addForwardZone
        ;;
      "Quit")
        break 2
        ;;
      *)
        showMenuForwardZoneRecord $opt
        ;;
      esac
      break
    done
  done
}

function createBackupZone() {
  local domain=$1
  local masterIP=$hostIp

  if [[ $enabled -eq 1 ]]; then
    ssh root@$ns2 '/bin/echo -e "zone \"'$domain'\" {\n\ttype slave;\n\tfile \"/var/named/slaves/'$domain'\";\n\tmasters { '$masterIP'; };\n};" >> /etc/named.conf; systemctl restart named'
  fi

}

function showMenuForwardZoneRecord() {
  while true; do
    clear
    local zoneRecordChosen=$1
    echo "================================================================"
    echo "||                   MANAGE RESOURCE RECORD                    ||"
    echo "================================================================"
    local PS3='Please enter your choice: '
    local forwardRecordOption=("Add A record" "Remove A record" "Back")
    local opt
    select opt in "${forwardRecordOption[@]}"; do
      case $opt in
      "Add A record")
        addARecord $zoneRecordChosen
        break
        ;;
      "Remove A record")
        removeARecord $zoneRecordChosen
        break
        ;;
      "Back")
        break 2
        ;;
      *) echo "Invalid option $REPLY" ;;
      esac
    done
  done
}

function listForwardZone() {
  local configFile="/etc/named.conf"
  # Check config file is exsited
  if ! [[ -f "$configFile" ]]; then
    echo "[Error] File /etc/named.conf not exsited"
    exit 1
  fi

  local zones="$(grep 'file "forward.' $configFile | cut -d'"' -f2 | sed 's/forward.//g')"
  echo $zones
}

function addForwardZone() {
  local masterIP=$hostIp
  clear
  echo "================================================================"
  echo "||                      ADD FORWARD ZONE                      ||"
  echo "================================================================"
  echo ""
  echo -n "Enter zone: "
  read domain

  echo -n "Enter ip: "
  read ip
  validateIp $ip

  if [[ $enabled -eq 0 ]]; then
    echo -e "\$TTL 86400
@ IN SOA ns1.${domain}. root.${domain}. (
\t1 ;Serial
\t3600 ;Refresh
\t1800 ;Retry
\t604800 ;Expire
\t86400 ;Minimum TTL
)

@ IN NS ns1.${domain}.
ns1 IN A ${masterIP}
@ IN A ${ip}" >/var/named/forward.${domain}
  else
    echo -e "\$TTL 86400
@ IN SOA ns1.${domain}. root.${domain}. (
\t1 ;Serial
\t3600 ;Refresh
\t1800 ;Retry
\t604800 ;Expire
\t86400 ;Minimum TTL
)

@ IN NS ns1.${domain}.
ns1 IN A ${masterIP}
@ IN NS ns2.${domain}.
ns2 IN A ${ns2}
@ IN A ${ip}" >/var/named/forward.${domain}
  fi

  echo -e "zone \"${domain}\" IN {
\ttype master;
\tfile \"forward.${domain}\";
\tallow-update { none; };
};" >>/etc/named.conf

  createReverseZone $ip $domain

  systemctl restart named

  createBackupZone $domain
}

function addARecord() {
  local forwardFile="/var/named/forward.$1"
  clear
  echo "================================================================"
  echo "||                      ADD NEW HOST                          ||"
  echo "================================================================"
  echo ""
  echo -n "Enter sub domain (subdomain.$1): "
  read subDomain

  validateSubDomain $subDomain

  local findResult=$(sed -n "/$subDomain IN A/=" $forwardFile)

  if ! [[ -z $findResult ]]; then
    echo "[Error] Subdomain is existed"
    exit 1
  fi

  echo -n "Enter IP: "
  read ip
  validateIp $ip

  createReverseZoneWhenCreateARecord $ip $subDomain $1

  echo "$subDomain IN A $ip" >>$forwardFile

  sed -i -E 's|([0-9]*) ;Serial|echo "\t$(( \1+1 )) ;Serial"|e' $forwardFile
  rndc reload $1
}

function removeARecord() {
  local forwardFile="/var/named/forward.$1"
  echo "================================================================"
  echo "||                      REMOVE A RECORD                       ||"
  echo "================================================================"
  echo -n "Enter sub domain (subdomain.$1): "
  read subDomain

  validateSubDomain $subDomain

  local findResult=$(sed -n "/$subDomain IN A/=" $forwardFile)

  if [[ -z $findResult ]]; then
    echo "[Error] Subdomain is not existed"
    exit 1
  fi

  local ipDelele="$(grep "$subDomain IN A" $forwardFile | cut -d' ' -f4)"
  local reverseIp=$(echo $ipDelele | sed -E 's|([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3})|\3.\2.\1|')
  local reverseFile="/var/named/reverse.${reverseIp}"
  echo $ipDelele
  echo $reverseIp
  echo $reverseFile
  local netAddress=$(echo $ipDelele | sed -E 's|([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3})|\4|')

  local findResultReverse=$(sed -n "/$netAddress IN PTR $subDomain.$1./=" $reverseFile)

  if ! [[ -z $findResultReverse ]]; then
    sed -i -E "/$netAddress IN PTR $subDomain.$1./d" $reverseFile
    sed -i -E 's|([0-9]*) ;Serial|echo "\t$(( \1+1 )) ;Serial"|e' $reverseFile
  fi

  sed -i -E "/$subDomain IN A .+/d" $forwardFile

  sed -i -E 's|([0-9]*) ;Serial|echo "\t$(( \1+1 )) ;Serial"|e' $forwardFile

  rndc reload $1
}

function createReverseZoneWhenCreateARecord() {
  local ip=$1
  local subDomain=$2
  local domain=$3

  local reverseIp=$(echo $ip | sed -E 's|([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3})|\3.\2.\1|')
  local reverseFile="/var/named/reverse.${reverseIp}"
  local netAddress=$(echo $ip | sed -E 's|([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3})|\4|')

  if [[ -f "$reverseFile" ]]; then
    echo "$netAddress IN PTR $subDomain.$domain." >>$reverseFile
    return
  fi

  local masterIP=$hostIp

  if [[ $enabled -eq 0 ]]; then
    echo -e "\$TTL 86400
@ IN SOA ns1.${domain}. root.${domain}. (
\t1 ;Serial
\t3600 ;Refresh
\t1800 ;Retry
\t604800 ;Expire
\t86400 ;Minimum TTL
)

@ IN NS ns1.${domain}.
ns1 IN A ${masterIP}
$netAddress IN PTR $subDomain.$domain." >$reverseFile
  else
    echo -e "\$TTL 86400
@ IN SOA ns1.${domain}. root.${domain}. (
\t1 ;Serial
\t3600 ;Refresh
\t1800 ;Retry
\t604800 ;Expire
\t86400 ;Minimum TTL
)

@ IN NS ns1.${domain}.
ns1 IN A ${masterIP}
@ IN NS ns2.${domain}.
ns2 IN A ${ns2}
$netAddress IN PTR $subDomain.$domain." >$reverseFile
  fi

  echo -e "zone \"${reverseIp}.in-addr.arpa\" IN {
\ttype master;
\tfile \"reverse.${reverseIp}\";
\tallow-update { none; };
};" >>/etc/named.conf

  systemctl restart named
}

function createReverseZone() {
  local ip=$1
  local domain=$2

  local reverseIp=$(echo $ip | sed -E 's|([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3})|\3.\2.\1|')
  local reverseFile="/var/named/reverse.${reverseIp}"
  local netAddress=$(echo $ip | sed -E 's|([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3}).([0-9]{1,3})|\4|')

  if [[ -f "$reverseFile" ]]; then
    echo "$netAddress IN PTR $domain." >>$reverseFile
    return
  fi

  local masterIP=$hostIp

  if [[ $enabled -eq 0 ]]; then
    echo -e "\$TTL 86400
@ IN SOA ns1.${domain}. root.${domain}. (
\t1 ;Serial
\t3600 ;Refresh
\t1800 ;Retry
\t604800 ;Expire
\t86400 ;Minimum TTL
)

@ IN NS ns1.${domain}.
ns1 IN A ${masterIP}
$netAddress IN PTR $domain." >$reverseFile
  else
    echo -e "\$TTL 86400
@ IN SOA ns1.${domain}. root.${domain}. (
\t1 ;Serial
\t3600 ;Refresh
\t1800 ;Retry
\t604800 ;Expire
\t86400 ;Minimum TTL
)

@ IN NS ns1.${domain}.
ns1 IN A ${masterIP}
@ IN NS ns2.${domain}.
ns2 IN A ${ns2}
$netAddress IN PTR $domain." >$reverseFile
  fi

  echo -e "zone \"${reverseIp}.in-addr.arpa\" IN {
\ttype master;
\tfile \"reverse.${reverseIp}\";
\tallow-update { none; };
};" >>/etc/named.conf

  systemctl restart named
}

main
