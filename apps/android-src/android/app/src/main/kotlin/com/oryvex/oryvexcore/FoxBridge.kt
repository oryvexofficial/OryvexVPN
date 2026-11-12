package com.oryvex.oryvexcore

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.URL

/** Android-side bridge to the bundled Fox mobile core and its local account dashboard. */
object FoxBridge {
    private const val DEFAULT_DASHBOARD_PORT = 10820

    fun dataDir(context: Context): File = File(context.filesDir, "fox")

    fun configure(context: Context, socksPort: Int? = null, shareLan: Boolean = false): Int {
        val dir = dataDir(context)
        if (!dir.exists() && !dir.mkdirs()) error("Could not create Fox data folder")
        val file = File(dir, "config.json")
        val root = if (file.isFile) JSONObject(file.readText()) else JSONObject()
        val proxy = root.optJSONObject("proxy") ?: JSONObject()
        if (socksPort != null) {
            proxy.put("listen", "${if (shareLan) "0.0.0.0" else "127.0.0.1"}:$socksPort")
        } else if (!proxy.has("listen")) {
            proxy.put("listen", "127.0.0.1:1819")
        }
        root.put("proxy", proxy)
        val dashboard = root.optJSONObject("dashboard") ?: JSONObject()
        var port = dashboard.optString("listen", "").substringAfterLast(':').toIntOrNull() ?: 0
        if (port !in 1..65535) port = availableDashboardPort()
        dashboard.put("listen", "127.0.0.1:$port")
        root.put("dashboard", dashboard)
        file.writeText(root.toString(2))
        return port
    }

    private fun availableDashboardPort(): Int {
        for (port in listOf(DEFAULT_DASHBOARD_PORT) + (18220..18283).toList()) {
            try {
                ServerSocket().use { it.bind(InetSocketAddress("127.0.0.1", port)) }
                return port
            } catch (_: Exception) {
                // Try another loopback-only port.
            }
        }
        error("No free port for the Fox dashboard")
    }

    /** Issues a one-use local login link; the local API token never leaves this process. */
    fun dashboardUrl(context: Context): String {
        val port = configure(context)
        if (!mobile.Mobile.running()) {
            mobile.Mobile.start(dataDir(context).absolutePath, false)
        }
        val tokenFile = File(dataDir(context), "local-api.token")
        repeat(80) {
            if (tokenFile.isFile) {
                val token = tokenFile.readText().trim()
                if (token.isNotEmpty()) {
                    val connection = URL("http://127.0.0.1:$port/api/session/link")
                        .openConnection() as HttpURLConnection
                    try {
                        connection.requestMethod = "POST"
                        connection.connectTimeout = 3000
                        connection.readTimeout = 5000
                        connection.setRequestProperty("X-Local-Token", token)
                        connection.setRequestProperty("Content-Type", "application/json")
                        connection.doOutput = true
                        connection.outputStream.use { it.write("{}".toByteArray()) }
                        val response = connection.inputStream.bufferedReader().use { it.readText() }
                        val path = JSONObject(response).optString("path")
                        if (path.startsWith("/")) return "http://127.0.0.1:$port$path"
                    } finally {
                        connection.disconnect()
                    }
                }
            }
            Thread.sleep(250)
        }
        error("Fox dashboard did not start")
    }

    fun status(context: Context): JSONObject {
        val dir = dataDir(context)
        val configFile = File(dir, "config.json")
        val port = try {
            JSONObject(configFile.readText()).optJSONObject("dashboard")
                ?.optString("listen", "")?.substringAfterLast(':')?.toIntOrNull()
                ?.takeIf { it in 1..65535 } ?: configure(context)
        } catch (_: Exception) {
            configure(context)
        }
        val tokenFile = File(dir, "local-api.token")
        val token = if (tokenFile.isFile) tokenFile.readText().trim() else ""
        if (token.isEmpty()) error("Fox local API token is missing")
        val connection = URL("http://127.0.0.1:$port/api/status").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 2500
            connection.readTimeout = 3500
            connection.setRequestProperty("X-Local-Token", token)
            val text = connection.inputStream.bufferedReader().use { it.readText() }
            return JSONObject(text)
        } finally {
            connection.disconnect()
        }
    }
}
