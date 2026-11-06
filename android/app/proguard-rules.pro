# R8 rules for release builds.

# kotlinx.serialization generates a serializer per @Serializable type; R8 must keep both the
# serializer and the generated Companion accessors used by the layout/config codecs.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer {
    *** descriptor;
}
-keepclasseswithmembers class com.simonkaring.voltlink.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.simonkaring.voltlink.data.**$$serializer {
    *;
}

# Enum names are persisted in SharedPreferences (profile selection, unit choices).
-keepclassmembers enum com.simonkaring.voltlink.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
