FROM alpine:3.17.2
RUN apk update && \
    apk upgrade && \
    apk add haproxy openssl

COPY entrypoint.sh /app/entrypoint.sh

CMD ["/app/entrypoint.sh"]   