# youtubedl-android: Jackson (reflection) parses the updater's GitHub API response.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**
-dontwarn java.beans.**

# Unpacking the bundled Python/ffmpeg uses Apache Commons Compress, which registers its zip
# extra-field classes in a static table and instantiates them reflectively. Without this,
# release builds fail on first launch with "ExceptionInInitializerError ... is not a concrete class".
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**
-keep class org.apache.commons.io.** { *; }
-dontwarn org.apache.commons.io.**
