# syntax=docker/dockerfile:1.4

ARG FILEBOT_VERSION=5.2.3

## Stage 1: download and extract filebot portable
FROM --platform=$BUILDPLATFORM alpine:3.20 AS filebot
ARG FILEBOT_VERSION
ARG FILEBOT_URL=https://get.filebot.net/filebot/FileBot_${FILEBOT_VERSION}/FileBot_${FILEBOT_VERSION}-portable.tar.xz
RUN apk --no-cache add curl \
 && mkdir -p /tmp/filebot \
 && curl -# -L -f "${FILEBOT_URL}" | tar xJ -C /tmp/filebot \
 && mkdir -p /opt/filebot \
 && cp -R /tmp/filebot/jar /opt/filebot/

## Stage 2: runtime with projector
FROM alpine:3.20

LABEL maintainer="Reinhard Pointner <rednoah@filebot.net>"

ARG FILEBOT_VERSION
ENV FILEBOT_VERSION=${FILEBOT_VERSION}
ENV HOME="/data"
ENV LANG="C.UTF-8"
ENV PUID="1000"
ENV PGID="1000"
ENV PUSER="filebot"
ENV PGROUP="filebot"

# install dependencies + projector
RUN set -eux \
 && apk add --no-cache \
      sudo \
      trash-cli \
      unzip \
      curl \
      openjdk17-jre \
 && apk add --no-cache \
      --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
      java-jna-native \
      font-wqy-microhei \
 # install projector
 && curl -fsSL -o /tmp/projector-server.zip https://github.com/JetBrains/projector-server/releases/download/v1.8.1/projector-server-v1.8.1.zip \
 && unzip /tmp/projector-server.zip -d /opt \
 && mv /opt/projector-server-* /opt/projector-server \
 && rm -rf /opt/projector-server/lib/slf4j-* /opt/projector-server/bin /tmp/projector-server.zip \
 && apk del --no-cache unzip curl

# install filebot
COPY --from=filebot /opt/filebot /opt/filebot

# create filebot launcher with projector config baked in
COPY --chmod=0755 <<'EOF' /usr/local/bin/filebot
#!/bin/sh
export APP_DATA="$HOME"
exec java \
  -classpath "/opt/projector-server/lib/*:/opt/filebot/jar/*" \
  -Dapplication.deployment=docker \
  -Duser.home="$HOME" \
  -Dnet.filebot.UserFiles.trash=XDG \
  -Dorg.jetbrains.projector.server.enable=true \
  -Dorg.jetbrains.projector.server.classToLaunch=net.filebot.Main \
  -XX:+EnableDynamicAgentLoading \
  -Djdk.attach.allowAttachSelf=true \
  -Dnet.filebot.UserFiles.fileChooser=Swing \
  -Dnet.filebot.glass.effect=false \
  --add-opens=java.desktop/sun.font=ALL-UNNAMED \
  --add-opens=java.desktop/java.awt=ALL-UNNAMED \
  --add-opens=java.desktop/sun.java2d=ALL-UNNAMED \
  --add-opens=java.desktop/java.awt.peer=ALL-UNNAMED \
  --add-opens=java.desktop/sun.awt.image=ALL-UNNAMED \
  --add-opens=java.desktop/java.awt.dnd.peer=ALL-UNNAMED \
  --add-opens=java.desktop/java.awt.image=ALL-UNNAMED \
  org.jetbrains.projector.server.ProjectorLauncher "$@"
EOF

# install custom launcher scripts
COPY generic /
RUN chmod +x /opt/bin/run-as-user /opt/bin/run /opt/share/activate.sh

# inline projector launcher script
COPY --chmod=0755 <<'EOF' /opt/filebot-projector/start
#!/bin/sh
filebot "$@" | grep -E -v 'IdeState|isIdeAttached|ProjectorBatchTransformer|InjectorAgent|IDE'
EOF

EXPOSE 8887

ENTRYPOINT ["/opt/bin/run-as-user", "/opt/bin/run", "/opt/filebot-projector/start"]
