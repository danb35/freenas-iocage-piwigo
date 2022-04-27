# freenas-iocage-piwigo
 Script to create an iocage jail on Free/TrueNAS for the latest [PiWigo](https://piwigo.org/) release, including Caddy 2.x and MariaDB 10.3

# Installation
Change to a convenient directory, clone the repository using `git clone https://github.com/danb35/freenas-iocage-piwigo`, change to the freenas-iocage-piwigo directory, and create a configuration file called `piwigo-config` with your favorite text editor (if you don't have a favorite text editor, `nano` is a good choice--run `nano piwigo-config`).  Then run the script with `script piwigo.log ./piwigo-jail.sh`.

## Configuration options
In its minimal form, the configuration file would look like this:
```
JAIL_IP="192.168.1.78"
DEFAULT_GW_IP="192.168.1.1"
POOL_PATH="/mnt/tank"
```

* JAIL_IP:  The IP address to assign the jail.  You may optionally specify a netmask in CIDR notion.  If none is specified, the default is /24.  Values of less than 8 bits or more than 30 bits will also result in a 24-bit netmask.
* DEFAULT_GW_IP:  The IP address of your default gateway.
* POOL_PATH:  The path to your main data pool (e.g., `/mnt/tank`).  The Caddyfile and piwigo installation files (i.e., the web pages themselves) will be stored there, in $POOL_PATH/apps/piwigo.  If you have more than one pool, choose the one you want to use for this purpose.
* JAIL_NAME:  Optional.  The name of the jail.  If not given, will default to "piwigo".

## Post-install configuration
This script uses the [Caddy](https://caddyserver.com/) web server, which supports automatic HTTPS, reverse proxying, and many other powerful features.  It is configured using a Caddyfile, which is stored at `/usr/local/www/Caddyfile` in your jail, and under `/apps/piwigo/` on your main data pool.  You can edit it as desired to enable these or other features.  For further information, see [my Caddy script](https://github.com/danb35/freenas-iocage-caddy), specifically the included `Caddyfile.example`, or the [Caddy docs](https://caddyserver.com/docs/caddyfile).

This script installs Caddy from the FreeBSD binary package, which does not include any [DNS validation plugins](https://caddyserver.com/download).  If you need to use these, you'll need to build Caddy from source.  The tools to do this are installed in the jail.  To build Caddy, run these commands:
```
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
xcaddy build --output /usr/local/bin/caddy --with github.com/caddy-dns/${DNS_PLUGIN}
```
...with `${DNS_PLUGIN}` representing the name of the plugin, listed on the page linked above.  You'll then need to modify your configuration as described in the Caddy docs.
