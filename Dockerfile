# syntax=docker/dockerfile:1.4


ARG FILEBOT_VERSION=5.2.3


## ** download filebot portable and xpra www customizations
FROM alpine:3.20 AS filebot
ARG FILEBOT_VERSION
RUN set -eux \
 && apk --no-cache add curl \
 && mkdir -p /tmp/filebot \
 && curl -fsSL "https://get.filebot.net/filebot/FileBot_${FILEBOT_VERSION}/FileBot_${FILEBOT_VERSION}-portable.tar.xz" \
    | tar xJ -C /tmp/filebot \
 && mkdir -p /opt/filebot \
 && cp -a /tmp/filebot/jar /opt/filebot/ \
 ## ** fetch xpra www customizations from upstream repository
 && curl -fsSL https://github.com/filebot/filebot-docker/archive/refs/heads/master.tar.gz -o /tmp/repo.tar.gz \
 && mkdir -p /tmp/repo \
 && tar -xzf /tmp/repo.tar.gz -C /tmp/repo --strip-components=1 \
 && mkdir -p /opt/xpra-www \
 && cp -a /tmp/repo/xpra/usr/share/xpra/www/. /opt/xpra-www/ \
 && rm -rf /tmp/repo /tmp/repo.tar.gz /tmp/filebot


## ** runtime
FROM alpine:3.20
ARG FILEBOT_VERSION

LABEL maintainer="Reinhard Pointner <rednoah@filebot.net>"


ENV FILEBOT_VERSION="${FILEBOT_VERSION}"
ENV HOME="/data"
ENV LANG="C.UTF-8"

ENV PUID="1000"
ENV PGID="1000"
ENV PUSER="filebot"
ENV PGROUP="filebot"

ENV XPRA_BIND="0.0.0.0"
ENV XPRA_PORT="5454"
ENV XPRA_AUTH="none"


## ** install dependencies and xpra
RUN set -eux \
 && apk --no-cache add \
    openjdk17-jre \
    sudo \
    coreutils \
    xpra \
    xauth \
    dbus-x11 \
    zenity \
    ttf-dejavu \
    adwaita-icon-theme \
    font-wqy-zenhei \
    xdg-utils \
    desktop-file-utils \
 ## ** java-jna-native only available in edge community
 && apk --no-cache add \
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
    java-jna-native \
 ## ** silence xpra startup error messages
 && mkdir -m 777 -p /tmp/xdg/xpra \
 && rm -f /usr/share/xpra/www/default-settings.* \
 && mkdir -p /run/user && chmod 777 /run/user \
 && mkdir -m 777 -p /run/xpra \
 && chmod 775 /run/xpra \
 && mkdir -m 777 -p /etc/xdg/menus \
 && echo "<Menu/>" > /etc/xdg/menus/kde-debian-menu.menu \
 && echo "<Menu/>" > /etc/xdg/menus/debian-menu.menu


## ** copy filebot portable and xpra www from build stage
COPY --from=filebot /opt/filebot /opt/filebot
COPY --from=filebot /opt/xpra-www /usr/share/xpra/www


## ** inline filebot launcher (replaces deb-installed /usr/bin/filebot)
COPY --chmod=0755 <<'EOF' /usr/bin/filebot
#!/bin/sh
exec java \
  --add-exports=java.desktop/sun.swing=ALL-UNNAMED \
  --add-exports=java.desktop/sun.awt=ALL-UNNAMED \
  --add-opens=java.desktop/sun.swing=ALL-UNNAMED \
  --add-opens=java.desktop/sun.awt=ALL-UNNAMED \
  -Dapplication.deployment=docker \
  -Duser.home="${HOME:-/data}" \
  -Dnet.filebot.UserFiles.trash=XDG \
  ${FILEBOT_OPTS:-} \
  -jar /opt/filebot/jar/filebot.jar \
  "$@"
EOF


## ** copy launcher scripts from build context
COPY --chmod=0755 generic/opt/ /opt/


EXPOSE $XPRA_PORT


ENTRYPOINT ["/opt/bin/run-as-user", "/opt/bin/run", "/opt/filebot-xpra/start"]
