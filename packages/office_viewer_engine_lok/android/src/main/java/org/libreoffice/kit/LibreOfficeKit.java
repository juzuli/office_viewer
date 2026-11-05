package org.libreoffice.kit;

import android.content.SharedPreferences;
import android.content.res.AssetManager;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.reflect.Field;
import java.nio.Buffer;
import java.nio.ByteBuffer;

/**
 * Minimal JNI surface matching symbols exported by liblo-native-code.so
 * (F-Droid viewer / Bootstrap). MPL-2.0 origin: LibreOfficeKit android/Bootstrap.
 *
 * Package/class names are locked to {@code org.libreoffice.kit.LibreOfficeKit} because
 * the .so exports {@code Java_org_libreoffice_kit_LibreOfficeKit_*}; do not rename.
 *
 * Also mirrors the viewer APK's copyFromAssets("unpack", dataDir) so udkapi.rdb etc.
 * land under {@code <dataDir>/program} before {@code libreofficekit_hook}.
 */
public final class LibreOfficeKit {
    private static final String TAG = "LibreOfficeKit";
    private static final String PREFS = "office_viewer_engine_lok";
    private static final String PREFS_UNPACK_VERSION = "assets_unpacked_v";
    /** Bump when unpack asset layout changes to force re-copy. */
    private static final int UNPACK_VERSION = 2;

    private static boolean libsLoaded = false;
    private static boolean initializeDone = false;

    private LibreOfficeKit() {}

    private static native boolean initializeNative(
            String dataDir, String cacheDir, String apkFile, AssetManager mgr);

    public static native ByteBuffer getLibreOfficeKitHandle();

    public static native void putenv(String string);

    public static native void redirectStdio(boolean state);

    public static synchronized void loadNativeLibraries() {
        if (libsLoaded) return;
        System.loadLibrary("nspr4");
        System.loadLibrary("plds4");
        System.loadLibrary("plc4");
        System.loadLibrary("nssutil3");
        System.loadLibrary("freebl3");
        System.loadLibrary("sqlite3");
        System.loadLibrary("softokn3");
        System.loadLibrary("nss3");
        System.loadLibrary("nssckbi");
        System.loadLibrary("nssdbm3");
        System.loadLibrary("smime3");
        System.loadLibrary("ssl3");
        System.loadLibrary("c++_shared");
        System.loadLibrary("lo-native-code");
        libsLoaded = true;
    }

    public static synchronized long init(
            String dataDir,
            String cacheDir,
            String apkFile,
            AssetManager assets,
            SharedPreferences prefs) {
        loadNativeLibraries();
        if (!initializeDone) {
            redirectStdio(true);
            ensureUnpacked(assets, dataDir, prefs);
            if (!initializeNative(dataDir, cacheDir, apkFile, assets)) {
                Log.e(TAG, "initializeNative failed");
                throw new IllegalStateException("LibreOfficeKit initializeNative failed");
            }
            initializeDone = true;
        }
        final ByteBuffer handle = getLibreOfficeKitHandle();
        if (handle == null) {
            throw new IllegalStateException("getLibreOfficeKitHandle returned null");
        }
        return directBufferAddress(handle);
    }

    public static synchronized boolean isInitialized() {
        return initializeDone;
    }

    static void ensureUnpacked(AssetManager assets, String dataDir, SharedPreferences prefs) {
        final int done = prefs.getInt(PREFS_UNPACK_VERSION, 0);
        final File marker = new File(dataDir, "program/udkapi.rdb");
        if (done == UNPACK_VERSION && marker.isFile()) {
            Log.i(TAG, "unpack assets already present");
            return;
        }
        Log.i(TAG, "copying assets/unpack -> " + dataDir);
        if (!copyFromAssets(assets, "unpack", dataDir)) {
            throw new IllegalStateException("Failed to copy assets/unpack into " + dataDir);
        }
        patchFontconfigCacheDir(dataDir);
        prefs.edit().putInt(PREFS_UNPACK_VERSION, UNPACK_VERSION).apply();
    }

    /**
     * Upstream fonts.conf may hard-code the F-Droid viewer package data path.
     * Rewrite the cache dir to this app's dataDir so fontconfig can write.
     */
    static void patchFontconfigCacheDir(String dataDir) {
        File conf = new File(dataDir, "etc/fonts/fonts.conf");
        if (!conf.isFile()) return;
        try {
            String xml = new String(java.nio.file.Files.readAllBytes(conf.toPath()),
                    java.nio.charset.StandardCharsets.UTF_8);
            String patched = xml.replace(
                    "/data/data/org.documentfoundation.libreoffice/fontconfig",
                    dataDir + "/fontconfig");
            // Ensure a <cachedir> exists even if the upstream conf omitted our package.
            if (!patched.contains(dataDir + "/fontconfig")) {
                patched = patched.replace(
                        "</fontconfig>",
                        "\t<cachedir>" + dataDir + "/fontconfig</cachedir>\n</fontconfig>");
            }
            // Prefer bundled Liberation/Carlito fonts from unpack.
            if (!patched.contains(dataDir + "/user/fonts")) {
                patched = patched.replace(
                        "<dir>/system/fonts</dir>",
                        "<dir>" + dataDir + "/user/fonts</dir>\n\t<dir>/system/fonts</dir>");
            }
            java.nio.file.Files.write(conf.toPath(),
                    patched.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            // noinspection ResultOfMethodCallIgnored
            new File(dataDir, "fontconfig").mkdirs();
        } catch (IOException e) {
            Log.w(TAG, "Could not patch fonts.conf: " + e.getMessage());
        }
    }

    /** Recursive copy of an asset folder into {@code targetDir}, same as Viewer. */
    static boolean copyFromAssets(AssetManager assetManager, String fromAssetPath, String targetDir) {
        try {
            String[] files = assetManager.list(fromAssetPath);
            if (files == null) return false;
            boolean res = true;
            for (String file : files) {
                String childAsset = fromAssetPath + "/" + file;
                String[] children = assetManager.list(childAsset);
                if (children == null) continue;
                if (children.length == 0) {
                    // file
                    // noinspection ResultOfMethodCallIgnored
                    new File(targetDir).mkdirs();
                    res &= copyAsset(assetManager, childAsset, targetDir + "/" + file);
                } else {
                    res &= copyFromAssets(assetManager, childAsset, targetDir + "/" + file);
                }
            }
            return res;
        } catch (Exception e) {
            Log.e(TAG, "copyFromAssets failed: " + e.getMessage(), e);
            return false;
        }
    }

    private static boolean copyAsset(AssetManager assetManager, String fromAssetPath, String toPath) {
        try (InputStream in = assetManager.open(fromAssetPath);
             OutputStream out = new FileOutputStream(toPath)) {
            byte[] buf = new byte[16 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return true;
        } catch (IOException e) {
            Log.e(TAG, "copyAsset " + fromAssetPath + " -> " + toPath + ": " + e.getMessage());
            return false;
        }
    }

    static long directBufferAddress(ByteBuffer buffer) {
        if (!buffer.isDirect()) {
            throw new IllegalArgumentException("expected direct ByteBuffer");
        }
        try {
            Field address = Buffer.class.getDeclaredField("address");
            address.setAccessible(true);
            return address.getLong(buffer);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("cannot read direct ByteBuffer address", e);
        }
    }
}
