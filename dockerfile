FROM alpine
RUN apk add --update \
    curl bash jq \
    && rm -rf /var/cache/apk/*
ADD "/home/travis/VaultServiceIDFactory" /VaultServiceIDFactory
ADD "scripts/docker_init.sh" /docker_init.sh
CMD ["/docker_init.sh"]