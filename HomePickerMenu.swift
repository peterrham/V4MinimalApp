//
//  HomePickerMenu.swift
//  V4MinimalApp
//
//  Reusable home-switching dropdown menu for toolbars
//

import SwiftUI

struct HomePickerMenu: View {
    @EnvironmentObject var inventoryStore: InventoryStore

    var body: some View {
        if inventoryStore.homes.count > 1 {
            Menu {
                ForEach(inventoryStore.homes) { home in
                    Button {
                        inventoryStore.switchHome(to: home.id)
                    } label: {
                        HStack {
                            Label(home.name, systemImage: home.icon)
                            if home.id == inventoryStore.currentHomeId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: inventoryStore.currentHome?.icon ?? "house.fill")
                        .font(.caption)
                    Text(inventoryStore.currentHome?.name ?? "Home")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(AppTheme.Colors.primary)
            }
        }
    }
}
