# Garmin Connect unmarshals these Parcelables in a separate app process.
# Keep their class names stable across the Binder/Intent boundary.
-keepnames class com.garmin.android.connectiq.** implements android.os.Parcelable
