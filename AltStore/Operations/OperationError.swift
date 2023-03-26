//
//  OperationError.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign
import minimuxer

enum OperationError: LocalizedError
{
    static let domain = OperationError.unknown._domain
    
    case unknown
    case unknownResult
    case cancelled
    case timedOut
    
    case notAuthenticated
    case appNotFound
    
    case unknownUDID
    
    case invalidApp
    case invalidParameters
    
    case maximumAppIDLimitReached(application: ALTApplication, requiredAppIDs: Int, availableAppIDs: Int, nextExpirationDate: Date)
    
    case noSources
    
    case openAppFailed(name: String)
    case missingAppGroup
    
    case noDevice
    case createService(name: String)
    case getFromDevice(name: String)
    case setArgument(name: String)
    case afc
    case install
    case uninstall
    case lookupApps
    case detach
    case attach
    case functionArguments
    case profileManage
    case noConnection
    case invalidPairingFile(details: String)
    case swiftBridgeIssue
    
    case invalidAnisette
    case provisioningError
    case anisetteError
    
    var failureReason: String? {
        switch self {
        case .unknown: return NSLocalizedString("An unknown error occured.", comment: "")
        case .unknownResult: return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
        case .timedOut: return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .appNotFound: return NSLocalizedString("App not found.", comment: "")
        case .unknownUDID: return NSLocalizedString("Unknown device UDID.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is invalid.", comment: "")
        case .invalidParameters: return NSLocalizedString("Invalid parameters.", comment: "")
        case .noSources: return NSLocalizedString("There are no SideStore sources.", comment: "")
        case .openAppFailed(let name): return String(format: NSLocalizedString("SideStore was denied permission to launch %@.", comment: ""), name)
        case .missingAppGroup: return NSLocalizedString("SideStore's shared app group could not be found.", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs.", comment: "")
        case .noDevice: return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .createService(let name): return String(format: NSLocalizedString("Cannot start a %@ server on the device.", comment: ""), name)
        case .getFromDevice(let name): return String(format: NSLocalizedString("Cannot fetch %@ from the device.", comment: ""), name)
        case .setArgument(let name): return String(format: NSLocalizedString("Cannot set %@ on the device.", comment: ""), name)
        case .afc: return NSLocalizedString("AFC was unable to manage files on the device", comment: "")
        case .install: return NSLocalizedString("Unable to install the app from the staging directory", comment: "")
        case .uninstall: return NSLocalizedString("Unable to uninstall the app", comment: "")
        case .lookupApps: return NSLocalizedString("Unable to fetch apps from the device", comment: "")
        case .detach: return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .attach: return NSLocalizedString("Unable to attach to the app's process", comment: "")
        case .functionArguments: return NSLocalizedString("A function was passed invalid arguments", comment: "")
        case .profileManage: return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .noConnection: return NSLocalizedString("Unable to connect to the device, make sure Wireguard is enabled and you're connected to WiFi", comment: "")
        case .invalidPairingFile(let details): return String(format: NSLocalizedString("Invalid pairing file. %@", comment: ""), details)
        case .swiftBridgeIssue: return NSLocalizedString("There was an issue giving bytes to Rust. PLEASE REPORT THIS TO GITHUB ISSUES!", comment: "")
        case .invalidAnisette: return NSLocalizedString("Anisette server returned invalid data. Try using another anisette server.", comment: "")
        case .provisioningError: return NSLocalizedString("An error occurred when provisioning. Please try again. If the issue persists, report it on GitHub Issues!", comment: "")
        case .anisetteError: return NSLocalizedString("An error occurred when getting anisette data. Please try again. If the issue persists, report it on GitHub Issues!", comment: "")
        }
    }
    
    var recoverySuggestion: String? {
        switch self
        {
        case .maximumAppIDLimitReached(let application, let requiredAppIDs, let availableAppIDs, let date):
            let baseMessage = NSLocalizedString("Delete sideloaded apps to free up App ID slots.", comment: "")
            let message: String
            
            if requiredAppIDs > 1
            {
                let availableText: String
                
                switch availableAppIDs
                {
                case 0: availableText = NSLocalizedString("none are available", comment: "")
                case 1: availableText = NSLocalizedString("only 1 is available", comment: "")
                default: availableText = String(format: NSLocalizedString("only %@ are available", comment: ""), NSNumber(value: availableAppIDs))
                }
                
                let prefixMessage = String(format: NSLocalizedString("%@ requires %@ App IDs, but %@.", comment: ""), application.name, NSNumber(value: requiredAppIDs), availableText)
                message = prefixMessage + " " + baseMessage
            }
            else
            {
                let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: date)
                
                let dateComponentsFormatter = DateComponentsFormatter()
                dateComponentsFormatter.maximumUnitCount = 1
                dateComponentsFormatter.unitsStyle = .full
                
                let remainingTime = dateComponentsFormatter.string(from: dateComponents)!
                
                let remainingTimeMessage = String(format: NSLocalizedString("You can register another App ID in %@.", comment: ""), remainingTime)
                message = baseMessage + " " + remainingTimeMessage
            }
            
            return message
            
        default: return nil
        }
    }
}

func minimuxerToOperationError(_ error: Error) -> OperationError {
    if let error = error as? Errors {
        switch error {
        case .NoDevice:
            return OperationError.noDevice
        case .NoConnection:
            return OperationError.noConnection
        case .PairingFile:
            return OperationError.invalidPairingFile(details: "Your pairing file either didn't have a UDID, or it wasn't a valid plist. Please use jitterbugpair to generate it")
        case .UDIDMismatch:
            return OperationError.invalidPairingFile(details: "Your pairing file's UDID didn't match up with your device. Please regenerate the pairing file, and ensure you generate it for the correct device")
        case .CreateDebug:
            return OperationError.createService(name: "debug")
        case .CreateInstproxy:
            return OperationError.createService(name: "instproxy")
        case .LookupApps:
            return OperationError.getFromDevice(name: "installed apps")
        case .FindApp:
            return OperationError.getFromDevice(name: "path to the app")
        case .BundlePath:
            return OperationError.getFromDevice(name: "bundle path")
        case .MaxPacket:
            return OperationError.setArgument(name: "max packet")
        case .WorkingDirectory:
            return OperationError.setArgument(name: "working directory")
        case .Argv:
            return OperationError.setArgument(name: "argv")
        case .LaunchSuccess:
            return OperationError.getFromDevice(name: "launch success")
        case .Detach:
            return OperationError.detach
        case .Attach:
            return OperationError.attach
        case .CreateAfc:
            return OperationError.createService(name: "AFC")
        case .RwAfc:
            return OperationError.afc
        case .InstallApp:
            return OperationError.install
        case .UninstallApp:
            return OperationError.uninstall
        case .CreateMisagent:
            return OperationError.createService(name: "misagent")
        case .ProfileInstall:
            return OperationError.profileManage
        case .ProfileRemove:
            return OperationError.profileManage
        }
    }
    print("\n\nERROR GIVEN TO minimuxerToOperationError IS NOT AN Errors!!!!!!!!!!!!!!!!!! \(error)\n\n")
    return OperationError.unknown
}
