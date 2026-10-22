"""Checks an App Store IPA before it is uploaded: what App Store Connect refuses at upload (missing
purpose strings ITMS-90683, required-reason APIs without a privacy manifest ITMS-91053, an icon
with transparency ITMS-90717) and what review asks about (iPhone support, keys left in the app,
the Pro products). usage: python tools/appstore_check.py Murekkep-AppStore.ipa"""
import io
import plistlib
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_SOURCE = ROOT / "Murekkep.swiftpm"
BUNDLE = "Payload/Murekkep.app/"

# API (in the Swift sources) -> the Info.plist purpose string it needs.
PURPOSE = {
    "NSMicrophoneUsageDescription": r"AVAudioRecorder|requestRecordPermission|inputNode",
    "NSSpeechRecognitionUsageDescription": r"SFSpeechRecognizer",
    "NSCameraUsageDescription": r"VNDocumentCameraViewController|AVCaptureDevice|UIImagePickerController|DataScannerViewController",
    "NSPhotoLibraryUsageDescription": r"PHAsset\.fetch|PHPhotoLibrary\.requestAuthorization\(for: \.readWrite",
    "NSLocationWhenInUseUsageDescription": r"CLLocationManager",
    "NSContactsUsageDescription": r"CNContactStore",
    "NSCalendarsUsageDescription": r"EKEventStore",
    "NSBluetoothAlwaysUsageDescription": r"CBCentralManager",
    "NSFaceIDUsageDescription": r"LAContext",
}

# Symbols in the app binary -> the privacy manifest category that must declare them.
REQUIRED_REASON = {
    "NSPrivacyAccessedAPICategoryUserDefaults": [b"NSUserDefaults"],
    "NSPrivacyAccessedAPICategoryFileTimestamp": [b"_stat\x00", b"_fstat\x00", b"_lstat\x00", b"_getattrlist\x00",
                                                  b"NSFileCreationDate", b"NSFileModificationDate",
                                                  b"NSURLContentModificationDateKey", b"NSURLCreationDateKey"],
    "NSPrivacyAccessedAPICategoryDiskSpace": [b"NSURLVolumeAvailableCapacity", b"NSFileSystemFreeSize",
                                              b"_statfs\x00", b"_statvfs\x00", b"_fstatfs\x00"],
    "NSPrivacyAccessedAPICategorySystemBootTime": [b"_mach_absolute_time\x00", b"systemUptime"],
    "NSPrivacyAccessedAPICategoryActiveKeyboards": [b"activeInputModes"],
}

PRODUCTS = [b"murekkep.pro.monthly", b"murekkep.pro.yearly", b"murekkep.pro.lifetime"]


def main(ipa):
    z = zipfile.ZipFile(ipa)
    names = set(z.namelist())
    info = plistlib.loads(z.read(BUNDLE + "Info.plist"))
    binary = z.read(BUNDLE + "Murekkep")
    code = "\n".join(p.read_text(encoding="utf-8") for p in APP_SOURCE.glob("*.swift"))
    failures = 0

    def check(ok, text):
        nonlocal failures
        print(("ok    " if ok else "FAIL  ") + text)
        failures += not ok

    print(f"{Path(ipa).name}: {info.get('CFBundleIdentifier')} {info.get('CFBundleShortVersionString')} "
          f"({info.get('CFBundleVersion')}), iOS {info.get('MinimumOSVersion')}+")
    check(str(info.get("CFBundleVersion", "")).isdigit(), "build number is a whole number")
    check(info.get("UIDeviceFamily") == [2], f"iPad only (UIDeviceFamily {info.get('UIDeviceFamily')})")
    check(info.get("ITSAppUsesNonExemptEncryption") is False, "export compliance answered (no own encryption)")
    check("CFBundleIcons~ipad" in info and BUNDLE + "Assets.car" in names, "iPad icons compiled")
    icon = APP_SOURCE / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    try:
        from PIL import Image
        im = Image.open(icon)
        check(im.size == (1024, 1024) and "A" not in im.mode, f"1024 px icon without transparency ({im.size}, {im.mode})")
    except ImportError:
        print("skip  icon check (Pillow is not installed)")

    for key, pattern in PURPOSE.items():
        if re.search(pattern, code):
            check(bool(info.get(key)), f"purpose string {key}")

    manifest_path = BUNDLE + "PrivacyInfo.xcprivacy"
    check(manifest_path in names, "privacy manifest in the app")
    declared = {}
    if manifest_path in names:
        manifest = plistlib.load(io.BytesIO(z.read(manifest_path)))
        declared = {e["NSPrivacyAccessedAPIType"]: e["NSPrivacyAccessedAPITypeReasons"]
                    for e in manifest.get("NSPrivacyAccessedAPITypes", [])}
        check(manifest.get("NSPrivacyTracking") is False, "no tracking declared")
    for category, symbols in REQUIRED_REASON.items():
        used = [s.decode().strip("\x00") for s in symbols if s in binary]
        if used:
            check(bool(declared.get(category)), f"{category.removeprefix('NSPrivacyAccessedAPICategory')} declared (uses {', '.join(used)})")

    for product in PRODUCTS:
        check(product in binary, f"Pro product {product.decode()} in the app")
    check(re.search(rb"sk-ant-[A-Za-z0-9_-]{20,}", binary) is None, "no Anthropic key left in the app")
    background = info.get("UIBackgroundModes", [])
    if background:
        print(f"note  background modes {background}: say why in the review notes (lecture recording, overview audio)")

    print("all checks passed" if failures == 0 else f"{failures} check(s) failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
