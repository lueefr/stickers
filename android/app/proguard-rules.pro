# JNI entry points and the config fields read by libwebp_connector.cpp.
# Avoid broad plugin/package keeps: plugins ship their own consumer rules.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keep class de.loicezt.stickers.video.WebPConfig { *; }
-keep class de.loicezt.stickers.video.WebPImageHint { *; }
