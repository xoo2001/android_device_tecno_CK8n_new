#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=X6739
VENDOR=infinix

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

export TARGET_ENABLE_CHECKELF=true

# Define the default patchelf version used to patch blobs
# This will also be used for utility functions like FIX_SONAME
# Older versions break some camera blobs for us
export PATCHELF_VERSION=0_17_2

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup {
    case "$1" in
        system_ext/etc/init/init.vtservice.rc |\
        vendor/etc/init/android.hardware.neuralnetworks@1.3-service-mtk-neuron.rc)
            [ "$2" = "" ] && return 0
            sed -i "s|start|enable|g" "${2}"
            ;;
        system_ext/lib64/libimsma.so)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --replace-needed "libsink.so" "libsink-mtk.so" "${2}"
            ;;
        system_ext/lib64/libsource.so)
            [ "$2" = "" ] && return 0
            grep -q libui_shim.so "$2" || "$PATCHELF" --add-needed libui_shim.so "$2"
            ;;
        vendor/bin/hw/android.hardware.media.c2@1.2-mediatek-64b)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --add-needed "libstagefright_foundation-v33.so" "${2}"
            "$PATCHELF" --replace-needed "libavservices_minijail_vendor.so" "libavservices_minijail.so" "${2}"
            ;;
        vendor/bin/hw/camerahalserver |\
        vendor/bin/hw/vendor.mediatek.hardware.pq@2.2-service)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --replace-needed "libbinder.so" "libbinder-v31.so" "${2}"
            "$PATCHELF" --replace-needed "libhidlbase.so" "libhidlbase-v31.so" "${2}"
            "$PATCHELF" --replace-needed "libutils.so" "libutils-v31.so" "${2}"
            ;;
        vendor/etc/init/android.hardware.bluetooth@1.1-service-mediatek.rc)
            [ "$2" = "" ] && return 0
            sed -i '/vts/Q' "$2"
            ;;
        vendor/bin/mnld |\
        vendor/lib*/libaalservice.so |\
        vendor/lib64/hw/android.hardware.sensors@2.X-subhal-mediatek.so |\
        vendor/lib64/libcam.utils.sensorprovider.so)
            [ "$2" = "" ] && return 0
            grep -q "libshim_sensors.so" "$2" || "$PATCHELF" --add-needed "libshim_sensors.so" "$2"
            ;;
        vendor/etc/init/android.hardware.media.c2@1.2-mediatek.rc)
            [ "$2" = "" ] && return 0
            sed -i 's/@1.2-mediatek/@1.2-mediatek-64b/g' "${2}"
            ;;
        vendor/etc/vintf/manifest/manifest_media_c2_V1_2_default.xml)
            [ "$2" = "" ] && return 0
            sed -i 's/1.1/1.2/' "$2"
            ;;
        vendor/lib*/hw/audio.primary.mt6893.so)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --replace-needed "libalsautils.so" "libalsautils-v31.so" "${2}"
            grep -q "libstagefright_foundation-v33.so" "${2}" || "$PATCHELF" --add-needed "libstagefright_foundation-v33.so" "${2}"
            ;;
        vendor/lib*/libMtkOmxCore.so)
            [ "$2" = "" ] && return 0
            sed -i "s/mtk.vendor.omx.core.log/ro.vendor.mtk.omx.log\x00\x00/" "$2"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
