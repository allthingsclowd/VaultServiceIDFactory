FROM alpine
RUN apk add --update \
    curl bash jq \
    && rm -rf /var/cache/apk/*
ADD $TRAVIS_BUILD_DIR/VaultServiceIDFactory /
ADD "scripts/docker_init.sh" /
CMD ["/docker_init.sh"]