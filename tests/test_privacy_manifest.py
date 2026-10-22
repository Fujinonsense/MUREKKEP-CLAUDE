"""The app's privacy manifest: App Store Connect refuses uploads whose binary uses a required-reason
API without a declared reason (ITMS-91053). The build-25 binary uses UserDefaults, file dates
(stat, fstat, NSURLContentModificationDateKey) and free disk space (NSURLVolumeAvailableCapacity...)."""
import plistlib
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "Murekkep.swiftpm"


def manifest():
    return plistlib.loads((APP / "PrivacyInfo.xcprivacy").read_bytes())


def test_no_tracking_and_no_collected_data():
    m = manifest()
    assert m["NSPrivacyTracking"] is False
    assert m["NSPrivacyTrackingDomains"] == []
    assert m["NSPrivacyCollectedDataTypes"] == []


def test_required_reason_apis_declared():
    reasons = {e["NSPrivacyAccessedAPIType"]: e["NSPrivacyAccessedAPITypeReasons"]
               for e in manifest()["NSPrivacyAccessedAPITypes"]}
    assert reasons == {
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
    }
