package com.oryvex.oryvexcore

import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method

/**
 * hev-socks5-tunnel turns the VPN's tun fd into SOCKS5 connections to the core. Its JNI_OnLoad
 * registers natives on hev.htproxy.TProxyService (java/hev/htproxy), so loading the library is
 * all the wiring needed. A build without the library still works, in proxy-only mode.
 *
 * The binding is reached by reflection on purpose: the Kotlin compiler then never needs to see
 * the generated Java class (that compile-time link is what broke `compileReleaseKotlin` with
 * "Unresolved reference 'hev'"), and hev releases that switch the natives between void and
 * boolean returns keep working without touching this file. proguard-rules.pro keeps the class.
 */
object TunBridge {
    private const val BINDING = "hev.htproxy.TProxyService"

    private val binding: Class<*>? by lazy {
        try {
            Class.forName(BINDING)
        } catch (_: Throwable) {
            null
        }
    }

    val available: Boolean by lazy {
        try {
            System.loadLibrary("hev-socks5-tunnel")
            binding != null
        } catch (_: Throwable) {
            false
        }
    }

    private fun method(name: String, vararg types: Class<*>): Method? =
        try {
            binding?.getMethod(name, *types)
        } catch (_: Throwable) {
            null
        }

    private fun call(m: Method, vararg args: Any?): Any? =
        try {
            m.invoke(null, *args)
        } catch (e: InvocationTargetException) {
            throw e.targetException ?: e
        }

    fun start(configPath: String, fd: Int) {
        val m = method("TProxyStartService", String::class.java, Integer.TYPE)
            ?: throw IllegalStateException("the VPN engine binding has no TProxyStartService")
        val result = call(m, configPath, fd)
        if (result == false) throw IllegalStateException("the VPN engine refused to start")
    }

    fun stop() {
        try {
            method("TProxyStopService")?.let { call(it) }
        } catch (_: Throwable) {}
    }

    val running: Boolean
        get() = try {
            method("TProxyIsRunning")?.let { call(it) } == true
        } catch (_: Throwable) {
            false
        }
}
