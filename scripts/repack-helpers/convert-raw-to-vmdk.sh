#!/bin/bash -eux

if [ -t 0 ]; then
  echo 'USAGE: $0 <<< raw-image-directory'
  exit 2
fi

raw_image_path=$(cat)

converted_raw_path=$(mktemp -d)
ovf=$(mktemp -d)
output_image=$(mktemp -d)

cleanup() {
  rm -rf ${ovf}
}

trap cleanup EXIT

disk_size=$(($(stat --printf="%s" ${raw_image_path}) / (1024*1024)))

# 512 bytes per sector
disk_sectors=$(($disk_size * 2048))

# 255 * 63 = 16065 sectors per head
disk_cylinders=$(($disk_sectors / 16065))


# Output disk description
cat > $ovf/root.vmdk <<EOS
version=1
CID=ffffffff
parentCID=ffffffff
createType="vmfs"

# Extent description
RW $disk_sectors FLAT "${raw_image_path}" 0
ddb.toolsVersion = "0"
ddb.adapterType = "lsilogic"
ddb.geometry.biosSectors = "63"
ddb.geometry.biosHeads = "255"
ddb.geometry.biosCylinders = "$disk_cylinders"
ddb.geometry.sectors = "63"
ddb.geometry.heads = "255"
ddb.geometry.cylinders = "$disk_cylinders"
ddb.virtualHWVersion = "4"
EOS

vm_mem=512
vm_cpus=1
vm_hostname=ubuntu
vm_arch=amd64
vm_guestos=ubuntu-64

cat > $ovf/$vm_hostname.vmx <<EOS
config.version = "8"
virtualHW.version = 9
floppy0.present = "FALSE"
nvram = "nvram"
deploymentPlatform = "windows"
virtualHW.productCompatibility = "hosted"
tools.upgrade.policy = "useGlobal"
powerType.powerOff = "preset"
powerType.powerOn = "preset"
powerType.suspend = "preset"
powerType.reset = "preset"

displayName = "$vm_hostname $vm_arch"

numvcpus = "$vm_cpus"
scsi0.present = "true"
scsi0.sharedBus = "none"
scsi0.virtualDev = "lsilogic"
memsize = "$vm_mem"

scsi0:0.present = "true"
scsi0:0.fileName = "root.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"

ide0:0.present = "true"
ide0:0.clientDevice = "TRUE"
ide0:0.deviceType = "cdrom-raw"
ide0:0.startConnected = "FALSE"

guestOSAltName = "$vm_guestos ($vm_arch)"
guestOS = "$vm_guestos"

toolScripts.afterPowerOn = "true"
toolScripts.afterResume = "true"
toolScripts.beforeSuspend = "true"
toolScripts.beforePowerOff = "true"

scsi0:0.redo = ""

tools.syncTime = "FALSE"
tools.remindInstall = "TRUE"

evcCompatibilityMode = "FALSE"
EOS

pushd $ovf > /dev/null
  ovftool *.vmx image.ovf > /dev/stderr
  OLD_OVF_SHA=$(sha1sum image.ovf | cut -d ' ' -f 1)
  sed 's/useGlobal/manual/' -i image.ovf
  NEW_OVF_SHA=$(sha1sum image.ovf | cut -d ' ' -f 1)
  sed "s/$OLD_OVF_SHA/$NEW_OVF_SHA/" -i image.mf
popd > /dev/null

pushd $ovf > /dev/null
  tar zcf $output_image/image image.ovf image.mf image-disk1.vmdk
popd > /dev/null

echo $output_image
