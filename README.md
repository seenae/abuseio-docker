# abuseio-docker (WIP)
Docker image for AbuseIO, still a work in progress

### building the image
    
    # docker build -t abuseio:latest .
    
### running the container

    # docker run -d -p 8000:8000 -p 3306:3306 abuseio:latest
    
and connect your browser to http://localhost:8000

### TODO

 1. Cleanup / Fix / Document Dockerfile
 2. Add fetchmail/procmail
 3. Document Dockerfile Volume / Expose
 3. Speedup first run
 