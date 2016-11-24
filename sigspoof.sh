#!/bin/bash

#
# When you adjust the variables below and install all requirements (see
# README.md), this script will generate a modified image files, that can
# be flashed onto your smartphone. However, the resulting system WILL
# NOT WORK. This code is published only to help others who try to code
# something similar.
#
# License for this file: Everything I've added: Public Domain; the parts
# from mikeperry's mission-improbable's re-sign.sh near the end: ask
# mikeperry.
#


DIR="/home/builder/Downloads/CopperheadOS"
ARCHIVE="bullhead-factory-2016.11.10.09.53.38.tar.xz"
ID="bullhead-nbd91p"
MOUNTDIR="/mnt/image-$ID"
PATCHDIR="$DIR/patchdir-$ID"
APILEVEL=24
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
KEYDIR="$SCRIPTDIR/keys"
SUPERBOOTDIR="$SCRIPTDIR/extras/super-bootimg"
OUTPUTDIR="$DIR/sigspoof-output-$ID"


# $1: file to disassemble
function disassemble()
{
	dex_files=$(baksmali list dex $1)
	for dex_file in $dex_files; do
		echo "## Disassembling $1 (${dex_file})"
		DISASSEMBLED="$PATCHDIR/disassembled/$1${dex_file}"
		mkdir -p "$DISASSEMBLED/"
		echo "-> $DISASSEMBLED"
		baksmali x -o "$DISASSEMBLED/" \
			-d "$MOUNTDIR/" \
			-d "$MOUNTDIR/framework/arm/" \
			-d "$MOUNTDIR/framework/oat/arm/" "$1${dex_file}"
	done
}

# $1: file to reassemble
# the same file must be disassembled before!
function reassemble()
{
	dex_files=$(baksmali list dex $1)
	for dex_file in $dex_files; do
		echo "## Re-assembling $1 (${dex_file})"
		DISASSEMBLED="$PATCHDIR/disassembled/$1${dex_file}"
		REASSEMBLED="$PATCHDIR/reassembled/$1${dex_file}"
		mkdir -p "$(dirname $PATCHDIR/reassembled/$1/${dex_file})"
		echo "-> $REASSEMBLED"
		smali a -o "$REASSEMBLED" \
			--api $APILEVEL \
			"$DISASSEMBLED"
	done
}

if [ ! -f "$KEYDIR/verity_key.pub" ]; then
	echo "## Creating sign keys"
	mkdir -p "$KEYDIR"
	cd "$KEYDIR"
	for key in releasekey platform shared media verity; do
		echo "-> creating $key"
		$SCRIPTDIR/extras/make_key $key \
			'/C=CA/ST=Ontario/L=Toronto/O=CopperheadOS/OU=CopperheadOS/CN=CopperheadOS/emailAddress=copperheados@copperhead.co'
	done
	
	echo "## Creating verity key"
	$SCRIPTDIR/extras/generate_verity_key -convert verity.x509.pem \
		verity_key || exit 1
fi


# Clean up left-overs
if [ -d "$MOUNTDIR" ]; then
	echo "## MOUNTDIR still exists: $MOUNTDIR"
	echo "Cleaning up first."
	sudo umount "$MOUNTDIR"
	sudo rmdir "$MOUNTDIR" || exit 1
fi
if [ -d "$PATCHDIR" ]; then
	echo "## Removing old patchdir: $PATCHDIR"
	rm -r "$PATCHDIR"
fi
if [ -d "$DIR/bootimg-$ID" ]; then
	echo "## Removing old bootimg dir: $DIR/bootimg-$ID"
	rm -r "$DIR/bootimg-$ID"
fi
if [ -d "$DIR/ramdisk-$ID" ]; then
	echo "## Removing old ramdisk dir: $DIR/ramdisk-$ID"
	rm -rf "$DIR/ramdisk-$ID"
fi


echo "## Extracting: $ARCHIVE"
if [ -d "$DIR/$ID" ]; then
	echo "Skipping, because folder exists: $ID"
else
	cd $DIR
	tar -kxvf $ARCHIVE || exit 2
fi

echo "## Extracting image-$ID.zip to $DIR/image-$ID/"
if [ -f "$DIR/image-$ID/system.img" ]; then
	echo "Skipping, because file exists: system.img"
else
	mkdir -p "$DIR/image-$ID"
	cd "$DIR/image-$ID/"
	unzip "$DIR/$ID/image-$ID.zip" || exit 3
fi


echo "## Unpacking *.img"
cd "$DIR/image-$ID/"
for IMG in *.img; do
	[[ "$IMG" == *.raw.img ]] && continue
	RAW="$(basename "$IMG" .img).raw.img"
	if [ -f "$DIR/image-$ID/${RAW}" ]; then
		echo "-> $RAW already exists (skipping!)"
	else
		echo "-> $IMG => $RAW"
		simg2img ${IMG} ${RAW} || rm -v ${RAW}
	fi
done

echo "## Mounting system.raw.img"
sudo mkdir -p $MOUNTDIR || exit 5
sudo mount -t ext4 -o loop "$DIR/image-$ID/system.raw.img" $MOUNTDIR \
	|| exit 6

echo "## Patching system.raw.img"
if [ -e "${MOUNTDIR}/framework/arm64/boot-framework.oat" ]; then
	# Disassemble, patch, reassemble
	cd "$MOUNTDIR/framework/arm"
	disassemble boot-framework.oat
	echo "## Applying sigspoof patch"
	"$SCRIPTDIR/tingle_standalone.py" \
		"$PATCHDIR/disassembled/boot-framework.oat/system/framework/framework.jar/android/content/pm/PackageParser.smali" \
			|| exit 1
	reassemble boot-framework.oat

	echo "## Putting patched files back into the image"
	sudo cp -v $PATCHDIR/reassembled/boot-framework.oat/system/framework/* "${MOUNTDIR}/framework/" || exit 1
	sudo rm -v "${MOUNTDIR}/framework/arm/boot-framework.oat" || exit 1
	sudo rm -v "${MOUNTDIR}/framework/arm64/boot-framework.oat" || exit 1
	
	rm -r "$PATCHDIR"
else
	echo "-> skipping, system.raw.img is already patched."
fi
echo "## Umounting system.raw.img"
cd "$DIR"
sudo umount "${MOUNTDIR}"
sudo rmdir "${MOUNTDIR}" || exit 1


echo "## Signing *.raw.img files with custom key"
mkdir -p "$DIR/resigned-$ID/"
cd "$DIR/image-$ID/"
for RAW in *.raw.img; do
	IMG="$(basename "$RAW" .raw.img).img"
	NOEXT="$(basename "$RAW" .raw.img)"
	[ -f "$DIR/resigned-$ID/${IMG}.part" ] \
		&& rm -v "$DIR/resigned-$ID/${IMG}.part"
	if [ -f "$DIR/resigned-$ID/${IMG}" ]; then
		echo "-> $IMG is already re-signed (skipping!)"
		
	else
		cd "$DIR/image-$ID/"
		# FIXME: can we use img2simg instead?
		echo "-> ${RAW} (1): converting to simg (ext2simg)"
		RAW_SIZE=$($SCRIPTDIR/extras/ext2simg -v ${RAW} $DIR/resigned-$ID/${IMG}.part \
			| grep "Size: " | cut -d: -f2)
		echo "RAW_SIZE: ${RAW_SIZE}"
		
		# This salt hash is hardcoded everywhere. Not much of a salt then, huh?
		#  https://android.googlesource.com/platform/build/+/master/tools/releasetools/build_image.py
		FIXED_SALT="aee087a5be3b982978c923f566a94613496b417f2af592639bc80d141e34dfe7"
		
		
		cd "$DIR/resigned-$ID/"
		echo "-> ${RAW} (2): hashing the image (build_verity_tree)"
		[ -e verity.img ] && rm -v verity.img
		RAW_ROOT_HASH=$($SCRIPTDIR/extras/build_verity_tree -A ${FIXED_SALT} ${IMG}.part verity.img)
		echo "RAW_ROOT_HASH: ${RAW_ROOT_HASH}"
		
		
		# NOTE: RAW_ROOT_HASH contains two arguments for
		# build_verity_metadata
		echo "-> ${RAW} (3): build_verity_metadata"
		[ -e verity_metadata.img ] && rm -v verity_metadata.img
		$SCRIPTDIR/extras/build_verity_metadata.py \
			${RAW_SIZE} \
			verity_metadata.img \
			${RAW_ROOT_HASH} \
			/dev/block/platform/soc.0/f9824900.sdhci/by-name/${NOEXT} \
			$SCRIPTDIR/extras/verity_signer \
			${KEYDIR}/verity.pk8 \
		|| exit 1
		
		echo "-> ${RAW} (4): appending verity_metadata and verity to ${IMG}"
		append2simg ${IMG}.part verity_metadata.img || exit 1
		append2simg ${IMG}.part verity.img || exit 1
		
		mv ${IMG}.part ${IMG}
	fi
done

cd "$DIR/image-$ID/"
[ -e verity.img ] && rm -v verity.img
[ -e verity_metadata.img ] && rm -v verity_metadata.img


#
# The following code is loosely based on re-sign.sh from
# mission-improbable.
#
for IMG in recovery.img boot.img; do
	echo "## Putting keys in $IMG"
	if "$DIR/resingned-$ID/$IMG"; then
		echo "-> Skipping, output already exists: $DIR/resigned-$ID/$IMG"
	else
		# missing-improbable: RECOVERYRAMDISK_DIR
		echo "## Extracting $IMG"
		[ -d "$DIR/bootimg-$ID/" ] && rm -rf "$DIR/bootimg-$ID/"
		mkdir -p "$DIR/bootimg-$ID/"
		cd "$DIR/bootimg-$ID/"
		${SUPERBOOTDIR}/scripts/bin/bootimg-extract "$DIR/image-$ID/$IMG" \
			|| exit 1

		# missing-improbable: RECOVERYFILES_DIR
		echo "## Extracting ramdisk.gz"
		[ -d "$DIR/ramdisk-$ID/" ] && rm -rf "$DIR/ramdisk-$ID/"
		mkdir -p "$DIR/ramdisk-$ID/"
		cd "$DIR/ramdisk-$ID/"
		(gunzip -c "$DIR/bootimg-$ID"/ramdisk.gz | cpio -i) || exit 1
		(gunzip -c "$DIR/bootimg-$ID"/ramdisk.gz > ramdisk1) || exit 1

		echo "## Copying custom sign keys to extracted ramdisk"
		cp -v "$KEYDIR/releasekey.x509.pem" ./res/keys
		cp -v "$KEYDIR/verity_key.pub" ./verity_key
		(echo "res/keys verity_key" |tr ' ' '\n' | cpio -o -H newc > ramdisk2) \
			|| exit 1
		rm -f cpio-*

		echo "## Packing ramdisk.gz again"
		${SUPERBOOTDIR}/scripts/bin/strip-cpio \
			ramdisk1 \
			res/keys \
			verity_key \
		|| exit 1
		(cat cpio-* ramdisk2 \
			| gzip -9 -c > "$DIR/bootimg-$ID"/ramdisk.gz) \
		|| exit 1
		rm -rf "$DIR/ramdisk-$ID/"


		# missing-improbable: RECOVERYRAMDISK_DIR
		echo "## Packing $IMG again"
		cd "$DIR/bootimg-$ID/"
		rm -f cpio-*
		${SUPERBOOTDIR}/scripts/bin/bootimg-repack \
			"$DIR/image-$ID/$IMG" \
		|| exit 1
		mv -v new-boot.img "$DIR/resigned-$ID/$IMG"
		rm -rf "$DIR/bootimg-$ID/"
	fi
done


echo "## Zipping the re-signed images"
if [ -e "$OUTPUTDIR/image-$ID.zip" ]; then
	echo "-> output file already exists!"
else
	cp -v "$DIR/image-$ID/android-info.txt" "$DIR/resigned-$ID/"
	mkdir -p "$OUTPUTDIR"
	cd "$DIR/resigned-$ID"
	zip -v -0 "$OUTPUTDIR/image-$ID.zip" \
		"android-info.txt" *.img \
	|| exit 1
fi

echo "## Copying unchanged files from the original .tar.xz"
cd "$DIR/$ID"
cp -n -v flash-*.sh bootloader-*.img radio-*.img "$OUTPUTDIR/" \
	|| exit 1









