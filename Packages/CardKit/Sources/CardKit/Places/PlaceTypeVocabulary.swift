import Foundation

/// Which Google place types may be **asked for**, as opposed to understood
/// when they come back.
///
/// **This exists because of a bug that reached a real phone and could not have
/// been caught anywhere else.** CardWise's Map, opened in Athens, Georgia,
/// showed zero pins and the words
/// "Could not look up nearby places. The place lookup was refused (400).
/// Unsupported types: grocery_or_supermarket."
///
/// Zero pins, not zero grocers. **One unrecognised entry in `includedTypes`
/// fails the entire `searchNearby` request**, so a single stale string takes
/// down every category at once. And CI could not have found it: the
/// screenshot job seeds its own places and never calls Google, so the live API
/// had never once been asked a question until the app was on a handset.
///
/// The mistake underneath was one vocabulary doing two jobs that want opposite
/// things:
///
/// - **Reading** a response wants every alias Google has ever emitted. A place
///   tagged `grocery_or_supermarket` is a grocer whatever generation named it,
///   and dropping the alias would silently misfile it.
/// - **Asking** a question wants only what the new API admits to knowing.
///   Anything else is not a narrower search, it is no search.
///
/// Both were the same array. `MapCategory.placeTypes` even carried a comment
/// asking for "deliberately conservative" *and* "covers both generations",
/// which cannot both be true of one list.
///
/// **Both halves of the app made the same mistake**, which is the real
/// argument for this type existing rather than a fix in each place:
/// `MapCategory` phrases the Map's request, `MerchantCategoryMap` phrases the
/// geofence planner's, and both were handing Google their reading vocabulary.
/// The Map failure was visible — an error on screen. The geofence one was not:
/// a refused lookup there means no merchants, so no regions, so **no reminders
/// ever**, looking exactly like a quiet week.
public enum PlaceTypeVocabulary {

    /// Types a response may still carry that a request must never contain.
    ///
    /// **When in doubt, a type belongs in here.** The asymmetry settles it:
    /// an invalid type costs the whole request, while a valid one left out
    /// costs at most a few results that a sibling type almost always picks up
    /// anyway. Every entry below has such a sibling, so none of this narrows
    /// what the app can find:
    ///
    /// - `grocery_or_supermarket` — proven dead by the 400 above.
    ///   `supermarket`, `grocery_store` and `convenience_store` still ask.
    /// - `lodging` — the legacy umbrella the new API split into specific
    ///   kinds. `hotel`, `motel` and `resort_hotel` still ask.
    /// - `food` — a legacy grouping rather than a place type. Every eating
    ///   place it stood for is asked for by name: `restaurant`, `cafe`,
    ///   `bakery`, `bar`, `fast_food_restaurant` and the rest.
    /// - `shopping_center` — could not be confirmed in the new vocabulary, and
    ///   an unconfirmed type is precisely what this list is for.
    ///   `shopping_mall` and ten specific store types still ask.
    ///
    /// Adding to this list is safe. Removing from it needs evidence from the
    /// live API, not a reading of the documentation — that is what the
    /// original comment had, and it was wrong.
    public static let legacyOnly: Set<String> = [
        "grocery_or_supermarket",
        "lodging",
        "food",
        "shopping_center"
    ]

    /// The same types, minus anything Google would refuse.
    ///
    /// Order is preserved, so a caller that had sorted its list keeps the
    /// sort.
    public static func requestable(_ types: [String]) -> [String] {
        types.filter { !legacyOnly.contains($0) }
    }
}
