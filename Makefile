CROSSCOMPILE=$(CURDIR)/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin
URLTOOLS="https://github.com/raspberrypi/tools.git"
URLFIRMWARE="https://github.com/raspberrypi/firmware.git"
URLPLATFORM="https://github.com/Pulse-Eight/platform.git"
URLLIBCEC="https://github.com/Pulse-Eight/libcec.git"

VC_LIB=$(CURDIR)/firmware/hardfp/opt/vc/lib
VC_INCLUDE=$(CURDIR)/firmware/hardfp/opt/vc/include

NUMCPUS=$(shell grep -c '^processor' /proc/cpuinfo)
RPI_MODEL?=rbp2

export PKG_CONFIG_LIBDIR := $(CURDIR)/tmp/lib/pkgconfig
export LDFLAGS :=-L$(CURDIR)/tmp/lib -L$(CURDIR)/firmware/hardfp/opt/vc/lib -lEGL -lGLESv2 -lbcm_host -lvcos -lvchiq_arm
export CFLAGS :=-I$(CURDIR)/tmp/include -I$(CURDIR)/firmware/hardfp/opt/vc/include

ifeq ($(RPI_MODEL),rbp1)
	ARCH=armhf
	CROSS_COMPILE=$(CROSSCOMPILE)/arm-linux-gnueabihf
endif

ifeq ($(RPI_MODEL),rbp2)
	ARCH=armhf
	CROSS_COMPILE=$(CROSSCOMPILE)/arm-linux-gnueabihf
endif

ifeq ($(RPI_MODEL),rbp3)
	ARCH=arm64
	CROSS_COMPILE=$(CROSSCOMPILE)/arch64-linux-gnu
endif

all:.pull-firmware .pull-tools platform libcec

rbp%:
	RPI_MODEL=$@ $(MAKE) package
	
.pull-tools:
	rm -rf tools
	git clone $(URLTOOLS) --depth=1
	touch $@

.pull-firmware:
	rm -rf firmware
	git clone $(URLFIRMWARE) --depth=1
	touch $@

.pull-platform:
	rm -rf platform
	git clone $(URLPLATFORM) --depth=1
	touch $@

.configure-platform:.pull-platform
	cd platform;cmake -DCMAKE_INSTALL_PREFIX=/ -DCMAKE_C_COMPILER=$(CROSS_COMPILE)-gcc -DCMAKE_CXX_COMPILER=$(CROSS_COMPILE)-g++ -DCMAKE_STRIP=$(CROSS_COMPILE)-strip .

.make-platform:.configure-platform
	cd platform;make -j$(NUMCPUS)

platform:.make-platform
	cd platform;make install DESTDIR="$(CURDIR)/tmp"

.pull-libcec:
	rm -rf libcec
	git clone $(URLLIBCEC) --depth=1
	echo "override_dh_shlibdeps:" >> libcec/debian/rules
	echo "override_dh_auto_clean:" >> libcec/debian/rules
	echo "override_dh_auto_build:" >> libcec/debian/rules
	sed "s/#DIST#/stretch/g" libcec/debian/changelog.in > libcec/debian/changelog
	sed "s/~stretch//g" -i libcec/debian/changelog
	sed "/CMAKE/d" -i libcec/debian/rules
	sed '51,60d' -i libcec/debian/control

.configure-libcec:.pull-libcec
	cd libcec;patch -p1 -i ../patchs/remove_git_info.patch
	cd libcec;cmake -DCMAKE_CXX_FLAGS=-I$(CURDIR)/tmp/include -DRPI_INCLUDE_DIR=$(VC_INCLUDE) -DRPI_LIB_DIR=$(VC_LIB) -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=1 -DCMAKE_C_COMPILER=$(CROSS_COMPILE)-gcc -DCMAKE_CXX_COMPILER=$(CROSS_COMPILE)-g++ -DCMAKE_STRIP=$(CROSS_COMPILE)-strip -DSKIP_PYTHON_WRAPPER:STRING=1 .

libcec:.configure-libcec
	cd libcec;make -j$(NUMCPUS)

package: .pull-firmware .pull-tools platform libcec
	cd libcec;dpkg-buildpackage -d -us -uc -B -aarmhf
	mv cec-utils* libcec4* libcec_* ..

reset:
	rm -rf tmp tools firmware platform libcec .pull-tools .pull-firmware .pull-platform
