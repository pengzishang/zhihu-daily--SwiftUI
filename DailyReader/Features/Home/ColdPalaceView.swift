import SwiftUI

struct ColdPalaceView: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        List {
            if viewModel.hiddenStories.isEmpty {
                ContentUnavailableView(
                    "冷宫空空如也",
                    systemImage: "snowflake",
                    description: Text("在日报列表中左滑，点击“不感兴趣”即可将文章移入冷宫。")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.hiddenSections) { section in
                    Section {
                        ForEach(section.stories) { story in
                            NavigationLink {
                                ArticleDetailView(story: story, homeViewModel: viewModel, source: .coldPalace, date: section.date)
                            } label: {
                                StoryRowView(story: story, isRead: viewModel.isStoryRead(story.id))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(DS.hairline)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    viewModel.restoreStory(story.id)
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(DS.indigo)
                            }
                        }
                    } header: {
                        DatelineHeader(date: section.date, storyCount: section.stories.count)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
                    }
                }
            }
        }
        .listStyle(.plain)
        .paperListBackground()
        .navigationTitle("冷宫")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.hiddenStories.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("恢复全部") {
                        viewModel.restoreAllHidden()
                    }
                    .font(DS.songBold(15))
                    .foregroundStyle(DS.indigo)
                    .accessibilityLabel("恢复全部冷宫文章")
                }
            }
        }
    }
}
