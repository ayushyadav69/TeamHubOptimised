//
//  NetworkCall.swift
//  TeamHubFinal
//
//  Created by Atin Joshi on 29/03/26.
//

import Foundation

protocol APIClient {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
}

final class URLSessionAPIClient: APIClient {

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {

        guard let url = endpoint.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body

        endpoint.headers.forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }

        print("Request: \(request.httpMethod ?? "") \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        print("Status Code: \(httpResponse.statusCode)")
        
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = try? JSONDecoder().decode(BaseResponseDTO.self, from: data).message
            throw NetworkError.invalidStatusCode(httpResponse.statusCode, message: message)
        }

        // Handle DELETE (no response body)
        if httpResponse.statusCode == 204 {
            return EmptyResponse() as! T
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}

//  For DELETE responses
struct EmptyResponse: Decodable {}
struct DuplicateResponse: Decodable{
    let message: String
}
