import Foundation

private struct WAVHelper {
    enum AudioFormat: UInt16 {
        case pcm = 1       // Linear PCM (integer)
        case ieeeFloat = 3 // 32-bit float
    }

    static func makeWav(fromPCM pcm: Data,
                        sampleRate: UInt32,
                        bitsPerSample: UInt16,
                        channels: UInt16,
                        format: AudioFormat) -> Data {
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = UInt16(UInt32(channels) * bytesPerSample)
        let subchunk2Size = UInt32(pcm.count)
        let chunkSize = 36 + subchunk2Size

        var data = Data()
        // RIFF
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(chunkSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)
        // fmt 
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)                  // Subchunk1Size for PCM/float
        data.append(format.rawValue.littleEndianData)             // AudioFormat (1=PCM, 3=IEEE float)
        data.append(channels.littleEndianData)
        data.append(sampleRate.littleEndianData)
        data.append(byteRate.littleEndianData)
        data.append(blockAlign.littleEndianData)
        data.append(bitsPerSample.littleEndianData)
        // data
        data.append("data".data(using: .ascii)!)
        data.append(subchunk2Size.littleEndianData)
        data.append(pcm)
        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var le = self.littleEndian
        return Data(bytes: &le, count: MemoryLayout<Self>.size)
    }
}

final class GoogleDriveUploader {
    enum UploadError: Error {
        case invalidToken
        case requestFailed(String)
        case badResponse(Int)
        case noData
    }
    
    var chunkCounter: Int = 0
    // Cache for target folder
    var targetFolderId: String?
    
    // Added root folder cache and name
    private var appRootFolderId: String?
    private let appRootFolderName = "MyAppRoot"
    
    private let launchFolderName: String

    init() {
        self.launchFolderName = "Audio Chunks " + GoogleDriveUploader.iso8601FilenameTimestamp()
    }
    
    static func iso8601FilenameTimestamp(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var ts = formatter.string(from: date)
        ts = ts.replacingOccurrences(of: ":", with: "-")
        ts = ts.replacingOccurrences(of: ".", with: "-")
        return ts
    }
    
    func currentAccessToken() -> String? {
        return AuthManager.shared.getAccessToken()
    }
    
    // Public helper to ensure the root and session subfolder exist and cache IDs
    func ensureDrivePathReady(completion: @escaping (Result<String, Error>) -> Void) {
        guard let token = currentAccessToken() else {
            completion(.failure(UploadError.invalidToken)); return
        }
        // Reuse the same helper logic as in upload path
        func ensureAppSessionFolder(token: String, completion: @escaping (Result<String, Error>) -> Void) {
            let finishWithSession: (String) -> Void = { rootId in
                self.ensureFolderId(named: self.launchFolderName, token: token, parentId: rootId) { result in
                    switch result {
                    case .success(let sessionId):
                        completion(.success(sessionId))
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
            }
            if let cachedRoot = self.appRootFolderId {
                finishWithSession(cachedRoot)
            } else {
                self.ensureFolderId(named: self.appRootFolderName, token: token, parentId: nil) { result in
                    switch result {
                    case .success(let rootId):
                        self.appRootFolderId = rootId
                        finishWithSession(rootId)
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
            }
        }
        ensureAppSessionFolder(token: token) { result in
            switch result {
            case .success(let sessionId):
                self.targetFolderId = sessionId
                appBootLog.infoWithContext("[Drive] ensureDrivePathReady ok: root=\(self.appRootFolderName) session=\(self.launchFolderName) id=\(sessionId)")
                completion(.success(sessionId))
            case .failure(let err):
                appBootLog.errorWithContext("[Drive] ensureDrivePathReady failed: \(err.localizedDescription)")
                completion(.failure(err))
            }
        }
    }
}

extension GoogleDriveUploader {
    private func findFolderId(named name: String, token: String, parentId: String?, completion: @escaping (Result<String?, Error>) -> Void) {
        var q = "name='\(name)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        if let parentId = parentId {
            q += " and '\(parentId)' in parents"
        }
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else { completion(.success(nil)); return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let files = json["files"] as? [[String: Any]],
                   let first = files.first,
                   let id = first["id"] as? String {
                    completion(.success(id))
                } else {
                    completion(.success(nil))
                }
            } catch { completion(.failure(error)) }
        }
        task.resume()
    }

    private func createFolder(named name: String, token: String, parentId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files") else {
            completion(.failure(UploadError.requestFailed("Invalid URL"))); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let parentId = parentId {
            body["parents"] = [parentId]
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else { completion(.failure(UploadError.noData)); return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? String {
                    completion(.success(id))
                } else {
                    completion(.failure(UploadError.requestFailed("No id in folder create response")))
                }
            } catch { completion(.failure(error)) }
        }
        task.resume()
    }

    private func ensureFolderId(named name: String, token: String, parentId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        findFolderId(named: name, token: token, parentId: parentId) { result in
            switch result {
            case .failure(let err): completion(.failure(err))
            case .success(let maybeId):
                if let id = maybeId {
                    completion(.success(id))
                } else {
                    self.createFolder(named: name, token: token, parentId: parentId, completion: completion)
                }
            }
        }
    }
}

extension GoogleDriveUploader {
    func uploadDataChunk(data: Data, mimeType: String, baseFilename: String, completion: @escaping (Result<String, Error>) -> Void) {
        
        appBootLog.infoWithContext("BEFORE_QUARD")
        
        
        guard let token = currentAccessToken() else {
            appBootLog.errorWithContext("[Drive] Missing access token (invalid or not authorized for Drive)")
            completion(.failure(UploadError.invalidToken))
            return
        }
        
        appBootLog.infoWithContext("GOGGLE_DRIVE_UPDATER")

        chunkCounter += 1

        let timestamp = GoogleDriveUploader.iso8601FilenameTimestamp()
        let filename: String
        if mimeType == "audio/wav" {
            filename = "\(timestamp)-chunk-\(chunkCounter).wav"
        } else {
            filename = "\(timestamp)-chunk-\(chunkCounter)"
        }
        let logTag = "[Drive][\(timestamp)][chunk=\(chunkCounter)]"

        var uploadData = data
        var uploadMimeType = mimeType
        if mimeType == "audio/wav" {
            // If not already a RIFF/WAVE file, assume raw PCM and wrap with a WAV header.
            appBootLog.infoWithContext("\(logTag) Input first 12 bytes: \(data.prefix(12) as NSData)")
            let isLikelyWav = data.starts(with: Data("RIFF".utf8))
            appBootLog.infoWithContext("\(logTag) isLikelyWav=\(isLikelyWav)")
            if !isLikelyWav {
                // Validate float32 little-endian mono frame alignment (4 bytes per sample), 44100 Hz
                if data.count % 4 != 0 {
                    appBootLog.errorWithContext("\(logTag) Float32 raw data size (\(data.count)) is not a multiple of 4 bytes; header will be written but content may be misaligned.")
                }
                // Writing a standard IEEE float32 little-endian mono 44100 Hz WAV header. This should match the actual capture format.
                let sampleRate: UInt32 = 44100
                let bitsPerSample: UInt16 = 32
                let channels: UInt16 = 1
                let wavData = WAVHelper.makeWav(fromPCM: data,
                                                sampleRate: sampleRate,
                                                bitsPerSample: bitsPerSample,
                                                channels: channels,
                                                format: .ieeeFloat)
                let headerPreview = wavData.prefix(64)
                appBootLog.infoWithContext("\(logTag) _WAV header (first 64 bytes): \(headerPreview as NSData)")
                let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(timestamp)-chunk-\(chunkCounter).wav")
                do {
                    try wavData.write(to: tmpURL)
                    appBootLog.infoWithContext("\(logTag) Temp _WAV written: \(tmpURL.path)")
                } catch {
                    appBootLog.errorWithContext("\(logTag) Failed to write temp _WAV: \(error.localizedDescription)")
                }

                appBootLog.infoWithContext("\(logTag) !!! ENTERING_WAV_WRAP_PATH !!! mimeType=\(mimeType) rawBytes=\(data.count)")

                // Detailed WAV header validation
                func leUInt16(_ d: Data, _ offset: Int) -> UInt16 {
                    return d.subdata(in: offset..<(offset+2)).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
                }
                func leUInt32(_ d: Data, _ offset: Int) -> UInt32 {
                    return d.subdata(in: offset..<(offset+4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
                }

                let hdr = wavData
                if hdr.count >= 44 {
                    let riff = String(data: hdr.prefix(4), encoding: .ascii) ?? "?"
                    let wave = String(data: hdr[8..<12], encoding: .ascii) ?? "?"
                    let fmt_ = String(data: hdr[12..<16], encoding: .ascii) ?? "?"
                    let chunkSize = leUInt32(hdr, 4)
                    let subchunk1Size = leUInt32(hdr, 16)
                    let audioFormat = leUInt16(hdr, 20)
                    let channelsLE = leUInt16(hdr, 22)
                    let sampleRateLE = leUInt32(hdr, 24)
                    let byteRateLE = leUInt32(hdr, 28)
                    let blockAlignLE = leUInt16(hdr, 32)
                    let bitsLE = leUInt16(hdr, 34)
                    let dataStr = String(data: hdr[36..<40], encoding: .ascii) ?? "?"
                    let subchunk2SizeLE = leUInt32(hdr, 40)

                    appBootLog.infoWithContext("\(logTag) WAV check: riff=\(riff) wave=\(wave) fmt=\(fmt_) chunkSize=\(chunkSize) sub1=\(subchunk1Size) fmtCode=\(audioFormat) ch=\(channelsLE) sr=\(sampleRateLE) br=\(byteRateLE) ba=\(blockAlignLE) bps=\(bitsLE) dataTag=\(dataStr) dataSize=\(subchunk2SizeLE) payload=\(data.count)")
                    
                    // Assertion-style checks against expected values
                    let expectedAudioFormat: UInt16 = 3
                    let expectedChannels: UInt16 = 1
                    let expectedSampleRate: UInt32 = 44100
                    let expectedBitsPerSample: UInt16 = 32
                    let expectedBlockAlign: UInt16 = 4 // channels * bytesPerSample = 1 * 4
                    let expectedByteRate: UInt32 = expectedSampleRate * UInt32(expectedBlockAlign) // 44100 * 4 = 176400

                    if audioFormat != expectedAudioFormat ||
                        channelsLE != expectedChannels ||
                        sampleRateLE != expectedSampleRate ||
                        bitsLE != expectedBitsPerSample ||
                        blockAlignLE != expectedBlockAlign ||
                        byteRateLE != expectedByteRate {
                        appBootLog.errorWithContext("\(logTag) WAV header mismatch detected: expected fmtCode=\(expectedAudioFormat), ch=\(expectedChannels), sr=\(expectedSampleRate), bps=\(expectedBitsPerSample), ba=\(expectedBlockAlign), br=\(expectedByteRate). Got fmtCode=\(audioFormat), ch=\(channelsLE), sr=\(sampleRateLE), bps=\(bitsLE), ba=\(blockAlignLE), br=\(byteRateLE).")
                    }
                } else {
                    appBootLog.errorWithContext("\(logTag) WAV data too short for header validation: \(hdr.count) bytes")
                }

                // ASSERT-STYLE BYTE DUMP FOR QUICK CONSOLE SEARCH
                // [WAV_ASSERT_BYTES_28_TO_35] Dump ByteRate(28-31), BlockAlign(32-33), BitsPerSample(34-35)
                if wavData.count >= 36 {
                    let range28to35 = 28..<(36)
                    let slice = wavData.subdata(in: range28to35)
                    let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
                    // Parse fields again directly from wavData to avoid confusion
                    func leUInt16(_ d: Data, _ offset: Int) -> UInt16 {
                        return d.subdata(in: offset..<(offset+2)).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
                    }
                    func leUInt32(_ d: Data, _ offset: Int) -> UInt32 {
                        return d.subdata(in: offset..<(offset+4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
                    }
                    let br = leUInt32(wavData, 28)
                    let ba = leUInt16(wavData, 32)
                    let bps = leUInt16(wavData, 34)
                    appBootLog.infoWithContext("\(logTag) <<< WAV_ASSERT_HEADER_BYTES_28_35 >>> hex=\(hex) br=\(br) ba=\(ba) bps=\(bps)")
                    appBootLog.infoWithContext("\(logTag) [WAV_ASSERT_BYTES_28_TO_35] hex=\(hex) parsed br=\(br) ba=\(ba) bps=\(bps)")
                    appBootLog.infoWithContext("\(logTag) !!! WAV_ASSERT_CORE_FIELDS (BR/BA/BPS) !!! hex=\(hex) br=\(br) ba=\(ba) bps=\(bps)")
                } else {
                    appBootLog.errorWithContext("\(logTag) [WAV_ASSERT_BYTES_28_TO_35] wavData too short: \(wavData.count) bytes")
                }

                uploadData = wavData
                uploadMimeType = "audio/wav"
                appBootLog.infoWithContext("\(logTag) Wrapped raw FLOAT PCM into WAV: in=\(data.count) out=\(wavData.count) sr=\(sampleRate) ch=\(channels) bps=\(bitsPerSample)")
            }
        }

        let ensureAndUpload: (String?) -> Void = { parentId in
            appBootLog.infoWithContext("\(logTag) Starting upload: filename=\(filename), bytes=\(uploadData.count)")
            self.multipartUpload(data: uploadData, mimeType: uploadMimeType, filename: filename, parentId: parentId, token: token) { result in
                switch result {
                case .failure(let err):
                    appBootLog.errorWithContext("[Drive] Upload failed: \(err.localizedDescription)")
                    completion(.failure(err))
                case .success(let json):
                    let id = json["id"] as? String ?? "<unknown>"
                    let name = json["name"] as? String ?? filename
                    let webViewLink = json["webViewLink"] as? String
                    appBootLog.infoWithContext("[Drive] Upload success: id=\(id) name=\(name) link=\(webViewLink ?? "<none>")")
                    completion(.success(name))
                }
            }
        }

        if let cachedId = targetFolderId {
            ensureAndUpload(cachedId)
        } else {
            ensureFolderId(named: launchFolderName, token: token, parentId: nil) { result in
                switch result {
                case .failure(let err):
                    appBootLog.errorWithContext("[Drive] Folder ensure failed: \(err.localizedDescription)")
                    completion(.failure(err))
                case .success(let folderId):
                    self.targetFolderId = folderId
                    appBootLog.infoWithContext("[Drive] Using folder: \(self.launchFolderName) id=\(folderId)")
                    ensureAndUpload(folderId)
                }
            }
        }
    }
}

extension GoogleDriveUploader {
    private func multipartUpload(data: Data, mimeType: String, filename: String, parentId: String?, token: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let boundary = "Boundary-\(UUID().uuidString)"
        guard var comps = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files") else {
            completion(.failure(UploadError.requestFailed("Invalid URL"))); return
        }
        comps.queryItems = [URLQueryItem(name: "uploadType", value: "multipart"), URLQueryItem(name: "fields", value: "id,name,webViewLink,webContentLink")]
        guard let url = comps.url else { completion(.failure(UploadError.requestFailed("Invalid URL"))); return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build metadata JSON
        var meta: [String: Any] = ["name": filename, "mimeType": mimeType]
        if let parentId = parentId { meta["parents"] = [parentId] }
        let metaData = try? JSONSerialization.data(withJSONObject: meta)

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }
        // Part 1: metadata
        append("--\(boundary)\r\n")
        append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metaData ?? Data())
        append("\r\n")
        // Part 2: media
        append("--\(boundary)\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let task = URLSession.shared.dataTask(with: req) { responseData, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse else { completion(.failure(UploadError.requestFailed("No HTTP response"))); return }
            guard (200..<300).contains(http.statusCode) else {
                let bodyString = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                appBootLog.errorWithContext("[Drive] Multipart bad response: \(http.statusCode) body=\(bodyString)")
                completion(.failure(UploadError.badResponse(http.statusCode)))
                return
            }
            guard let responseData = responseData else { completion(.failure(UploadError.noData)); return }
            do {
                if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(UploadError.requestFailed("Invalid JSON")))
                }
            } catch { completion(.failure(error)) }
        }
        task.resume()
    }
}

