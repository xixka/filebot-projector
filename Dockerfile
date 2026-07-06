# syntax=docker/dockerfile:1.4
FROM ubuntu:25.04

LABEL maintainer="Reinhard Pointner <rednoah@filebot.net>"


ENV FILEBOT_VERSION="5.2.3"


RUN set -eux \
 ## ** install dependencies
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jre libjna-java mediainfo libchromaprint-tools trash-cli unzip unrar p7zip-full p7zip-rar xz-utils ffmpeg mkvtoolnix atomicparsley imagemagick webp libavif-bin libjxl-tools sudo git gnupg curl file tree inotify-tools rsync jdupes duperemove \
 ## ** remove large recommended dependencies that are not actually used
    mesa-vulkan-drivers- pocketsphinx-en-us- qt6-translations-l10n- adwaita-icon-theme- poppler-data- fonts-urw-base35- fonts-droid-fallback- fonts-dejavu-core- fonts-dejavu-mono- \
 && rm -rvf /var/lib/apt/lists/* \
 ## ** FIX libjna-java (see https://bugs.launchpad.net/ubuntu/+source/libjna-java/+bug/2000863)
 && ln -s /usr/lib/*-linux-gnu*/jni /usr/lib/jni \
 ## ** print installed packages index
 && dpkg-query -W -f='${Installed-Size} ${Package}\n' | sort -n


RUN set -eux \
 ## ** install filebot
 && curl -fsSL "https://raw.githubusercontent.com/filebot/plugins/master/gpg/maintainer.pub" | gpg --dearmor --output "/usr/share/keyrings/filebot.gpg"  \
 && echo "deb [arch=all signed-by=/usr/share/keyrings/filebot.gpg] https://get.filebot.net/deb/ universal main" > /etc/apt/sources.list.d/filebot.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends filebot \
 && rm -rvf /var/lib/apt/lists/* \
 ## ** generate CDS archive
 && java -Xshare:dump -XX:SharedClassListFile="/usr/share/filebot/jsa/classes.jsa.lst" -XX:SharedArchiveFile="/usr/share/filebot/jsa/classes.jsa" -jar "/usr/share/filebot/jar/filebot.jar" \
 ## ** apply custom application configuration
 && sed -i 's|APP_DATA=.*|APP_DATA="$HOME"|g; s|-Dapplication.deployment=deb|-Dapplication.deployment=docker -Duser.home="$HOME" -Dnet.filebot.UserFiles.trash=XDG -XX:SharedArchiveFile=/usr/share/filebot/jsa/classes.jsa|g' /usr/bin/filebot


RUN set -eux \
 ## ** install projector
 && curl -fsSL -o /tmp/projector-server.zip https://github.com/JetBrains/projector-server/releases/download/v1.8.1/projector-server-v1.8.1.zip \
 && unzip /tmp/projector-server.zip -d /opt \
 && mv -v /opt/projector-server-* /opt/projector-server \
 && rm -rvf /opt/projector-server/lib/slf4j-* /opt/projector-server/bin /tmp/projector-server.zip \
 ## ** apply custom application configuration for projector
 && sed -i 's|-jar "$FILEBOT_HOME/jar/filebot.jar"|-classpath "/opt/projector-server/lib/*:/usr/share/filebot/jar/*" -Dorg.jetbrains.projector.server.enable=true -Dorg.jetbrains.projector.server.classToLaunch=net.filebot.Main org.jetbrains.projector.server.ProjectorLauncher|g; s|-XX:SharedArchiveFile=/usr/share/filebot/jsa/classes.jsa||g; s|-XX:+DisableAttachMechanism|-XX:+EnableDynamicAgentLoading -Djdk.attach.allowAttachSelf=true -Dnet.filebot.UserFiles.fileChooser=Swing -Dnet.filebot.glass.effect=false --add-opens=java.desktop/sun.font=ALL-UNNAMED --add-opens=java.desktop/java.awt=ALL-UNNAMED --add-opens=java.desktop/sun.java2d=ALL-UNNAMED --add-opens=java.desktop/java.awt.peer=ALL-UNNAMED --add-opens=java.desktop/sun.awt.image=ALL-UNNAMED --add-opens=java.desktop/java.awt.dnd.peer=ALL-UNNAMED --add-opens=java.desktop/java.awt.image=ALL-UNNAMED|g' /usr/bin/filebot


# install custom launcher scripts
COPY generic /

# inline projector launcher script
COPY --chmod=0755 <<'EOF' /opt/filebot-projector/start
#!/bin/sh
filebot "$@" | egrep -v 'IdeState|isIdeAttached|ProjectorBatchTransformer|InjectorAgent|IDE'
EOF


ENV HOME="/data"
ENV LANG="C.UTF-8"

ENV PUID="1000"
ENV PGID="1000"
ENV PUSER="filebot"
ENV PGROUP="filebot"


EXPOSE 8887

ENTRYPOINT ["/opt/bin/run-as-user", "/opt/bin/run", "/opt/filebot-projector/start"]
