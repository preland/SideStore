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

extension MinimuxerError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .NoDevice:
            return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .NoConnection:
            return NSLocalizedString("Unable to connect to the device, make sure Wireguard is enabled and you're connected to WiFi", comment: "")
        case .PairingFile:
            return NSLocalizedString("Invalid pairing file. Your pairing file either didn't have a UDID, or it wasn't a valid plist. Please use jitterbugpair to generate it", comment: "")
            
        case .CreateDebug:
            return self.createService(name: "debug")
        case .LookupApps:
            return self.getFromDevice(name: "installed apps")
        case .FindApp:
            return self.getFromDevice(name: "path to the app")
        case .BundlePath:
            return self.getFromDevice(name: "bundle path")
        case .MaxPacket:
            return self.setArgument(name: "max packet")
        case .WorkingDirectory:
            return self.setArgument(name: "working directory")
        case .Argv:
            return self.setArgument(name: "argv")
        case .LaunchSuccess:
            return self.getFromDevice(name: "launch success")
        case .Detach:
            return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .Attach:
            return NSLocalizedString("Unable to attach to the app's process", comment: "")
            
        case .CreateInstproxy:
            return self.createService(name: "instproxy")
        case .CreateAfc:
            return self.createService(name: "AFC")
        case .RwAfc:
            return NSLocalizedString("AFC was unable to manage files on the device", comment: "")
        case .InstallApp:
            return NSLocalizedString("Unable to install the app from the staging directory", comment: "")
        case .UninstallApp:
            return NSLocalizedString("Unable to uninstall the app", comment: "")

        case .CreateMisagent:
            return self.createService(name: "misagent")
        case .ProfileInstall:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .ProfileRemove:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        }
    }
    
    fileprivate func createService(name: String) -> String {
        return String(format: NSLocalizedString("Cannot start a %@ server on the device.", comment: ""), name)
    }
    
    fileprivate func getFromDevice(name: String) -> String {
        return String(format: NSLocalizedString("Cannot fetch %@ from the device.", comment: ""), name)
    }
    
    fileprivate func setArgument(name: String) -> String {
        return String(format: NSLocalizedString("Cannot set %@ on the device.", comment: ""), name)
    }
}
