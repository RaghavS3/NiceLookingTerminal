import AppKit
import Foundation
import MyTermCore
import SwiftUI

// MARK: - Pasteboard Image Helper

func pasteImageFromClipboard() -> Data? {
    let pasteboard = NSPasteboard.general
    return pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
}

// MARK: - Kanban Card

struct KanbanCardView: View {
    var card: KanbanCard
    @State private var isHovered = false

    let onDelete: () -> Void
    let onMoveForward: (() -> Void)?
    let onMoveBackward: (() -> Void)?
    let onPasteImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Screenshot attachment layer
            if let imgData = card.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 130)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }

            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(card.priority.color)
                        .frame(width: 5, height: 5)
                    Text(card.priority.rawValue.uppercased())
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(card.priority.color.opacity(0.2))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(card.priority.color.opacity(0.35), lineWidth: 1))

                Spacer()

                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: onPasteImage) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Attach screenshot from clipboard")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                }
            }

            Text(card.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            if !card.description.isEmpty {
                Text(card.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }

            // Movement Chevrons (Hover based Linear layout!)
            if isHovered {
                HStack(spacing: 6) {
                    if let onBack = onMoveBackward {
                        Button(action: onBack) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Back")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if let onForward = onMoveForward {
                        Button(action: onForward) {
                            HStack(spacing: 3) {
                                Text("Move")
                                    .font(.system(size: 8, weight: .bold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.blue.opacity(0.75))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color.white.opacity(isHovered ? 0.04 : 0.02))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(isHovered ? 0.08 : 0.04), lineWidth: 1))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Kanban Column View (Linear Glass Panels)

struct KanbanColumnView: View {
    @Binding var column: KanbanColumn
    let nextColumnAction: ((KanbanCard) -> Void)?
    let prevColumnAction: ((KanbanCard) -> Void)?
    let onPasteImage: (UUID) -> Void

    @State private var showAddCard = false
    @State private var newCardTitle = ""
    @State private var newCardDesc = ""
    @State private var newCardPriority = CardPriority.medium

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text(column.name.uppercased())
                    .font(.system(size: 11.5, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text("\(column.cards.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 4)

            // Scrollable cards panel
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(column.cards) { card in
                        KanbanCardView(
                            card: card,
                            onDelete: {
                                column.cards.removeAll { $0.id == card.id }
                            },
                            onMoveForward: nextColumnAction != nil
                                ? {
                                    nextColumnAction?(card)
                                } : nil,
                            onMoveBackward: prevColumnAction != nil
                                ? {
                                    prevColumnAction?(card)
                                } : nil,
                            onPasteImage: {
                                onPasteImage(card.id)
                            })
                    }

                    if showAddCard {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Card Title...", text: $newCardTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)

                            TextField("Details...", text: $newCardDesc)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)

                            HStack {
                                ForEach(CardPriority.allCases, id: \.self) { prio in
                                    Button(action: { newCardPriority = prio }) {
                                        Text(prio.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(newCardPriority == prio ? .white : .white.opacity(0.4))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(newCardPriority == prio ? Color.white.opacity(0.12) : Color.clear)
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)

                            HStack {
                                Button(action: {
                                    showAddCard = false
                                    newCardTitle = ""
                                    newCardDesc = ""
                                }) {
                                    Text("Cancel")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.03))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: {
                                    if !newCardTitle.isEmpty {
                                        let card = KanbanCard(title: newCardTitle, description: newCardDesc, priority: newCardPriority)
                                        column.cards.append(card)
                                    }
                                    showAddCard = false
                                    newCardTitle = ""
                                    newCardDesc = ""
                                }) {
                                    Text("Add Card")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.8))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    } else {
                        Button(action: { showAddCard = true }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("New Item")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 290)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.45)
                .cornerRadius(16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .onPasteCommand(of: [.text, .tiff]) { providers in
            let pb = NSPasteboard.general

            // 1. Handle Image Paste
            if (pb.types?.contains(.png) == true || pb.types?.contains(.tiff) == true), pasteImageFromClipboard() != nil {
                // If we have an existing card being hovered or just add to top
                if let card = column.cards.first {
                    onPasteImage(card.id)
                }
                return
            }

            if let text = pb.string(forType: .string) {
                for title in KanbanTextParser.cardTitles(from: text) {
                    column.cards.append(KanbanCard(title: title, description: "", priority: .medium))
                }
            }
        }
    }
}

// MARK: - Kanban Board Container

struct KanbanView: View {
    @ObservedObject var store: PlannerStore

    func pasteImageToCard(cardID: UUID) {
        if let data = pasteImageFromClipboard() {
            if let idx = store.todoColumn.cards.firstIndex(where: { $0.id == cardID }) {
                store.todoColumn.cards[idx].imageData = data
            } else if let idx = store.progressColumn.cards.firstIndex(where: { $0.id == cardID }) {
                store.progressColumn.cards[idx].imageData = data
            } else if let idx = store.doneColumn.cards.firstIndex(where: { $0.id == cardID }) {
                store.doneColumn.cards[idx].imageData = data
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            KanbanColumnView(
                column: $store.todoColumn,
                nextColumnAction: { card in
                    store.todoColumn.cards.removeAll { $0.id == card.id }
                    store.progressColumn.cards.append(card)
                }, prevColumnAction: nil, onPasteImage: pasteImageToCard)

            KanbanColumnView(
                column: $store.progressColumn,
                nextColumnAction: { card in
                    store.progressColumn.cards.removeAll { $0.id == card.id }
                    store.doneColumn.cards.append(card)
                },
                prevColumnAction: { card in
                    store.progressColumn.cards.removeAll { $0.id == card.id }
                    store.todoColumn.cards.append(card)
                }, onPasteImage: pasteImageToCard)

            KanbanColumnView(
                column: $store.doneColumn, nextColumnAction: nil,
                prevColumnAction: { card in
                    store.doneColumn.cards.removeAll { $0.id == card.id }
                    store.progressColumn.cards.append(card)
                }, onPasteImage: pasteImageToCard)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 8)
    }
}
