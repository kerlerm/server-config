#!/bin/bash

echo "${green}************************${col_reset}"
echo "${green}* set up map functions *${col_reset}"
echo "${green}************************${col_reset}"


# nur fuer map noetig
apt install --show-progress --assume-yes python3 python3-jsonschema curl

{
	# compile npm/nodejs (no package for debian stretch)
	curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash - 
	apt install --show-progress --assume-yes nodejs

	# get lastest yarn
	curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
	echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
	apt update && apt install --show-progress --assume-yes yarn

	# remove possible build remains of meshviewer
	rm -rf meshviewer

	echo "(I) ${green}Build meshviewer${col_reset}"
	mkdir -p /var/www/meshviewer/
	# place to store JSONs
	mkdir -p /var/www/data/
	apt install --show-progress --assume-yes git
	# get ffrgb meshviewer
	git clone https://github.com/ffrgb/meshviewer.git
	cd meshviewer
	yarn
	yarn global add gulp-cli
	# copy config to build root
	cp ../etc/meshviewer/config.js .
	cp ../etc/meshviewer/config.default.js .
	cp ../etc/meshviewer/scss/custom/_custom.scss ./scss/custom/
	# build it
	gulp
	# copy build to webroot
	cp -r build/* /var/www/meshviewer/
	cd ..

	# destroy build
	rm -rf meshviewer

	# owner of webfiles should be webserver
	chown -R www-data:www-data /var/www
}
