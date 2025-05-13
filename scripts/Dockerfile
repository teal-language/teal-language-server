FROM python:3-alpine
WORKDIR /app
RUN apk update && apk upgrade
RUN apk add bash git coreutils build-base readline-dev wget cmake icu-dev
ADD create_binary.sh /app
RUN "./create_binary.sh"
