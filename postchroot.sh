#!/tools/bin/bash

echo "Hello Chroot!"

function create_directories()
{
	mkdir -pv /{bin,boot,etc/{opt,sysconfig},home,lib,mnt,opt,run}
	mkdir -pv /{media/{floppy,cdrom},sbin,srv,var}
	install -dv -m 0750 /root
	install -dv -m 1777 /tmp /var/tmp
	mkdir -pv /usr/{,local/}{bin,include,lib,sbin,src}
	mkdir -pv /usr/{,local/}share/{doc,info,locale,man}
	mkdir -v /usr/{,local/}share/{misc,terminfo,zoneinfo}
	mkdir -pv /usr/{,local/}share/man/man{1..8}
	for dir in /usr /usr/local; do
	ln -sv share/{man,doc,info} $dir
	done
	case $(uname -m) in
	x86_64) ln -sv lib /lib64 && ln -sv lib /usr/lib64 ;;
	esac
	mkdir -v /var/{log,mail,spool}
	ln -sv /run /var/run
	ln -sv /run/lock /var/lock
	mkdir -pv /var/{opt,cache,lib/{misc,locate},local}
}

function create_symlinks()
{
	ln -sv $ZION/tools/bin/{bash,cat,echo,pwd,stty} /bin
	ln -sv $ZION/tools/bin/perl /usr/bin
	ln -sv $ZION/tools/lib/libgcc_s.so{,.1} /usr/lib
	ln -sv $ZION/tools/lib/libstdc++.so{,.6} /usr/lib
	sed 's@$ZION/tools@/usr@' $ZION/tools/lib/libstdc++.la > /usr/lib/libstdc++.la
	ln -sv bash /bin/sh

	touch /etc/mtab
	cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF
	cat > /etc/group << "EOF"
root:x:0:
bin:x:1:
sys:x:2:
kmem:x:3:
tty:x:4:
tape:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
mail:x:34:
nogroup:x:99:
EOF
	touch /var/run/utmp /var/log/{btmp,lastlog,wtmp}
	chgrp -v utmp /var/run/utmp /var/log/lastlog
	chmod -v 664 /var/run/utmp /var/log/lastlog
	chmod -v 600 /var/log/btmp
}

#create_directories
#create_symlinks

exec $ZION/tools/bin/bash --login +h
