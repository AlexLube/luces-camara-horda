import com.android.apksig.ApkSigner;
import java.io.*;
import java.security.*;
import java.security.cert.X509Certificate;
import java.util.*;

/** Minimal apksigner: java -cp apksig.jar:. Sign <keystore> <storepass> <alias> <in.apk> <out.apk> */
public class Sign {
    public static void main(String[] a) throws Exception {
        KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
        try (InputStream in = new FileInputStream(a[0])) { ks.load(in, a[1].toCharArray()); }
        PrivateKey key = (PrivateKey) ks.getKey(a[2], a[1].toCharArray());
        X509Certificate cert = (X509Certificate) ks.getCertificate(a[2]);
        ApkSigner.SignerConfig sc = new ApkSigner.SignerConfig.Builder("CERT", key, Collections.singletonList(cert)).build();
        new ApkSigner.Builder(Collections.singletonList(sc)).setInputApk(new File(a[3])).setOutputApk(new File(a[4]))
            .setV1SigningEnabled(false).setV2SigningEnabled(true).setMinSdkVersion(24).build().sign();
        System.out.println("signed " + a[4]);
    }
}
