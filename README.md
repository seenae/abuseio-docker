# abuseio-docker
Standalone docker image for AbuseIO on NGINX with MySQL, fetchmail and procmail

### building the image
    
    # docker build -t abuseio:latest .
    
### running the container

    # docker run -d -p 8000:8000 -p 3306:3306 -v <host_config_dir>:/config abuseio:latest
    
and connect your browser to [http://localhost:8000/](http://localhost:8000/)

### config the container
Fetchmail `fetchmailrc` and AbuseIO environment settings `abuseio.env` can be editted in the `/config` directory on the container or in the directory on the host that is bound to it.
These contain, for example, incoming `fetchmailrc` and outgoing `abuseio.env` mail settings.
The `/config` also contains the AbuseIO config directory, here you can edit advanced settings e.g. parser and collector settings.

 - [AbuseIO environment settings](https://docs.abuse.io/en/latest/installation/#environment-settings)
 - [AbuseIO main configuration](https://docs.abuse.io/en/latest/configuration_main/)
 - [Gmail POP3 with fetchmail](https://www.axllent.org/docs/view/gmail-pop3-with-fetchmail/)
 - [Using Fetchmail to Retrieve Email](https://www.linode.com/docs/email/clients/using-fetchmail-to-retrieve-email)
 
When you edit fetchmailrc, don't delete or alter the last line.
    
    mda "/usr/bin/procmail -m /etc/procmailrc"
    
This line ensures that the mails are delivered to AbuseIO.

### ports
NGINX is accessible on container port 8000 and MySQL is accessible on port 3306. These ports can be published 
on the host by using the -p option of Docker, see [incoming ports](https://docs.docker.com/engine/reference/run/#expose-incoming-ports)
of the Docker Manual.

### volumes
The container exports four volumes

 - `/config`
   all the necessary files to config AbuseIO e.g. mail credentials 
   
 - `/opt/abuseio/storage/mailarchive`
   the received mails
 
 - `/var/log/abuseio`
   logging from AbuseIO, NGINX and procmail
   
 - `/var/lib/mysql`
   database data
 
The volumes can be mapped to local persistent storage, using the -v option of Docker, see [mount volume](https://docs.docker.com/engine/reference/commandline/run/#mount-volume--v---read-only) of the Docker manual for more information

### TODO

 1. Cleanup / Fix / Document Dockerfile
 
