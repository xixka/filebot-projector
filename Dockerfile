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
    xpra \
    zenity \
    ttf-dejavu \
    adwaita-icon-theme \
    font-wqy-zenhei \
 ## ** java-jna-native only available in edge community
 && apk --no-cache add \
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
    java-jna-native \
 ## ** remove unneeded icons to reduce image size
 && rm -rf /usr/share/icons/Adwaita/cursors \
 && find /usr/share/icons/Adwaita -type f -name '*.svg' -delete 2>/dev/null || true \
 && find /usr/share/icons/Adwaita -type f -name '*.png' -delete 2>/dev/null || true \
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
  -Dapplication.deployment=docker \
  -Duser.home="${HOME:-/data}" \
  -Dnet.filebot.UserFiles.trash=XDG \
  ${FILEBOT_OPTS:-} \
  -jar /opt/filebot/jar/filebot.jar \
  "$@"
EOF


## ** inline launcher scripts
COPY --chmod=0755 <<'EOF' /opt/bin/run
#!/bin/sh -u
# print license activation help for new users
if [ ! -f "$HOME/license.txt" ]; then
	/opt/share/activate.sh
fi
# set working directory
cd "$HOME"
# execute filebot with the given arguments
exec "$@"
EOF

COPY --chmod=0755 <<'EOF' /opt/bin/run-as-user
#!/bin/sh -u
# run as root (or explicitly specified docker --user)
if [ 0 -eq "$PUID" ] || [ 0 -ne "$(id -u)" ]; then
	exec "$@"
fi
# configure normal user
export HOME="$HOME/$PUSER"
(
	addgroup -g "$PGID" "$PGROUP" 2>/dev/null || true
	adduser -u "$PUID" -G "$PGROUP" -D -h "$HOME" "$PUSER" 2>/dev/null || true
	mkdir -p "$HOME"
	chown -R "$PUID:$PGID" "$HOME"
) > /dev/null 2>&1
# run as normal user
sudo --user "#$PUID" --group "#$PGID" --non-interactive --preserve-env -- "$@"
EOF

COPY --chmod=0755 <<'EOF' /opt/share/activate.sh
#!/bin/sh
echo "
--------------------------------------------------------------------------------
Hello! Do you need help Getting Started?
# FAQ
https://www.filebot.net/linux/docker.html
# Read License Key from Console
docker run --rm -it -v data:/data -e PUID=$(id -u) -e PGID=$(id -g) rednoah/filebot --license
--------------------------------------------------------------------------------
"
echo "
\033[38;5;214m
# env
USER=$(id -un)($(id -u))
HOME=$HOME
\033[0m
"
if [ "$(id -u)" -eq 0 ]; then
echo "
\033[38;5;196m
	!!! YOU ARE RUNNING AS ROOT AND NOT AS NORMAL USER !!!
\033[0m
"
fi
if [ ! -d "$HOME" ] || [ "$(df -P "$HOME" | awk 'NR==2{print $1}')" = "overlay" ]; then
echo "
\033[38;5;196m
	!!! YOU DID NOT BIND MOUNT $HOME TO A PERSISTENT HOST FOLDER !!!
	All data stored to the application data folder \`$HOME\` will be lost on container shutdown, like tears in rain.
	Please add \`-v data:/data\` to your \`docker\` command lest your application data, such as license key, be lost in time.
\033[0m
"
fi
EOF

COPY --chmod=0755 <<'EOF' /opt/filebot-xpra/start
#!/bin/sh
# silence xpra startup error messages
export XDG_RUNTIME_DIR="/tmp"
mkdir -m 700 -p "/tmp/xpra/0"
mkdir -m 700 -p "/run/user/$PUID/xpra"
# run xpra service
xpra start \
  --start-child="filebot" \
  --bind-tcp="$XPRA_BIND:$XPRA_PORT" \
  --tcp-auth="$XPRA_AUTH" \
  --daemon=no \
  --pulseaudio=no \
  --bell=no \
  --printing=no \
  --speaker=disabled \
  --microphone=disabled \
  --system-tray=no \
  --min-quality='80' \
  --video-scaling='0' \
  --html=on \
  $XPRA_OPTS 2>&1 \
| grep -v \
  -e 'pointer device emulation using XTest' \
  -e 'uinput' \
  -e "missing 'audio' module" \
  -e 'for Python 3' \
  -e 'failed to choose pdev' \
  -e 'failed to create drisw screen' \
  -e 'some GStreamer elements are missing' \
  -e 'vah264lpenc' \
  -e 'gtk_widget_realize' \
  -e 'encoding failed' \
  -e 'all the codecs have failed' \
  -e '.X11-unix will not be created' \
  -e 'created unix domain socket' \
  -e '/run/user/1000/xpra' \
  -e '/home/ubuntu/.xpra' \
  -e '/tmp/xpra/0/socket' \
  -e 'created abstract sockets' \
  -e '@xpra/0' \
  -e '/data/filebot/.xpra' \
  -e 'private server socket path' \
  -e '/tmp/xpra/0/pulse/pulse/native' \
  -e 'cannot create group socket' \
  -e '/run/dbus/system_bus_socket' \
  -e 'Errno 13' \
  -e 'import asyncore' \
  -e 'watching for applications menu changes' \
  -e '/usr/share/applications' \
  -e '/usr/share/xpra/www' \
  -e '/tmp/xpra/0/server.pid' \
  -e 'ibus-daemon' \
  -e 'D-Bus notification forwarding is available' \
  -e 'org.freedesktop.DBus.Error.Failed: No global engine' \
  -e 'start menu entries' \
  -e 'No OpenGL_accelerate module loaded' \
  -e 'xkbcomp' \
  -e 'Could not resolve keysym' \
  -e 'DeprecationWarning' \
  -e '_stop_event' \
  -e 'webcam forwarding is disabled' \
  -e 'video4linux' \
  -e 'v4l2loopback' \
  -e 'webcam' \
  -e 'lpinfo command failed' \
  -e '/usr/sbin/lpinfo' \
  -e 'printer forwarding enabled' \
  -e 'IPv6 loopback address is not supported' \
  -e 'org.gnome.Nautilus' \
  -e 'org.freedesktop.Tracker3.Miner.Files'
EOF


EXPOSE $XPRA_PORT


ENTRYPOINT ["/opt/bin/run-as-user", "/opt/bin/run", "/opt/filebot-xpra/start"]
