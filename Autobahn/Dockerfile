FROM swift:5.1

RUN apt-get update && apt-get install -y libssl-dev libcurl4-openssl-dev libz-dev

COPY . /WebSocketEchoServer

WORKDIR /WebSocketEchoServer

RUN swift build

CMD .build/debug/WebSocketEchoServer
