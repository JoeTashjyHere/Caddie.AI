//
//  ProfileView.swift
//  Caddie.ai
//
//  Profile view for setting club distances and tendencies
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: ProfileViewModel
    @State private var showingAddClub = false
    @State private var newClubName = ""
    @State private var newClubYards = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Shot Preferences") {
                    TextField("Preferred Shot Shape", text: $viewModel.profile.preferredShotShape)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Miss Left: \(Int(viewModel.profile.missesLeftPct))%")
                        Slider(value: $viewModel.profile.missesLeftPct, in: 0...100, step: 1)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Miss Right: \(Int(viewModel.profile.missesRightPct))%")
                        Slider(value: $viewModel.profile.missesRightPct, in: 0...100, step: 1)
                    }
                }
                
                Section("Club Distances") {
                    ForEach($viewModel.profile.clubs) { $club in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Club Name", text: $club.name)
                                .font(.headline)
                            
                            HStack {
                                Text("Carry Yards:")
                                Spacer()
                                TextField("Yards", value: $club.carryYards, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        viewModel.profile.clubs.remove(atOffsets: indexSet)
                    }
                    
                    Button(action: { showingAddClub = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Club")
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        viewModel.saveProfile()
                    }) {
                        HStack {
                            Spacer()
                            Text("Save Profile")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingAddClub) {
                NavigationView {
                    Form {
                        Section("New Club") {
                            TextField("Club Name", text: $newClubName)
                            TextField("Carry Yards", text: $newClubYards)
                                .keyboardType(.numberPad)
                        }
                    }
                    .navigationTitle("Add Club")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingAddClub = false
                                newClubName = ""
                                newClubYards = ""
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Add") {
                                if let yards = Int(newClubYards), !newClubName.isEmpty {
                                    viewModel.profile.clubs.append(
                                        ClubDistance(name: newClubName, carryYards: yards)
                                    )
                                    showingAddClub = false
                                    newClubName = ""
                                    newClubYards = ""
                                }
                            }
                            .disabled(newClubName.isEmpty || Int(newClubYards) == nil)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(ProfileViewModel())
}

