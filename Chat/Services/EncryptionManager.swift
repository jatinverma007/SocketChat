//
//  EncryptionManager.swift
//  Chat
//
//  End-to-end encryption manager for secure messaging
//

import Foundation
import Security
import CryptoKit

class EncryptionManager {
    static let shared = EncryptionManager()
    
    private let keychainService = "com.shadowswap.chat.encryption"
    private let privateKeyTag = "com.shadowswap.privatekey"
    private let publicKeyTag = "com.shadowswap.publickey"
    
    private init() {}
    
    // MARK: - Key Pair Management
    
    /// Generate RSA key pair on first app launch
    func generateKeyPair() throws -> (publicKey: SecKey, privateKey: SecKey) {
        print("🔐 Generating RSA key pair...")
        
        // Check if keys already exist
        if let existingKeys = try? getExistingKeyPair() {
            print("✅ Using existing key pair")
            return existingKeys
        }
        
        // Generate new 2048-bit RSA key pair
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: privateKeyTag.data(using: .utf8)!,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ],
            kSecPublicKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: publicKeyTag.data(using: .utf8)!,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            print("❌ Failed to generate key pair: \(error!.takeRetainedValue())")
            throw error!.takeRetainedValue() as Error
        }
        
        print("✅ Key pair generated successfully")
        return (publicKey, privateKey)
    }
    
    /// Get existing key pair from Keychain
    func getExistingKeyPair() throws -> (publicKey: SecKey, privateKey: SecKey)? {
        // Query private key
        let privateKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]
        
        var privateKeyRef: CFTypeRef?
        let privateStatus = SecItemCopyMatching(privateKeyQuery as CFDictionary, &privateKeyRef)
        
        guard privateStatus == errSecSuccess,
              let keyRef = privateKeyRef else {
            return nil
        }
        
        // Force cast is safe here since we queried specifically for a key type
        let privateKey = (keyRef as! SecKey)
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        
        return (publicKey, privateKey)
    }
    
    /// Export public key as Base64 string for server upload
    func exportPublicKey(_ publicKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error!.takeRetainedValue() as Error
        }
        
        return publicKeyData.base64EncodedString()
    }
    
    /// Import public key from Base64 string (for other users)
    func importPublicKey(_ base64String: String) throws -> SecKey {
        guard let publicKeyData = Data(base64Encoded: base64String) else {
            throw EncryptionError.invalidPublicKey
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(publicKeyData as CFData, attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return publicKey
    }
    
    // MARK: - Server Communication
    
    /// Upload public key to server
    func uploadPublicKeyToServer(authToken: String) async throws {
        print("🔐 Uploading public key to server...")
        
        // Generate or get existing key pair
        let keyPair = try generateKeyPair()
        let publicKeyString = try exportPublicKey(keyPair.publicKey)
        
        // Prepare request
        let url = URL(string: ServerConfig.encryptionUploadKey)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "public_key": publicKeyString,
            "key_format": "RSA-2048"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EncryptionError.uploadFailed
        }
        
        print("🔐 Upload response status: \(httpResponse.statusCode)")
        
        // Accept both 200 (success) and 400 (already exists) as valid
        if httpResponse.statusCode == 200 {
            print("✅ Public key uploaded successfully")
        } else if httpResponse.statusCode == 400 {
            if let responseString = String(data: data, encoding: .utf8),
               responseString.contains("already exists") {
                print("✅ Public key already exists on server - OK")
            } else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Upload failed - Response: \(responseString)")
                }
                throw EncryptionError.uploadFailed
            }
        } else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Upload failed - Response: \(responseString)")
            }
            throw EncryptionError.uploadFailed
        }
    }
    
    /// Fetch public keys for all users in a room
    func fetchRoomKeys(roomId: String, authToken: String) async throws -> [String] {
        print("🔐 Fetching room keys for room: \(roomId)")
        
        let url = URL(string: ServerConfig.encryptionRoomKeys(roomId))!
        print("🔐 Request URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw EncryptionError.keysFetchFailed
        }
        
        print("🔐 Fetch room keys status: \(httpResponse.statusCode)")
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔐 Response body: \(responseString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ Fetch room keys failed with status: \(httpResponse.statusCode)")
            throw EncryptionError.keysFetchFailed
        }
        
        do {
            let roomKeysResponse = try JSONDecoder().decode(RoomKeysResponse.self, from: data)
            print("✅ Fetched \(roomKeysResponse.users.count) public keys")
            return roomKeysResponse.users.map { $0.public_key }
        } catch {
            print("❌ Failed to decode room keys response: \(error)")
            throw EncryptionError.keysFetchFailed
        }
    }
    
    // MARK: - Message Encryption (Hybrid: AES + RSA)
    
    /// Encrypt a message for multiple recipients
    func encryptMessage(_ message: String, forRecipients recipientPublicKeys: [String]) throws -> String {
        print("🔐 Encrypting message for \(recipientPublicKeys.count) recipients...")
        
        // 1. Generate random AES-256 key
        let aesKey = SymmetricKey(size: .bits256)
        let aesKeyData = aesKey.withUnsafeBytes { Data($0) }
        
        // 2. Encrypt message with AES-GCM
        guard let messageData = message.data(using: .utf8) else {
            throw EncryptionError.invalidMessage
        }
        
        let sealedBox = try AES.GCM.seal(messageData, using: aesKey)
        guard let encryptedMessage = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        // 3. Encrypt AES key with each recipient's RSA public key
        var encryptedKeys: [String] = []
        
        for recipientKeyString in recipientPublicKeys {
            do {
                let recipientPublicKey = try importPublicKey(recipientKeyString)
                
                var error: Unmanaged<CFError>?
                guard let encryptedKeyData = SecKeyCreateEncryptedData(
                    recipientPublicKey,
                    .rsaEncryptionOAEPSHA256,
                    aesKeyData as CFData,
                    &error
                ) as Data? else {
                    print("⚠️ Failed to encrypt key for recipient, skipping...")
                    continue
                }
                
                encryptedKeys.append(encryptedKeyData.base64EncodedString())
            } catch {
                print("⚠️ Failed to process recipient key: \(error)")
                continue
            }
        }
        
        guard !encryptedKeys.isEmpty else {
            throw EncryptionError.noValidRecipients
        }
        
        // 4. Combine encrypted message + encrypted keys
        let payload: [String: Any] = [
            "encrypted_message": encryptedMessage.base64EncodedString(),
            "encrypted_keys": encryptedKeys,
            "version": "AES-256-GCM"
        ]
        
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let finalPayload = payloadData.base64EncodedString()
        
        print("✅ Message encrypted successfully")
        return finalPayload
    }
    
    // MARK: - Message Decryption
    
    /// Decrypt a received message
    func decryptMessage(_ encryptedPayload: String) throws -> String {
        print("🔐 Decrypting message...")
        
        // 1. Decode the payload
        guard let payloadData = Data(base64Encoded: encryptedPayload),
              let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let encryptedMessageB64 = payload["encrypted_message"] as? String,
              let encryptedKeys = payload["encrypted_keys"] as? [String],
              let encryptedMessageData = Data(base64Encoded: encryptedMessageB64) else {
            print("❌ Invalid encrypted payload format")
            throw EncryptionError.invalidPayload
        }
        
        // 2. Get our private key
        guard let keyPair = try getExistingKeyPair() else {
            print("❌ No private key found")
            throw EncryptionError.noPrivateKey
        }
        
        // 3. Try to decrypt the AES key with our private key
        var aesKeyData: Data?
        
        for encryptedKeyString in encryptedKeys {
            guard let encryptedKeyData = Data(base64Encoded: encryptedKeyString) else {
                continue
            }
            
            var error: Unmanaged<CFError>?
            if let decryptedKey = SecKeyCreateDecryptedData(
                keyPair.privateKey,
                .rsaEncryptionOAEPSHA256,
                encryptedKeyData as CFData,
                &error
            ) as Data? {
                aesKeyData = decryptedKey
                break
            }
        }
        
        guard let aesKeyData = aesKeyData else {
            print("❌ Could not decrypt AES key with our private key")
            throw EncryptionError.decryptionFailed
        }
        
        // 4. Decrypt message with AES key
        let aesKey = SymmetricKey(data: aesKeyData)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedMessageData)
        let decryptedData = try AES.GCM.open(sealedBox, using: aesKey)
        
        guard let decryptedMessage = String(data: decryptedData, encoding: .utf8) else {
            print("❌ Could not decode decrypted message")
            throw EncryptionError.decryptionFailed
        }
        
        print("✅ Message decrypted successfully")
        return decryptedMessage
    }
}

// MARK: - Data Models

struct RoomKeysResponse: Codable {
    let room_id: Int
    let room_name: String
    let users: [PublicKeyInfo]
}

struct PublicKeyInfo: Codable {
    let user_id: Int
    let username: String
    let public_key: String
    let key_format: String
    let created_at: String
    let updated_at: String
}

// MARK: - Errors

enum EncryptionError: Error, LocalizedError {
    case invalidPublicKey
    case invalidMessage
    case invalidPayload
    case encryptionFailed
    case decryptionFailed
    case noPrivateKey
    case noValidRecipients
    case uploadFailed
    case keysFetchFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "Invalid public key format"
        case .invalidMessage:
            return "Invalid message format"
        case .invalidPayload:
            return "Invalid encrypted payload"
        case .encryptionFailed:
            return "Failed to encrypt message"
        case .decryptionFailed:
            return "Failed to decrypt message"
        case .noPrivateKey:
            return "No private key found"
        case .noValidRecipients:
            return "No valid recipients for encryption"
        case .uploadFailed:
            return "Failed to upload public key"
        case .keysFetchFailed:
            return "Failed to fetch room keys"
        }
    }
}

