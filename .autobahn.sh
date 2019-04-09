# A script that runs swift test followed by the autobahn test suite.
# Note: this is script must be used only on Linux for now.

# Generate the fuzzingclient.json file for the given tests
fuzzing_client() {
    TESTS=$1
    echo "{\"outdir\": \"./reports/servers\", \"servers\": [{ \"url\": \"ws://127.0.0.1:9001\" }], \"cases\": [$TESTS],\"exclude-cases\": []}" > fuzzingclient.json
}

# Launch the WebSocket service and run a subset of Autobahn tests. On failures or unclean closures, exit with a non-zero code.
run_autobahn()
{
    # The first argument holds the lists of tests to be run
    TESTS=$1

    # Launch the WebSocketService, save its PID
    swift run TestWebSocketService &
    PID=$!

    # Make sure the server has enough time to be up and running
    sleep 5

    # Generate the fuzzingclient.json
    fuzzing_client $TESTS

    # Run the autobahn fuzzingclient
    wstest -m fuzzingclient

    # Count the number of failed tests or unclean connection closures
    FAILED_OR_UNCLEAN=`grep behavior reports/servers/index.json | cut -d':' -f2 | cut -d'"' -f2 | sort -u | xargs | grep -E "FAILED|UNCLEAN" | wc -l`
    if [ $FAILED_OR_UNCLEAN -ne "0" ]; then
        return $FAILED_OR_UNCLEAN
    fi

    # Kill the service
    kill $PID

    # Remove the reports and the generated json file
    rm -rf reports fuzzingclient.json
}

# Run swift test
travis_start "swift_test"
swift test
SWIFT_TEST_STATUS=$?
travis_end
if [ $SWIFT_TEST_STATUS -ne 0 ]; then
    return $SWIFT_TEST_STATUS
fi

set -e
# Build and run the TestWebSocketService
echo "Building in release mode for autobahn testing"
swift build -c release

set +e
# Install python, pip and autobahn
apt-get update \
    && apt-get -y upgrade \
    && apt-get -y install sudo \
    && sudo apt-get -y install python-pip \
    && pip install autobahntestsuite

# Run tests 1-4
travis_start "Running autobahn tests 1-4"
run_autobahn \"1.*\",\"2.*\",\"3.*\",\"4.*\"
travis_end

# Run tests 5-8
travis_start "Running autobahn tests 5-8"
run_autobahn \"5.*\",\"6.*\",\"7.*\",\"8.*\"
travis_end

# Run tests 9-10
travis_start "Running autobahn tests 9,10"
run_autobahn \"9.*\",\"10.*\"
travis_end

# Run tests 12-13, disabled due to a hang that happens only in the CI
# run_autobahn \"12.*\",\"13.*\"

# All tests have passed
