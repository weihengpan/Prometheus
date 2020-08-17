//
//  Queue.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/11.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

/// A simple implementation of a generic FIFO queue implemented with `Array`, prioritizing dequeuing performance.
struct Queue<Element> {
    
    /// The storage of the queue.
    private var array: [Element] = []
    
    var isEmpty: Bool { return array.isEmpty }
    var count: Int { return array.count }
    
    // MARK: - Initializers
    
    /// Initializes an empty queue.
    init() {}
    
    /// Initializes a queue by supplying the content of an array.
    /// - Parameter array: The array to supply with. The first element will be placed at the end of the queue, so that it will be dequeued first.
    init(_ array: [Element]) {
        self.array = array.reversed()
    }
    
    // MARK: - Methods
    
    /// Enqueues a new element into the queue. Time complexity: O(n)
    /// - Parameter newElement: The element to enqueue.
    mutating func enqueue(_ newElement: Element) {
        array.insert(newElement, at: 0)
    }
    
    /// Enqueues the content of a collection to the queue. Time complexity: O(n)
    /// - Parameter newElements: The new elements to enqueue. The first one will be dequeued first.
    mutating func enqueue<C>(contentsOf newElements: C) where C: Collection, C.Element == Element {
        array.insert(contentsOf: newElements.reversed(), at: 0)
    }
    
    /// Removes and returns the element at the end of the queue. Time complexity: O(1)
    /// - Returns: The element at the end of the queue. If the queue is empty, `nil` is returned.
    mutating func dequeue() -> Element? {
        guard let lastElement = array.last else { return nil }
        array.removeLast()
        return lastElement
    }
    
    /// Returns the element at the end of the queue without removing it. Time complexity: O(1)
    /// - Returns: The element at the end of the queue. If the queue is empty, `nil` is returned.
    func peek() -> Element? {
        return array.last
    }
    
    /// Empties the queue's content.
    mutating func clear() {
        array = []
    }
    
}
