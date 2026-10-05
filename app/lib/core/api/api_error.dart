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
        'home_zone' => "You're inside your home quiet zone, so public drops can't go here. "
            'Share it with a circle instead, or change the zone in Passport → Settings.',
        'exclusion_zone' => "Drops can't be left in this area.",
        'handle_taken' => 'That handle is taken.',
        'trail_order' => 'This trail goes in order. Find the previous stop first.',
        'invalid_stops' => 'Trails can only use your own public drops that aren’t in another trail.',
        'duplicate_stop' => 'Each drop can only be one stop.',
        'visibility_conflict' => 'A drop can go to a circle or to specific people, not both.',
        'not_a_member' => "You're not in that circle.",
        'invalid_code' => "That invite code doesn't match any circle.",
        'circle_full' => 'That circle is full (50 people).',
        'circle_limit' => 'You can run up to 10 circles.',
        'owner_cannot_leave' => "You started this circle, so you can't leave it.",
        'own_relay' => 'You started this relay. Let someone else carry it.',
        'carried_before' => "You've carried this relay before. Let it meet someone new.",
        'already_carried' => 'Someone just picked this relay up.',
        'carrying_limit' => 'You can carry 3 relays at a time. Drop one first.',
        'not_carrying' => "You're not carrying this relay.",
        'too_close' => 'A relay has to travel. Take it at least 1 km from where you found it.',
        'note_rejected' => 'That note can’t travel with the relay. Try different words.',
        'relay_must_be_public' => 'Relays travel in public, so they can’t be sealed or private.',
        'angle_required' => 'Save the camera angle before leaving a Then/Now drop.',
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
