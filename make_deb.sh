#!/bin/bash
WORKDIR=work
RUBY=ruby
BINDIR=usr/games
LIBDIR=usr/lib/games/ninix-kagari

SAORIPATH=/usr/lib/games/ninix-kagari/saori
SOPATH=${SAORIPATH}:/usr/lib/games/ninix-kagari/kawari8:/usr/lib/games/ninix-kagari/yaya:/usr/lib/games/ninix-kagari/kagari

VERSION=$(./print_version.rb)

mkdir -p ${WORKDIR}/${BINDIR} ${WORKDIR}/${LIBDIR}
cp -r debian ${WORKDIR}/DEBIAN
sed -e "s,@ruby,${RUBY},g" -e "s,@libdir,/${LIBDIR},g" -e "s,@so_path,${SOPATH},g" -e "s,@saori_path,${SAORIPATH},g" < bin/ninix.in > ${WORKDIR}/usr/games/ninix
cp -r lib/* ${WORKDIR}/usr/lib/games/ninix-kagari/

pushd ${WORKDIR}
find usr -type f -exec md5sum {} \+ > DEBIAN/md5sums
INSTALLED_SIZE=$(du -sk usr | cut -f 1)
sed -i -e "s/@installed_size/${INSTALLED_SIZE}/g" -e "s/@version/${VERSION}/g" DEBIAN/control
popd
fakeroot dpkg-deb --build ${WORKDIR} .
