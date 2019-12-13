# Migration test

## Actions to run locally
```sh
    #1. source install.sh
    source tests/install.sh

    #2. build master cds version
    clone_master
    build_cds_master

    #3. build current cds version
    build_cds_current

    #4. build debpacker
    build_debpacker
```

## Boot the Vagrant vm and ssh into
```sh
    vagrant up
    vagrant ssh
```

## Actions to run in the vm
```sh
    #1. connect as root and go to /vagrant
    sudo su
    cd /vagrant

    #2. source install.sh
    source tests/install.sh

    #3. build smtpmock
    build_smtpmock

    #4. package both cds versions
    package_cds_master
    package_cds_current

    #5. install dependencies
    install_dependencies

    #6. install master version
    install_master
    post_install
```

