//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CommonCrypto
import Starscream

import AltStoreCore
import AltSign
import Roxas

@objc(FetchAnisetteDataOperation)
final class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, WebSocketDelegate
{
    let context: OperationContext
    var socket: WebSocket!
    
    var url: URL?
    var startProvisioningURL: URL?
    var endProvisioningURL: URL?
    
    var clientInfo: String?
    var userAgent: String?
    
    var mdLu: String?
    var deviceId: String?
    
    init(context: OperationContext)
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        // if you're using this test build we're gonna force you to use ani.sidestore.io
        self.url = URL(string: "https://ani.sidestore.io")!
//        self.url = AnisetteManager.currentURL
        print("Anisette URL: \(self.url!.absoluteString)")
        
        if let identifier = Keychain.shared.identifier,
           let adiPb = Keychain.shared.adiPb {
            fetchAnisetteV3(identifier, adiPb)
        } else {
            provision()
        }
    }
    
    func handleV1() {
        print("Server is V1")
        
        if UserDefaults.shared.trustedServerURL == AnisetteManager.currentURLString {
            print("Server has already been trusted, fetching anisette")
            return self.fetchAnisetteV1()
        }
        
        print("Alerting user about outdated server")
        let alert = UIAlertController(title: "WARNING", message: "We've detected you are using an older anisette server. Using this server has a higher likelihood of locking your account and causing other issues. Are you sure you want to continue?", preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: "Continue", style: UIAlertAction.Style.destructive, handler: { action in
            print("Fetching anisette via V1")
            UserDefaults.shared.trustedServerURL = AnisetteManager.currentURLString
            self.fetchAnisetteV1()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { action in
            print("Cancelled anisette operation")
            self.finish(.failure(OperationError.cancelled))
        }))

        let keyWindow = UIApplication.shared.windows.filter { $0.isKeyWindow }.first

        DispatchQueue.main.async {
            if let presentingController = keyWindow?.rootViewController?.presentedViewController {
                presentingController.present(alert, animated: true)
            } else {
                keyWindow?.rootViewController?.present(alert, animated: true)
            }
        }
    }
    
    func fetchAnisetteV1() {
        print("Fetching anisette V1")
        URLSession.shared.dataTask(with: self.url!) { data, response, error in
            do {
                guard let data = data, error == nil else { throw OperationError.invalidAnisette }
                
                // make sure this JSON is in the format we expect
                // convert data to json
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    // try to read out a dictionary
                    // for some reason serial number isn't needed but it doesn't work unless it has a value
                    var formattedJSON: [String: String] = ["deviceSerialNumber": "0"]
                    if let machineID = json["X-Apple-I-MD-M"] { formattedJSON["machineID"] = machineID }
                    if let oneTimePassword = json["X-Apple-I-MD"] { formattedJSON["oneTimePassword"] = oneTimePassword }
                    if let localUserID = json["X-Apple-I-MD-LU"] { formattedJSON["localUserID"] = localUserID }
                    if let routingInfo = json["X-Apple-I-MD-RINFO"] { formattedJSON["routingInfo"] = routingInfo }
                    if let deviceUniqueIdentifier = json["X-Mme-Device-Id"] { formattedJSON["deviceUniqueIdentifier"] = deviceUniqueIdentifier }
                    if let deviceDescription = json["X-MMe-Client-Info"] { formattedJSON["deviceDescription"] = deviceDescription }
                    if let date = json["X-Apple-I-Client-Time"] { formattedJSON["date"] = date }
                    if let locale = json["X-Apple-Locale"] { formattedJSON["locale"] = locale }
                    if let timeZone = json["X-Apple-I-TimeZone"] { formattedJSON["timeZone"] = timeZone }
                    
                    if let response = response as? HTTPURLResponse,
                       let version = response.value(forHTTPHeaderField: "Implementation-Version") {
                        print("Implementation-Version: \(version)")
                    } else { print("No Implementation-Version header") }
                    
                    print("Anisette used: \(formattedJSON)")
                    print("Original JSON: \(json)")
                    if let anisette = ALTAnisetteData(json: formattedJSON) {
                        print("Anisette is valid!")
                        self.finish(.success(anisette))
                    } else {
                        print("Anisette is invalid!!!!")
                        throw OperationError.invalidAnisette
                    }
                }
            } catch let error as NSError {
                print("Failed to load: \(error.localizedDescription)")
                self.finish(.failure(OperationError.invalidAnisette)) // always show the user invalidAnisette so they know what it was caused by
            }
        }.resume()
    }
    
    func provision() {
        print("Trying to get client_info")
        let clientInfoURL = self.url!.appendingPathComponent("v3").appendingPathComponent("client_info")
        URLSession.shared.dataTask(with: clientInfoURL) { data, response, error in
            do {
                guard let data = data, error == nil else { throw OperationError.anisetteError }
                
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    if let clientInfo = json["client_info"] {
                        print("Server is V3")
                        
                        self.clientInfo = clientInfo
                        self.userAgent = json["user_agent"]!
                        print("Client-Info: \(self.clientInfo!)")
                        print("User-Agent: \(self.userAgent!)")
                        
                        if Keychain.shared.identifier == nil {
                            print("Generating identifier")
                            var bytes = [Int8](repeating: 0, count: 16)
                            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                            
                            if status != errSecSuccess {
                                print("ERROR GENERATING IDENTIFIER!!! \(status)")
                                return self.finish(.failure(OperationError.provisioningError))
                            }
                            
                            Keychain.shared.identifier = Data(bytes: &bytes, count: bytes.count).base64EncodedString()
                        }
                        
                        let decoded = Data(base64Encoded: Keychain.shared.identifier!)!
                        self.mdLu = decoded.sha256().hexEncodedString()
                        print("X-Apple-I-MD-LU: \(self.mdLu!)")
                        let uuid: UUID = decoded.object()
                        self.deviceId = uuid.uuidString.uppercased()
                        print("X-Mme-Device-Id: \(self.deviceId!)")
                        
                        print("Getting provisioning URLs")
                        var request = self.buildAppleRequest(url: URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!)
                        request.httpMethod = "GET"
                        URLSession.shared.dataTask(with: request) { data, response, error in
                            let plist = try! PropertyListSerialization.propertyList(from: data!, format: nil) as! Dictionary<String, Dictionary<String, Any>>
                            self.startProvisioningURL = URL(string: plist["urls"]!["midStartProvisioning"] as! String)!
                            self.endProvisioningURL = URL(string: plist["urls"]!["midFinishProvisioning"] as! String)!
                            print("startProvisioningURL: \(self.startProvisioningURL!.absoluteString)")
                            print("endProvisioningURL: \(self.endProvisioningURL!.absoluteString)")
                            print("Starting a provisioning session")
                            self.startProvisioningSession()
                        }.resume()
                    } else { self.handleV1() }
                } else { self.handleV1() }
            } catch let error as NSError {
                print("Failed to load: \(error.localizedDescription)")
                self.finish(.failure(OperationError.anisetteError)) // always show the user anisetteError so they know what it was caused by
            }
        }.resume()
    }
    
    func startProvisioningSession() {
        let provisioningSessionURL = self.url!.appendingPathComponent("v3").appendingPathComponent("provisioning_session")
        var wsRequest = URLRequest(url: provisioningSessionURL)
        wsRequest.timeoutInterval = 5
        self.socket = WebSocket(request: wsRequest)
        self.socket.delegate = self
        self.socket.connect()
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .text(let string):
            do {
                if let json = try JSONSerialization.jsonObject(with: string.data(using: .utf8)!, options: []) as? [String: Any] {
                    let result = json["result"]! as! String
                    print("Received result: \(result)")
                    switch result {
                    case "TryAgainSoon":
                        let duration = json["duration"]! as! Double
                        print("Trying again in \(duration) milliseconds")
                        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + (duration / 1000)) {
                            print("Trying again")
                            self.startProvisioningSession()
                        }
                        
                    case "GiveIdentifier":
                        print("Giving identifier")
                        client.json(["identifier": Keychain.shared.identifier!])
                        
                    case "GiveStartProvisioningData":
                        print("Getting start provisioning data")
                        let body = [
                            "Header": [String: Any](),
                            "Request": [String: Any](),
                        ]
                        var request = self.buildAppleRequest(url: self.startProvisioningURL!)
                        request.httpMethod = "POST"
                        request.httpBody = try! PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
                        URLSession.shared.dataTask(with: request) { data, response, error in
                            let plist = try! PropertyListSerialization.propertyList(from: data!, format: nil) as! Dictionary<String, Dictionary<String, Any>>
                            let spim = plist["Response"]!["spim"] as! String
                            print("Giving start provisioning data")
                            client.json(["spim": spim])
                        }.resume()
                        
                    case "GiveEndProvisioningData":
                        print("Getting end provisioning data")
                        let cpim = json["cpim"]! as! String
                        let body = [
                            "Header": [String: Any](),
                            "Request": [
                                "cpim": cpim,
                            ],
                        ]
                        var request = self.buildAppleRequest(url: self.endProvisioningURL!)
                        request.httpMethod = "POST"
                        request.httpBody = try! PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
                        URLSession.shared.dataTask(with: request) { data, response, error in
                            let plist = try! PropertyListSerialization.propertyList(from: data!, format: nil) as! Dictionary<String, Dictionary<String, Any>>
                            let ptm = plist["Response"]!["ptm"] as! String
                            let tk = plist["Response"]!["tk"] as! String
                            print("Giving end provisioning data")
                            client.json(["ptm": ptm, "tk": tk])
                        }.resume()
                        
                    case "ProvisioningSuccess":
                        print("Provisioning succeeded!")
                        Keychain.shared.adiPb = json["adi_pb"]! as? String
                        client.disconnect(closeCode: 0)
                        self.fetchAnisetteV3(Keychain.shared.identifier!, Keychain.shared.adiPb!)
                        
                    default:
                        if result.contains("Error") || result.contains("Invalid") || result == "ClosingPerRequest" || result == "Timeout" || result == "TextOnly" {
                            print("Failing because of \(result)")
                            self.finish(.failure(OperationError.provisioningError))
                        }
                    }
                }
            } catch let error as NSError {
                print("Failed to handle text: \(error.localizedDescription)")
                self.finish(.failure(OperationError.provisioningError))
            }
            
        case .connected:
            print("Connected")
            
        case .disconnected(let string, let code):
            print("Disconnected: \(code); \(string)")
            
        case .error(let error):
            print("Got error: \(String(describing: error))")
            
        default:
            print("Unknown event: \(event)")
        }
    }
    
    func fetchAnisetteV3(_ identifier: String, _ adiPb: String) {
        print("Fetching anisette V3")
        var request = URLRequest(url: self.url!.appendingPathComponent("v3").appendingPathComponent("get_headers"))
        request.httpMethod = "POST"
        request.httpBody = try! JSONSerialization.data(withJSONObject: [
            "identifier": identifier,
            "adi_pb": adiPb
        ], options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { data, response, error in
            do {
                guard let data = data, error == nil else { throw OperationError.anisetteError }
                
                // make sure this JSON is in the format we expect
                // convert data to json
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    if json["result"] == "GetHeadersError" {
                        print("Error getting V3 headers: \(json["message"]!)")
                        throw OperationError.anisetteError
                    }
                    
                    // try to read out a dictionary
                    // for some reason serial number isn't needed but it doesn't work unless it has a value
                    var formattedJSON: [String: String] = ["deviceSerialNumber": "0"]
                    if let machineID = json["X-Apple-I-MD-M"] { formattedJSON["machineID"] = machineID }
                    if let oneTimePassword = json["X-Apple-I-MD"] { formattedJSON["oneTimePassword"] = oneTimePassword }
                    if let routingInfo = json["X-Apple-I-MD-RINFO"] { formattedJSON["routingInfo"] = routingInfo }
                    formattedJSON["deviceDescription"] = self.clientInfo!
                    formattedJSON["localUserID"] = self.mdLu!
                    formattedJSON["deviceUniqueIdentifier"] = self.deviceId!
                    
                    // Generate date stuff on client
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.calendar = Calendar(identifier: .gregorian)
                    formatter.timeZone = TimeZone.current
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                    let dateString = formatter.string(from: Date())
                    formattedJSON["date"] = dateString
                    formattedJSON["locale"] = Locale.current.identifier
                    formattedJSON["timeZone"] = TimeZone.current.abbreviation()
                    
                    if let response = response as? HTTPURLResponse,
                       let version = response.value(forHTTPHeaderField: "Implementation-Version") {
                        print("Implementation-Version: \(version)")
                    } else { print("No Implementation-Version header") }
                    
                    print("Anisette used: \(formattedJSON)")
                    print("Original JSON: \(json)")
                    if let anisette = ALTAnisetteData(json: formattedJSON) {
                        print("Anisette is valid!")
                        self.finish(.success(anisette))
                    } else {
                        print("Anisette is invalid!!!!")
                        throw OperationError.anisetteError
                    }
                }
            } catch let error as NSError {
                print("Failed to load: \(error.localizedDescription)")
                self.finish(.failure(OperationError.anisetteError)) // always show the user anisetteError so they know what it was caused by
            }
        }.resume()
    }
    
    func buildAppleRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(self.clientInfo!, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(self.userAgent!, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        request.setValue(self.mdLu, forHTTPHeaderField: "X-Apple-I-MD-LU")
        request.setValue(self.deviceId, forHTTPHeaderField: "X-Mme-Device-Id")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let dateString = formatter.string(from: Date())
        request.setValue(dateString, forHTTPHeaderField: "X-Apple-I-Client-Time")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(TimeZone.current.abbreviation(), forHTTPHeaderField: "X-Apple-I-TimeZone")
        return request
    }
}

extension WebSocket {
    func json(_ dictionary: [String: String]) {
        let data = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
        self.write(string: String(data: data, encoding: .utf8)!)
    }
}

extension Data {
    // https://stackoverflow.com/a/25391020
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
    
    // https://stackoverflow.com/a/40089462
    func hexEncodedString() -> String {
        return self.map { String(format: "%02hhX", $0) }.joined()
    }
    
    // https://stackoverflow.com/a/59127761
    func object<T>() -> T { self.withUnsafeBytes { $0.load(as: T.self) } }
}
