#!/usr/bin/env bash

CONFIGURED=/config/.configured
ABUSEIO_CONF=/config/abuseio
ABUSEIO_CONF_ORG=/opt/abuseio/config
ABUSEIO_CONF_NEW=/opt/abuseio/config_new
ABUSEIO_ENV=/config/abuseio.env
ABUSEIO_ENV_EX=/opt/abuseio/.env.example
ABUSEIO_ENV_ORG=/opt/abuseio/.env
PROGRESSFILE=/opt/setup/progress.txt
PASSWORDFILE=/opt/setup/password.txt
RESTARTFILE=/opt/setup/restart.txt

MYSQL_DATABASE=`sed -n -e '/DB_DATABASE/ s/.*\= *//p' $ABUSEIO_ENV_EX`
MYSQL_ROOT_PASSWORD=`sed -n -e '/DB_PASSWORD/ s/.*\= *//p' $ABUSEIO_ENV_EX`

ABUSEIO_ADMIN_PASSWORD=`date | md5sum | cut -c2-9`

# check if the container is already configured
# if not initialize the database and migrate abuseio
if [ -f "$CONFIGURED" ]
then

    echo "30 checking AbuseIO config" > $PROGRESSFILE

    # check to see if the config is linked
    if [ ! -h "$ABUSEIO_CONF_ORG" ]
    then
        rm -rf $ABUSEIO_CONF_NEW # defensive programming
        mv $ABUSEIO_CONF_ORG $ABUSEIO_CONF_NEW
        ln -s $ABUSEIO_CONF $ABUSEIO_CONF_ORG
    fi

    echo "60 checking AbuseIO environment" > $PROGRESSFILE

    # check to see if the env is linked
    if [ ! -h "$ABUSEIO_ENV_ORG" ]
    then
        ln -s $ABUSEIO_ENV $ABUSEIO_ENV_ORG
    fi

    # switching to abuseio
    echo "95 Enabling AbuseIO" > $PROGRESSFILE

    rm /etc/nginx/sites-enabled/setup.conf
    ln -s /etc/nginx/sites-available/abuseio.conf /etc/nginx/sites-enabled/abuseio.conf

    echo "100 Done" > $PROGRESSFILE

else

    echo "20 copying AbuseIO config" > $PROGRESSFILE

    # copy abuseio config
    # remove old configuration if it exists
    rm -rf $ABUSEIO_ENV
    rm -rf $ABUSEIO_CONF

    echo "40 copying AbuseIO environment" > $PROGRESSFILE

    # copy and link the env
    cp $ABUSEIO_ENV_EX $ABUSEIO_ENV
    if [ ! -h "$ABUSEIO_ENV_ORG" ]
    then
       ln -s $ABUSEIO_ENV $ABUSEIO_ENV_ORG
    fi

    if [ ! -h "$ABUSEIO_CONF_ORG" ]
    then
        rm -rf $ABUSEIO_CONF_NEW
        mv $ABUSEIO_CONF_ORG $ABUSEIO_CONF_NEW
        cp -R $ABUSEIO_CONF_NEW $ABUSEIO_CONF
        ln -s $ABUSEIO_CONF $ABUSEIO_CONF_ORG
    fi

    echo "60 Initializing AbuseIO database" > $PROGRESSFILE

    # initialize database
    # wait a while, to make sure mysql is up and running
    sleep 30;
    mysqladmin -uroot -p$MYSQL_ROOT_PASSWORD create $MYSQL_DATABASE

    #create a root user which can be used from the host
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE USER 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD'"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES"

    echo "80 Migrating initial AbuseIO database" > $PROGRESSFILE

    # abuseio migrate
    cd /opt/abuseio
    php ./artisan migrate --force

    echo "90 Creating System Administrator user" > $PROGRESSFILE

    # create admin user
    php ./artisan user:create admin@isp.local $ABUSEIO_ADMIN_PASSWORD system administrator en Default
    echo $ABUSEIO_ADMIN_PASSWORD > $PASSWORDFILE

    # add the admin role to the user
    php ./artisan role:assign --role=Admin --user=1

    # switching to abuseio
    echo "95 Enabling AbuseIO" > $PROGRESSFILE

    rm /etc/nginx/sites-enabled/setup.conf
    ln -s /etc/nginx/sites-available/abuseio.conf /etc/nginx/sites-enabled/abuseio.conf

    echo "100 Done" > $PROGRESSFILE
fi

#supervisor
cp /opt/abuseio/extra/etc/supervisor/conf.d/* /etc/supervisor/conf.d

# wait for the restart notification
while [ ! -f $RESTARTFILE ]
do
  sleep 1
done

# mark the container as configured
touch "$CONFIGURED"

# restart supervisord
kill -HUP `cat /var/run/supervisord.pid`
