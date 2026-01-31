import SwiftUI
import GoogleSignIn

class GoogleSignInManager: ObservableObject {
    @Published var user: GIDGoogleUser? = nil
    var proactiveRefreshLeeway: TimeInterval = 60 // seconds before expiry to refresh proactively
    
    private let signInConfig: GIDConfiguration
    
    private var refreshTimer: Timer?
    
    private var useFixedTestInterval: Bool = false
    private var fixedTestIntervalSeconds: TimeInterval = 30
    
    private func logUserState(prefix: String) {
        if let u = GIDSignIn.sharedInstance.currentUser {
            let name = u.profile?.name ?? "<no name>"
            let email = u.profile?.email ?? "<no email>"
            let token = u.accessToken.tokenString
            let expires = u.accessToken.expirationDate?.description ?? "<no date>"
            appBootLog.infoWithContext("[GSI] \(prefix): user=\(name) email=\(email) token=\(token.prefix(12))… exp=\(expires)")
        } else {
            appBootLog.infoWithContext("[GSI] \(prefix): currentUser = nil")
        }
    }
    
    private func scheduleProactiveRefresh() {
        refreshTimer?.invalidate()
        guard let user = GIDSignIn.sharedInstance.currentUser, let exp = user.accessToken.expirationDate else {
            appBootLog.infoWithContext("[GSI] scheduleProactiveRefresh: no user or expiration; not scheduling")
            return
        }
        let computed = max(5, exp.timeIntervalSinceNow - proactiveRefreshLeeway)
        let interval = useFixedTestInterval ? fixedTestIntervalSeconds : computed
        appBootLog.infoWithContext("[GSI] scheduleProactiveRefresh in \(interval) seconds (exp=\(exp), fixed=\(useFixedTestInterval))")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refreshAccessToken(reason: self?.useFixedTestInterval == true ? "proactive-timer-fixed" : "proactive-timer") { _ in }
        }
    }
    
    /// Adjust the proactive refresh leeway (seconds before expiry) and reschedule the timer
    func setProactiveRefreshLeeway(_ seconds: TimeInterval, reason: String = "debug") {
        proactiveRefreshLeeway = seconds
        appBootLog.infoWithContext("[GSI] setProactiveRefreshLeeway: now \(seconds)s (reason=\(reason))")
        scheduleProactiveRefresh()
    }
    
    /// Enable a fixed proactive refresh interval (for testing) and reschedule
    func enableFixedRefreshInterval(seconds: TimeInterval) {
        useFixedTestInterval = true
        fixedTestIntervalSeconds = seconds
        appBootLog.infoWithContext("[GSI] enableFixedRefreshInterval: \(seconds)s")
        scheduleProactiveRefresh()
    }

    /// Disable fixed interval mode and return to expiry-based scheduling
    func disableFixedRefreshInterval() {
        useFixedTestInterval = false
        appBootLog.infoWithContext("[GSI] disableFixedRefreshInterval; returning to expiry-based scheduling")
        scheduleProactiveRefresh()
    }
    
    func refreshAccessToken(reason: String = "manual", completion: @escaping (Result<String, Error>) -> Void) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            appBootLog.errorWithContext("[GSI] refreshAccessToken(\(reason)): no currentUser; cannot refresh")
            completion(.failure(NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "No current user"])));
            return
        }
        logUserState(prefix: "refreshAccessToken start [\(reason)]")
        user.refreshTokensIfNeeded { [weak self] refreshedUser, error in
            if let error = error {
                appBootLog.errorWithContext("[GSI] refreshTokensIfNeeded failed [\(reason)]: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let refreshed = refreshedUser else {
                appBootLog.errorWithContext("[GSI] refreshTokensIfNeeded returned nil user [\(reason)]")
                completion(.failure(NSError(domain: "GoogleSignIn", code: -2, userInfo: [NSLocalizedDescriptionKey: "Nil refreshed user"])));
                return
            }
            self?.user = refreshed
            let token = refreshed.accessToken.tokenString
            let exp = refreshed.accessToken.expirationDate?.description ?? "<no date>"
            appBootLog.infoWithContext("[GSI] refreshTokensIfNeeded ok [\(reason)]: new token prefix=\(token.prefix(12))… exp=\(exp)")
            self?.scheduleProactiveRefresh()
            completion(.success(token))
        }
    }
    
    func ensureFreshToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            appBootLog.errorWithContext("[GSI] ensureFreshToken: no currentUser")
            completion(.failure(NSError(domain: "GoogleSignIn", code: -3, userInfo: [NSLocalizedDescriptionKey: "No current user"])));
            return
        }
        let exp = user.accessToken.expirationDate ?? Date.distantPast
        if exp.timeIntervalSinceNow <= proactiveRefreshLeeway {
            appBootLog.infoWithContext("[GSI] ensureFreshToken: token near/after expiry; refreshing now")
            refreshAccessToken(reason: "ensureFreshToken") { result in completion(result) }
        } else {
            appBootLog.infoWithContext("[GSI] ensureFreshToken: token is fresh (valid for ~\(Int(exp.timeIntervalSinceNow))s)")
            completion(.success(user.accessToken.tokenString))
        }
    }
    
    public func tokenString() -> String {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            appBootLog.errorWithContext("[GSI] tokenString(): no current user/token")
            return ""
        }
        logWithTimestamp("tokenString(): \(token)")
        return token
    }

    @Published var spreadsheetID: String = ""
    
    init(clientID: String) {
        
        logWithTimestamp("GoogleSignInManager() init")
        
        
        // Initialize GIDConfiguration with your client ID
        self.signInConfig = GIDConfiguration(clientID: clientID)
        
        GIDSignIn.sharedInstance.configuration = self.signInConfig
        
        user = GIDSignIn.sharedInstance.currentUser
        
        logUserState(prefix: "init: post-restore state")
        scheduleProactiveRefresh()
        
        if  user == nil {
            logWithTimestamp("user == nil")
            logWithTimestamp("user: \(String(describing: user))")
        } else {
            logWithTimestamp("Existing Token String: \(GIDSignIn.sharedInstance.currentUser!.accessToken.tokenString)")
        }
    }
    
    func appendTest() {
        
        // Assuming you have a valid access token and spreadsheet ID
        let accessToken =  self.user?.accessToken.tokenString
        var spreadsheetId = "YOUR_SPREADSHEET_ID"
        
        let apiClient = GoogleSheetsAPI(accessToken: accessToken!)
        
        
        let semaphore = DispatchSemaphore(value: 0)
        
        apiClient.createSpreadsheet(title: "New Sheet") { result in
            switch result {
            case .success(let spreadsheetId):
                logWithTimestamp("Spreadsheet created with ID: \(spreadsheetId)")
                self.spreadsheetID = spreadsheetId
            case .failure(let error):
                logWithTimestamp("Error creating spreadsheet: \(error)")
            }
            
            semaphore.signal()  // Signal that async work is complete
        }
        
        // Wait for the async function to complete
        semaphore.wait()

        // Data to append: a 2D array where each inner array is a row
        let values = [
            ["Name", "Age", "City"],
            ["Alice", "30", "Seattle"],
            ["Bob", "25", "San Francisco"]
        ]

        apiClient.appendData(to: self.spreadsheetID, range: "Sheet1!A1", values: values) { result in
            switch result {
            case .success:
                logWithTimestamp("Data successfully appended.")
            case .failure(let error):
                logWithTimestamp("Error appending data: \(error)")
            }
        }

    }
    
    func createSpreadsheet() {
        
        guard let accessToken = self.user?.accessToken.tokenString else {
            logWithTimestamp("Access token is missing.")
            return
        }
            createGoogleSheet(accessToken: accessToken)
    }

    func createGoogleSheet(accessToken: String) {
        // Define the Google Sheets API URL for creating a new spreadsheet
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!
        
        // Set up the URL request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd HHmm"
        let timestamp = dateFormatter.string(from: Date())

        
        // Set the request body with spreadsheet properties
        let requestBody: [String: Any] = [
            "properties": [
                "title": timestamp + ": Inventory Application Spreadsheet"
            ]
        ]
        
        // Serialize the request body to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            logWithTimestamp("Error creating request body: \(error)")
            return
        }
        
        // Make the API call to create the spreadsheet
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                logWithTimestamp("Error creating spreadsheet: \(error)")
                return
            }
            
            guard let data = data else {
                logWithTimestamp("No data received from Sheets API")
                return
            }
            
            // Parse the response
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    logWithTimestamp("New Spreadsheet created: \(json)")
                    
                    if let localSpreadsheetId = json["spreadsheetId"] as? String {
                            logWithTimestamp("New Spreadsheet created with ID: \(localSpreadsheetId)")
                        self.spreadsheetID = localSpreadsheetId
                            // You can now use `spreadsheetId` for further API calls
                        } else {
                            logWithTimestamp("Error: Could not find spreadsheetId in response.")
                        }
                }
            } catch {
                logWithTimestamp("Error parsing JSON response: \(error)")
            }
        }
        
        task.resume()
    }

    
    func disconnect() {
        GIDSignIn.sharedInstance.disconnect { error in
            if let error = error {
                logWithTimestamp("Error disconnecting: \(error)")
            } else {
                logWithTimestamp("Successfully disconnected. The user will need to reauthorize.")
                self.refreshTimer?.invalidate()
                self.refreshTimer = nil
                appBootLog.infoWithContext("[GSI] Signed out/disconnected; cleared refresh timer")
            }
        }
    }
    
    func signIn(completion: (() -> Void)? = nil) {
        guard let rootViewController = UIApplication.shared.windows.first?.rootViewController else {
            logWithTimestamp("Error: Unable to access root view controller.")
            return
        }
        
        // Start sign-in with configuration and presenting view controller
        //  GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController, hint:"testhint", additionalScopes: ["https://www.googleapis.com/auth/drive.file", "https://www.googleapis.com/auth/spreadsheets",
                                                                                                                "https://www.googleapis.com/auth/spreadsheets"]
        ) { [weak self] result, error in
            
            
            if let error = error {
                logWithTimestamp("Error signing in: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user else {
                logWithTimestamp("Error: Sign-in result is nil.")
                return
            }
            
            self?.user = user
            self?.logUserState(prefix: "signIn success")
            self?.scheduleProactiveRefresh()
            logWithTimestamp("Signed in successfully! User: \(user.profile?.name ?? "No Name")")
            
            // Retrieve the access token
            if let accessToken = self?.user!.accessToken.tokenString {
                logWithTimestamp("Access Token: \(accessToken)")
                // You can use this access token with Google APIs, such as the People API
            }
            
            // Validate ID token if needed
            if let idToken = user.idToken?.tokenString {
                self?.validateIDToken(idToken)
            }
            
            if let grantedScopes = self?.user!.grantedScopes {
                logWithTimestamp("Granted Scopes: \(grantedScopes)")
            }

            // Delay to let the OAuth sheet finish dismissing before triggering view changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion?()
            }
        }
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        user = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        appBootLog.infoWithContext("[GSI] Signed out/disconnected; cleared refresh timer")
        logWithTimestamp("Signed out")
    }
    
    func validateIDToken(_ idToken: String) {
        guard let url = URL(string: "https://oauth2.googleapis.com/tokeninfo?id_token=\(idToken)") else {
            logWithTimestamp("Invalid URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                logWithTimestamp("Error validating token: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    logWithTimestamp("Token Validation Response: \(json)")
                    // Additional checks can be added, such as verifying audience ("aud") or expiration ("exp")
                }
            } catch {
                logWithTimestamp("JSON parsing error: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    func fetchAndPrintUserInfo() {
        guard let accessToken = self.user?.accessToken.tokenString else {
            logWithTimestamp("Access token is missing.")
            return
        }
        
        guard let url = URL(string: "https://openidconnect.googleapis.com/v1/userinfo") else {
            logWithTimestamp("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                logWithTimestamp("Error fetching user info: \(error)")
                return
            }
            
            guard let data = data else {
                logWithTimestamp("No data received")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    // Print each piece of user information to the console
                    logWithTimestamp("User Info: \(json)")
                    if let name = json["name"] as? String {
                        logWithTimestamp("Name: \(name)")
                    }
                    if let email = json["email"] as? String {
                        logWithTimestamp("Email: \(email)")
                    }
                    if let picture = json["picture"] as? String {
                        logWithTimestamp("Profile Picture URL: \(picture)")
                    }
                }
            } catch {
                logWithTimestamp("Error parsing JSON: \(error)")
            }
        }
        
        task.resume()
    }
}


