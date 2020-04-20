FROM debian:buster-slim

# Used only for triggering a rebuild
LABEL zend="2.0.20"

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install ca-certificates curl wget apt-transport-https lsb-release libgomp1 jq gnupg gosu \
    && echo 'deb https://zencashofficial.github.io/repo/ '$(lsb_release -cs)' main' | tee --append /etc/apt/sources.list.d/zen.list \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv 219F55740BBF7A1CE368BA45FB7053CE4991B669 \
    && gpg --export 219F55740BBF7A1CE368BA45FB7053CE4991B669 | apt-key add - \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install zen \
    && gosu nobody true
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

# Default p2p communication port, can be changed via $OPTS (e.g. docker run -e OPTS="-port=9876")
# or via a "port=9876" line in zen.conf.
#Defaults are 9033/19033 (Testnet)
EXPOSE 9033
EXPOSE 19033

# Default rpc communication port, can be changed via $OPTS (e.g. docker run -e OPTS="-rpcport=8765")
# or via a "rpcport=8765" line in zen.conf. This port should never be mapped to the outside world
# via the "docker run -p/-P" command.
#Defaults are 8231/18231 (Testnet)
EXPOSE 8231
EXPOSE 18231

# Data volumes, if you prefer mounting a host directory use "-v /path:/mnt/zen" command line
# option (folder ownership will be changed to the same UID/GID as provided by the docker run command)
VOLUME ["/mnt/zen"]

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["zend"]