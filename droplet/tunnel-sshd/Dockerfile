FROM alpine:3.22.5

RUN apk add --no-cache openssh-server \
    && adduser -D -h /home/tunnel -s /bin/ash tunnel \
    && passwd -d tunnel \
    && mkdir -p /home/tunnel/.ssh /etc/ssh/keys /run/sshd \
    && chown -R tunnel:tunnel /home/tunnel \
    && chmod 0700 /home/tunnel/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/tunnel-sshd-entrypoint
RUN chmod 0755 /usr/local/bin/tunnel-sshd-entrypoint

EXPOSE 22022
ENTRYPOINT ["/usr/local/bin/tunnel-sshd-entrypoint"]
