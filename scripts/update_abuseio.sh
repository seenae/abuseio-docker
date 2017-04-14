#!/usr/bin/env bash

# AbuseIO version
VERSION=latest
ABUSEIO_URL=https://packages.abuse.io/releases/abuseio-$VERSION.tar.gz

# paths
CURRENT_DIR=`pwd`
ABUSEIO_PARENT_DIR=/opt
ABUSEIO_DIR=$ABUSEIO_PARENT_DIR/abuseio
CONFIG_DIR=/config

# download AbuseIO
wget -O /tmp/abuseio-latest.tar.gz $ABUSEIO_URL

# extract and update the new AbuseIO
cd $ABUSEIO_PARENT_DIR &&
tar xvzf /tmp/abuseio-latest.tar.gz && \
chown -R abuseio:abuseio abuseio && \
chmod -R 770 abuseio/storage/ && \
chmod -R 770 abuseio/bootstrap/cache/ && \
rm -rf $ABUSEIO_DIR/config_new && \
mv $ABUSEIO_DIR/config $ABUSEIO_DIR/config_new && \
ln -s /config/abuseio $ABUSEIO_DIR/config && \
cp -rv $ABUSEIO_DIR/config_new $CONFIG_DIR/abuseio_new && \
rm /tmp/abuseio-latest.tar.gz

# run the migrations
cd $ABUSEIO_DIR && \
php ./artisan migrate --force

# back to the original working dir
cd $CURRENT_DIR

# output
echo
echo "Please check and when needed update your config."
echo "New config files can be found in $CONFIG_DIR/abuseio_new."
echo





