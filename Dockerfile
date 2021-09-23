FROM alpine:3.13

LABEL maintainer="peez@stiffi.de"

RUN apk add --no-cache bash curl
COPY / /opt/dropbox_uploader
RUN mkdir -p /config && mkdir -p /workdir

VOLUME /config /workdir

WORKDIR /workdir

ENTRYPOINT ["/opt/dropbox_uploader/dropbox_uploader.sh", "-f", "/config/dropbox_uploader.conf"]
