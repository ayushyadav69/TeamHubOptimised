//////
//////  EmployeeRepositoryProtocol.swift
//////  TeamHubFinal
//////
//////  Created by Atin Joshi on 24/03/26.
//////
////

import Foundation
import Combine
import CoreData
protocol EmployeeRepositoryProtocol {
    
    
    
    // MARK: List
    func loadInitial() async -> [Employee]
    func loadMore() async -> [Employee]
    func refresh() async
    
    // MARK: Search + Filter
    func searchNFilter(
        query: String?,
        designations: [String],
        departments: [String],
        statuses: [String],
    ) async -> [Employee]
    
    // MARK: CRUD
    func addEmployee(_ employee: Employee)
    func updateEmployee(_ employee: Employee)
    func deleteEmployee(_ id: String)
    
    // MARK: Filters
    func fetchFilters() async -> Filters
    func fetchFiltersFromDB() -> Filters
    
    // MARK: Sync
    func syncFromServer() async
    
    func fetchPendingSync() -> [Employee]
    func markSynced(_ id: String)
    
    func syncCreate(_ employee: Employee) async throws
    func syncUpdate(_ employee: Employee) async throws
    func syncDelete(_ id: String) async throws
    
    func getSyncAction(for id: String) -> String
    func fetchFromLocal(limit: Int) -> [Employee]
    
    func searchNFilterLoadMore(
        query: String?,
        designations: [String],
        departments: [String],
        statuses: [String]
    ) async -> [Employee]
    func loadUntilFilled(targetCount: Int) async -> [Employee]
    func fetchFromDB(limit: Int) -> [Employee]
    func emailExists(_ email: String, excludingEmployeeID: String?) -> Bool
    func homePhoneExists(_ number: String, excludingEmployeeID: String?) -> Bool
    var canLoadMoreEmployees: Bool { get }
    var canLoadMoreSearchResults: Bool { get }
}

final class EmployeeRepository: EmployeeRepositoryProtocol {
    
    private let remote: EmployeeRemoteDataSourceProtocol
    private let local: EmployeeLocalDataSourceProtocol
    private let network: NetworkMonitoring
    
    
    private var apiOffset: Int = UserDefaults.standard.integer(forKey: "api_offset")
    private var dbOffset = 0
    private let listPageSize = 10
    private let searchPageSize = 20
    private var hasNext = true
    private var searchOffset = 0
    private var searchHasNext = true
    
    init(remote: EmployeeRemoteDataSourceProtocol,
         local: EmployeeLocalDataSourceProtocol,
         network: NetworkMonitor) {
        self.remote = remote
        self.local = local
        self.network = network
    }

    var canLoadMoreEmployees: Bool {
        !local.fetchNonDeleted(limit: 1, offset: dbOffset).isEmpty || (network.isConnected && hasNext)
    }

    var canLoadMoreSearchResults: Bool {
        network.isConnected && searchHasNext
    }
    
    
    func fetchFromDB(limit: Int) -> [Employee] {
        return local.fetchNonDeleted(limit: limit, offset: 0)
    }

    func emailExists(_ email: String, excludingEmployeeID: String?) -> Bool {
        local.emailExists(email, excludingEmployeeID: excludingEmployeeID)
    }

    func homePhoneExists(_ number: String, excludingEmployeeID: String?) -> Bool {
        local.homePhoneExists(number, excludingEmployeeID: excludingEmployeeID)
    }
    
    // MARK: - INITIAL
    func loadInitial() async -> [Employee] {
        
        apiOffset = 0
        dbOffset = 0
        hasNext = true
        UserDefaults.standard.set(apiOffset, forKey: "api_offset")
        
        let dbData = local.fetchNonDeleted(limit: listPageSize, offset: 0)
        
        if !dbData.isEmpty {
            
            let initial = Array(dbData.prefix(listPageSize))
            dbOffset = initial.count
            return initial
        }
        
        return await loadMore()
    }
    // MARK: - PAGINATION
    func loadMore() async -> [Employee] {
        
        print("dbOffset:", dbOffset, "apiOffset:", apiOffset)
        
        // STEP 1: Try DB first
        let dbData = local.fetchNonDeleted(limit: listPageSize, offset: dbOffset)
        
        if !dbData.isEmpty {
            dbOffset += dbData.count
            return dbData
        }
        
        //  STEP 2: DB exhausted → call API
        guard hasNext else {
            return []
        }
        
        guard network.isConnected else {
            return []
        }

        while hasNext {
            do {
                print("API CALL → offset:", apiOffset)
                
                let res = try await remote.fetch(limit: listPageSize, offset: apiOffset)
                
                let domain = res.data.map { $0.toDomain() }

                if domain.isEmpty {
                    hasNext = false
                    break
                }

                local.save(domain)
                
                apiOffset += res.data.count
                hasNext = res.meta.hasNextPage
                UserDefaults.standard.set(apiOffset, forKey: "api_offset")

                let newData = local.fetchNonDeleted(limit: listPageSize, offset: dbOffset)
                if !newData.isEmpty {
                    dbOffset += newData.count
                    return newData
                }
                
            } catch {
                print("API fail:", error.localizedDescription)
                break
            }
        }

        return []
    }
    
    
    func fetchFromLocal(limit: Int) -> [Employee] {
        local.fetch(limit: limit, offset: 0)
    }
    
    // MARK: - REFRESH
    func refresh() async {
        
        print("REFRESH START")
        
        if network.isConnected{
            await local.clearAllExceptPendingSync()
        }
        
    }
    
    // MARK: - SEARCH + FILTER (UNIFIED)
    
    func searchNFilter(
        query: String?,
        designations: [String],
        departments: [String],
        statuses: [String]
    ) async -> [Employee] {
        
        searchOffset = 0
        searchHasNext = true
        
        if network.isConnected {
            do {
                let res = try await remote.fetchSearchNFilteredEmployees(
                    limit: searchPageSize,
                    offset: searchOffset,
                    search: query,
                    designations: designations,
                    departments: departments,
                    statuses: statuses
                )
                searchOffset = res.data.count
                searchHasNext = res.meta.hasNextPage
                
                return res.data
                    .map { $0.toDomain() }
                    .filter { $0.deletedAt == nil }
                
            } catch {
                print("API search fail → fallback DB")
            }
        }
        
        return local.fetchFiltered(
            search: query,
            designations: designations,
            departments: departments,
            statuses: statuses
        )
    }
    
    func searchNFilterLoadMore(
        query: String?,
        designations: [String],
        departments: [String],
        statuses: [String]
    ) async -> [Employee] {
        
        
        if network.isConnected {
            
            guard searchHasNext else { return [] }
            do {
                while searchHasNext {
                    let res = try await remote.fetchSearchNFilteredEmployees(
                        limit: searchPageSize,
                        offset: searchOffset,
                        search: query,
                        designations: designations,
                        departments: departments,
                        statuses: statuses
                    )
                    searchOffset += res.data.count
                    searchHasNext = res.meta.hasNextPage
                    
                    if res.data.isEmpty {
                        searchHasNext = false
                        return []
                    }

                    let result = res.data
                        .map { $0.toDomain() }
                        .filter { $0.deletedAt == nil }

                    if !result.isEmpty {
                        return result
                    }
                }

                return []
            } catch {
                print("API search fail → fallback DB")
            }
            
        }
        return []
    }
    // MARK: - CRUD
    
    func addEmployee(_ employee: Employee) {
        local.add(employee)
        
    }
    
    func updateEmployee(_ employee: Employee) {
        local.update(employee)
        
    }
    
    func deleteEmployee(_ id: String) {
        local.delete(id)
        
    }
    
    // MARK: - FILTERS
    
    func fetchFilters() async -> Filters {
        (try? await remote.fetchFilters().toDomain()) ?? local.fetchFiltersFromDB()
    }
    
    func fetchFiltersFromDB() -> Filters {
        local.fetchFiltersFromDB()
    }
    
    // MARK: - SYNC
    func syncFromServer() async {
        let lastSeq = UserDefaults.standard.integer(forKey: "sync_seq")
        
        do {
            let res = try await remote.sync(seq: lastSeq)
            let employees = res.data.employees.map { $0.toDomain() }
            
            if lastSeq == 0 {
                // First launch: DB already populated via paginated API.
                // Just save the cursor — do NOT apply changes to avoid
                // re-inserting everything and triggering observer flood.
                print("Bootstrap sync — skipping apply, saving seq only")
            } else if !employees.isEmpty {
                //  Incremental sync — batch update in a single CoreData save
                defer {
                    SyncNotifier.shared.notify()
                }
                local.batchUpdateFromServer(employees)
                for employee in employees {
                    SyncNotifier.shared.notifyEmployeeUpdate(employee)
                }
                print(employees)
                print("Sync applied \(employees.count) changes")
                
            } else {
                print("Sync — nothing new (seq: \(lastSeq))")
            }
            
            // Always advance the cursor
            UserDefaults.standard.set(res.data.nextCursor.seq, forKey: "sync_seq")
            
        } catch {
            print("Sync failed:", error)
        }
    }
    
    func fetchPendingSync() -> [Employee] {
        local.fetchPendingSync()
    }
    
    func markSynced(_ id: String) {
        local.markSynced(id)
    }
    
    func getSyncAction(for id: String) -> String {
        local.getSyncAction(for: id)
    }
    
    func syncCreate(_ employee: Employee) async throws {
        try await remote.createEmployee(employee)
        
    }
    
    func syncUpdate(_ employee: Employee) async throws {
        try await remote.updateEmployee(employee)
    }
    
    func syncDelete(_ id: String) async throws {
        try await remote.deleteEmployee(id)
    }
    
    func loadUntilFilled(targetCount: Int) async -> [Employee] {
        
        hasNext = true
        dbOffset = 0
        var visible = local.fetchNonDeleted(limit: targetCount, offset: dbOffset)
        
        if visible.isEmpty {
            apiOffset = 0
            UserDefaults.standard.set(apiOffset, forKey: "api_offset")
        }
        while visible.count < targetCount && hasNext && network.isConnected {
            
            do {
                let res = try await remote.fetch(limit: listPageSize, offset: apiOffset)
                
                let domain = res.data.map { $0.toDomain() }
                if domain.isEmpty {
                    hasNext = false
                    break
                }

                local.save(domain)
                
                if apiOffset == 0 {
                    UserDefaults.standard.set(res.meta.latestUpdatedSeq, forKey: "sync_seq")
                }
                apiOffset += res.data.count
                hasNext = res.meta.hasNextPage
                UserDefaults.standard.set(apiOffset, forKey: "api_offset")
                
            } catch {
                print("failed inside loadUntilFilled",error.localizedDescription)
                break
            }
            
            visible = local.fetchNonDeleted(limit: targetCount, offset: 0)
        }
        
        dbOffset = visible.count
        return visible
    }
}
