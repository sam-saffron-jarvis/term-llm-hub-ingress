FROM alpine:3.22.5

RUN apk add --no-cache autossh openssh-client

COPY entrypoint.sh /usr/local/bin/autossh-entrypoint
RUN chmod 0755 /usr/local/bin/autossh-entrypoint

ENTRYPOINT ["/usr/local/bin/autossh-entrypoint"]
