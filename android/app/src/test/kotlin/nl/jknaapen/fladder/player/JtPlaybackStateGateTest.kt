package nl.jknaapen.fladder.player

import PlaybackState
import nl.jknaapen.fladder.utility.formatTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// WP2.12: the position label of the native Android TV player must stand still while paused.
// The gate decides what reaches VideoPlayerObject; the label shows formatTime(position) of the
// last published snapshot, so that is what these tests follow.
class JtPlaybackStateGateTest {
    private val film = 95 * 60_000L + 1_000L // 1:35:01
    private val real = 5 * 60_000L + 28_000L // 5:28 (Jochen's photo)
    private val other = 15 * 60_000L + 1_000L // 15:01 (Jochen's photo)

    private fun state(position: Long, playing: Boolean, buffering: Boolean = false, duration: Long = film) =
        PlaybackState(
            position = position,
            buffered = position + 30_000L,
            duration = duration,
            playing = playing,
            buffering = buffering,
            completed = false,
            failed = false,
        )

    /** Feeds snapshots through the gate and returns the label after each one. */
    private class Label(private val gate: JtPlaybackStateGate) {
        var published: PlaybackState? = null
        val history = mutableListOf<String>()
        fun feed(s: PlaybackState, forced: Boolean = false) {
            if (gate.accept(s, forced)) published = s
            history += formatTime(published?.position ?: 0L)
        }
    }

    @Test
    fun labelStaysStillDuringPauseEvenWhenTicksAlternate() {
        val label = Label(JtPlaybackStateGate())
        label.feed(state(real - 2_000L, playing = true))
        label.feed(state(real - 1_000L, playing = true))
        label.feed(state(real, playing = false), forced = true) // pause (EVENT_IS_PLAYING_CHANGED)

        // 12 s of pause with the 1 s tick delivering alternating values, like on the Mi Box S
        repeat(12) { i ->
            label.feed(state(if (i % 2 == 0) other else real, playing = false, duration = film + if (i % 2 == 0) other - real else 0L))
        }

        val duringPause = label.history.drop(2)
        assertEquals(List(13) { "5:28" }, duringPause)
    }

    @Test
    fun seekWhilePausedIsStillShown() {
        val label = Label(JtPlaybackStateGate())
        label.feed(state(real, playing = false), forced = true)
        label.feed(state(real + 30_000L, playing = false), forced = true) // EVENT_POSITION_DISCONTINUITY
        label.feed(state(real, playing = false)) // stray tick
        assertEquals(listOf("5:28", "5:58", "5:58"), label.history)
    }

    @Test
    fun playingAndBufferingTicksStillUpdate() {
        val gate = JtPlaybackStateGate()
        assertTrue(gate.accept(state(1_000L, playing = true)))
        assertTrue(gate.accept(state(2_000L, playing = true)))
        assertTrue(gate.accept(state(2_000L, playing = false, buffering = true)))
        assertTrue(gate.accept(state(2_000L, playing = false, buffering = true)))
        assertTrue(gate.accept(state(2_000L, playing = false))) // buffering -> ready: flag change
        assertFalse(gate.accept(state(9_000L, playing = false))) // paused tick: dropped
        assertTrue(gate.accept(state(2_000L, playing = true))) // resume tick
    }

    @Test
    fun firstSnapshotIsAlwaysPublished() {
        assertTrue(JtPlaybackStateGate().accept(state(0L, playing = false)))
    }
}
