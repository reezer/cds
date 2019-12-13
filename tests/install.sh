#!/bin/bash

clone_master() {
    (rm -rf tests/tmp/master && mkdir -p tests/tmp/master)
    (cd tests/tmp/master && git clone https://github.com/ovh/cds.git --branch master --single-branch)
}

build_debpacker() {
    (cd tools/debpacker && GO111MODULE=on make build)
}
    
build_smtpmock() {
    (cd /vagrant/tools/smtpmock/cmd/smtpmocksrv && docker build -t smtpmocksrv .)
}

install_dependencies() {
    ln -s /vagrant/tools/debpacker/dist/debpacker-linux-amd64 /usr/bin/debpacker
    docker rm -f redis-cds postgres-cds smtpmocksrv
    docker run  -p 2023:2023 -p 2024:2024 -d --name  smtpmocksrv smtpmocksrv
    (cd /vagrant/engine && make test-db-start-docker-light test-redis-start-docker)
    curl https://github.com/ovh/venom/releases/download/v0.27.0/venom.linux-amd64 -L -o /usr/bin/venom
    chmod +x /usr/bin/venom
}

build_cds_master() {
    cp ./tests/tmp/master/cds/cli/cdsctl/Makefile ./tests/tmp/master/cds/cli/cdsctl/Makefile.bkp
    sed "s/build: \$(TARGET_DIR) \$(TARGET_BINARIES_VARIANT) \$(TARGET_BINARIES)/build: \$(TARGET_DIR) \$(TARGET_BINARIES_VARIANT)/g" ./tests/tmp/master/cds/cli/cdsctl/Makefile.bkp > ./tests/tmp/master/cds/cli/cdsctl/Makefile
    (cd tests/tmp/master/cds && OS="linux" ARCH="amd64" GO111MODULE=on make build)
}

build_cds_current() {
    OS="linux" ARCH="amd64" GO111MODULE=on make clean build
}

package_cds_master() {
    (cd /vagrant/tests/tmp/master/cds && make deb)
}

package_cds_current() {
    (cd /vagrant && make deb)
}

install_master() {
    dpkg -i /vagrant/tests/tmp/master/cds/target/cds-engine.deb
}

install_current() {
    dpkg -i /vagrant/target/cds-engine.deb
}

post_install() {
    usermod -aG docker cds-engine

    chmod +x /usr/bin/cds-engine-linux-amd64

    (mkdir -p /var/lib/cds-engine/artifacts && chown cds-engine:cds-engine /var/lib/cds-engine/artifacts)

    /usr/bin/cds-engine-linux-amd64 database upgrade --db-host localhost --db-port 5432 --db-user cds --db-password cds --db-name cds --db-sslmode disable --migrate-dir /var/lib/cds-engine/sql

    /usr/bin/cds-engine-linux-amd64 config new api ui hatchery:swarm hooks > /etc/cds-engine/cds-engine.new.toml

    export IP_ADDR=$(hostname -I | awk '{print $1}')
    /usr/bin/cds-engine-linux-amd64 config edit /etc/cds-engine/cds-engine.new.toml \
        api.defaultArch=amd64 \
        api.defaultOS=linux \
        api.directories.download=/var/lib/cds-engine \
        api.artifact.mode=local \
        api.artifact.local.baseDirectory=/var/lib/cds-engine/artifacts \
        api.smtp.disable=false \
        api.smtp.port=2023 \
        api.smtp.host=localhost \
        api.url.api=http://$IP_ADDR:8081 \
        api.url.ui=http://$IP_ADDR:4200 \
        hooks.name=hooks \
        hooks.api.http.url=http://$IP_ADDR:8081 \
        ui.name=ui \
        ui.url=http://$IP_ADDR:4200 \
        ui.staticdir=/var/lib/cds-engine/ui \
        ui.api.http.url=http://$IP_ADDR:8081 \
        ui.http.port=4200 \
        log.level=debug \
        hatchery.swarm.commonConfiguration.name=hatchery-swarm \
        hatchery.swarm.ratioService=50 \
        hatchery.swarm.commonConfiguration.api.http.url=http://$IP_ADDR:8081 \
        hatchery.swarm.dockerEngines.default.host=unix:///var/run/docker.sock \
        hatchery.swarm.dockerEngines.default.maxContainers=10 \
        > /etc/cds-engine/cds-engine.toml

    sed -i 's/Environment=.*/Environment="CDS_SERVICE=api hooks hatchery:swarm ui"/' /lib/systemd/system/cds-engine.service
    systemctl daemon-reload

    systemctl restart cds-engine
}

migrate_current() {
    systemctl stop cds-engine    

    dpkg -i /vagrant/target/cds-engine.deb
    chmod +x /usr/bin/cds-engine-linux-amd64

    /usr/bin/cds-engine-linux-amd64 database upgrade --db-host localhost --db-port 5432 --db-user cds --db-password cds --db-name cds --db-sslmode disable --migrate-dir /var/lib/cds-engine/sql

    cp /etc/cds-engine/cds-engine.toml /etc/cds-engine/cds-engine.bkp.toml
    /usr/bin/cds-engine-linux-amd64 config regen /etc/cds-engine/cds-engine.bkp.toml /etc/cds-engine/cds-engine.regen.toml
    
    /usr/bin/cds-engine-linux-amd64 config edit /etc/cds-engine/cds-engine.regen.toml \
        api.name=api \
        api.auth.local.enabled=true \
        > /etc/cds-engine/cds-engine.toml

    sed -i 's/Environment=.*/Environment="CDS_SERVICE=api"/' /lib/systemd/system/cds-engine.service
    systemctl daemon-reload

    systemctl restart cds-engine

    # run a venom test to reset admin password then create some consumers for exsiting services
}

test_master() {
    cp /var/lib/cds-engine/cdsctl-linux-amd64-nokeychain /usr/bin/cdsctl
    chmod +x /usr/bin/cdsctl
    (cd /vagrant/tests/tmp/master/cds/tests && ./test.sh)
}