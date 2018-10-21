#!/bin/bash -e

. /etc/os-release
print_usage() {
    echo "build_deb.sh -target <codename>"
    echo "  --target target distribution codename"
    exit 1
}
TARGET=
while [ $# -gt 0 ]; do
    case "$1" in
        "--target")
            TARGET=$2
            shift 2
            ;;
        *)
            print_usage
            ;;
    esac
done

is_redhat_variant() {
    [ -f /etc/redhat-release ]
}
is_debian_variant() {
    [ -f /etc/debian_version ]
}


pkg_install() {
    if is_redhat_variant; then
        sudo yum install -y $1
    elif is_debian_variant; then
        sudo apt-get install -y $1
    else
        echo "Requires to install following command: $1"
        exit 1
    fi
}

if [ ! -e dist/debian/build_deb.sh ]; then
    echo "run build_deb.sh in top of scylla dir"
    exit 1
fi
if [ "$(arch)" != "x86_64" ]; then
    echo "Unsupported architecture: $(arch)"
    exit 1
fi

if [ -e debian ] || [ -e build/release ]; then
    sudo rm -rf debian build
    mkdir build
fi
if is_debian_variant; then
    sudo apt-get -y update
fi
# this hack is needed since some environment installs 'git-core' package, it's
# subset of the git command and doesn't works for our git-archive-all script.
if is_redhat_variant && [ ! -f /usr/libexec/git-core/git-submodule ]; then
    sudo yum install -y git
fi
if [ ! -f /usr/bin/git ]; then
    pkg_install git
fi
if [ ! -f /usr/bin/python ]; then
    pkg_install python
fi
if [ ! -f /usr/sbin/pbuilder ]; then
    pkg_install pbuilder
fi
if [ ! -f /usr/bin/mvn ]; then
    pkg_install maven
fi
if [ ! -f /usr/bin/dh_testdir ]; then
    pkg_install debhelper
fi


if [ -z "$TARGET" ]; then
    if is_debian_variant; then
        if [ ! -f /usr/bin/lsb_release ]; then
            pkg_install lsb-release
        fi
        TARGET=`lsb_release -c|awk '{print $2}'`
    else
        echo "Please specify target"
        exit 1
    fi
fi

VERSION=$(./SCYLLA-VERSION-GEN)
SCYLLA_VERSION=$(cat build/SCYLLA-VERSION-FILE | sed 's/\.rc/~rc/')
SCYLLA_RELEASE=$(cat build/SCYLLA-RELEASE-FILE)
echo $VERSION > version
./scripts/git-archive-all --extra version --force-submodules --prefix scylla-jmx ../scylla-jmx_$SCYLLA_VERSION-$SCYLLA_RELEASE.orig.tar.gz 

cp -a dist/debian/debian debian
cp dist/debian/changelog.in debian/changelog
cp dist/debian/rules.in debian/rules
sed -i -e "s/@@VERSION@@/$SCYLLA_VERSION/g" debian/changelog
sed -i -e "s/@@RELEASE@@/$SCYLLA_RELEASE/g" debian/changelog
sed -i -e "s/@@CODENAME@@/$TARGET/g" debian/changelog
if [ "$TARGET" = "trusty" ] || [ "$TARGET" = "xenial" ] || [ "$TARGET" = "yakkety" ] || [ "$TARGET" = "zesty" ] || [ "$TARGET" = "artful" ]; then
    sed -i -e "s/@@REVISION@@/0ubuntu1~$TARGET/g" debian/changelog
else
    sed -i -e "s/@@REVISION@@/1~$TARGET/g" debian/changelog
fi
if [ "$TARGET" = "trusty" ]; then
    sed -i -e "s/@@DH_INSTALLINIT@@/--upstart-only/g" debian/rules
else
    sed -i -e "s/@@DH_INSTALLINIT@@//g" debian/rules
fi
cp dist/common/systemd/scylla-jmx.service.in debian/scylla-jmx.service
sed -i -e "s#@@SYSCONFDIR@@#/etc/default#g" debian/scylla-jmx.service

sudo rm -fv /var/cache/pbuilder/scylla-jmx-$TARGET.tgz
sudo -E DIST=$TARGET /usr/sbin/pbuilder clean --configfile ./dist/debian/pbuilderrc
sudo -E DIST=$TARGET /usr/sbin/pbuilder create --configfile ./dist/debian/pbuilderrc
sudo -E DIST=$TARGET /usr/sbin/pbuilder update --configfile ./dist/debian/pbuilderrc
if [ "$TARGET" = "jessie" ]; then
    echo "apt-get install -y -t jessie-backports ca-certificates-java" > build/jessie-pkginst.sh
    chmod a+rx build/jessie-pkginst.sh
    sudo -E DIST=$TARGET /usr/sbin/pbuilder execute --configfile ./dist/debian/pbuilderrc  build/jessie-pkginst.sh
fi
sudo -E DIST=$TARGET pdebuild --configfile ./dist/debian/pbuilderrc --buildresult build/debs
