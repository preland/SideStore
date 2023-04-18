//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas
import minimuxer

@objc(RefreshAppOperation)
final class RefreshAppOperation: ResultOperation<InstalledApp>
{
    let context: AppOperationContext
    
    // Strong reference to managedObjectContext to keep it alive until we're finished.
    let managedObjectContext: NSManagedObjectContext
    
    init(context: AppOperationContext)
    {
        self.context = context
        self.managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            
            guard let profiles = self.context.provisioningProfiles else { throw OperationError.invalidParameters }
            
            guard let app = self.context.app else { throw OperationError.appNotFound }
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                print("Sending refresh app request...")

                for p in profiles {
                    do {
                        let bytes = p.value.data.toRustByteSlice()
                        try install_provisioning_profile(bytes.forRust())
                    } catch {
                        return self.finish(.failure(error))
                    }
                    
                    self.progress.completedUnitCount += 1
                    
                    let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
                    self.managedObjectContext.perform {
                        guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
                            return
                        }
                        installedApp.update(provisioningProfile: p.value)
                        for installedExtension in installedApp.appExtensions {
                            guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
                            installedExtension.update(provisioningProfile: provisioningProfile)
                        }
                        self.finish(.success(installedApp))
                    }
                }
            }
        }
        catch
        {
            self.finish(.failure(error))
        }
    }
}
