FROM alpine
RUN apk add --update \
    curl bash jq \
    && rm -rf /var/cache/apk/*
ADD /usr/local/bin/VaultServiceIDFactory /VaultServiceIDFactory
ADD /usr/local/bootstrap/scripts/docker_init.sh /docker_init.sh
CMD [/docker_init.sh]