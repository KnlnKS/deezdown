import Foundation
import Synchronization

/// Hands a response body over in whole chunks.
///
/// `URLSession.bytes(from:)` vends one byte per async resumption, which measures at roughly
/// 0.2 MB/s and puts the ceiling on a download well below the network. The data delegate
/// delivers the same body in whole `Data` chunks and leaves the network setting the pace.
final class ResponseBodies: NSObject, URLSessionDataDelegate, Sendable {
    typealias Body = AsyncThrowingStream<Data, any Error>

    private struct Sink: Sendable {
        var waiting: CheckedContinuation<URLResponse, any Error>?
        var chunks: Body.Continuation
    }

    private let sinks = Mutex<[Int: Sink]>([:])

    /// Starts `task` and returns once its headers have arrived; the body follows on the stream.
    func start(_ task: URLSessionDataTask) async throws -> (URLResponse, Body) {
        let (stream, continuation) = Body.makeStream()
        let id = task.taskIdentifier
        continuation.onTermination = { [weak self] reason in
            guard case .cancelled = reason else { return }
            task.cancel()
            self?.sinks.withLock { $0[id] = nil }
        }
        do {
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { waiting in
                    sinks.withLock { $0[id] = Sink(waiting: waiting, chunks: continuation) }
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
            return (response, stream)
        } catch {
            continuation.finish(throwing: error)
            throw error
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        let waiting = sinks.withLock { sinks in
            defer { sinks[dataTask.taskIdentifier]?.waiting = nil }
            return sinks[dataTask.taskIdentifier]?.waiting
        }
        waiting?.resume(returning: response)
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        sinks.withLock { $0[dataTask.taskIdentifier]?.chunks }?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let sink = sinks.withLock({ $0.removeValue(forKey: task.taskIdentifier) }) else { return }
        sink.waiting?.resume(throwing: error ?? URLError(.badServerResponse))
        sink.chunks.finish(throwing: error)
    }
}
