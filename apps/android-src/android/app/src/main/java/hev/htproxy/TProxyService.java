package hev.htproxy;

/**
 * JNI binding for hev-socks5-tunnel. Its JNI_OnLoad registers natives on this class by name
 * (PKGNAME hev/htproxy, CLSNAME TProxyService), and RegisterNatives needs the exact signatures.
 *
 * gui/tool/gen_tproxy_binding.py regenerates this file from the hev-jni.c it is built with,
 * so a newer hev-socks5-tunnel can never drift out of step. This checked-in copy matches its
 * current README contract.
 */
public final class TProxyService {
    private TProxyService() {}

    public static native boolean TProxyStartService(String configPath, int fd);

    public static native boolean TProxyStopService();

    public static native boolean TProxyIsRunning();

    public static native long[] TProxyGetStats();
}
