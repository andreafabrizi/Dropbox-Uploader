FROM hypriot/rpi-alpine-scratch
MAINTAINER github@vanefferenonline.nl

RUN apk update && apk add bash curl
COPY *.sh /opt/dropbox_uploader/
RUN mkdir -p /config && mkdir -p /workdir

VOLUME /config /workdir

WORKDIR /workdir

ENTRYPOINT ["/opt/dropbox_uploader/dropbox_uploader.sh", "-f", "/config/dropbox_uploader.conf"]
