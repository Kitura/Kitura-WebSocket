# Run swift test
swift test

if [ $? -ne 0 ]; then
    return $?
fi

# Build and run the TestWebSocketService
swift build -c release
swift run TestWebSocketService &

# Install python, pip and autobahn
apt-get update \
    && apt-get -y upgrade \
    && apt-get -y install sudo \
    && sudo apt-get -y install python-pip \
    && pip install autobahntestsuite

# Run autobahn
wstest -m fuzzingclient

# Check if all tests passed
OUTPUT = `grep behavior reports/servers/index.json | cut -d':' -f2 | cut -d'"' -f2 | sort -u | xargs`

echo "Behaviors output by tests: $OUTPUT"

if [ $OUTPUT -ne "OK" ]; then
    return 1
fi

return 0 

