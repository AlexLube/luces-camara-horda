# APK de Android sin el SDK completo

Godot 4.3 exporta el APK sin gradle (preset «Android»). Para firmarlo basta la librería `apksig`, que está en Maven Central:

```
curl -O https://repo1.maven.org/maven2/com/android/tools/build/apksig/2.3.0/apksig-2.3.0.jar
javac -cp apksig-2.3.0.jar Sign.java
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... GODOT_ANDROID_KEYSTORE_RELEASE_USER=... GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=... \
  godot --headless --path . --export-release Android        # sale sin firmar si no hay build-tools
java --add-exports java.base/sun.security.x509=ALL-UNNAMED --add-exports java.base/sun.security.pkcs=ALL-UNNAMED \
  --add-exports java.base/sun.security.util=ALL-UNNAMED -cp apksig-2.3.0.jar:. \
  Sign <keystore> <contraseña> <alias> build/android/LucesCamaraHorda.apk LucesCamaraHorda_firmado.apk
```

Firma con el esquema v2 (Android 7 o superior). Las credenciales de la firma nunca van al repositorio.
