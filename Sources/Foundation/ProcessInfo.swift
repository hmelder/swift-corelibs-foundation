// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//

import CoreFoundation

public struct OperatingSystemVersion {
    public var majorVersion: Int
    public var minorVersion: Int
    public var patchVersion: Int
    public init() {
        self.init(majorVersion: 0, minorVersion: 0, patchVersion: 0)
    }
    
    public init(majorVersion: Int, minorVersion: Int, patchVersion: Int) {
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
        self.patchVersion = patchVersion
    }
}



open class ProcessInfo: NSObject {
    
    public static let processInfo = ProcessInfo()
    
    internal override init() {
        
    }
    
    open var environment: [String : String] {
        let equalSign = Character("=")
        let strEncoding = String.defaultCStringEncoding
        let envp = _CFEnviron()
        var env: [String : String] = [:]
        var idx = 0

        while let entry = envp.advanced(by: idx).pointee {
            if let entry = String(cString: entry, encoding: strEncoding),
               let i = entry.firstIndex(of: equalSign) {
                let key = String(entry.prefix(upTo: i))
                let value = String(entry.suffix(from: i).dropFirst())
                env[key] = value
            }
            idx += 1
        }
        return env
    }
    
    open var arguments: [String] {
        return CommandLine.arguments // seems reasonable to flip the script here...
    }
    
    open var hostName: String {
        if let name = Host.current().name {
            return name
        } else {
            return "localhost"
        }
    }
    
    open var processName: String = _CFProcessNameString()._swiftObject
    
    open var processIdentifier: Int32 {
#if os(Windows)
        return Int32(GetProcessId(GetCurrentProcess()))
#else
        return Int32(getpid())
#endif
    }
    
    open var globallyUniqueString: String {
        let uuid = CFUUIDCreate(kCFAllocatorSystemDefault)
        return CFUUIDCreateString(kCFAllocatorSystemDefault, uuid)._swiftObject
    }

#if os(Windows)
    internal var _rawOperatingSystemVersionInfo: RTL_OSVERSIONINFOEXW? {
        guard let ntdll = ("ntdll.dll".withCString(encodedAs: UTF16.self) {
            LoadLibraryExW($0, nil, DWORD(LOAD_LIBRARY_SEARCH_SYSTEM32))
        }) else {
            return nil
        }
        defer { FreeLibrary(ntdll) }
        typealias RTLGetVersionTy = @convention(c) (UnsafeMutablePointer<RTL_OSVERSIONINFOEXW>) -> NTSTATUS
        guard let pfnRTLGetVersion = unsafeBitCast(GetProcAddress(ntdll, "RtlGetVersion"), to: Optional<RTLGetVersionTy>.self) else {
            return nil
        }
        var osVersionInfo = RTL_OSVERSIONINFOEXW()
        osVersionInfo.dwOSVersionInfoSize = DWORD(MemoryLayout<RTL_OSVERSIONINFOEXW>.size)
        guard pfnRTLGetVersion(&osVersionInfo) == 0 else {
            return nil
        }
        return osVersionInfo
    }
#endif
    
    internal lazy var _operatingSystemVersionString: String = {
#if canImport(Darwin)
        // Just use CoreFoundation on Darwin
        return CFCopySystemVersionString()?._swiftObject ?? "Darwin"
#elseif os(Linux)
        // Try to parse a `PRETTY_NAME` out of `/etc/os-release`.
        if let osReleaseContents = try? String(contentsOf: URL(fileURLWithPath: "/etc/os-release", isDirectory: false)),
           let name = osReleaseContents.split(separator: "\n").first(where: { $0.hasPrefix("PRETTY_NAME=") })
        {
            // This is extremely simplistic but manages to work for all known cases.
            return String(name.dropFirst("PRETTY_NAME=".count).trimmingCharacters(in: .init(charactersIn: "\"")))
        }
        
        // Okay, we can't get a distro name, so try for generic info.
        var versionString = "Linux"
        
        // Try to get a release version number from `uname -r`.
        var utsNameBuffer = utsname()
        if uname(&utsNameBuffer) == 0 {
            let release = withUnsafePointer(to: &utsNameBuffer.release.0) { String(cString: $0) }
            if !release.isEmpty {
                versionString += " \(release)"
            }
        }
        
        return versionString
#elseif os(Windows)
        var versionString = "Windows"
        
        guard let osVersionInfo = self._rawOperatingSystemVersionInfo else {
            return versionString
        }

        // Windows has no canonical way to turn the fairly complex `RTL_OSVERSIONINFOW` version info into a string. We
        // do our best here to construct something consistent. Unfortunately, to provide a useful result, this requires
        // hardcoding several of the somewhat ambiguous values in the table provided here:
        //  https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/ns-wdm-_osversioninfoexw#remarks
        switch (osVersionInfo.dwMajorVersion, osVersionInfo.dwMinorVersion) {
            case (5, 0): versionString += " 2000"
            case (5, 1): versionString += " XP"
            case (5, 2) where osVersionInfo.wProductType == VER_NT_WORKSTATION: versionString += " XP Professional x64"
            case (5, 2) where osVersionInfo.wSuiteMask == VER_SUITE_WH_SERVER: versionString += " Home Server"
            case (5, 2): versionString += " Server 2003"
            case (6, 0) where osVersionInfo.wProductType == VER_NT_WORKSTATION: versionString += " Vista"
            case (6, 0): versionString += " Server 2008"
            case (6, 1) where osVersionInfo.wProductType == VER_NT_WORKSTATION: versionString += " 7"
            case (6, 1): versionString += " Server 2008 R2"
            case (6, 2) where osVersionInfo.wProductType == VER_NT_WORKSTATION: versionString += " 8"
            case (6, 2): versionString += " Server 2012"
            case (6, 3) where osVersionInfo.wProductType == VER_NT_WORKSTATION: versionString += " 8.1"
            case (6, 3): versionString += " Server 2012 R2" // We assume the "10,0" numbers in the table for this are a typo
            case (10, 0) where osVersionInfo.wProductType == VER_NT_WORKSTATION: versionString += " 10"
            case (10, 0): versionString += " Server 2019" // The table gives identical values for 2016 and 2019, so we just assume 2019 here
            case let (maj, min): versionString += " \(maj).\(min)" // If all else fails, just give the raw version number
        }
        versionString += " (build \(osVersionInfo.dwBuildNumber))"
        // For now we ignore the `szCSDVersion`, `wServicePackMajor`, and `wServicePackMinor` values.
        return versionString
#else
        // On other systems at least return something.
        return "Unknown"
#endif
    }()
    open var operatingSystemVersionString: String { return _operatingSystemVersionString }
    
    open var operatingSystemVersion: OperatingSystemVersion {
        // The following fallback values match Darwin Foundation
        let fallbackMajor = -1
        let fallbackMinor = 0
        let fallbackPatch = 0
        let versionString: String

#if canImport(Darwin)
        guard let systemVersionDictionary = _CFCopySystemVersionDictionary() else {
            return OperatingSystemVersion(majorVersion: fallbackMajor, minorVersion: fallbackMinor, patchVersion: fallbackPatch)
        }
        
        let productVersionKey = unsafeBitCast(_kCFSystemVersionProductVersionKey, to: UnsafeRawPointer.self)
        guard let productVersion = unsafeBitCast(CFDictionaryGetValue(systemVersionDictionary, productVersionKey), to: NSString?.self) else {
            return OperatingSystemVersion(majorVersion: fallbackMajor, minorVersion: fallbackMinor, patchVersion: fallbackPatch)
        }
        versionString = productVersion._swiftObject
#elseif os(Windows)
        guard let osVersionInfo = self._rawOperatingSystemVersionInfo else {
            return OperatingSystemVersion(majorVersion: fallbackMajor, minorVersion: fallbackMinor, patchVersion: fallbackPatch)
        }

        return OperatingSystemVersion(
            majorVersion: Int(osVersionInfo.dwMajorVersion),
            minorVersion: Int(osVersionInfo.dwMinorVersion),
            patchVersion: Int(osVersionInfo.dwBuildNumber)
        )
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android)
        var utsNameBuffer = utsname()
        guard uname(&utsNameBuffer) == 0 else {
            return OperatingSystemVersion(majorVersion: fallbackMajor, minorVersion: fallbackMinor, patchVersion: fallbackPatch)
        }
        let release = withUnsafePointer(to: &utsNameBuffer.release.0) {
            return String(cString: $0)
        }
        let idx = release.firstIndex(of: "-") ?? release.endIndex
        versionString = String(release[..<idx])
#else
        return OperatingSystemVersion(majorVersion: fallbackMajor, minorVersion: fallbackMinor, patchVersion: fallbackPatch)
#endif
        let versionComponents = versionString.split(separator: ".").map(String.init).compactMap({ Int($0) })
        let majorVersion = versionComponents.dropFirst(0).first ?? fallbackMajor
        let minorVersion = versionComponents.dropFirst(1).first ?? fallbackMinor
        let patchVersion = versionComponents.dropFirst(2).first ?? fallbackPatch
        return OperatingSystemVersion(majorVersion: majorVersion, minorVersion: minorVersion, patchVersion: patchVersion)
    }
    
    internal let _processorCount = __CFProcessorCount()
    open var processorCount: Int {
        return Int(_processorCount)
    }
    
    internal let _activeProcessorCount = __CFActiveProcessorCount()
    open var activeProcessorCount: Int {
        return Int(_activeProcessorCount)
    }
    
    internal let _physicalMemory = __CFMemorySize()
    open var physicalMemory: UInt64 {
        return _physicalMemory
    }
    
    open func isOperatingSystemAtLeast(_ version: OperatingSystemVersion) -> Bool {
        let ourVersion = operatingSystemVersion
        if ourVersion.majorVersion < version.majorVersion {
            return false
        }
        if ourVersion.majorVersion > version.majorVersion {
            return true
        }
        if ourVersion.minorVersion < version.minorVersion {
            return false
        }
        if ourVersion.minorVersion > version.minorVersion {
            return true
        }
        if ourVersion.patchVersion < version.patchVersion {
            return false
        }
        if ourVersion.patchVersion > version.patchVersion {
            return true
        }
        return true
    }
    
    open var systemUptime: TimeInterval {
        return CFGetSystemUptime()
    }
    
    open var userName: String {
        return NSUserName()
    }
    
    open var fullUserName: String {
        return NSFullUserName()
    }
}

// SPI for TestFoundation
internal extension ProcessInfo {
  var _processPath: String {
    return String(cString: _CFProcessPath())
  }
}
