package com.oryvex.oryvexcore

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter <-> service bridge.
 *
 *  oryvexcore/core   (methods)  configDir, requestNotifications, status, since, start, stop,
 *                               openUrl (release page / download), deviceInfo (ABIs, for updates)
 *  oryvexcore/events (stream)   {type: line|vpn|exit, run: <session id>, seq: <line no>, ...}
 *
 * `since` lets the UI pull lines it missed, so the Connect page can never sit on a stage with
 * an empty Activity log because the event stream attached late.
 */
class MainActivity : FlutterActivity() {

    private class Pending(val request: StartRequest, val result: MethodChannel.Result)

    private var pending: Pending? = null
    private var sink: EventChannel.EventSink? = null
    private val listener: (Map<String, Any?>) -> Unit = { event ->
        // Lines arrive on the core's reader thread; the sink may only be used on the main thread.
        runOnUiThread {
            try { sink?.success(event) } catch (_: Throwable) {}
        }
    }

    /** Saves the MITM certificate to Downloads and opens the system's certificate install. */
    private fun installCertificate(path: String): String {
        val file = java.io.File(path)
        if (!file.isFile) return "missing"
        val bytes = file.readBytes()
        var where = ""
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val values = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Downloads.DISPLAY_NAME, "oryvex-mitm-ca.crt")
                    put(android.provider.MediaStore.Downloads.MIME_TYPE, "application/x-x509-ca-cert")
                    put(android.provider.MediaStore.Downloads.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS)
                }
                val uri = contentResolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri != null) {
                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    where = "Downloads"
                }
            }
        } catch (_: Throwable) {
        }
        // Android 10 and older install it straight from the app; 11+ must do it from Settings.
        if (Build.VERSION.SDK_INT < 30) {
            try {
                val intent = android.security.KeyChain.createInstallIntent()
                intent.putExtra(android.security.KeyChain.EXTRA_CERTIFICATE, bytes)
                intent.putExtra(android.security.KeyChain.EXTRA_NAME, "OryvexVPN MITM CA")
                startActivity(intent)
                return "installer $where"
            } catch (_: Throwable) {
            }
        }
        try {
            startActivity(Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS))
        } catch (_: Throwable) {
        }
        return "settings $where"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "oryvexcore/core").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configDir" -> result.success(filesDir.absolutePath)
                    "requestNotifications" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    "status" -> result.success(CoreBus.snapshot())
                    "since" -> {
                        val after = call.argument<Number>("seq")?.toLong() ?: 0L
                        result.success(CoreBus.since(after))
                    }
                    "start" -> {
                        val req = StartRequest(
                            args = call.argument<List<String>>("args") ?: emptyList(),
                            vpn = call.argument<Boolean>("vpn") ?: true,
                            socksPort = call.argument<Number>("socksPort")?.toInt() ?: 1819,
                            fakeDns = call.argument<Boolean>("fakeDns") ?: true,
                            ipv6 = call.argument<Boolean>("ipv6") ?: true,
                            runId = call.argument<Number>("runId")?.toLong() ?: System.currentTimeMillis(),
                            protocol = call.argument<String>("protocol") ?: "auto",
                        )
                        if (req.vpn) {
                            val consent = try { VpnService.prepare(this) } catch (_: Throwable) { null }
                            if (consent != null) {
                                pending?.result?.error("VPN_DENIED", "superseded by a newer request", null)
                                pending = Pending(req, result)
                                startActivityForResult(consent, REQUEST_VPN)
                                return@setMethodCallHandler
                            }
                        }
                        launch(req, result)
                    }
                    "stop" -> {
                        OryvexVpnService.stop(this)
                        result.success(true)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (!url.startsWith("https://") && !url.startsWith("http://")) {
                            result.success(false)
                        } else {
                            val opened = try {
                                startActivity(
                                    Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                true
                            } catch (_: Throwable) {
                                false
                            }
                            result.success(opened)
                        }
                    }
                    "installCertificate" -> result.success(installCertificate(call.argument<String>("path") ?: ""))
                    "deviceInfo" -> result.success(
                        mapOf(
                            "abis" to Build.SUPPORTED_ABIS.toList(),
                            "sdk" to Build.VERSION.SDK_INT,
                        )
                    )
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("NATIVE_ERROR", e.message ?: e.javaClass.simpleName, null)
            }
        }

        EventChannel(messenger, "oryvexcore/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                CoreBus.removeListener(listener)
                CoreBus.addListener(listener)
            }

            override fun onCancel(arguments: Any?) {
                CoreBus.removeListener(listener)
                sink = null
            }
        })
    }

    private fun launch(req: StartRequest, result: MethodChannel.Result) {
        try {
            OryvexVpnService.start(this, req)
            result.success(true)
        } catch (e: Throwable) {
            result.error("START_FAILED", e.message ?: "could not start the service", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VPN) return
        val p = pending ?: return
        pending = null
        if (resultCode == Activity.RESULT_OK) {
            launch(p.request, p.result)
        } else {
            p.result.error("VPN_DENIED", "VPN permission denied", null)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), REQUEST_NOTIFICATIONS)
        }
    }

    override fun onDestroy() {
        CoreBus.removeListener(listener)
        sink = null
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_VPN = 0x0571
        private const val REQUEST_NOTIFICATIONS = 0x0572
    }
}
