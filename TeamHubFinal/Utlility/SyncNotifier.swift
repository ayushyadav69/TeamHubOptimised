//
//  SyncNotifier.swift
//  TeamHubFinal
//
//  Created by Atin Joshi on 06/04/26.
//

import Foundation

final class SyncNotifier{
    static let shared = SyncNotifier()
    private init(){}
    private var observer: [UUID: ()-> Void] = [:]
    private var updateDisplayedEmployeesObserver: [UUID: (Employee) -> Void] = [:]
    
    func addObserver(_ callback: @escaping ()-> Void) -> UUID{
        let id = UUID()
        observer[id] = callback
        return id
    }
    
    func addUpdateDisplayedEmployeesObserver(_ callback: @escaping (Employee) -> Void) -> UUID {
        let id = UUID()
        updateDisplayedEmployeesObserver[id] = callback
        return id
    }
    
    func notify(){
        observer.values.forEach{$0()}
    }
    
    func notifyEmployeeUpdate(_ employee: Employee) {
        let callbacks = Array(updateDisplayedEmployeesObserver.values)
        
        callbacks.forEach { $0(employee) }
    }
}
