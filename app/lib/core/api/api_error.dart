/// An error returned by the Trace API, with a human message for every known code.
class ApiError implements Exception {
  const ApiError(this.code, {this.status});

  final String code;
  final int? status;

  String get message => switch (code) {
        'too_far' => "You're close, but not there yet. Step inside the glow.",
        'low_accuracy' => 'Your GPS is fuzzy right now. Head toward open sky and try again.',
        'stale' => 'That location was a little old. Hold still for a second and retry.',
        'suspicious' => "Your location jumped in a way we can't trust. Try again in a moment.",
        'condition_locked' => 'This drop is waiting for the right moment.',
        'capsule_locked' => "This time capsule hasn't opened yet.",
        'not_visible' || 'not_found' => 'This drop is no longer here.',
        'locked' => 'You have to be there to open this one.',
        'daily_limit' => "You've left 10 drops today. Come back tomorrow.",
        'place_limit' => "You've already left 3 drops around here today.",
        'home_zone' => "You're inside your home quiet zone. Public drops can't be left here.",
        'exclusion_zone' => "Drops can't be left in this area.",
        'handle_taken' => 'That handle is taken.',
        'capsule_too_soon' => 'A time capsule has to stay sealed for at least a day.',
        'capsule_too_far' => 'Time capsules can be sealed for up to 25 years.',
        'unknown_recipient' => "One of those handles doesn't exist.",
        'too_many_recipients' => 'A capsule can be addressed to at most 20 people.',
        'media_unavailable' => 'Photo uploads are not available right now.',
        'unauthorized' => 'Your session expired. Please sign in again.',
        'banned' => 'This account has been suspended.',
        'network' => "Can't reach Trace. Check your connection.",
        _ => 'Something went wrong. Please try again.',
      };

  @override
  String toString() => 'ApiError($code)';
}
