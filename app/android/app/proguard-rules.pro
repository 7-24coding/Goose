# Keep Go mobile runtime & sequences
-keep class go.** { *; }
-keep class android.** { *; }
-keep class Seq.** { *; }

# Keep methods called via JNI
-keepclassmembers class * {
    native <methods>;
}
