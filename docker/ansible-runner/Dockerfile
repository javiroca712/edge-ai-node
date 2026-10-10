FROM alpine:latest
RUN apk add --no-cache ansible-core openssh-client sshpass bash
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
WORKDIR /work
ENTRYPOINT ["/entrypoint.sh"]
