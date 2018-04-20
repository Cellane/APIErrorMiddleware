import Vapor
import Foundation

/// Catches errors thrown from route handlers or middleware
/// further down the responder chain and converts it to
/// a JSON response.
///
/// Errors with an identifier of `modelNotFound` get
/// a 404 status code.
public final class APIErrorMiddleware: Middleware {
    
    // We define an empty init because the one
    // synthesized bby Swift is marked `internal`.
    
    /// Create an instance if `APIErrorMiddleware`.
    public init() {}
    
    /// Catch all errors thrown by the route handler or
    /// middleware futher down the responder chain and
    /// convert it to a JSON response.
    public func respond(to request: Request, chainingTo next: Responder) throws -> Future<Response> {
        
        // We create a new promise that wraps a `Response` object.
        // No, there are not any initializers to do this.
        let result = request.eventLoop.newPromise(Response.self)
        
        // Call the next responder in the reponse chain.
        // If the future returned contains an error, or if
        // the next responder throws an error, catch it and
        // convert it to a JSON response.
        // If no error is found, succed the promise with the response
        // returned by the responder.
        do {
            return try next.respond(to: request).do({ (response) in
                result.succeed(result: response)
            }).catch({ (error) in
                result.succeed(result: self.response(for: error, with: request))
            })
        } catch {
            result.succeed(result: self.response(for: error, with: request))
        }
        
        return result.futureResult
    }
    
    /// Creates a response with a JSON body.
    ///
    /// - Parameters:
    ///   - error: The error that will be the value of the
    ///     `error` key in the responses JSON body.
    ///   - request: The request we wil get a container from
    ///     to create the resulting reponse in.
    ///
    /// - Returns: A response with a JSON body with a `{"error":<error>}` structure.
    private func response(for error: Error, with request: Request) -> Response {
        
        // The value for the JSON `error` key.
        let message: String
        
        // The status code of the response.
        let status: HTTPStatus?
        
        if let error = error as? Debuggable, error.identifier == "modelNotFound" {
            
            // We have the infamous `modelNotFound` error from Fluent that returns
            // a 500 status code instead of a 404.
            // Set the message to the error's `reason` and the status to 404 (Not Found)
            message = error.reason
            status = .notFound
        } else if let error = error as? AbortError {
            
            // We have an `AbortError` which has both a
            // status code and error message.
            // Assign the data to the correct varaibles.
            message = error.reason
            status = error.status
        } else {
            
            // We have some other error.
            // Set the message to the error's `description`.
            let error = error as CustomStringConvertible
            message = error.description
            status = nil
        }
        
        // Create JSON with an `error` key with the `message` constant as its value.
        // We default to no data instead of throwing, because we don't want any errors
        // leaving the middleware body.
        let json = (try? JSONEncoder().encode(["error": message])) ?? message.data(using: .utf8) ?? Data()
        
        // Create an HTTPResponse with
        // - The detected status code, using
        //   400 (Bad Request) if one does not exist.
        // - A `application/json` Content Type header.
        // A body with the JSON we created.
        let httpResponse = HTTPResponse(
            status: status ?? .badRequest,
            headers: ["Content-Type": "application/json"],
            body: HTTPBody(data: json)
        )
        
        // Create the response and return it.
        return Response(http: httpResponse, using: request.sharedContainer)
    }
}
