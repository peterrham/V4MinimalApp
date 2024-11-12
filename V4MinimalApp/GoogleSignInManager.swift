import SwiftUI
import GoogleSignIn

class GoogleSignInManager: ObservableObject {
    @Published var user: GIDGoogleUser? = nil
    private let signInConfig: GIDConfiguration
    
    @Published var spreadsheetID: String = ""
    
    init(clientID: String) {
        // Initialize GIDConfiguration with your client ID
        self.signInConfig = GIDConfiguration(clientID: clientID)
        
        GIDSignIn.sharedInstance.configuration = self.signInConfig
        
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
                print("Spreadsheet created with ID: \(spreadsheetId)")
                self.spreadsheetID = spreadsheetId
            case .failure(let error):
                print("Error creating spreadsheet: \(error)")
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
                print("Data successfully appended.")
            case .failure(let error):
                print("Error appending data: \(error)")
            }
        }

    }
    
    func createSpreadsheet() {
        
        guard let accessToken = self.user?.accessToken.tokenString else {
            print("Access token is missing.")
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
            print("Error creating request body: \(error)")
            return
        }
        
        // Make the API call to create the spreadsheet
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error creating spreadsheet: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received from Sheets API")
                return
            }
            
            // Parse the response
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("New Spreadsheet created: \(json)")
                    
                    if let localSpreadsheetId = json["spreadsheetId"] as? String {
                            print("New Spreadsheet created with ID: \(localSpreadsheetId)")
                        self.spreadsheetID = localSpreadsheetId
                            // You can now use `spreadsheetId` for further API calls
                        } else {
                            print("Error: Could not find spreadsheetId in response.")
                        }
                }
            } catch {
                print("Error parsing JSON response: \(error)")
            }
        }
        
        task.resume()
    }

    
    func disconnect() {
        GIDSignIn.sharedInstance.disconnect { error in
            if let error = error {
                print("Error disconnecting: \(error)")
            } else {
                print("Successfully disconnected. The user will need to reauthorize.")
            }
        }
    }
    
    func signIn() {
        guard let rootViewController = UIApplication.shared.windows.first?.rootViewController else {
            print("Error: Unable to access root view controller.")
            return
        }
        
        // Start sign-in with configuration and presenting view controller
        //  GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController, hint:"testhint", additionalScopes: ["https://www.googleapis.com/auth/drive.file", "https://www.googleapis.com/auth/spreadsheets",
                                                                                                                "https://www.googleapis.com/auth/spreadsheets"]
        ) { [weak self] result, error in
            
            
            if let error = error {
                print("Error signing in: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user else {
                print("Error: Sign-in result is nil.")
                return
            }
            
            self?.user = user
            print("Signed in successfully! User: \(user.profile?.name ?? "No Name")")
            
            // Retrieve the access token
            if let accessToken = self?.user!.accessToken.tokenString {
                print("Access Token: \(accessToken)")
                // You can use this access token with Google APIs, such as the People API
            }
            
            // Validate ID token if needed
            if let idToken = user.idToken?.tokenString {
                self?.validateIDToken(idToken)
            }
            
            if let grantedScopes = self?.user!.grantedScopes {
                print("Granted Scopes: \(grantedScopes)")
            }
        }
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        user = nil
        print("Signed out")
    }
    
    func validateIDToken(_ idToken: String) {
        guard let url = URL(string: "https://oauth2.googleapis.com/tokeninfo?id_token=\(idToken)") else {
            print("Invalid URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error validating token: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("Token Validation Response: \(json)")
                    // Additional checks can be added, such as verifying audience ("aud") or expiration ("exp")
                }
            } catch {
                print("JSON parsing error: \(error.localizedDescription)")
            }
        }
        
        task.resume()
    }
    
    func fetchAndPrintUserInfo() {
        guard let accessToken = self.user?.accessToken.tokenString else {
            print("Access token is missing.")
            return
        }
        
        guard let url = URL(string: "https://openidconnect.googleapis.com/v1/userinfo") else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error fetching user info: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    // Print each piece of user information to the console
                    print("User Info: \(json)")
                    if let name = json["name"] as? String {
                        print("Name: \(name)")
                    }
                    if let email = json["email"] as? String {
                        print("Email: \(email)")
                    }
                    if let picture = json["picture"] as? String {
                        print("Profile Picture URL: \(picture)")
                    }
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }
        
        task.resume()
    }
}


