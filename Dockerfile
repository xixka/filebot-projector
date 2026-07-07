FROM openjdk:17-alpine

LABEL maintainer="Reinhard Pointner <rednoah@filebot.net>"


ENV FILEBOT_VERSION="5.2.3"
ENV FILEBOT_URL="https://get.filebot.net/filebot/FileBot_$FILEBOT_VERSION/FileBot_$FILEBOT_VERSION-portable.tar.xz"
ENV FILEBOT_SHA256="0dae8364f9d465707ff30031d055dcc7c6b24907d96823ced3d4e979f1519d0c"
ENV FILEBOT_HOME="/opt/filebot"


RUN set -eux \
 ## ** install runtime dependencies
 && apk add --no-cache --update \
    mediainfo chromaprint p7zip unrar \
    xpra openbox xauth dbus-x11 \
    zenity xdg-utils xdg-user-dirs desktop-file-utils \
    ttf-dejavu font-wqy-zenhei \
    sudo wget \
 ## ** install java-jna-native from edge community
 && apk add --no-cache --update \
    java-jna-native \
    --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
 ## ** fetch and install filebot portable
 && wget -O /tmp/filebot.tar.xz "$FILEBOT_URL" \
 && echo "$FILEBOT_SHA256 */tmp/filebot.tar.xz" | sha256sum -c - \
 && mkdir -p "$FILEBOT_HOME" \
 && tar --extract --file /tmp/filebot.tar.xz --directory "$FILEBOT_HOME" \
 && rm -v /tmp/filebot.tar.xz \
 ## ** delete incompatible native binaries
 && find /opt/filebot/lib -type f -not -name libjnidispatch.so -delete \
 ## ** link /opt/filebot/data -> /data to persist application data files to the persistent data volume
 && ln -s /data /opt/filebot/data \
 ## ** create filebot command symlink
 && ln -s /opt/filebot/filebot.sh /usr/local/bin/filebot \
 ## ** silence xpra startup error messages
 && mkdir -m 777 -p /tmp/xdg/xpra \
 && rm -rvf /usr/share/xpra/www/default-settings.* \
 && chmod 777 /run/user \
 && mkdir -m 777 -p /run/xpra \
 && chmod 775 /run/xpra \
 && mkdir -m 777 -p /etc/xdg/menus \
 && echo "<Menu/>" > /etc/xdg/menus/kde-debian-menu.menu \
 && echo "<Menu/>" > /etc/xdg/menus/debian-menu.menu \
 ## ** clean up
 && rm -rf /var/cache/apk/*


# install custom launcher scripts
COPY xpra /


ENV HOME="/data"
ENV LANG="C.UTF-8"
ENV FILEBOT_OPTS="-Dapplication.deployment=docker -Dnet.filebot.archive.extractor=ShellExecutables -Duser.home=$HOME"

ENV PUID="1000"
ENV PGID="1000"
ENV PUSER="filebot"
ENV PGROUP="filebot"

ENV XPRA_BIND="0.0.0.0"
ENV XPRA_PORT="5454"
ENV XPRA_AUTH="none"


EXPOSE $XPRA_PORT


ENTRYPOINT ["/opt/bin/run-as-user", "/opt/bin/run", "/opt/filebot-xpra/start"]
