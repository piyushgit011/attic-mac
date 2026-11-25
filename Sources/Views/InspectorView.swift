import SwiftUI

struct InspectorView: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library
    @Environment(OCRIndex.self) private var ocr

    var body: some View {
        if let url = nav.focused ?? nav.selection.first, let item = library.item(for: url) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ThumbView(url: item.url, side: 280)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { nav.quickLook(item.url, in: [item.url]) }
                    Text(item.name).font(.headline).textSelection(.enabled)
                    Text(item.kind).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        row("Size", Fmt.bytes(item.size) + (item.allocatedSize != item.size ? " (\(Fmt.bytes(item.allocatedSize)) on disk)" : ""))
                        row("Added", Fmt.date(item.arrivalDate))
                        row("Modified", Fmt.date(item.modified))
                        if let a = item.accessed { row("Last opened", Fmt.date(a)) }
                        if let s = item.source { row("From", s) }
                        row("Where", Fmt.path(item.url.deletingLastPathComponent()))
                    }
                    .font(.callout)
                    if let link = item.whereFroms.first, let u = URL(string: link) {
                        Link(destination: u) { Label(u.host ?? link, systemImage: "link") }.font(.callout)
                    }
                    if let text = ocr.text(for: item.url), !text.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Text in image").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(text).font(.callout).textSelection(.enabled).lineLimit(12)
                        }
                    }
                    HStack {
                        Button("Open") { FileActions.open([item]) }
                        Button("Show in Finder") { FileActions.reveal([item]) }
                    }
                    if !item.url.isAtticStub {
                        Button { nav.offloadRequest = [item] } label: { Label("Offload to R2 or iCloud…", systemImage: "icloud.and.arrow.up") }
                    }
                }
                .padding(16)
            }
        } else {
            EmptyStateView(symbol: "sidebar.right", title: "No selection", message: "Select a file to see its details.")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled).lineLimit(3)
        }
    }
}
