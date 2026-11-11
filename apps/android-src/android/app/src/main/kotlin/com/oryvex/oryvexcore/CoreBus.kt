package com.oryvex.oryvexcore

import java.util.ArrayDeque
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Process-wide hub between the service (which runs the core) and whatever UI is attached.
 *
 * Every event carries the run id of the session that produced it, so the UI can drop late lines
 * or a late exit from a session it already stopped. Every log line also carries a sequence
 * number that only ever grows (it is never reset, not even between runs), so the UI can pull
 * whatever it missed with `since(seq)` and drop duplicates when a line arrives both ways. That
 * pull is the safety net that keeps the Connect page and Activity alive even if the event stream
 * is ever late to attach (the cause of "stuck on Identity with no logs" in 2.4.1).
 */
object CoreBus {
    private val lock = Any()
    private val recent = ArrayDeque<Pair<Long, String>>()
    private val listeners = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()
    private const val KEEP = 800

    @Volatile var running = false
    @Volatile var stopping = false
    @Volatile var vpnUp = false
    @Volatile var vpnError: String? = null
    @Volatile var runId: Long = 0
    @Volatile var exitCode: Int? = null
    private var seq: Long = 0

    fun addListener(l: (Map<String, Any?>) -> Unit) { listeners.addIfAbsent(l) }
    fun removeListener(l: (Map<String, Any?>) -> Unit) { listeners.remove(l) }

    fun begin(run: Long) {
        synchronized(lock) { recent.clear() }
        runId = run
        running = true
        stopping = false
        vpnUp = false
        vpnError = null
        exitCode = null
    }

    fun line(run: Long, text: String) {
        val n: Long = synchronized(lock) {
            seq += 1
            recent.addLast(seq to text)
            while (recent.size > KEEP) recent.pollFirst()
            seq
        }
        emit(mapOf("type" to "line", "line" to text, "run" to run, "seq" to n))
    }

    fun vpn(run: Long, up: Boolean, error: String? = null) {
        vpnUp = up
        if (error != null) vpnError = error
        emit(mapOf("type" to "vpn", "up" to up, "error" to error, "run" to run))
    }

    fun exit(run: Long, code: Int?) {
        if (run == runId) {
            running = false
            stopping = false
            vpnUp = false
            exitCode = code
        }
        emit(mapOf("type" to "exit", "code" to code, "run" to run))
    }

    /** Everything the UI needs to (re)build its state: the session, and its recent lines. */
    fun snapshot(): Map<String, Any?> = since(0)

    /** The session state plus every line newer than [after]. */
    fun since(after: Long): Map<String, Any?> {
        val lines = ArrayList<String>()
        val seqs = ArrayList<Long>()
        val last: Long = synchronized(lock) {
            for ((n, text) in recent) {
                if (n > after) {
                    seqs.add(n)
                    lines.add(text)
                }
            }
            seq
        }
        return mapOf(
            "running" to running,
            "stopping" to stopping,
            "vpn" to vpnUp,
            "vpnError" to vpnError,
            "run" to runId,
            "exitCode" to exitCode,
            "seq" to last,
            "seqs" to seqs,
            "lines" to lines,
        )
    }

    private fun emit(event: Map<String, Any?>) {
        for (l in listeners) {
            try { l(event) } catch (_: Throwable) {}
        }
    }
}
