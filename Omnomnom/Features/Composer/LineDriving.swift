import Foundation

/// A model that retrieves for itself: given what was written or photographed, it searches
/// this device's own tables and answers with the rows it chose.
///
/// The seam is "resolve a line" rather than "estimate a meal", and the difference is the
/// searching. An estimator is asked what a meal holds and answers out of what it knows; a
/// driver is given the database and asked which rows of it were eaten. Everything the app
/// used to do between those two — guess the wording a composition table uses, search with
/// the guess, score what came back, ask a second model whether the retriever had chosen
/// well — existed only because the model could not look for itself, and none of it is here.
///
/// Its own file because three types now implement it and they have nothing in common but
/// this shape: two speak HTTP, over protocols that resemble each other only distantly, and
/// the third speaks to a framework on the device and has no conversation to write at all.
/// It lived in the first conformer's file while there was only one, which read as though the
/// seam were that provider's idea.
@MainActor
protocol LineDriving: Sendable {
    func resolve(_ input: EstimationInput) async throws -> DrivenLine
}

/// A line a model resolved, with the candidates it was shown.
///
/// The pool travels with the answer because the answer is only ids. Redeeming them needs
/// the store — a bundled row wants this person's history with that food, a product wants
/// the cache and the fetch a scan uses — and that belongs to `LineResolver` rather than
/// here, where it would drag a `ModelContext` into something that otherwise only speaks
/// HTTP.
///
/// It is also what keeps a model from inventing a food. The answer can only name ids, and
/// the only ids that mean anything are the ones in this pool, so a number nobody issued
/// reads as "none of these" exactly as 0 does and the row goes to the user to settle.
nonisolated struct DrivenLine: Hashable, Sendable {
    let answer: ResolvedLine
    let pool: LineCandidatePool
}
