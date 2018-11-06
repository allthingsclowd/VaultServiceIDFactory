FROM alpine
RUN apk add --update \
    curl bash jq \
    && rm -rf /var/cache/apk/*
RUN mkdir /factory 
ADD /home/travis/VaultServiceIDFactory /factory/VaultServiceIDFactory
ADD scripts/docker_init.sh /factory/docker_init.sh
CMD [/factory/docker_init.sh]