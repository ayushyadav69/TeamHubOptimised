//
//  DTOModels.swift
//  TeamHubFinal
//
//  Created by Atin Joshi on 24/03/26.
//
import Foundation

//{
//  "status": "success",
//  "message": "Employees fetched successfully",
//  "data": [
//    {
//      "id": "92070369-5c04-48f1-8a74-39ae9893425a",
//      "name": "Anil",
//      "designation": "Android ",
//      "department": "Engineering",
//      "is_active": true,
//      "img_url": "",
//      "email": "anii.12345@gmail.com",
//      "city": "Noida",
//      "country": "India",
//      "joining_date": "2026-04-07",
//      "updated_at": "2026-04-13T14:03:10Z",
//      "deleted_at": "",
//      "version": 1,
//      "created_at": "2026-04-13T14:03:10Z",
//      "mobiles": []
//    }
//  ],
//  "meta": {
//    "total_count": 261,
//    "page": 1,
//    "page_size": 1,
//    "has_next_page": true,
//    "latest_updated_seq": 933
//  }
//}
struct EmployeesResponseDTO: Decodable {
    let data: [EmployeeDTO]
    let meta: MetaDTO
}
struct MetaDTO: Decodable {
    let hasNextPage: Bool
    let latestUpdatedSeq: Int
    enum CodingKeys: String,CodingKey {
        case hasNextPage = "has_next_page"
        case latestUpdatedSeq = "latest_updated_seq"
    }
}
struct EmployeeDTO: Codable {
    let id: String?
    let name: String?
    let designation: String?
    let department: String?
    let isActive: Bool?
    let imgUrl: String?
    let email: String?
    let city: String?
    let joiningDate: String?
    let country: String?
    var deletedAt: String?
    let createdAt: String?
    let version: Int?
    let mobiles: [PhoneDTO]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case designation
        case department
        case isActive = "is_active"
        case imgUrl = "img_url"
        case email
        case city
        case joiningDate = "joining_date"
        case country
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case version
        case mobiles
    }
}
struct PhoneDTO: Codable {
    let id: String?
    let type: String?
    let number: String?
}
struct EditablePhone: Identifiable {
    let id: String
    var type: String
    var number: String
    // For existing phones
    init(from phone: Phone) {
        self.id = phone.id
        self.type = phone.type
        self.number = phone.number
    }
    // For new phones
       init(id: String, type: String, number: String) {
           self.id = id
           self.type = type
           self.number = number
       }
    func toDomain() -> Phone {
        Phone(id: id, type: type, number: number)
    }
}

extension EmployeeDTO {
    func toDomain() -> Employee {
        let formatter = ISO8601DateFormatter()
        return Employee(
            id: id ?? UUID().uuidString,
            name: name ?? "Unknown",
            designation: designation ?? "N/A",
            department: department ?? "N/A",
            isActive: isActive ?? false,
            imgUrl: imgUrl,
            email: email ?? "",
            city: city ?? "",
            joiningDate: joiningDate ?? "",
            country: country ?? "",
            phones: mobiles?.compactMap {
                Phone(
                    id: $0.id ?? UUID().uuidString,
                    type: $0.type ?? "other",
                    number: $0.number ?? ""
                )
            } ?? [],
            createdAt: formatter.date(from: createdAt ?? ""),   //
            deletedAt: formatter.date(from: deletedAt ?? "")
        )
    }
}

enum SyncAction: String {
    case create
    case update
    case delete
}

struct SyncResponseDTO: Decodable {
    let data: SyncDataDTO
    let success: Bool
}
struct SyncDataDTO: Decodable {
    let employees: [EmployeeDTO]
    let nextCursor: CursorDTO
    let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case employees
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}
struct CursorDTO: Decodable {
    let seq: Int
}
extension SyncResponseDTO {
    var employees: [EmployeeDTO] {
        data.employees
    }
    
    var nextSeq: Int {
        data.nextCursor.seq
    }
    
    var hasMore: Bool {
        data.hasMore
    }
}

struct BaseResponseDTO: Decodable {
    let status: String
    let message: String
}
