# Run swift test
swift test

if [ $? -ne 0 ]; then
    return $?
fi

# Run the server in the background
swift run TestWebSocketService &

# Install autobahn
pip install autobahntestsuite

# Run autobahn
wstest -m fuzzingclient

# Check if all tests passed
OUTPUT = `grep behavior reports/servers/index.json | cut -d':' -f2 | cut -d'"' -f2 | sort -u | xargs`

echo $OUTPUT

if [ $OUTPUT -ne "OK" ]; then
    return 1
fi

return 0 

