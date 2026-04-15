//
//  FilterModesl.swift
//  TeamHubFinal
//
//  Created by Atin Joshi on 25/03/26.
//

import Foundation

struct Filters {
    let designations: [String]
    let departments: [String]
    let statuses: [String]
}
//
struct FiltersResponseDTO: Decodable {
    let status: String?
    let message: String?
    let data: FiltersDataDTO?
}

struct FiltersDataDTO: Decodable {
    let designations: [String]?
    let departments: [String]?
    let statuses: [StatusDTO]?
    let mobileTypes: [MobileTypeDTO]?
}
struct StatusDTO: Decodable {
    let label: String?
    let value: String?
}
struct MobileTypeDTO: Decodable {
    let label: String?
    let value: String?
}
extension FiltersResponseDTO {
    func toDomain() -> Filters {
        Filters(
            designations: data?.designations ?? [],
            departments: data?.departments ?? [],
            statuses: data?.statuses?.compactMap { $0.value } ?? []
        )
    }
}
