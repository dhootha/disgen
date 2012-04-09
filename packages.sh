#!/bin/bash

echo "Installing Packages"

ZION_SRC=/sources
#MAKEFLAGS="-j4"

function install_kernel_headers()
{
	cd $ZION_SRC
	echo "Removing old kernel folder"
	rm -rf linux-3.2.6
	echo "Extracting Linux kernel"
	tar -xf linux-3.2.6.tar.xz
	cd linux-3.2.6
	make mrproper
	make headers_check
	make INSTALL_HDR_PATH=dest headers_install
	find dest/include \( -name .install -o -name ..install.cmd \) -delete
	cp -rv dest/include/* /usr/include
	cd $ZION
}

function install_man_pages()
{
	cd $ZION_SRC
	echo "Extracting man pages"
	tar -xf man-pages-3.35.tar.gz
	cd man-pages-3.35
	make install
	cd $ZION
}

function install_glibc()
{
	cd $ZION_SRC
	echo "Removing old Glibc directory"
	rm -rf glibc-2.14.1
	echo "Extracting Glibc"
	tar -xf glibc-2.14.1.tar.bz2
	cd glibc-2.14.1
	DL=$(readelf -l /bin/sh | sed -n 's@.*interpret.*/tools\(.*\)]$@\1@p')
	sed -i "s|libs -o|libs -L/usr/lib -Wl,-dynamic-linker=$DL -o|" \
		scripts/test-installation.pl
	unset DL
	sed -i -e 's/"db1"/& \&\& $name ne "nss_test1"/' scripts/test-installation.pl
	sed -i 's|@BASH@|/bin/bash|' elf/ldd.bash.in
	patch -Np1 -i ../glibc-2.14.1-fixes-1.patch
	patch -Np1 -i ../glibc-2.14.1-sort-1.patch
	patch -Np1 -i ../glibc-2.14.1-gcc_fix-1.patch
	sed -i '195,213 s/PRIVATE_FUTEX/FUTEX_CLOCK_REALTIME/' \
		nptl/sysdeps/unix/sysv/linux/x86_64/pthread_rwlock_timed{rd,wr}lock.S
	mkdir -v build
	cd build
	case `uname -m` in
		i?86) echo "CFLAGS += -march=i486 -mtune=native -O3 -pipe" > configparms ;;
	esac
	../configure --prefix=/usr \
		--disable-profile --enable-add-ons \
		--enable-kernel=2.6.25 --libexecdir=/usr/lib/glibc
	make $MAKEFLAGS
	if [ "$?" -ne "0" ]; then
		echo "Errors occurred"
		exit
	fi
	cp -v ../iconvdata/gconv-modules iconvdata
	make -k check 2>&1 | tee glibc-check-log
	grep Error glibc-check-log
	touch /etc/ld.so.conf
	make install
	cp -v ../sunrpc/rpc/*.h /usr/include/rpc
	cp -v ../sunrpc/rpcsvc/*.h /usr/include/rpcsvc
	cp -v ../nis/rpcsvc/*.h /usr/include/rpcsvc
	mkdir -pv /usr/lib/locale
	localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
	localedef -i de_DE -f ISO-8859-1 de_DE
	localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
	localedef -i de_DE -f UTF-8 de_DE.UTF-8
	localedef -i en_HK -f ISO-8859-1 en_HK
	localedef -i en_PH -f ISO-8859-1 en_PH
	localedef -i en_US -f ISO-8859-1 en_US
	localedef -i en_US -f UTF-8 en_US.UTF-8
	localedef -i es_MX -f ISO-8859-1 es_MX
	localedef -i fa_IR -f UTF-8 fa_IR
	localedef -i fr_FR -f ISO-8859-1 fr_FR
	localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
	localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
	localedef -i it_IT -f ISO-8859-1 it_IT
	localedef -i ja_JP -f EUC-JP ja_JP
	localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
	localedef -i zh_CN -f GB18030 zh_CN.GB18030

	cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
# End /etc/nsswitch.conf
EOF
	# TODO: Set timezone (page 106)

	cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib
EOF

	cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf
EOF
	mkdir /etc/ld.so.conf.d

	cd $ZION
}

function adjust_toolchain()
{
	mv -v $ZION/tools/bin/{ld,ld-old}
	mv -v $ZION/tools/$(gcc -dumpmachine)/bin/{ld,ld-old}
	mv -v $ZION/tools/bin/{ld-new,ld}
	ln -sv $ZION/tools/bin/ld $ZION/tools/$(gcc -dumpmachine)/bin/ld

	gcc -dumpspecs | sed -e "s@$ZION/tools@@g" \
		-e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
		-e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' > \
		`dirname $(gcc --print-libgcc-file-name)`/specs
}

function sanity_check()
{
	echo "Running sanity check on development environment"
	echo 'main(){}' > dummy.c
	cc dummy.c -v -Wl,--verbose &> dummy.log
	readelf -l a.out | grep ': /lib'
	grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log
	grep -B1 '^ /usr/include' dummy.log
	grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
	grep "/lib.*/libc.so.6 " dummy.log
	grep found dummy.log
	rm -v dummy.c a.out dummy.log
}


function install_generic()
{
	cd $ZION_SRC
	echo "Installing $1"
	rm -rf "$1"
	tar -xf "$2"
	cd "$1"
	./configure --prefix=/usr
	make $MAKEFLAGS
	make check
	make install
}

function install_zlib()
{
	cd $ZION_SRC
	echo "Installing Zlib"
	install_generic "zlib-1.2.6" "zlib-1.2.6.tar.bz2"
	mv -v /usr/lib/libz.so.* /lib
	ln -sfv ../../lib/libz.so.1.2.6 /usr/lib/libz.so
	cd $ZION
}

function install_binutils()
{
	cd $ZION_SRC
	rm -rf binutils-2.22
	tar -jxf binutils-2.22.tar.bz2
	cd binutils-2.22
	rm -fv etc/standards.info
	sed -i.bak '/^INFO/s/standards.info //' etc/Makefile.in
	sed -i "/exception_defines.h/d" ld/testsuite/ld-elf/new.cc
	sed -i "s/-fvtable-gc //" ld/testsuite/ld-selective/selective.exp
	mkdir build
	cd build
	../configure --prefix=/usr --enable-shared
	make tooldir=/usr $MAKEFLAGS
	make -k check
	if [ "$?" -ne "0" ]; then
		echo "Tests failed"
		exit 1
	fi
	make tooldir=/usr install
	cp -v ../include/libiberty.h /usr/include
	cd $ZION
}

function install_gmp()
{
	cd $ZION_SRC
	rm -rf gmp-5.0.4
	tar -xf gmp-5.0.4.tar.xz
	cd gmp-5.0.4
	ABI=32 ./configure --prefix=/usr --enable-cxx --enable-mpbsd
	#./configure --prefix=/usr --enable-cxx --enable-mpbsd
	if [ "$?" -ne "0" ]; then
		"Configuring GMP failed"
		exit 1
	fi
	make $MAKEFLAGS
	make check 2>&1 | tee gmp-check-log
	awk '/tests passed/{total+=$2} ; END{print total}' gmp-check-log
	echo -n "Continue? [y/n]: "
	read cont
	case $cont in
		[yY])
			echo "Continuing";;
		[nN])
			echo "Exiting"
			exit 1;;
		*)
			echo "Invalid input. Exiting"
			exit 1;;
	esac

	make install
	mkdir -v /usr/share/doc/gmp-5.0.4
	cp -v doc/{isa_abi_headache,configuration} doc/*.html \
		/usr/share/doc/gmp-5.0.4

	cd $ZION
}

function install_mpfr()
{
	cd $ZION_SRC
	tar -jxf mpfr-3.1.0.tar.bz2
	cd mpfr-3.1.0
	patch -Np1 -i ../mpfr-3.1.0-fixes-1.patch
	./configure --prefix=/usr --enable-thread-safe \
		--docdir=/usr/share/doc/mpfr-3.1.0
	make $MAKEFLAGS
	make check
	if [ "$?" -ne "0" ]; then
		echo "MPFR Tests Failed"
		exit 1
	fi
	make install
	make html
	make install-html
	cd $ZION
}

function install_gcc()
{
	cd $ZION_SRC
	rm -rf gcc-4.6.2
	tar -jxf gcc-4.6.2.tar.bz2
	cd gcc-4.6.2
	sed -i 's/install_to_$(INSTALL_DEST) //' libiberty/Makefile.in
	case `uname -m` in
		i?86) sed -i 's/^T_CFLAGS =$/& -fomit-frame-pointer/' \
			gcc/Makefile.in ;;
	esac
	sed -i 's@\./fixinc\.sh@-c true@' gcc/Makefile.in
	mkdir -v build
	cd build
	../configure --prefix=/usr \
		--libexecdir=/usr/lib --enable-shared \
		--enable-threads=posix --enable-__cxa_atexit \
		--enable-clocale=gnu --enable-languages=c,c++ \
		--disable-multilib --disable-bootstrap --with-system-zlib
	make $MAKEFLAGS
	ulimit -s 16384
	make -k check
	../contrib/test_summary
	make install
	ln -sv ../usr/bin/cpp /lib
	ln -sv gcc /usr/bin/cc
	cd $ZION
}


install_kernel_headers
install_man_pages
install_glibc
adjust_toolchain
sanity_check

install_zlib
install_generic "file-5.10" "file-5.10.tar.gz"
install_binutils
install_gmp
install_mpfr
install_generic "mpc-0.9" "mpc-0.9.tar.gz"
install_gcc
sanity_check
