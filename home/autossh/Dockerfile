FROM alpine:3.22.5

ARG AUTOSSH_UID=1000
ARG AUTOSSH_GID=1000

RUN apk add --no-cache autossh openssh-client \
    && addgroup -g "$AUTOSSH_GID" autossh \
    && adduser -D -H -u "$AUTOSSH_UID" -G autossh autossh

COPY entrypoint.sh /usr/local/bin/autossh-entrypoint
RUN chmod 0755 /usr/local/bin/autossh-entrypoint

ENTRYPOINT ["/usr/local/bin/autossh-entrypoint"]
