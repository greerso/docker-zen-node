FROM node:buster-slim

ENV TINI_VERSION v0.16.1
ENV NODE_ENV production
ENV ZENCONF /mnt/zen/config/zen.conf
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

RUN apt-get update \
&& DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install curl jq gnupg ca-certificates gosu git \
&& gosu nobody true

WORKDIR /home/node/

RUN cd /home/node/ \
    && git clone https://github.com/ZencashOfficial/secnodetracker.git \
    && cd secnodetracker \
    && npm install

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/tini", "--", "/usr/local/bin/entrypoint.sh"]
