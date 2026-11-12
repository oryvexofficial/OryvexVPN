package com.oryvex.oryvexcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreLinesTest {
    @Test
    fun theSocksListenerOnTheChosenPortIsReady() {
        assertTrue(CoreLines.isSocksReady("[+] socks5 server listening on 127.0.0.1:1819", 1819))
        assertTrue(CoreLines.isSocksReady("[+] socks5 server listening on 0.0.0.0:1819  ", 1819))
    }

    @Test
    fun otherListenersAreNotReady() {
        assertFalse(CoreLines.isSocksReady("[+] http proxy listening on 127.0.0.1:1819", 1819))
        assertFalse(CoreLines.isSocksReady("[+] socks5 server listening on 127.0.0.1:41819", 1819))
        assertFalse(CoreLines.isSocksReady("[*] bootstrapping tor", 1819))
    }

    @Test
    fun theTorExitIsRead() {
        assertEquals("de", CoreLines.torExit("[+] tor exit: using de (Germany), the fastest at 842 ms"))
        assertEquals("auto", CoreLines.torExit("[+] tor exit: using auto (tor picks a fast exit)"))
        assertNull(CoreLines.torExit("[*] tor exit: trying NL (Netherlands)"))
    }
}
