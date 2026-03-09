import Foundation

@MainActor
class CourseIntelligenceViewModel: ObservableObject {
    @Published var insights: CourseInsights?
    @Published var state: ViewState = .idle
    
    private let apiService = APIService.shared
    private var holeShotLookup: [Int: [CourseInsights.HoleShot]] = [:]
    
    // Legacy computed properties for backward compatibility
    var isLoading: Bool {
        state == .loading
    }
    
    var errorMessage: String? {
        state.errorMessage
    }
    
    func fetchInsights(courseId: String) async {
        state = .loading
        
        do {
            let insights = try await apiService.fetchCourseInsights(courseId: courseId)
            self.insights = insights
            self.holeShotLookup = Dictionary(
                uniqueKeysWithValues: insights.holeDetails.map { ($0.hole, $0.shots) }
            )
            state = .loaded
        } catch {
            state = .error("Failed to load insights: \(error.localizedDescription)")
            print("Error fetching insights: \(error)")
        }
    }
    
    func shots(for hole: Int) -> [CourseInsights.HoleShot] {
        holeShotLookup[hole] ?? []
    }
}

