#!/bin/bash

SCRIPT_PATH=$( dirname "$( readlink -f "$( basename "$0" )" )" )

function zion_usage() {
	echo "Usage: $0 <path>"
	exit 1
}

# Check if the directory exists and create it if needed
function make_dir()
{
	if [[ ! -d "$1" ]]; then
		mkdir "$1"
		if [[ "$?" -ne "0" ]]; then
			echo "Failed to create directory"
			exit 1;
		fi
	fi
}

function zion_get_sources()
{
	cd $ZION_SRC
	# Get wget-list
	# wget -i wget-list
	# rm -rf wget_list
	cp /home/mvanga/src/lfs/*.patch /home/mvanga/src/lfs/*[z2] .
	cd $ZION
}

function setup_env()
{
	# TODO: Clean up the environment here :-/
	set +h
	umask 022
	export LC_ALL=POSIX
	export ZION_TGT=$(uname -m)-zion-linux-gnu
	PATH=$ZION_TOOLS/bin:/bin:/usr/bin
	export ZION LC_ALL ZION_TGT PATH
	export MAKEFLAGS="-j4"
#	env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash -norc
}

function step_binutils_pass1()
{
	echo "STEP: Binutils Pass 1"
	cd $ZION_SRC
	echo "Extracting binutils"
	tar -xf binutils-2.22.tar.bz2
	cd binutils-2.22
	mkdir -v build
	cd build
	echo "Running configure..."
	../configure \
		--target=$ZION_TGT --prefix=$ZION/tools \
		--disable-nls --disable-werror
	make $MAKEFLAGS
	make install
	cd $ZION
}

function step_gcc_pass1()
{
	echo "STEP: GCC Pass 1"
	cd $ZION_SRC
	echo "Extracting GCC"
	tar -jxf gcc-4.6.2.tar.bz2
	cd gcc-4.6.2
	echo "Extracting MPFR libraries"
	tar -jxf ../mpfr-3.1.0.tar.bz2
	mv -v mpfr-3.1.0 mpfr
	echo "Extracting GMP libraries"
	tar -Jxf ../gmp-5.0.4.tar.xz
	mv -v gmp-5.0.4 gmp
	echo "Extracting MPC libraries"
	tar -zxf ../mpc-0.9.tar.gz
	mv -v mpc-0.9 mpc
	echo "Patching GCC to support cross-builds"
	patch -Np1 -i ../gcc-4.6.2-cross_compile-1.patch
	mkdir -v build
	cd build
	echo "Running configure..."
	../configure \
		--target=$ZION_TGT --prefix=$ZION/tools \
		--disable-nls --disable-shared --disable-multilib \
		--disable-decimal-float --disable-threads \
		--disable-libmudflap --disable-libssp \
		--disable-libgomp --disable-libquadmath \
		--disable-target-libiberty --disable-target-zlib \
		--enable-languages=c --without-ppl --without-cloog \
		--with-mpfr-include=$(pwd)/../mpfr/src \
		--with-mpfr-lib=$(pwd)/mpfr/src/.libs
	make $MAKEFLAGS
	make install
	ln -vs libgcc.a `$ZION_TGT-gcc -print-libgcc-file-name | \
		sed 's/libgcc/&_eh/'`
	cd $ZION
}

function step_kernel_headers()
{
	cd $ZION_SRC
	tar -xf linux-3.2.6.tar.xz
	cd linux-3.2.6
	echo "Generating kernel headers"
	make mrproper
	make INSTALL_HDR_PATH=dest headers_install
	echo "Installing kernel headers"
	cp -rv dest/include/* $ZION/tools/include
	cd $ZION
}

function step_glibc_pass1()
{
	cd $ZION_SRC
	echo "Extracting Glibc"
	tar -jxf glibc-2.14.1.tar.bz2
	cd glibc-2.14.1
	echo "Applying additional patches"
	patch -Np1 -i ../glibc-2.14.1-gcc_fix-1.patch
	patch -Np1 -i ../glibc-2.14.1-cpuid-1.patch
	mkdir -v build
	cd build
	case `uname -m` in
		i?86) echo "CFLAGS += -march=i486 -mtune=native" > configparms ;;
	esac
	../configure --prefix=$ZION/tools \
		--host=$ZION_TGT --build=$(../scripts/config.guess) \
		--disable-profile --enable-add-ons \
		--enable-kernel=2.6.25 --with-headers=$ZION/tools/include \
		libc_cv_forced_unwind=yes libc_cv_c_cleanup=yes
	make $MAKEFLAGS
	make install
	cd $ZION
}

function adjust_paths()
{
	SPECS=`dirname $($ZION_TGT-gcc -print-libgcc-file-name)`/specs
	$ZION_TGT-gcc -dumpspecs | sed \
		-e "s@/lib\(64\)\?/ld@$ZION/tools&@g" \
		-e "/^\*cpp:$/{n;s,$, -isystem $ZION/tools/include,}" > $SPECS
	echo "New specs file is: $SPECS"
	unset SPECS
}

function sanity_check_pass1()
{
	echo "Running sanity check on development environment"
	echo 'main(){}' > dummy.c
	$ZION_TGT-gcc -B$ZION/tools/lib dummy.c
	readelf -l a.out | grep ": .*/tools"
	rm -v dummy.c a.out
}

function step_binutils_pass2()
{
	cd $ZION_SRC
	echo "Removing old binutils folder"
	rm -rf binutils-2.22
	echo "Extracting binutils"
	tar -jxf binutils-2.22.tar.bz2
	cd binutils-2.22
	mkdir build
	cd build
	echo "Running configure..."
	CC="$ZION_TGT-gcc -B$ZION/tools/lib/" \
		AR=$ZION_TGT-ar \
		RANLIB=$ZION_TGT-ranlib \
		../configure --prefix=$ZION/tools \
		--disable-nls --with-lib-path=$ZION/tools/lib
	echo "Running make..."
	make $MAKEFLAGS
	make install
	echo "Preparing for re-adjusting phase"
	make -C ld clean
	make -C ld LIB_PATH=/usr/lib:/lib
	cp -v ld/ld-new $ZION/tools/bin
	cd $ZION
}

function step_gcc_pass2()
{
	cd $ZION_SRC
	echo "Removing old GCC folder"
	rm -rf gcc-4.6.2

	echo "Extracting GCC"
	tar -jxf gcc-4.6.2.tar.bz2
	cd gcc-4.6.2

	echo "Patching GCC to allow searching for startfiles"
	patch -Np1 -i ../gcc-4.6.2-startfiles_fix-1.patch

	echo "Suppressing fixincludes from running"
	cp -v gcc/Makefile.in{,.orig}
	sed 's@\./fixinc\.sh@-c true@' gcc/Makefile.in.orig > gcc/Makefile.in

	echo "Force the use of -fomit-frame-pointer"
	cp -v gcc/Makefile.in{,.tmp}
	sed 's/^T_CFLAGS =$/& -fomit-frame-pointer/' gcc/Makefile.in.tmp \
		> gcc/Makefile.in
	
	echo "Modifying paths to use newly compiler linker"
	for file in \
	$(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
	do
		cp -uv $file{,.orig}
		sed -e "s@/lib\(64\)\?\(32\)\?/ld@$ZION/tools&@g" \
			-e "s@/usr@$ZION/tools@g" $file.orig > $file
		echo '
#undef STANDARD_INCLUDE_DIR
#define STANDARD_INCLUDE_DIR 0
#define STANDARD_STARTFILE_PREFIX_1 ""
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
		touch $file.orig
	done

	case $(uname -m) in
	x86_64)
		echo "x86_64 found: unsetting multilib spec"
		for file in $(find gcc/config -name t-linux64) ; do \
			cp -v $file{,.orig}
			sed '/MULTILIB_OSDIRNAMES/d' $file.orig > $file
		done
		;;
	esac

	echo "Extracting MPFR libraries"
	tar -jxf ../mpfr-3.1.0.tar.bz2
	mv -v mpfr-3.1.0 mpfr
	echo "Extracting GMP libraries"
	tar -Jxf ../gmp-5.0.4.tar.xz
	mv -v gmp-5.0.4 gmp
	echo "Extracting MPC libraries"
	tar -zxf ../mpc-0.9.tar.gz
	mv -v mpc-0.9 mpc

	mkdir -v build
	cd build

	CC="$ZION_TGT-gcc -B$ZION/tools/lib/" \
	AR=$ZION_TGT-ar RANLIB=$ZION_TGT-ranlib \
	../configure --prefix=$ZION/tools \
		--with-local-prefix=$ZION/tools --enable-clocale=gnu \
		--enable-shared --enable-threads=posix \
		--enable-__cxa_atexit --enable-languages=c,c++ \
		--disable-libstdcxx-pch --disable-multilib \
		--disable-bootstrap --disable-libgomp \
		--without-ppl --without-cloog \
		--with-mpfr-include=$(pwd)/../mpfr/src \
		--with-mpfr-lib=$(pwd)/mpfr/src/.libs
	make $MAKEFLAGS
	make install
	ln -vs gcc $ZION/tools/bin/cc

	cd $ZION
}

if [[ "$#" -ne "1" ]] ; then
	zion_usage;
fi

export ZION="`pwd`/$1";
make_dir $ZION
echo "Setup working directory: $ZION"
export ZION_TOOLS=$ZION/tools
make_dir $ZION_TOOLS
echo "Setup tools directory: $ZION_TOOLS"
export ZION_SRC=$ZION/sources
make_dir $ZION_SRC
echo "Setup sources directory: $ZION_SRC"
cd $ZION

# zion_get_sources
setup_env
#step_binutils_pass1
#step_gcc_pass1
#step_kernel_headers
#step_glibc_pass1
#adjust_paths
#sanity_check_pass1
#step_binutils_pass2
#step_gcc_pass2
#sanity_check_pass1

function install_tcl()
{
	cd $ZION_SRC
	echo "Extracting TCL"
	tar -xf tcl8.5.11-src.tar.gz
	cd tcl8.5.11
	cd unix
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	TZ=UTC make test
	make install
	chmod -v u+w $ZION/tools/lib/libtcl8.5.so
	make install-private-headers
	ln -sv tclsh8.5 $ZION/tools/bin/tclsh
	cd $ZION
}

function install_expect()
{
	cd $ZION_SRC
	echo "Extracting Expect"
	tar -xf expect5.45.tar.gz
	cd expect5.45
	cp -v configure{,.orig}
	sed 's:/usr/local/bin:/bin:' configure.orig > configure
	./configure --prefix=$ZION/tools --with-tcl=$ZION/tools/lib \
		--with-tclinclude=$ZION/tools/include
	make $MAKEFLAGS
	make test
	make SCRIPTS="" install
	cd $ZION
}

function install_dejagnu()
{
	cd $ZION_SRC
	echo "Extracting DejaGNU"
	tar -xf dejagnu-1.5.tar.gz
	cd dejagnu-1.5
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make install
	make check
	cd $ZION
}

function install_check()
{
	cd $ZION_SRC
	echo "Extracting Check"
	tar -xf check-0.9.8.tar.gz
	cd check-0.9.8
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_ncurses()
{
	cd $ZION_SRC
	echo "Extracting Ncurses"
	tar -xf ncurses-5.9.tar.gz
	cd ncurses-5.9
	./configure --prefix=$ZION/tools --with-shared \
		--without-debug --without-ada --enable-overwrite
	make $MAKEFLAGS
	make install
	cd $ZION
}

function install_bash()
{
	cd $ZION_SRC
	echo "Extracting Bash"
	tar -xf bash-4.2.tar.gz
	cd bash-4.2
	patch -Np1 -i ../bash-4.2-fixes-4.patch
	./configure --prefix=$ZION/tools --without-bash-malloc
	make $MAKEFLAGS
	make tests
	make install
	ln -vs bash $ZION/tools/bin/sh
	cd $ZION
}

function install_bzip2()
{
	cd $ZION_SRC
	echo "Extracting Bzip2"
	tar -xf bzip2-1.0.6.tar.gz
	cd bzip2-1.0.6
	make $MAKEFLAGS
	make PREFIX=$ZION/tools install
	cd $ZION
}

function install_coreutils()
{
	cd $ZION_SRC
	echo "Extracting Coreutils"
	tar -xf coreutils-8.15.tar.xz
	cd coreutils-8.15
	./configure --prefix=$ZION/tools --enable-install-program=hostname
	make $MAKEFLAGS
	make RUN_EXPENSIVE_TESTS=yes check
	make install
	cp -v src/su $ZION/tools/bin/su-tools
	cd $ZION
}

function install_diffutils()
{
	cd $ZION_SRC
	echo "Extracting Diffutils"
	tar -xf diffutils-3.2.tar.gz
	cd diffutils-3.2
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_file()
{
	cd $ZION_SRC
	echo "Extracting File"
	tar -xf file-5.10.tar.gz
	cd file-5.10
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_findutils()
{
	cd $ZION_SRC
	echo "Extracting Findutils"
	tar -xf findutils-4.4.2.tar.gz
	cd findutils-4.4.2
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_gawk()
{
	cd $ZION_SRC
	echo "Extracting Gawk"
	tar -xf gawk-4.0.0.tar.bz2
	cd gawk-4.0.0
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_gettext()
{
	cd $ZION_SRC
	echo "Extracting Gettext"
	tar -xf gettext-0.18.1.1.tar.gz
	cd gettext-0.18.1.1
	cd gettext-tools
	./configure --prefix=$ZION/tools --disable-shared
	make -C gnulib-lib
	make -C src msgfmt
	cp -v src/msgfmt $ZION/tools/bin
	cd $ZION
}

function install_grep()
{
	cd $ZION_SRC
	echo "Extracting Grep"
	tar -xf grep-2.10.tar.xz
	cd grep-2.10
	./configure --prefix=$ZION/tools --disable-perl-regexp
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_gzip()
{
	cd $ZION_SRC
	echo "Extracting Gzip"
	tar -xf gzip-1.4.tar.gz
	cd gzip-1.4
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_m4()
{
	cd $ZION_SRC
	echo "Extracting M4"
	tar -xf m4-1.4.16.tar.bz2
	cd m4-1.4.16
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_make()
{
	cd $ZION_SRC
	echo "Extracting Make"
	tar -xf make-3.82.tar.bz2
	cd make-3.82
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_patch()
{
	cd $ZION_SRC
	echo "Extracting Patch"
	tar -xf patch-2.6.1.tar.bz2
	cd patch-2.6.1
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_perl()
{
	cd $ZION_SRC
	echo "Extracting Perl"
	tar -xf perl-5.14.2.tar.bz2
	cd perl-5.14.2
	patch -Np1 -i ../perl-5.14.2-libc-1.patch
	sh Configure -des -Dprefix=$ZION/tools
	make
	cp -v perl cpan/podlators/pod2man $ZION/tools/bin
	mkdir -pv $ZION/tools/lib/perl5/5.14.2
	cp -Rv lib/* $ZION/tools/lib/perl5/5.14.2
	cd $ZION
}

function install_sed()
{
	cd $ZION_SRC
	echo "Extracting Sed"
	tar -xf sed-4.2.1.tar.bz2
	cd sed-4.2.1
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_tar()
{
	cd $ZION_SRC
	echo "Extracting Tar"
	tar -xf tar-1.26.tar.bz2
	cd tar-1.26
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_texinfo()
{
	cd $ZION_SRC
	echo "Extracting Texinfo"
	tar -xf texinfo-4.13a.tar.gz
	cd texinfo-4.13a
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_xz()
{
	cd $ZION_SRC
	echo "Extracting Xz"
	tar -xf xz-5.0.3.tar.bz2
	cd xz-5.0.3
	./configure --prefix=$ZION/tools
	make $MAKEFLAGS
	make check
	make install
	cd $ZION
}

function install_tcl_stub()
{
	cd $ZION_SRC
	echo "Extracting TCL"
	tar -xf tcl8.5.11-src.tar.gz
	cd tcl8.5.11
	cd $ZION
}

#install_tcl
#install_expect
#install_dejagnu
#install_check
#install_ncurses
#install_bash
#install_bzip2
#install_coreutils
#install_diffutils
#install_file
#install_findutils
#install_gawk
#install_gettext
#install_grep
#install_gzip
#install_m4
#install_make
#install_patch
#install_perl
#install_sed
#install_tar
#install_texinfo
#install_xz

function step_cleanup()
{
	strip --strip-debug $ZION/tools/lib/*
	strip --strip-unneeded $ZION/tools/{,s}bin/*
	rm -rf $ZION/tools/{,share}/{info,man,doc}
}

function fix_ownership()
{
	sudo chown -R root:root $ZION/tools
}

function make_folders()
{
	sudo mkdir -vp $ZION/{dev,proc,sys}
	sudo mkdir -vp $ZION/$ZION/tools
	sudo mknod -m 600 $ZION/dev/console c 5 1
	sudo mknod -m 666 $ZION/dev/null c 1 3
	sudo mount -v --bind /dev $ZION/dev
	sudo mount -v --bind $ZION/tools $ZION/$ZION/tools
	sudo mount -vt devpts devpts $ZION/dev/pts
	sudo mount -vt tmpfs shm $ZION/dev/shm
	sudo mount -vt proc proc $ZION/proc
	sudo mount -vt sysfs sysfs $ZION/sys
}

function do_chroot()
{
	rm -rf $ZION/postchroot.sh
	sudo cp $SCRIPT_PATH/postchroot.sh $ZION/
	rm -rf $ZION/packages.sh
	sudo cp $SCRIPT_PATH/packages.sh $ZION/
	sudo chroot "$ZION" $ZION/tools/bin/env -i \
		HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
		ZION=$ZION \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin:$ZION/tools/bin \
		$ZION/tools/bin/bash --login +h
}

#step_cleanup
#fix_ownership
make_folders
do_chroot
