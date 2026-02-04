//
//  OpenAIChatView.swift
//  V4MinimalApp
//
//  Chat UI for OpenAI Chat Completions with streamed responses
//

import SwiftUI

struct OpenAIChatView: View {
    @StateObject private var chatService = OpenAIChatService()
    @State private var inputText: String = ""
    @State private var showingLog = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Response area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !chatService.isConfigured {
                            apiKeyWarning
                        }

                        if chatService.requestLog.isEmpty && chatService.responseText.isEmpty {
                            emptyState
                        }

                        // Chat messages
                        ForEach(chatService.requestLog) { entry in
                            chatBubble(entry)
                        }

                        // Live streaming response (not yet in log)
                        if chatService.isStreaming && !chatService.responseText.isEmpty {
                            liveBubble
                        }

                        // Error display
                        if let error = chatService.error {
                            errorBanner(error)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .onChange(of: chatService.responseText) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: chatService.requestLog.count) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input bar
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("OpenAI Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingLog.toggle()
                    } label: {
                        Label("Request Log", systemImage: "list.bullet.rectangle")
                    }

                    Button(role: .destructive) {
                        chatService.clearConversation()
                    } label: {
                        Label("Clear Conversation", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingLog) {
            requestLogSheet
        }
    }

    // MARK: - Subviews

    private var apiKeyWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("OpenAI API key not configured. Add OPENAI_API_KEY to Secrets.xcconfig.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Send a message to start chatting")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func chatBubble(_ entry: ChatLogEntry) -> some View {
        HStack {
            if entry.role == "user" { Spacer(minLength: 48) }

            VStack(alignment: entry.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(entry.content)
                    .font(.body)
                    .padding(12)
                    .background(entry.role == "user" ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(entry.role == "user" ? .white : .primary)
                    .cornerRadius(16)

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if entry.role == "assistant" { Spacer(minLength: 48) }
        }
    }

    private var liveBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(chatService.responseText)
                        .font(.body)

                    if chatService.isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
            }

            Spacer(minLength: 48)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: chatService.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.accentColor : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatService.isStreaming
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isStreaming else { return }
        inputText = ""
        Task {
            await chatService.sendMessage(text)
        }
    }

    // MARK: - Request Log Sheet

    private var requestLogSheet: some View {
        NavigationStack {
            List {
                if chatService.requestLog.isEmpty {
                    Text("No requests yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chatService.requestLog) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.role.uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(entry.role == "user" ? .blue : .green)

                                Spacer()

                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.content)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(10)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Request Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingLog = false
                    }
                }
            }
        }
    }
}
