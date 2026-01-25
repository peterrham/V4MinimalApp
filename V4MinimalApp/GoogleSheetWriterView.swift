import SwiftUI

struct GoogleSheetWriterView: View {
    @State private var isCreatingSheet = false
    @State private var sheetTitle = "New Google Sheet"
    @State private var sheetCreatedMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Google Sheet Creator")
                .font(.title)
            
            TextField("Enter Sheet Title", text: $sheetTitle)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: createGoogleSheet) {
                Text("Create Sheet")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isCreatingSheet)
            
            if let message = sheetCreatedMessage {
                Text(message)
                    .padding()
                    .foregroundColor(.green)
            }
        }
        .padding()
    }
    
    private func createGoogleSheet() {
        guard !sheetTitle.isEmpty else { return }
        isCreatingSheet = true
        
        let accessToken = getOAuthToken { result in
            logWithTimestamp(result!)
            logWithTimestamp("got call back")
            
        }
        // "AIzaSyCxEfgNN1f_aM_IksN8GNuA0RaSAKwBu8E" // You will need to obtain and store a valid OAuth token here
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let sheetRequestBody: [String: Any] = [
            "properties": ["title": sheetTitle]
        ]
        
        do {
            let requestBody = try JSONSerialization.data(withJSONObject: sheetRequestBody, options: [])
            request.httpBody = requestBody
        } catch {
            appBootLog.errorWithContext("Failed to serialize JSON request body: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isCreatingSheet = false
                
                if let error = error {
                    sheetCreatedMessage = "Failed to create sheet: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    logWithTimestamp(response!.description)
                    sheetCreatedMessage = "Failed to create sheet: Server error"
                    return
                }
                
                sheetCreatedMessage = "Google Sheet '\(sheetTitle)' created successfully!"
            }
        }.resume()
    }
}
