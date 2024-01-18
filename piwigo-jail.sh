#!/bin/sh

# Install Piwigo Photo Gallery (https://piwigo.org/)
# in a FreeNAS jail

# (No TrueNAS Forum Link at this time)

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

#####
#
# General configuration
#
#####

# Initialize defaults
JAIL_NAME="piwigo"
JAIL_IP=""
DEFAULT_GW_IP=""
POOL_PATH=""
DNS_PLUGIN=""
CONFIG_NAME="piwigo-config"

# Check for config file and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"

# Error checking and config sanity check
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
# If release is 13.1-RELEASE, change to 13.2-RELEASE
if [ "${RELEASE}" = "13.1-RELEASE" ]; then
  RELEASE="13.2-RELEASE"
fi 

mountpoint=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

# Create the jail, pre-installing needed packages
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs":[
  "nano",
  "caddy",
  "php82",
  "php82-mbstring",
  "php82-zip",
  "php82-tokenizer",
  "php82-pdo",
  "php82-filter",
  "php82-xml",
  "php82-ctype",
  "php82-session",
  "php82-dom",
  "php82-exif",
  "php82-gd",
  "php82-iconv",
  "php82-simplexml",
  "php82-sodium",
  "php82-zlib",
  "mariadb106-server",
  "imagemagick7",
  "wget",
  "mediainfo",
  "ffmpeg",
  "p5-Image-ExifTool",
  "go", 
  "git",
  "sudo",
  "bzip2",
  "php82-pdo_mysql",
  "php82-mysqli"
  ]
}
__EOF__

if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" \
  ip4_addr="vnet0|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" \
  host_hostname="${JAIL_NAME}" vnet="on"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

# Store Caddyfile and data outside the jail
mkdir -p "${POOL_PATH}"/"${JAIL_NAME}"/{config,db,galleries,upload}

iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/html/piwigo/{galleries,upload}
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/html/piwigo/local/config
iocage exec "${JAIL_NAME}" mkdir -p  /var/db/mysql
iocage fstab -a "${JAIL_NAME}" "${POOL_PATH}"/"${JAIL_NAME}"/galleries /usr/local/www/html/piwigo/galleries nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${POOL_PATH}"/"${JAIL_NAME}"/upload /usr/local/www/html/piwigo/upload nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${POOL_PATH}"/"${JAIL_NAME}"/config /usr/local/www/html/piwigo/local/config nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${POOL_PATH}"/"${JAIL_NAME}"/db /var/db/mysql nullfs rw 0 0

# Create Caddyfile
cat <<__EOF__ >"${mountpoint}"/jails/"${JAIL_NAME}"/root/usr/local/www/Caddyfile
:80 {
	root * /usr/local/www/html/piwigo
	file_server
	php_fastcgi 127.0.0.1:9000
}
__EOF__

# Enable and start database
iocage exec "${JAIL_NAME}" sysrc mysql_enable="YES"
iocage exec "${JAIL_NAME}" service mysql-server start

# Secure database, set root password, create Nextcloud DB, user, and password
iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE piwigo;"
iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL ON piwigo.* TO piwigo@localhost IDENTIFIED BY '${DB_PASSWORD}';"
iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
iocage exec "${JAIL_NAME}" mysql -u root -e "DROP DATABASE IF EXISTS test;"
iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
iocage exec "${JAIL_NAME}" mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload
#  iocage exec "${JAIL_NAME}" mysqladmin reload

# Create root .my.cnf file
cat <<__EOF__ >"${mountpoint}"/jails/"${JAIL_NAME}"/root/.my.cnf
# MySQL client config file
[client]
password="${DB_ROOT_PASSWORD}"
__EOF__

# Save passwords for later reference
echo "MariaDB root password is ${DB_ROOT_PASSWORD}" > /root/"${JAIL_NAME}"_db_password.txt
echo "Piwigo database password is ${DB_PASSWORD}" >> /root/"${JAIL_NAME}"_db_password.txt


# Download and install PiWigo
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/html
iocage exec "${JAIL_NAME}" fetch -o /tmp "http://piwigo.org/download/dlcounter.php?code=latest"
iocage exec "${JAIL_NAME}" mv "/tmp/dlcounter.php?code=latest" /tmp/piwigo.zip
iocage exec "${JAIL_NAME}" unzip -d /usr/local/www/html/ /tmp/piwigo.zip
iocage exec "${JAIL_NAME}" sh -c 'find /usr/local/www/ -type d -print0 | xargs -0 chmod 2775'
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/html/
iocage exec "${JAIL_NAME}" sysrc php_fpm_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_enable=YES
iocage exec "${JAIL_NAME}" sysrc caddy_config=/usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" service php-fpm start
iocage exec "${JAIL_NAME}" service caddy start

#####
#
# Output results to console
#
#####

# Done!
echo "Installation complete!"
echo "Using your web browser, go to http://${JAIL_IP} to log in"
echo ""
echo "Database Information"
echo "--------------------"
echo "Database user = piwigo"
echo "Database name = piwigo"
echo "Database password = ${DB_PASSWORD}"
echo "The MariaDB root password is ${DB_ROOT_PASSWORD}"
echo ""
echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"

