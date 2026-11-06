import Foundation
import OtterKeepDomain
import Darwin

/// General-purpose POSIX driver supporting HFS+, NFS, SMB, and other POSIX-compatible mounts.
public final class GenericPOSIXDriver: BasePOSIXFileSystemDriver, @unchecked Sendable {

    public override var fsTypeName: String {
        "generic"
    }

    public override init() {
        super.init()
    }
}
