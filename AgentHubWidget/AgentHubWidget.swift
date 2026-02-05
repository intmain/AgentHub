import WidgetKit
import SwiftUI

@main
struct AgentHubWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentHubWidget()
    }
}

struct AgentHubWidget: Widget {
    let kind: String = "AgentHubWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionTimelineProvider()) { entry in
            AgentHubWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AgentHub")
        .description("AI 에이전트 세션 모니터링")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry View

struct AgentHubWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SessionTimelineProvider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

#Preview(as: .systemSmall) {
    AgentHubWidget()
} timeline: {
    SessionEntry(date: Date(), summary: nil, sessions: [])
}

#Preview(as: .systemMedium) {
    AgentHubWidget()
} timeline: {
    SessionEntry(date: Date(), summary: nil, sessions: [])
}

#Preview(as: .systemLarge) {
    AgentHubWidget()
} timeline: {
    SessionEntry(date: Date(), summary: nil, sessions: [])
}
