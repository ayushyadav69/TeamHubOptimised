//
//  HomeViewModel.swift
//  TeamHubFinal
//
//  Created by Atin Joshi on 24/03/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    
    @Published private(set) var employees: [Employee] = []
    @Published private(set) var searchResults: [Employee] = []
    
    @Published var allDesignations: [String] = []
    @Published var allDepartments: [String] = []
    @Published var allStatuses: [String] = []
    
    @Published var selectedDesignations: Set<String> = []
    @Published var selectedDepartments: Set<String> = []
    @Published var selectedStatuses: Set<String> = []
    @Published var searchQuery = ""
    
    @Published var isPaginatingUI = false
    @Published var isLoading = false
    @Published var isRefreshing = false

    @Published var showNewBanner = false

    private var searchOffset = 0
    private let limit = 10
    private var lastSearchQuery: String?
    private(set) var isSearching = false
    private var currentLimit = 20
    
    // MARK: - UI STATE
    var hasLoadedInitially = false
    private var isRefreshingTaskRunning = false
    
    private var isPaginating = false
    private(set) var initialSearchRequestDone = false
    private var observerId: UUID?
    private var reloadTask: Task<Void,Never>?
    private var searchTask: Task<Void,Never>?
    private var loadingRequestCount = 0
    private var updateObserverId: UUID?
  
    
    let repo: EmployeeRepositoryProtocol
    let network: NetworkMonitor
    private let syncManager: SyncManaging
    private var cancellables = Set<AnyCancellable>()
    init(repo: EmployeeRepositoryProtocol, syncManager: SyncManaging,network:NetworkMonitor) {
        
        self.repo = repo
        self.syncManager = syncManager
        self.network = network
        
//        observerId = SyncNotifier.shared.addObserver {
//            [weak self] in
//            self?.reloadTask?.cancel()
//            self?.reloadTask = Task{
//                try? await Task.sleep(nanoseconds: 300_000_000)
//                print("Gonna initial load-----")
//                self?.hasLoadedInitially = false
//               await self?.loadInitial()
//                
//            }
//        }
        updateObserverId = SyncNotifier.shared
            .addUpdateDisplayedEmployeesObserver { [weak self] employee in
                
                Task { @MainActor in
                    guard let self else { return }
                    guard let _ = self.employees.first else { return }
                    
                    if employee.deletedAt != nil {
                        if let index = self.employees.firstIndex(where: { $0.id == employee.id }) {
                            withAnimation(.easeInOut) {
                                self.employees.remove(at: index)
                            }
                        }
                    } else if let index = self.employees.firstIndex(where: { $0.id.lowercased() == employee.id.lowercased() }) {
                        // UPDATE
                        self.employees[index] = employee
                    } else {
                        if employee.createdAt! > (self.employees.first?.createdAt)! {
                            withAnimation(.easeInOut) {
                                self.employees.insert(employee, at: 0)
                            }
                        }
                        
                    }
                    
                    
                }
            }
        
    }


    // MARK: - COMPUTED
    var selectedFilters: SelectedFilters {
        SelectedFilters(
            designations: selectedDesignations,
            departments: selectedDepartments,
            statuses: selectedStatuses
        )
    }
    
    var displayEmployees: [Employee] {
        isSearchingOrFiltering ? searchResults : employees
    }

     var isSearchingOrFiltering: Bool {
        !searchQuery.isEmpty ||
        !selectedDesignations.isEmpty ||
        !selectedDepartments.isEmpty ||
        !selectedStatuses.isEmpty
    }

    var shouldShowShimmer: Bool {
        isLoading && !isPaginatingUI
    }
    
    func filters() async {
        //  avoid refetch
        if !allDesignations.isEmpty { return }
        let data = await repo.fetchFilters()

        allDesignations = data.designations
        allDepartments = data.departments
        allStatuses = data.statuses
    }
    
   
    // MARK: - LOAD
    func loadInitial() async {
        guard !hasLoadedInitially else { return }
        hasLoadedInitially = true
        beginLoading()
        defer {
            endLoading()
            initialSearchRequestDone = false
        }
        let data = await repo.loadUntilFilled(targetCount: limit)
        
        if !syncManager.syncRunning {
           await syncManager.startAutoSync()
        }
        currentLimit = 20
        employees = data
    }

    func loadMore() async {
        guard !isPaginating else { return }
        guard repo.canLoadMoreEmployees else { return }
        isPaginating = true
        isPaginatingUI = true
        defer {
            isPaginating = false
            isPaginatingUI = false
        }
        
        let data = await repo.loadMore()
        appendUnique(data, into: &employees)
    }
    
    func refresh() async {
        
        guard !isRefreshingTaskRunning else { return }
        isRefreshingTaskRunning = true
        beginLoading()
        
        defer {
            endLoading()
            isRefreshingTaskRunning = false
        }
        if isSearchingOrFiltering {
            await performSearch(showLoading: false)
        }
        else {
            await repo.refresh()
            
            hasLoadedInitially = false
            await loadInitial()
        }
        
    }

    // MARK: - SEARCH (UNIFIED)
    
    func handleSearch(query _: String) {
        searchTask?.cancel()
        beginLoading()

        searchTask = Task {
            defer {
                Task { @MainActor [weak self] in
                    self?.endLoading()
                }
            }

            do {
                try await Task.sleep(nanoseconds: 900_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            await performSearch(showLoading: false)
        }
    }
    
    func performSearch(showLoading: Bool = true) async {
        if showLoading {
            beginLoading()
        }
        defer {
            if showLoading {
                endLoading()
            }
        }
        
        let result = await repo.searchNFilter(
            query: searchQuery,
            designations: Array(selectedDesignations),
            departments: Array(selectedDepartments),
            statuses: Array(selectedStatuses)
        )
        searchResults = result.filter { $0.deletedAt == nil }
    }
    
    func performSearchLoadMore() async {
        guard !isPaginating else { return }
        guard repo.canLoadMoreSearchResults else { return }
        isPaginating = true
        isPaginatingUI = true
        defer {
            isPaginating = false
            isPaginatingUI = false
        }
        
        let result = await repo.searchNFilterLoadMore(
            query: searchQuery,
            designations: Array(selectedDesignations),
            departments: Array(selectedDepartments),
            statuses: Array(selectedStatuses)
        )

        appendUnique(result.filter { $0.deletedAt == nil }, into: &searchResults)
    }

    func loadMoreIfNeeded(currentEmployee employee: Employee) {
        guard employee.id == displayEmployees.last?.id else { return }
        guard !isPaginating else { return }
        guard isSearchingOrFiltering ? repo.canLoadMoreSearchResults : repo.canLoadMoreEmployees else {
            return
        }

        Task {
            if isSearchingOrFiltering {
                await performSearchLoadMore()
            } else {
                await loadMore()
            }
        }
    }
    
    // MARK: - CRUD (INSTANT UI UPDATE)
    func addEmployee(_ emp: Employee) {

        repo.addEmployee(emp)

        // instant UI
        employees.insert(emp, at: 0)
        Task{
           await  syncManager.pushLocalChanges()
        }
    }

    func updateEmployee(_ emp: Employee) {

        repo.updateEmployee(emp)

        if let i = employees.firstIndex(where: { $0.id == emp.id }) {
            employees[i] = emp
        }
        Task{
           await syncManager.pushLocalChanges()
        }
    }

    func deleteEmployee(at offsets: IndexSet) {

        offsets.forEach {
            let emp = employees[$0]
            repo.deleteEmployee(emp.id)
        }

        employees.remove(atOffsets: offsets)
        Task{
          await  syncManager.pushLocalChanges()
        }
    }

    func emailExists(_ email: String, excludingEmployeeID: String? = nil) -> Bool {
        repo.emailExists(email, excludingEmployeeID: excludingEmployeeID)
    }

    func homePhoneExists(_ number: String, excludingEmployeeID: String? = nil) -> Bool {
        repo.homePhoneExists(number, excludingEmployeeID: excludingEmployeeID)
    }

    func ensureAutoSyncRunning() async {
        if !syncManager.syncRunning {
            await syncManager.startAutoSync()
        }
    }

    private func appendUnique(_ newEmployees: [Employee], into list: inout [Employee]) {
        guard !newEmployees.isEmpty else { return }

        let existingIDs = Set(list.map(\.id))
        let uniqueEmployees = newEmployees.filter { !existingIDs.contains($0.id) }
        list.append(contentsOf: uniqueEmployees)
    }

    private func beginLoading() {
        loadingRequestCount += 1
        isLoading = true
    }

    private func endLoading() {
        loadingRequestCount = max(loadingRequestCount - 1, 0)
        isLoading = loadingRequestCount > 0
    }
}
