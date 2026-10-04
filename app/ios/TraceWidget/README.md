# Trace iOS widget (spec F-15)

The Android widget ships with the app. On iOS a widget is a separate **Widget Extension target**,
which has to be added once in Xcode (it needs your signing team and an App Group):

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Widget Extension**. Product name `TraceWidget`, untick
   "Include Live Activity" and "Include Configuration App Intent". Embed in `Runner`.
3. Delete the Swift files Xcode generated in the new `TraceWidget` group and add
   `ios/TraceWidget/TraceWidget.swift` (this folder) to the `TraceWidget` target.
4. Select the **Runner** target → *Signing & Capabilities* → **+ Capability → App Groups** →
   add `group.app.trace.mobile`. Do the same for the **TraceWidget** target.
5. Set the TraceWidget target's iOS deployment target to 17.0 (for `containerBackground`).

The app already writes `nearby_count`, `nearest_teaser`, `nearest_distance` and `updated_at`
into that group and asks the widget to reload after every map refresh.

Live Activities (trail progress, relay deadline) and the App Clip need the same kind of
extension targets; see `TRACE_MVP.md` §14.
