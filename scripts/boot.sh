#!/usr/bin/env bash

CONFIGURED=/config/.configured
ABUSEIO_CONF=/config/abuseio
ABUSEIO_CONF_ORG=/opt/abuseio/config
ABUSEIO_CONF_NEW=/opt/abuseio/config_new
ABUSEIO_ENV=/config/abuseio.env
ABUSEIO_ENV_EX=/opt/abuseio/.env.example
ABUSEIO_ENV_ORG=/opt/abuseio/.env

ABUSEIO_MAILARCHIVE_ORG=/opt/abuseio/storage/mailarchive
ABUSEIO_MAILARCHIVE=/data/mailarchive

ABUSEIO_LOG_ORG=/var/log/abuseio
ABUSEIO_LOG=/log

MYSQL_DB_ORG=/var/lib/mysql
MYSQL_DB_NEW=/var/lib/mysql_new
MYSQL_DB=/data/mysql

PROGRESSFILE=/opt/setup/progress.txt
PASSWORDFILE=/opt/setup/password.txt
RESTARTFILE=/opt/setup/restart.txt

MYSQL_DATABASE=`sed -n -e '/^DB_DATABASE/ s/.*\= *//p' $ABUSEIO_ENV_EX`
MYSQL_ROOT_PASSWORD=`sed -n -e '/^DB_PASSWORD/ s/.*\= *//p' $ABUSEIO_ENV_EX`

ABUSEIO_ADMIN_PASSWORD=`date | md5sum | cut -c2-9`

# check if the container is already configured
# if not initialize the database and migrate abuseio
if [ -f "$CONFIGURED" ]
then

    echo "20 checking AbuseIO config" > $PROGRESSFILE

    # check to see if the config is linked
    if [ ! -h "$ABUSEIO_CONF_ORG" ]
    then
        rm -rf $ABUSEIO_CONF_NEW # defensive programming
        mv $ABUSEIO_CONF_ORG $ABUSEIO_CONF_NEW
        ln -s $ABUSEIO_CONF $ABUSEIO_CONF_ORG
    fi

    # check if the mailarchive is linked
    if [ ! -h "$ABUSEIO_MAILARCHIVE_ORG" ]
    then
        rm -rf $ABUSEIO_MAILARCHIVE_ORG
        ln -s $ABUSEIO_MAILARCHIVE $ABUSEIO_MAILARCHIVE_ORG
    fi

    echo "40 Checking AbuseIO environment" > $PROGRESSFILE

    # check to see if the env is linked
    if [ ! -h "$ABUSEIO_ENV_ORG" ]
    then
        ln -s $ABUSEIO_ENV $ABUSEIO_ENV_ORG
    fi

    echo "60 Checking databases"

    # check if the database directory is linked
    supervisorctl stop mysqld

    if [ ! -h "$MYSQL_DB_ORG" ]
    then
        if [ ! -d "$MYSQL_DB_NEW" ]
        then
            mv $MYSQL_DB_ORG $MYSQL_DB_NEW
        else
            rm -rf $MYSQL_DB_ORG
        fi
        ln -s $MYSQL_DB $MYSQL_DB_ORG
    fi

    supervisorctl start mysqld

    echo "80 Checking log directory" > $PROGRESSFILE

    # check if the log directory is linked
    supervisorctl stop rsyslog

    if [ ! -h "$ABUSEIO_LOG_ORG" ]
    then
        rm -rf $ABUSEIO_LOG_ORG
        ln -s $ABUSEIO_LOG $ABUSEIO_LOG_ORG
    fi
    supervisorctl start rsyslog


    # switching to abuseio
    echo "90 Enabling AbuseIO" > $PROGRESSFILE

    rm /etc/nginx/sites-enabled/setup.conf
    ln -s /etc/nginx/sites-available/abuseio.conf /etc/nginx/sites-enabled/abuseio.conf

    echo "100 Done" > $PROGRESSFILE

else

    echo "10 copying AbuseIO config" > $PROGRESSFILE

    # copy abuseio config
    # remove old configuration if it exists
    rm -rf $ABUSEIO_CONF

    if [ ! -h "$ABUSEIO_CONF_ORG" ]
    then
        rm -rf $ABUSEIO_CONF_NEW
        mv $ABUSEIO_CONF_ORG $ABUSEIO_CONF_NEW
        cp -ra --preserve=all $ABUSEIO_CONF_NEW $ABUSEIO_CONF
        ln -s $ABUSEIO_CONF $ABUSEIO_CONF_ORG
    fi

    # link the mailarchive to /data
    if [ ! -h "$ABUSEIO_MAILARCHIVE_ORG" ]
    then
        cp -ra --preserve=all $ABUSEIO_MAILARCHIVE_ORG $ABUSEIO_MAILARCHIVE
        rm -rf $ABUSEIO_MAILARCHIVE_ORG
        ln -s $ABUSEIO_MAILARCHIVE $ABUSEIO_MAILARCHIVE_ORG
    fi

    echo "20 copying AbuseIO environment" > $PROGRESSFILE
    # remove old configuration if it exists
    rm -rf $ABUSEIO_ENV

    # copy and link the env
    cp $ABUSEIO_ENV_EX $ABUSEIO_ENV
    chown abuseio:abuseio $ABUSEIO_ENV
    if [ ! -h "$ABUSEIO_ENV_ORG" ]
    then
       ln -s $ABUSEIO_ENV $ABUSEIO_ENV_ORG
    fi

    echo "40 Initializing AbuseIO database" > $PROGRESSFILE

    supervisorctl stop mysqld

    # link the db directory
    if [ ! -h "$MYSQL_DB_ORG" ]
    then
        if [ ! -d "$MYSQL_DB_NEW" ]
        then
            mv $MYSQL_DB_ORG $MYSQL_DB_NEW
        else
            rm -rf $MYSQL_DB_ORG
        fi
        cp -ra --preserve=all $MYSQL_DB_NEW $MYSQL_DB
        ln -s $MYSQL_DB $MYSQL_DB_ORG
    fi

    supervisorctl start mysqld

    # initialize database
    # wait a while, to make sure mysql is up and running
    sleep 20
    mysqladmin -uroot -p$MYSQL_ROOT_PASSWORD create $MYSQL_DATABASE

    # create a root user which can be used from the host
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "CREATE USER 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD'"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION"
    mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES"

    echo "50 Migrating initial AbuseIO database" > $PROGRESSFILE

    # abuseio migrate
    cd /opt/abuseio
    php ./artisan migrate --force

    echo "60 Updating System Administrator user" > $PROGRESSFILE

    # create admin user
    php ./artisan user:edit 1 --password=$ABUSEIO_ADMIN_PASSWORD
    echo $ABUSEIO_ADMIN_PASSWORD > $PASSWORDFILE

    # add the admin role to the user
    php ./artisan role:assign --role=Admin --user=1

    echo "70 Linking log directory" > $PROGRESSFILE

    # check if the log directory is linked
    supervisorctl stop rsyslog

    if [ ! -h "$ABUSEIO_LOG_ORG" ]
    then
        cp -ra --preserve=all $ABUSEIO_LOG_ORG/* $ABUSEIO_LOG
        rm -rf $ABUSEIO_LOG_ORG
        ln -s $ABUSEIO_LOG $ABUSEIO_LOG_ORG
    fi

    supervisorctl start rsyslog

    # switching to abuseio
    echo "80 Enabling AbuseIO" > $PROGRESSFILE

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
