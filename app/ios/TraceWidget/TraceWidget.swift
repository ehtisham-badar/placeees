import SwiftUI
import WidgetKit

/// "N drops waiting within 500 m" (spec F-15). The app writes the numbers via home_widget into the
/// shared app group; this extension only reads them.
private let appGroup = "group.app.trace.mobile"

struct NearbyEntry: TimelineEntry {
  let date: Date
  let count: Int
  let teaser: String
  let distance: String
  let updatedAt: Date?
}

struct NearbyProvider: TimelineProvider {
  func placeholder(in context: Context) -> NearbyEntry {
    NearbyEntry(date: .now, count: 3, teaser: "Best seat for the 6pm light.", distance: "120 m", updatedAt: .now)
  }

  func getSnapshot(in context: Context, completion: @escaping (NearbyEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : read())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyEntry>) -> Void) {
    // The app reloads the widget whenever it refreshes the map; no polling needed.
    completion(Timeline(entries: [read()], policy: .never))
  }

  private func read() -> NearbyEntry {
    let d = UserDefaults(suiteName: appGroup)
    let ms = d?.object(forKey: "updated_at") as? Int ?? 0
    return NearbyEntry(
      date: .now,
      count: d?.integer(forKey: "nearby_count") ?? 0,
      teaser: d?.string(forKey: "nearest_teaser") ?? "",
      distance: d?.string(forKey: "nearest_distance") ?? "",
      updatedAt: ms > 0 ? Date(timeIntervalSince1970: Double(ms) / 1000) : nil
    )
  }
}

private extension Color {
  static let ink = Color(red: 0.04, green: 0.05, blue: 0.07)
  static let ember = Color(red: 1.0, green: 0.48, blue: 0.30)
  static let sun = Color(red: 1.0, green: 0.71, blue: 0.28)
  static let muted = Color(red: 0.56, green: 0.59, blue: 0.65)
}

struct TraceWidgetView: View {
  let entry: NearbyEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Circle().fill(Color.ember).frame(width: 8, height: 8).shadow(color: .ember, radius: 4)
        Text("trace").font(.system(.footnote, design: .serif)).italic()
      }
      Text(entry.count == 0 ? "–" : "\(entry.count)")
        .font(.system(size: 36, weight: .medium, design: .serif))
        .foregroundStyle(Color.ember)
      Text(entry.count == 1 ? "drop within 500 m" : entry.count == 0 ? "Nothing within 500 m yet" : "drops within 500 m")
        .font(.caption.bold())
      if !entry.teaser.isEmpty {
        Text("“\(entry.teaser)”").font(.system(.caption, design: .serif)).italic().foregroundStyle(Color.sun).lineLimit(2)
      }
      Spacer(minLength: 0)
      if let updated = entry.updatedAt {
        Text(updated, style: .relative).font(.caption2).foregroundStyle(Color.muted)
      }
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .containerBackground(for: .widget) {
      LinearGradient(colors: [Color(red: 0.11, green: 0.09, blue: 0.08), .ink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }
}

@main
struct TraceWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TraceWidget", provider: NearbyProvider()) { entry in
      TraceWidgetView(entry: entry)
    }
    .configurationDisplayName("Nearby drops")
    .description("How many drops are waiting near you.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
