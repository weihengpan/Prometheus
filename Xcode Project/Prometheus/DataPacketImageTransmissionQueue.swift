//
//  DataPacketImageTransmissionQueue.swift
//  Prometheus
//
//  Created by PAN Weiheng on 2020/8/10.
//  Copyright © 2020 PAN Weiheng. Please refer to LICENSE for license information.
//

import Foundation

/// A class representing a data packet image transmission queue implemented with an `Array`.
///
/// This is not a FIFO queue despite the name, since one can insert elements at the end of queue.
class DataPacketImageTransmissionQueue {
    
    /// The storage of the queue. The first element is the front of the queue, while the last element is the end of the queue. This configuration makes dequeuing more efficient.
    private var array = [DataPacketImage]()
    
    // MARK: - Initializers
    
    /// Initializes an empty queue.
    init() {}

    /// Initializes a queue by supplying the content of an array.
    /// - Parameter array: The array to supply with. The first element will be placed at the end of the queue, so that it will be dequeued first.
    init(_ array: [DataPacketImage]) {
        self.array = array.reversed()
    }
    
    // MARK: - Methods
    
    /// Enqueues a new element into the queue. Time complexity: O(n)
    /// - Parameter newElement: The element to enqueue.
    func enqueue(_ newElement: DataPacketImage) {
        array.insert(newElement, at: 0)
    }
    
    /// Enqueues the content of a collection to the queue.
    /// - Parameter newElements: The new elements to enqueue. The first one will be dequeued first.
    func enqueue<C>(contentsOf newElements: C) where C: Collection, C.Element == DataPacketImage {
        array.insert(contentsOf: newElements.reversed(), at: 0)
    }
    
    /// Inserts a new element at the end of the queue.
    /// - Parameter newElement: The element to insert.
    func insertAtEnd(_ newElement: DataPacketImage) {
        array.append(newElement)
    }
    
    /// Inserts the content of a sequence at the end of the queue.
    /// - Parameter newElements: The new elements to insert. The first one will be dequeued first.
    func insertAtEnd<S>(contentsOf newElements: S) where S: Sequence, S.Element == DataPacketImage {
        array.append(contentsOf: newElements.reversed())
    }
    
    /// Removes and returns the element at the end of the queue.
    /// - Returns: The element at the end of the queue. If the queue is empty, `nil` is returned.
    func dequeue() -> DataPacketImage? {
        guard let lastElement = array.last else { return nil }
        array.removeLast()
        return lastElement
    }
    
    /// Returns the element at the end of the queue without removing it.
    /// - Returns: The element at the end of the queue. If the queue is empty, `nil` is returned.
    func peek() -> DataPacketImage? {
        return array.last
    }
    
    /// Empties the queue's content.
    func clear() {
        array = []
    }
    
}
