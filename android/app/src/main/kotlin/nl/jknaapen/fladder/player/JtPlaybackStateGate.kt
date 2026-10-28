package nl.jknaapen.fladder.player

import PlaybackState

// JT-HOOK: pause-stable-position (WP2.12)
// Decides which PlaybackState snapshots reach VideoPlayerObject (and with it the time labels
// and the "ends at" text of the native Android TV player).
//
// Upstream publishes a fresh snapshot every second and on every ExoPlayer event, also while
// paused. On the Mi Box S the position label then jumped every second between the real
// position and another value during a pause. While paused nothing is supposed to move, so
// periodic ticks are dropped there; only real changes get through:
//  - forced snapshots (seek/position discontinuity, play/pause, timeline or playback-state change);
//  - the first snapshot, and any change of playing/buffering/completed/failed;
//  - every tick while playing or buffering (unchanged upstream behaviour).
internal class JtPlaybackStateGate {
    private var last: PlaybackState? = null

    fun accept(next: PlaybackState, forced: Boolean = false): Boolean {
        val prev = last
        val publish = forced ||
                prev == null ||
                next.playing ||
                next.buffering ||
                prev.playing != next.playing ||
                prev.buffering != next.buffering ||
                prev.completed != next.completed ||
                prev.failed != next.failed
        if (publish) last = next
        return publish
    }
}
