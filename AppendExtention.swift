//
//  AppendExtention.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/12/24.
//


extension GoogleSheetsClient {
    

    func appendDataToGoogleSheet(data: [[String]]) {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/Sheet1!A1:append?valueInputOption=RAW")!
        
        // Prepare the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare the data payload
        let body = [
            "values": data
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("Error serializing JSON:", error)
            return
        }
        
        // Perform the network request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Request error:", error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Unexpected response:", response ?? "No response")
                return
            }
            
            print("Data successfully appended to Google Sheets.")
        }
        
        task.resume()
    }
}
