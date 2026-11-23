import XCTest
@testable import PlatenKit

final class OperationTests: XCTestCase {
    @MainActor func testExpiredWaitAndDuplicateCallbacksAllowAFreshOperation() async throws {
        let operation = OperationResult<Int>()
        do {
            _ = try await operation.wait(seconds: 0.01, deadline: { .failure(BenchError("timeout")) }, start: {})
            XCTFail("An expired operation returned a value")
        } catch { XCTAssertEqual(error.localizedDescription, "timeout") }
        XCTAssertFalse(operation.pending)
        operation.finish(.success(10))
        let value = try await operation.wait(seconds: 1, deadline: { .success(0) }) {
            operation.finish(.success(20))
            operation.finish(.success(30))
        }
        XCTAssertEqual(value, 20)
    }

    @MainActor func testCancellingAnInFlightWaitClearsItForReuse() async throws {
        let operation = OperationResult<Void>()
        let started = AsyncStream<Void>.makeStream()
        let worker = Task {
            try await operation.wait(seconds: 3, deadline: { .failure(BenchError("timeout")) }) {
                started.continuation.yield(())
                started.continuation.finish()
            }
        }
        for await _ in started.stream { break }
        worker.cancel()
        do { try await worker.value; XCTFail("A cancelled operation succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(operation.pending)
        try await operation.wait(seconds: 1, deadline: { .failure(BenchError("timeout")) }) {
            operation.finish(.success(()))
        }
    }

    func testLostLastAcknowledgmentPreservesTheUncertainPhysicalOutcome() throws {
        var pump = try WritePump(Data(0..<8), limit: 4, mode: .acknowledged)
        XCTAssertEqual(pump.next(canQueue: false), Data(0..<4))
        pump.didAcknowledge()
        XCTAssertEqual(pump.next(canQueue: false), Data(4..<8))
        XCTAssertFalse(pump.complete)
        let diagnostic = pump.failure("connection dropped").message
        XCTAssertTrue(diagnostic.contains("8/8 bytes handed"))
        XCTAssertTrue(diagnostic.contains("4 acknowledged"))
        XCTAssertNil(pump.next(canQueue: true))
    }
}
