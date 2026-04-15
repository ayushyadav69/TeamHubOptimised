//
//  NetworkError.swift
//  TeamHubFinal
//
//  Created by Atin Joshi on 24/03/26.
//

import Foundation
enum NetworkError: Error {
    case invalidURL
    case server
    case decoding
    case invalidStatusCode(Int, message: String?)
}
extension NetworkError {
    var message: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .decoding:
            return "decoding failed"
        case .server:
            return " Server Error"
        case .invalidStatusCode(_, let message):
            guard let message else { return "Something went wrong."}
            
            if message.contains("employees_email_key") {
                return "Error: Email exists"
            } else if message.contains("unique_home_number") {
                return "Error: Home phone number should be unique."
            } else {
                return message
            }
        }
    }
}
