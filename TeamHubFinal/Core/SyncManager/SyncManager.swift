//
//  SyncManager.swift
//  TeamHubFinal
//
//  Created by Atin Joshi on 27/03/26.
//

import Foundation
import Combine
protocol SyncManaging {
    func start()
    func syncNow() async
    func startAutoSync() async
    func stopAutoSync()
    func syncFromServer() async
    var syncRunning: Bool { get }
    func pushLocalChanges() async
}

final class SyncManager: SyncManaging {

    private let repo: EmployeeRepositoryProtocol
    private var network: NetworkMonitoring
    private var isSyncing = false
    private var syncTimer: Timer?
    private(set) var syncRunning = false
    private var hasStartedObserving = false
    
    init(repo: EmployeeRepositoryProtocol,
         network: NetworkMonitoring) {
        self.repo = repo
        self.network = network
    }

    // Start observing network
    func start() {
        guard !hasStartedObserving else { return }
        hasStartedObserving = true

        print("SyncManager started")

        //Immediate sync if already online
        if network.isConnected {
            Task { await syncNow() }
        }

        network.onStatusChange = { [weak self] isConnected in
            guard let self = self else { return }

            print("Network changed: \(isConnected)")

            if isConnected {
                Task {
                    await self.syncNow()
                }
            }
        }
    }

    // Manual trigger
    func syncNow() async {
        await runSyncCycle(pushLocalOnly: false)
    }
    
    
    func startAutoSync() async {
        start()
        stopAutoSync() // prevent duplicates
        syncRunning = true

        syncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            
            Task {
                await self?.syncNow()
            }
        }
    }
    
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        syncRunning = false
    }
    
    func syncFromServer() async {

        guard !isSyncing else { return }
        isSyncing = true

        defer { isSyncing = false }

        // your sync logic
        // startAutoSync()
        await repo.syncFromServer()
    }
}
extension SyncManager {

     func pushLocalChanges() async {
        await runSyncCycle(pushLocalOnly: true)
    }

    private func runSyncCycle(pushLocalOnly: Bool) async {
        guard network.isConnected else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        await pushPendingLocalChanges()

        guard !pushLocalOnly else { return }
        await repo.syncFromServer()
    }

    private func pushPendingLocalChanges() async {
        let pending = repo.fetchPendingSync()

        print("Pending items: \(pending.count)")

        for employee in pending {

            //  fetch syncAction from DB via repo
            let action = repo.getSyncAction(for: employee.id)

            do {
                switch action {

                case "create":
                    try await repo.syncCreate(employee)

                case "update":
                    try await repo.syncUpdate(employee)

                case "delete":
                    print("DELETE FLOW START:", employee.id)
                        try await repo.syncDelete(employee.id)
                        print("DELETE API SUCCESS:", employee.id)

                default:
                    continue
                }

                repo.markSynced(employee.id)

                print("Synced: \(employee.id)")

            } catch let error as NetworkError {
                print("Cannot sync \(employee.name):", error.message)
            } catch {
                print("Sync failed for \(employee.id): \(error)")
            }
        }
    }
}
 
