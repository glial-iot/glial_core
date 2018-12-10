FROM tarantool/tarantool:1.10.0

RUN apk add --no-cache tzdata git bash lua-dev gcc musl-dev

RUN luarocks install inspect
RUN luarocks install luasocket
RUN luarocks install dump
RUN luarocks install cron-parser
RUN luarocks install lbase64
RUN luarocks install fun
RUN luarocks install md5
RUN luarocks install luajson
RUN luarocks install busted

ADD . /glue_dist
WORKDIR /glue_dist

RUN tarantoolctl rocks install http
RUN tarantoolctl rocks install dump
RUN tarantoolctl rocks install cron-parser

WORKDIR /glue_dist/tests
#EXPOSE 8080