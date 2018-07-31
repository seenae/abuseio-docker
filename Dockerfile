# Multistage Dockerfile for AbuseIO latest

# create an intermediate image
FROM ubuntu:16.04 as intermediate

ARG GITHUB_TOKEN

# Ugly test to see if the github token is given as build arg

RUN if [ "x${GITHUB_TOKEN}" = "x" ]; then \
    echo "Please specify your Github OATH token as build argument"; \
    echo "docker build --build-arg GITHUB_TOKEN=<mytoken> .";\
    exit 1; \
    fi

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install curl php php-pear php-dev php-mcrypt php-mysql php-pgsql php-curl \
    php-intl php-bcmath php-cli php-cgi php-mbstring php-zip unzip wget -y

# tweak mbstring
RUN cp /usr/include/php/20151012/ext/mbstring/libmbfl/mbfl/mbfilter.h . && \
    awk '/#define MBFL_MBFILTER_H/{print;print "#undef HAVE_MBSTRING\n#define HAVE_MBSTRING 1";next}1' \
    mbfilter.h > /usr/include/php/20151012/ext/mbstring/libmbfl/mbfl/mbfilter.h

# install mailparse
RUN pecl install mailparse-3.0.2 && \
    echo extension=mailparse.so > /etc/php/7.0/mods-available/mailparse.ini && \
    phpenmod mailparse && phpenmod mcrypt

# install composer
RUN curl -sS https://getcomposer.org/installer | php && \
    mv composer.phar /usr/local/bin/composer && \
    chmod 755 /usr/local/bin/composer

# install github token
RUN composer config -g github-oauth.github.com ${GITHUB_TOKEN}

# get AbuseIO
RUN wget -O abuseio.zip https://github.com/AbuseIO/AbuseIO/archive/master.zip && \
    unzip abuseio.zip -d /tmp

# install dependencies
WORKDIR /tmp/AbuseIO-master
RUN composer install --no-scripts

# create the final image
FROM ubuntu:16.04

LABEL description="Docker image for AbuseIO, this image will install the latest version of AbuseIO 4.1" \
      vendor="AbuseIO" \
      product="AbuseIO" \
      version="latest" \
      maintainer="joost@abuse.io"

# Variables mysql
ENV MYSQL_ROOT_PASSWORD abuseio
ENV MYSQL_DATABASE abuseio

# set selection options
RUN echo "mysql-server mysql-server/root_password password ${MYSQL_ROOT_PASSWORD}" | debconf-set-selections
RUN echo "mysql-server mysql-server/root_password_again password ${MYSQL_ROOT_PASSWORD}" | debconf-set-selections

# Update system and install dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install curl fetchmail mysql-server mysql-client php php-pear php-dev \
    php-mcrypt php-mysql php-pgsql php-curl php-intl php-bcmath php-cli php-cgi php-fpm php-mbstring php-zip \
    procmail nginx rsyslog supervisor -y

# create directories
RUN mkdir -p \
    /config \
    /data \
    /log \
    /opt \
    /opt/setup \
    /var/log/abuseio \
    /var/log/php-fpm \
    /var/run/php \
    /var/run/mysqld \
    /scripts

# create users and groups
RUN adduser --system --group --home /opt/abuseio abuseio && \
    addgroup www-data abuseio

# set rights for directories
RUN chmod 775 /var/log/abuseio && \
    chown root:abuseio /var/log/abuseio && \
    chown mysql:mysql /var/run/mysqld && \
    chown root:abuseio /log && \
    chmod 775 /data && \
    chown www-data:www-data /opt/setup

# install the setuppage
USER www-data
COPY setuppage/* /opt/setup/
USER root

# install nginx config
ADD config/nginx/abuseio.conf /etc/nginx/sites-available
ADD config/nginx/setup.conf /etc/nginx/sites-available
RUN ln -s /etc/nginx/sites-available/setup.conf /etc/nginx/sites-enabled/setup.conf
RUN rm /etc/nginx/sites-enabled/default

# install php docker vars, let php behave better in docker
ADD config/php/docker-vars.ini /etc/php/7.0/mods-available
RUN phpenmod docker-vars

# install rsyslog
ADD config/rsyslog/48-abuseio.conf /etc/rsyslog.d
ADD config/rsyslog/46-fetchmail.conf /etc/rsyslog.d

# install supervisor confs
ADD config/supervisor/docker.conf /etc/supervisor/conf.d

# install boot script
ADD scripts/boot.sh /scripts
RUN chmod 755 /scripts/boot.sh

# install crons
ADD config/cron/root.cron /tmp
RUN crontab -u root /tmp/root.cron

# install fetchmailrc
ADD config/fetchmail/fetchmailrc /etc
RUN chmod 0600 /etc/fetchmailrc

# install procmailrc
ADD config/procmail/procmailrc /etc

# switch to /tmp
WORKDIR /tmp

# install composer
RUN curl -sS https://getcomposer.org/installer | php && \
    mv composer.phar /usr/local/bin/composer && \
    chmod 755 /usr/local/bin/composer

# tweak supervisord
RUN cp /etc/supervisor/supervisord.conf . && \
    awk '/\[supervisord\]/{print;print "nodaemon=true";next}1' \
    supervisord.conf > /etc/supervisor/supervisord.conf

# tweak mbstring
RUN cp /usr/include/php/20151012/ext/mbstring/libmbfl/mbfl/mbfilter.h . && \
    awk '/#define MBFL_MBFILTER_H/{print;print "#undef HAVE_MBSTRING\n#define HAVE_MBSTRING 1";next}1' \
    mbfilter.h > /usr/include/php/20151012/ext/mbstring/libmbfl/mbfl/mbfilter.h

# tweak php-fpm
RUN sed -i \
    -e "s/listen = \/run\/php\/php7.0-fpm.sock/listen = 127.0.0.1:9000/g" \
    -e "s/;clear_env = no/clear_env = no/g" \
    /etc/php/7.0/fpm/pool.d/www.conf

# tweak rsyslog
RUN sed -i \
    -e 's/module(load="imklog")/#module(load="imklog")/g' \
    -e 's/$KLogPermitNonKernelFacility on/#$KLogPermitNonKernelFacility off/g' \
    -e 's/$FileOwner syslog/$FileOwner root/g' \
    -e 's/$FileGroup adm/$FileGroup root/g' \
    -e 's/$FileCreateMode 0640/$FileCreateMode 0644/g' \
    -e 's/$PrivDropToUser/#$PrivDropToUser/g' \
    -e 's/$PrivDropToGroup/#$PrivDropToGroup/g' \
    /etc/rsyslog.conf

# tweak mysql, comment out a few problematic configuration values and
# don't reverse lookup hostnames
RUN sed -i \
    -E 's/^(bind-address|log)/#&/' /etc/mysql/mysql.conf.d/mysqld.cnf && \
	echo "[mysqld]\nskip-host-cache\nskip-name-resolve" > /etc/mysql/conf.d/docker.cnf

# install mailparse
RUN pecl install mailparse-3.0.2 && \
    echo extension=mailparse.so > /etc/php/7.0/mods-available/mailparse.ini && \
    phpenmod mailparse && phpenmod mcrypt

# install AbuseIO from the intermediate image
COPY --from=intermediate /tmp/AbuseIO-master /opt/abuseio
RUN chown -R abuseio:abuseio /opt/abuseio

WORKDIR /opt/abuseio
USER abuseio
RUN chmod -R 770 storage/ && \
    chmod -R 770 bootstrap/cache/

# generate abuseio APP_KEY, APP_ID, update DB_DATABASE and DB_PASSWORD
RUN sed -i \
    -e "s/APP_KEY=SomeRandomString/APP_KEY=`date +%D%T%N | md5sum | cut -d' ' -f1`/g" \
    -e "s/APP_ID=DEFAULT/APP_ID=`date +%N%D%T | md5sum | cut -d' ' -f1`/g" \
    -e "s;APP_URL='http://localhost/';APP_URL=;g" \
    -e "s/DB_DATABASE=abuseio/DB_DATABASE=${MYSQL_DATABASE}/g" \
    -e "s/DB_PASSWORD=/DB_PASSWORD=${MYSQL_ROOT_PASSWORD}/g" \
    /opt/abuseio/.env.example

# expose volumes and ports
VOLUME /config /data /log
EXPOSE 8000 3306

# set working user
USER root

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]