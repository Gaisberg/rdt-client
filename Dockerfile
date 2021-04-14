# Stage 1 - Build the frontend
FROM amd64/node:15.5-buster AS node-build-env

RUN mkdir /appclient
WORKDIR /appclient

RUN \
   git clone https://github.com/rogerfar/rdt-client.git . && \
   cd client && \
   npm ci && \
   npx ng build --prod --output-path=out

# Stage 2 - Build the backend
FROM mcr.microsoft.com/dotnet/sdk:5.0.103-alpine3.13-amd64 AS dotnet-build-env

RUN mkdir /appserver
WORKDIR /appserver

RUN \
   git clone https://github.com/rogerfar/rdt-client.git . && \
   cd server && \
   if [ "$BUILDPLATFORM" = "arm/v7" ] ; then dotnet restore -r linux-arm RdtClient.sln ; else dotnet restore RdtClient.sln ; fi && \
   if [ "$BUILDPLATFORM" = "arm/v7" ] ; then dotnet publish -r linux-arm -c Release -o out ; else dotnet publish -c Release -o out ; fi

# Stage 3 - Build runtime image
FROM ghcr.io/linuxserver/baseimage-mono:LTS

# set version label
ARG BUILD_DATE
ARG VERSION
ARG RDTCLIENT_VERSION
LABEL build_version="Linuxserver.io extended version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="ravensorb"

# set environment variables
ARG DEBIAN_FRONTEND="noninteractive"
ENV XDG_CONFIG_HOME="/config/xdg"
ENV RDTCLIENT_BRANCH="main"

RUN mkdir /app || true && mkdir -p /data/downloads /data/db || true && \
    echo "**** Updating package information ****" && \ 
    apt update -y -qq && \
    apt install -y -qq wget && \
    echo "**** Installing dotnet ****" && \
    wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb  && \
    dpkg -i packages-microsoft-prod.deb 2> /dev/null && \
    rm packages-microsoft-prod.deb && \
    apt update -y -qq && \
    apt install -y -qq apt-transport-https dotnet-runtime-5.0 aspnetcore-runtime-5.0 && \
    echo "**** Cleaning image ****" && \
    apt-get -y -qq -o Dpkg::Use-Pty=0 clean && apt-get -y -qq -o Dpkg::Use-Pty=0 purge && \
    echo "**** Setting permissions ****" && \
    chown -R abc:abc /data && \
    rm -rf \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/* || true

WORKDIR /app
COPY --from=dotnet-build-env /appserver/server/out .
COPY --from=node-build-env /appclient/client/out ./wwwroot

# ports and volumes
EXPOSE 6500
VOLUME ["/config", "/data" ]

ENTRYPOINT ["dotnet", "RdtClient.Web.dll"]