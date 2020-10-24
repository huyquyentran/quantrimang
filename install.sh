#! /bin/bash

curl https://raw.githubusercontent.com/huyquyentran/quantrimang/main/qdns.sh --output /usr/local/bin/qdns
curl https://raw.githubusercontent.com/huyquyentran/quantrimang/main/qdns.conf --output /etc/qdns.conf

chmod 755 /usr/local/bin/qdns
chmod +x /usr/local/bin/qdns

echo " =========================================================="
echo "||                  INSTALL SUCCESSFULLY                  ||"
echo "||       Please reopen this terminal to use my script     ||"
echo " =========================================================="
