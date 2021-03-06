//
//  Contract.swift
//  Web3
//
//  Created by Josh Pyles on 6/5/18.
//

import Foundation


/// Base protocol all contracts should adopt.
/// Brokers relationship between Web3 and contract methods and events
public protocol Contract: SolidityFunctionHandler {
    var address: Address? { get }
    var node: Blockchain.Node { get }
    var events: [SolidityEvent] { get }
}

/// Contract where all methods and events are defined statically
///
/// Pros: more type safety, cleaner calls
/// Cons: more work to implement
///
/// Best for when you want to code the methods yourself
public protocol StaticContract: Contract {
    init(address: Address?, node: Blockchain.Node)
}

/// Static Deployed Contract
/// A deployed `Contract` where all methods and events are defined statically
/// - note: Address should never return nil
public protocol DeployedContract: ERC20Contract, AnnotatedERC20 {

  init(address: Address, node: Blockchain.Node)

}
/// Contract that is dynamically generated from a JSON representation
///
/// Pros: compatible with existing json files
/// Cons: harder to call methods, less type safety
///
/// For when you want to import from json
public class DynamicContract: Contract {
    
    public var address: Address?
    public let node: Blockchain.Node
    
    private(set) public var constructor: SolidityConstructor?
    private(set) public var events: [SolidityEvent] = []
    private(set) var methods: [String: SolidityFunction] = [:]
    
    public init(abi: [ABIObject], address: Address?, node: Blockchain.Node) {
        self.address = address
        self.node = node
        self.parseABIObjects(abi: abi)
    }
    
    private func parseABIObjects(abi: [ABIObject]) {
        for abiObject in abi {
            switch (abiObject.type, abiObject.stateMutability) {
            case (.event, _):
                if let event = SolidityEvent(abiObject: abiObject) {
                    add(event: event)
                }
            case (.function, let stateMutability?) where stateMutability.isConstant:
                if let function = SolidityConstantFunction(abiObject: abiObject, handler: self) {
                    add(method: function)
                }
            case (.function, .nonpayable?):
                if let function = SolidityNonPayableFunction(abiObject: abiObject, handler: self) {
                    add(method: function)
                }
            case (.function, .payable?):
                if let function = SolidityPayableFunction(abiObject: abiObject, handler: self) {
                    add(method: function)
                }
            case (.constructor, _):
                self.constructor = SolidityConstructor(abiObject: abiObject, handler: self)
            default:
                print("Could not parse abi object: \(abiObject)")
            }
        }
    }
    
    /// Adds an event object to list of stored events. Generally this should be done automatically by Web3.
    ///
    /// - Parameter event: `ABIEvent` that can be emitted from this contract
    public func add(event: SolidityEvent) {
        events.append(event)
    }
    
    /// Adds a method object to list of stored methods. Generally this should be done automatically by Web3.
    ///
    /// - Parameter method: `ABIFunction` that can be called on this contract
    public func add(method: SolidityFunction) {
        methods[method.name] = method
    }
    
    /// Invocation of a method with the provided name
    /// For example: `MyContract['balanceOf']?(address).call() { ... }`
    ///
    /// - Parameter name: Name of function to call
    public subscript(_ name: String) -> ((ABIEncodable...) -> SolidityInvocation)? {
        return methods[name]?.invoke
    }
    
    /// Deploys a new instance of this contract to the network
    /// Example: contract.deploy(byteCode: byteCode, parameters: p1, p2)?.send(...) { ... }
    ///
    /// - Parameters:
    ///   - byteCode: Compiled bytecode of the contract
    ///   - parameters: Any input values for the constructor
    /// - Returns: Invocation object that can be called with .send(...)
    public func deploy(byteCode: DataObject, parameters: ABIEncodable...) -> SolidityConstructorInvocation? {
        return constructor?.invoke(byteCode: byteCode, parameters: parameters)
    }
    
    public func deploy(byteCode: DataObject, parameters: [ABIEncodable]) -> SolidityConstructorInvocation? {
        return constructor?.invoke(byteCode: byteCode, parameters: parameters)
    }
    
    public func deploy(byteCode: DataObject) -> SolidityConstructorInvocation? {
        return constructor?.invoke(byteCode: byteCode, parameters: [])
    }
}

// MARK: - Call & Send

extension Contract {
    
    /// Returns data by calling a constant function on the contract
    ///
    /// - Parameters:
    ///   - data: EthereumData object representing the method called
    ///   - outputs: Expected return values
    ///   - completion: Completion handler
    public func call(_ call: Call, outputs: [SolidityFunctionParameter], block: QuantityTag = .latest, completion: @escaping ([String: Any]?, Error?) -> Void) {
        node.call(call: call, block: block) { response in
            switch response.status {
            case .success(let data):
                do {
                    let dictionary = try ABI.decodeParameters(outputs, from: data.hex())
                    completion(dictionary, nil)
                } catch {
                    completion(nil, error)
                }
            case .failure(let error):
                completion(nil, error)
            }
        }
    }
    
    /// Modifies the contract's data by sending a transaction
    ///
    /// - Parameters:
    ///   - data: Encoded EthereumData for the methods called
    ///   - from: EthereumAddress to send from
    ///   - value: Amount of ETH to send, if applicable
    ///   - gas: Maximum gas allowed for the transaction
    ///   - gasPrice: Amount of wei to spend per unit of gas
    ///   - completion: completion handler. Either the transaction's hash or an error.
    public func send(_ transaction: Transaction, completion: @escaping (DataObject?, Error?) -> Void) {
        node.sendTransaction(transaction: transaction) { response in
            switch response.status {
            case .success(let hash):
                completion(hash, nil)
            case .failure(let error):
                completion(nil, error)
            }
        }
    }
    
    /// Estimates the amount of gas used for this method
    ///
    /// - Parameters:
    ///   - call: An ethereum call with the data for the transaction.
    ///   - completion: completion handler with either an error or the estimated amount of gas needed.
    public func estimateGas(_ call: Call, completion: @escaping (Quantity?, Error?) -> Void) {
        node.estimateGas(call: call) { response in
            switch response.status {
            case .success(let quantity):
                completion(quantity, nil)
            case .failure(let error):
                completion(nil, error)
            }
        }
    }
}
