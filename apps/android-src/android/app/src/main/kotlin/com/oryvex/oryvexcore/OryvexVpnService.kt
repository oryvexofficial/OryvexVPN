package com.oryvex.oryvexcore

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import java.io.File
import kotlin.concurrent.thread

/**
 * Runs the OryvexCore binary (packaged as lib/<abi>/liboryvexcore_cli.so, the only place Android
 * lets an app exec from) and, in VPN mode, hands a tun device to hev-socks5-tunnel, which feeds
 * every app's traffic into the core's SOCKS5 port. The app's own uid is left out of the VPN, so
 * the core's connections to the internet never loop back into it.
 *
 * Lifecycle rules (all state is touched on the main thread only):
 *  - one core process at a time; a START that arrives while one is running or stopping is
 *    queued and launched the moment the old process is confirmed gone, so its port is free;
 *  - STOP is idempotent and always ends in exactly one exit event for the session;
 *  - a core that ignores SIGTERM is killed after 3 s, and a session whose pipes never close is
 *    declared over after 6 s, so the UI can never get stuck on "Disconnecting".
 */
class OryvexVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.oryvex.oryvexcore.START"
        const val ACTION_STOP = "com.oryvex.oryvexcore.STOP"
        private const val CHANNEL_ID = "oryvexcore"
        private const val NOTIFICATION_ID = 1819
        private const val CORE_BINARY = "liboryvexcore_cli.so"
        private const val TERM_GRACE_MS = 3000L
        private const val GIVE_UP_MS = 6000L

        fun start(ctx: Context, req: StartRequest) {
            req.save(ctx)
            val intent = req.toIntent(Intent(ctx, OryvexVpnService::class.java).setAction(ACTION_START))
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(intent) else ctx.startService(intent)
        }

        fun stop(ctx: Context) {
            try {
                ctx.startService(Intent(ctx, OryvexVpnService::class.java).setAction(ACTION_STOP))
            } catch (_: Throwable) {
                // The service is gone already: make sure the UI hears about it.
                if (CoreBus.running) CoreBus.exit(CoreBus.runId, null)
            }
        }

        /** The core logs "[+] socks5 server listening on 127.0.0.1:1819" once the tunnel serves. */
        fun isReady(line: String, port: Int): Boolean = CoreLines.isSocksReady(line, port)
    }

    private val main = Handler(Looper.getMainLooper())
    private var process: Process? = null
    private var request: StartRequest? = null
    private var tun: ParcelFileDescriptor? = null
    private var tunRunning = false
    private var stopping = false
    private var queued: StartRequest? = null
    private val timers = mutableListOf<Runnable>()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                queued = null
                shutdown()
            }
            ACTION_START -> {
                goForeground(getString(R.string.status_starting))
                val req = StartRequest.fromIntent(intent)
                when {
                    req == null -> if (process == null) stopEverything()
                    process != null -> {
                        // A new session while the old one is still alive: retire it first.
                        queued = req
                        shutdown()
                    }
                    else -> launch(req)
                }
            }
            else -> {
                // Started by the system (always-on VPN) or restarted: replay the last request.
                goForeground(getString(R.string.status_connecting))
                val last = StartRequest.last(this)
                if (last == null) {
                    if (process == null) stopEverything()
                } else if (process == null) {
                    launch(last.copy(vpn = true))
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun launch(req: StartRequest) {
        if (process != null) {
            queued = req
            return
        }
        stopping = false
        request = req
        CoreBus.begin(req.runId)
        val run = req.runId

        val bin = File(applicationInfo.nativeLibraryDir, CORE_BINARY)
        if (!bin.exists()) {
            CoreBus.line(run, "[gui] the core binary is missing from this build (${bin.path})")
            CoreBus.exit(run, null)
            stopEverything()
            return
        }

        val pb = ProcessBuilder(listOf(bin.absolutePath) + req.args)
            .directory(filesDir)
            .redirectErrorStream(true)
        pb.environment().apply {
            put("HOME", filesDir.absolutePath)
            put("TMPDIR", cacheDir.absolutePath)
            put("RUST_LOG_STYLE", "never")
            put("NO_COLOR", "1")
        }

        val proc = try {
            pb.start()
        } catch (e: Throwable) {
            CoreBus.line(run, "[gui] could not start the core: ${e.message}")
            CoreBus.exit(run, null)
            stopEverything()
            return
        }
        process = proc
        try { proc.outputStream.close() } catch (_: Throwable) {}
        CoreBus.line(run, "[gui] started core: oryvexcore ${req.args.joinToString(" ")}")
        updateNotification(getString(R.string.status_connecting))

        thread(name = "oryvexcore-log-$run", isDaemon = true) {
            try {
                proc.inputStream.bufferedReader().forEachLine { line ->
                    CoreBus.line(run, line)
                    if (isReady(line, req.socksPort)) main.post { onTunnelUp(proc) }
                }
            } catch (_: Throwable) {}
            val code = try { proc.waitFor() } catch (_: Throwable) { null }
            main.post { onCoreExit(proc, code) }
        }
    }

    private fun onTunnelUp(proc: Process) {
        if (proc !== process || stopping) return
        updateNotification(getString(R.string.status_connected))
        val req = request ?: return
        if (req.vpn && !tunRunning) startTun(req)
    }

    private fun startTun(req: StartRequest) {
        val run = req.runId
        if (!TunBridge.available) {
            CoreBus.vpn(run, false, "This build has no VPN engine, so it runs as a proxy only.")
            return
        }
        val builder = Builder()
            .setSession("OryvexVPN")
            .setMtu(8500)
            .addAddress("198.18.0.1", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(if (req.fakeDns) "198.18.0.2" else "1.1.1.1")
        if (req.ipv6) {
            builder.addAddress("fc00::1", 128).addRoute("::", 0)
        }
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Throwable) {}
        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
        builder.setConfigureIntent(openAppIntent())

        val pfd = try {
            builder.establish()
        } catch (e: Throwable) {
            CoreBus.vpn(run, false, "Could not open the VPN: ${e.message}")
            return
        }
        if (pfd == null) {
            CoreBus.vpn(run, false, "VPN permission was revoked. Connect again to grant it.")
            return
        }
        tun = pfd

        try {
            val config = File(cacheDir, "tun2socks.yml")
            config.writeText(hevConfig(req))
            TunBridge.start(config.absolutePath, pfd.fd)
            tunRunning = true
            CoreBus.line(run, "[gui] VPN up: all device traffic now goes through the core")
            CoreBus.vpn(run, true)
            updateNotification(getString(R.string.status_vpn))
        } catch (e: Throwable) {
            CoreBus.vpn(run, false, "The VPN engine failed: ${e.message}")
            closeTun(run)
        }
    }

    private fun hevConfig(req: StartRequest): String = buildString {
        appendLine("tunnel:")
        appendLine("  mtu: 8500")
        appendLine("  ipv4: 198.18.0.1")
        if (req.ipv6) appendLine("  ipv6: 'fc00::1'")
        appendLine("socks5:")
        appendLine("  port: ${req.socksPort}")
        appendLine("  address: 127.0.0.1")
        appendLine("  udp: 'udp'")
        if (req.fakeDns) {
            appendLine("mapdns:")
            appendLine("  address: 198.18.0.2")
            appendLine("  port: 53")
            appendLine("  network: 100.64.0.0")
            appendLine("  netmask: 255.192.0.0")
            appendLine("  cache-size: 10000")
        }
        appendLine("misc:")
        appendLine("  task-stack-size: 81920")
        appendLine("  log-level: warn")
    }

    private fun closeTun(run: Long) {
        if (tunRunning) {
            TunBridge.stop()
            tunRunning = false
        }
        try { tun?.close() } catch (_: Throwable) {}
        tun = null
        if (CoreBus.vpnUp) CoreBus.vpn(run, false)
    }

    private fun shutdown() {
        val proc = process
        val run = request?.runId ?: CoreBus.runId
        if (proc == null) {
            closeTun(run)
            if (CoreBus.running) CoreBus.exit(run, null)
            val next = queued
            queued = null
            if (next != null) launch(next) else stopEverything()
            return
        }
        if (stopping) return
        stopping = true
        CoreBus.stopping = true
        updateNotification(getString(R.string.status_stopping))
        closeTun(run)
        try { proc.destroy() } catch (_: Throwable) {}

        schedule(TERM_GRACE_MS) {
            if (process === proc) forceKill(proc)
        }
        schedule(GIVE_UP_MS) {
            // The pipes never closed (a stuck reader): declare the session over anyway.
            if (process === proc) {
                CoreBus.line(run, "[gui] the core did not exit in time; it was killed")
                onCoreExit(proc, null)
            }
        }
    }

    private fun forceKill(proc: Process) {
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                proc.destroyForcibly()
                return
            }
            // Before API 26 there is no destroyForcibly: send SIGKILL to the pid ourselves.
            val f = proc.javaClass.getDeclaredField("pid")
            f.isAccessible = true
            android.os.Process.sendSignal(f.getInt(proc), 9)
        } catch (_: Throwable) {
            try { proc.destroy() } catch (_: Throwable) {}
        }
    }

    private fun onCoreExit(proc: Process, code: Int?) {
        if (proc !== process) return // A session we already wrapped up.
        val run = request?.runId ?: CoreBus.runId
        process = null
        cancelTimers()
        closeTun(run)
        val wasStopping = stopping
        stopping = false
        CoreBus.line(run, if (wasStopping) "[gui] core stopped" else "[gui] core exited${code?.let { " with code $it" } ?: ""}")
        CoreBus.exit(run, code)
        val next = queued
        queued = null
        if (next != null) launch(next) else stopEverything()
    }

    private fun schedule(delay: Long, block: () -> Unit) {
        val r = Runnable { block() }
        timers.add(r)
        main.postDelayed(r, delay)
    }

    private fun cancelTimers() {
        for (r in timers) main.removeCallbacks(r)
        timers.clear()
    }

    private fun stopEverything() {
        try {
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}
        stopSelf()
    }

    override fun onRevoke() {
        CoreBus.line(CoreBus.runId, "[gui] the system revoked the VPN (did another VPN take over?)")
        queued = null
        shutdown()
    }

    override fun onDestroy() {
        cancelTimers()
        val run = request?.runId ?: CoreBus.runId
        closeTun(run)
        val proc = process
        process = null
        if (proc != null) {
            try { proc.destroy() } catch (_: Throwable) {}
            CoreBus.exit(run, null)
        }
        super.onDestroy()
    }

    // --- notification -----------------------------------------------------------------------

    private fun immutable(): Int = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0

    private fun openAppIntent(): PendingIntent {
        val i = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(this, 0, i, immutable() or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(text: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL_ID) == null) {
            val ch = NotificationChannel(CHANNEL_ID, getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, OryvexVpnService::class.java).setAction(ACTION_STOP),
            immutable() or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        b.setSmallIcon(R.drawable.ic_stat_core)
            .setContentTitle("OryvexVPN")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(openAppIntent())
            .addAction(Notification.Action.Builder(0, getString(R.string.action_disconnect), stopIntent).build())
        b.setColor(0xFF0A84FF.toInt())
        return b.build()
    }

    private fun goForeground(text: String) {
        try {
            val n = buildNotification(text)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (_: Throwable) {}
    }

    private fun updateNotification(text: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification(text))
        } catch (_: Throwable) {}
    }
}
