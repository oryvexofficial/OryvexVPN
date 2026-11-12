package com.oryvex.oryvexcore

/** Plain readings of the core's log lines, kept free of Android types so they unit test on the JVM. */
internal object CoreLines {
    /** "[+] socks5 server listening on 127.0.0.1:1819": the proxy the device VPN feeds is up. */
    fun isSocksReady(line: String, port: Int): Boolean {
        if (!line.contains("listening on") || line.contains("http proxy")) return false
        return line.trimEnd().endsWith(":$port")
    }

    /** "[+] tor exit: using de (Germany), ...": the exit country Tor settled on, or "auto". */
    fun torExit(line: String): String? {
        val m = Regex("""tor exit: using (auto|[a-zA-Z]{2})\b""").find(line) ?: return null
        return m.groupValues[1].lowercase()
    }
}
