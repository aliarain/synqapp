
//  ReflectionSelectionView.swift
//  Spill — scope picker before entering voice session

import SwiftUI
import SynqCore

struct ReflectionSelectionView: View {

    @ObservedObject var vm: AppViewModel
    let colorScheme: ColorScheme

    private let scopes: [ReflectionScope] = [.session, .week, .month]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            // Back button
            Button {
                vm.backToWriting()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back to Writing")
                }
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.leading, 20)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

            // Center content
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Reflect")
                        .font(.largeTitle)
                        .fontWeight(.medium)
                    Text("Choose what you'd like to reflect on")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                VStack(spacing: 20) {
                    ForEach(scopes, id: \.title) { scope in
                        ReflectionTimeButton(scope: scope, colorScheme: colorScheme) {
                            vm.selectScope(scope)
                        }
                    }
                }
                .frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 80)
        }
    }
}

// MARK: - Card button

struct ReflectionTimeButton: View {

    let scope: ReflectionScope
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var hovering = false

    private var bgColor: Color {
        let base: Double = hovering ? 0.2 : 0.1
        return colorScheme == .dark
            ? Color.white.opacity(base)
            : Color.gray.opacity(base)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(scope.title)
                    .font(.title2)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(scope.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.2)) { hovering = h }
            h ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
    }
}
