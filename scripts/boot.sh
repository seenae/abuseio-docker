#!/usr/bin/env bash


CONFIGURED=/config/.configured
INITIALIZED=/config/.initialized
ABUSEIO_CONF=/config/abuseio
ABUSEIO_CONF_ORG=/opt/abuseio/config
ABUSEIO_CONF_NEW=/opt/abuseio/config_new
ABUSEIO_ENV=/config/abuseio.env
ABUSEIO_ENV_EX=/opt/abuseio/.env.example
ABUSEIO_ENV_ORG=/opt/abuseio/.env
PROGRESS=/opt/setup/progress.txt
PROGRESS_ABUSEIO=/opt/abuseio/public/progress.txt

MYSQL_DATABASE=`sed -n -e '/DB_DATABASE/ s/.*\= *//p' $ABUSEIO_ENV_EX`
MYSQL_ROOT_PASSWORD=`sed -n -e '/DB_PASSWORD/ s/.*\= *//p' $ABUSEIO_ENV_EX`

# check if the container is already configured
# if not initialize the database and migrate abuseio
if [ -f "$CONFIGURED" ]
then

    echo "30 checking AbuseIO config" > $PROGRESS

    # check to see if the config is linked
    if [ ! -h "$ABUSEIO_CONF_ORG" ]
    then
        rm -rf $ABUSEIO_CONF_NEW # defensive programming
        mv $ABUSEIO_CONF_ORG $ABUSEIO_CONF_NEW
        ln -s $ABUSEIO_CONF $ABUSEIO_CONF_ORG
    fi

    echo "60 checking AbuseIO environment" > $PROGRESS

    # check to see if the env is linked
    if [ ! -h "$ABUSEIO_ENV_ORG" ]
    then
        ln -s $ABUSEIO_ENV $ABUSEIO_ENV_ORG
    fi

    # switching to abuseio
    echo "95 Enabling AbuseIO" > $PROGRESS;

    rm /etc/nginx/sites-enabled/setup.conf
    ln -s /etc/nginx/sites-available/abuseio.conf /etc/nginx/sites-enabled/abuseio.conf

    echo "100 Done" > $PROGRESS
    echo "100 Done" > $PROGRESS_ABUSEIO

else

    echo "20 copying AbuseIO config" > $PROGRESS

    # copy abuseio config
    # remove old configuration if it exists
    rm -rf $ABUSEIO_ENV
    rm -rf $ABUSEIO_CONF

    echo "40 copying AbuseIO environment" > $PROGRESS

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

    echo "60 Initializing AbuseIO database" > $PROGRESS

    # initialize database
    # wait a while, to make sure mysql is up and running
    sleep 10;
    mysqladmin -uroot -p$MYSQL_ROOT_PASSWORD create $MYSQL_DATABASE

    #create a root user which can be used from the host
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE USER 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD'"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES"


    echo "80 Migrating initial AbuseIO database" > $PROGRESS

    # abuseio migrate
    cd /opt/abuseio
    php ./artisan migrate --force


    echo "90 Creating System Administrator user" > $PROGRESS

    # create admin user
    php ./artisan user:create admin@isp.local admin1 system administrator en Default

    # add the admin role to the user
    php ./artisan role:assign --role=Admin --user=1


    # switching to abuseio
    echo "95 Enabling AbuseIO" > $PROGRESS;

    rm /etc/nginx/sites-enabled/setup.conf
    ln -s /etc/nginx/sites-available/abuseio.conf /etc/nginx/sites-enabled/abuseio.conf

    echo "100 Done" > $PROGRESS
    echo "100 Done" > $PROGRESS_ABUSEIO

    touch "$CONFIGURED"
fi

#supervisor
cp /opt/abuseio/extra/etc/supervisor/conf.d/* /etc/supervisor/conf.d

# restart supervisord
kill -HUP `cat /var/run/supervisord.pid`
