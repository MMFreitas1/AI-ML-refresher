# kotlinx.serialization: keep generated serializers for the stored JSON models.
-keepattributes *Annotation*, InnerClasses
-keep,includedescriptorclasses class com.mmfreitas.aibrief.core.**$$serializer { *; }
-keepclassmembers class com.mmfreitas.aibrief.core.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
