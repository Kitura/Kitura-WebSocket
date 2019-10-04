#!/bin/bash
#
# Convenience script to build and run a Kitura-WebSocket echo server in a Docker container,
# and then to run the autobahn test suite Docker container against it.
#
# Once complete, the autobahn report (HTML format) will be opened.
#

# Create network
docker network rm autobahn
docker network create --driver bridge autobahn

# Build server
docker build -t wsserver .

# Execute server
docker container rm wsserver
docker run -d --network autobahn --name wsserver wsserver

# Execute client
docker run -it --rm \
    -v ${PWD}/config:/config \
    -v ${PWD}/reports:/reports \
    --name fuzzingclient \
    --network autobahn \
    crossbario/autobahn-testsuite \
    wstest -m fuzzingclient -s config/fuzzingclient.json

# Stop server
docker container stop wsserver

# Check out test report!
open ./reports/servers/index.html
