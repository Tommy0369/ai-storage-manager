import SwiftUI
import AppServices
import SafetyCore

@MainActor
public final class StorageViewModel: ObservableObject {
    @Published private(set) var overview: StorageOverviewState = .empty
    @Published private(set) var safeActions: [UICandidateItem] = []
    @Published private(set) var reviewNeeded: [UICandidateItem] = []
    @Published private(set) var protected: [UICandidateItem] = []
    @Published private(set) var recentActions: [UIActionHistoryItem] = []
    @Published private(set) var experienceSnapshot: StorageExperienceSnapshot?
    @Published private(set) var explorerSnapshot: StorageExplorerSnapshot?
    @Published private(set) var changeReport: StorageChangeReport?
    @Published private(set) var historyStatus: P302HistoryStatusReport?
    @Published var showChangeDetail = false
    @Published var showOptimizationPlan = false
    @Published var goalGigabytesText = "20"
    @Published private(set) var optimizationPlan: OptimizationPlan?
    @Published private(set) var scanStage: StorageScanStage = .idle
    @Published private(set) var isScanning = false
    @Published var selectedCandidateID: String?
    @Published var selectedMapNodeID: String?
    @Published private(set) var selectedMapNode: StorageMapNode?
    @Published private(set) var mapFocusPath: [StorageMapNode] = []
    @Published private(set) var mapFocusNode: StorageMapNode?
    @Published var selectedExplorerNodeID: String?
    @Published var hoveredExplorerNodeID: String?
    @Published private(set) var selectedExplorerNode: StorageNodePresentation?
    @Published private(set) var explorerFocusPath: [StorageNodePresentation] = []
    @Published private(set) var explorerFocusNode: StorageNodePresentation?
    @Published var mapLens: StorageMapLens = .structure
    @Published var explorerMode: ExplorerViewMode = .map
    @Published var explorerSearch: String = ""
    @Published private(set) var candidateDetail: UICandidateDetail?
    @Published private(set) var preflight: UIPreflightResult?
    @Published private(set) var isPreflighting = false
    @Published private(set) var pendingApproval: UIApprovalState?
    @Published var showApprovalSheet = false
    @Published private(set) var isExecuting = false
    @Published private(set) var executionOutcome: UIExecutionOutcome?
    @Published var errorMessage: String?

    @Published private(set) var actionFlowPhase: ProductActionFlowPhase = .idle
    private var presentationRequestID: UInt64 = 0
    private var presentationBinding = PresentationSelectionBinding(selectedEntityID: "", requestID: 0)

    private var explorerBackStack: [String] = []
    private var explorerForwardStack: [String] = []

    private let coordinator: any StorageActionCoordinating

    public init(coordinator: any StorageActionCoordinating) {
        self.coordinator = coordinator
        syncFromCoordinator()
    }

    var hoveredExplorerNode: StorageNodePresentation? {
        guard let id = hoveredExplorerNodeID, let root = explorerSnapshot?.presentedRoot else { return nil }
        return StorageExplorerBuilder.node(withID: id, in: root)
    }

    var canExplorerBack: Bool { !explorerBackStack.isEmpty }
    var canExplorerForward: Bool { !explorerForwardStack.isEmpty }

    func syncFromCoordinator() {
        overview = coordinator.overview
        safeActions = coordinator.safeActions
        reviewNeeded = coordinator.reviewNeeded
        protected = coordinator.protected
        recentActions = coordinator.recentActions
        isScanning = coordinator.isScanning
        experienceSnapshot = coordinator.experienceSnapshot
        explorerSnapshot = coordinator.explorerSnapshot
        changeReport = coordinator.changeReport
        historyStatus = coordinator.historyStatus
        scanStage = coordinator.scanStage
        if let plan = optimizationPlan, let currentID = coordinator.explorerSnapshot?.snapshotID {
            optimizationPlan = OptimizationPlanEngine.markStale(plan, currentSnapshotID: currentID)
        }
        if let latest = coordinator.optimizationPlan, optimizationPlan == nil {
            optimizationPlan = latest
        }
        preflight = coordinator.lastPreflight
        pendingApproval = coordinator.pendingApproval
        executionOutcome = coordinator.lastExecution
        if mapFocusNode == nil, let root = coordinator.experienceSnapshot?.mapRoot {
            mapFocusNode = root
            mapFocusPath = [root]
        }
        if explorerFocusNode == nil, let root = coordinator.explorerSnapshot?.presentedRoot {
            explorerFocusNode = root
            explorerFocusPath = [root]
            selectedExplorerNode = root
            selectedExplorerNodeID = root.id
        }
    }

    func scan() async {
        isScanning = true
        errorMessage = nil
        scanStage = .scanningFiles
        coordinator.scanProgressHandler = { [weak self] stage in
            DispatchQueue.main.async {
                self?.scanStage = stage
                self?.syncFromCoordinator()
                if stage == .hierarchyAvailable {
                    self?.resetExplorerFocusToRoot()
                }
            }
        }
        do {
            try await coordinator.scan()
            syncFromCoordinator()
            if let root = experienceSnapshot?.mapRoot {
                mapFocusNode = root
                mapFocusPath = [root]
            }
            resetExplorerFocusToRoot()
        } catch {
            errorMessage = error.localizedDescription
            scanStage = .failed
        }
        isScanning = false
        coordinator.scanProgressHandler = nil
    }

    func selectMapNode(_ node: StorageMapNode) {
        selectedMapNode = node
        selectedMapNodeID = node.id
        if let entityID = node.entityID {
            openCandidate(entityID)
        } else if !node.children.isEmpty {
            mapFocusNode = node
            if let root = experienceSnapshot?.mapRoot {
                mapFocusPath = buildPath(to: node, from: root) ?? [root, node]
            } else {
                mapFocusPath = [node]
            }
        }
    }

    func focusMapPath(_ index: Int) {
        guard index >= 0, index < mapFocusPath.count else { return }
        let node = mapFocusPath[index]
        mapFocusPath = Array(mapFocusPath.prefix(index + 1))
        mapFocusNode = node
        selectedMapNode = node
        selectedMapNodeID = node.id
    }

    func selectExplorerNode(_ node: StorageNodePresentation, drill: Bool) {
        selectedExplorerNode = node
        selectedExplorerNodeID = node.id
        if let entityID = node.decision.entityID ?? node.technicalEntityID {
            // Prefer opening only when decision source is canonical.
            if node.decision.source == "canonical_action_decision" {
                openCandidate(entityID)
            }
        }
        if drill, node.physical.isDirectory || node.physical.isAggregate {
            drillExplorer(to: node)
        }
    }

    func focusExplorerNode(_ node: StorageNodePresentation) {
        guard let root = explorerSnapshot?.presentedRoot,
              let path = StorageExplorerBuilder.pathTo(id: node.id, in: root) else { return }
        if let current = explorerFocusNode {
            explorerBackStack.append(current.id)
            explorerForwardStack.removeAll()
        }
        explorerFocusPath = path
        explorerFocusNode = node
        selectedExplorerNode = node
        selectedExplorerNodeID = node.id
        if node.physical.children.isEmpty, node.physical.isDirectory, !node.physical.isPackage {
            coordinator.expandPhysicalNode(id: node.id)
            syncFromCoordinator()
            if let refreshed = explorerSnapshot.flatMap({ StorageExplorerBuilder.node(withID: node.id, in: $0.presentedRoot) }) {
                explorerFocusNode = refreshed
                selectedExplorerNode = refreshed
                if let path = StorageExplorerBuilder.pathTo(id: node.id, in: explorerSnapshot!.presentedRoot) {
                    explorerFocusPath = path
                }
            }
        }
    }

    func focusExplorerPath(_ index: Int) {
        guard index >= 0, index < explorerFocusPath.count else { return }
        if let current = explorerFocusNode {
            explorerBackStack.append(current.id)
            explorerForwardStack.removeAll()
        }
        explorerFocusPath = Array(explorerFocusPath.prefix(index + 1))
        let node = explorerFocusPath[index]
        explorerFocusNode = node
        selectedExplorerNode = node
        selectedExplorerNodeID = node.id
    }

    func explorerBack() {
        guard let previousID = explorerBackStack.popLast(),
              let root = explorerSnapshot?.presentedRoot,
              let node = StorageExplorerBuilder.node(withID: previousID, in: root) else { return }
        if let current = explorerFocusNode {
            explorerForwardStack.append(current.id)
        }
        applyExplorerFocus(node)
    }

    func explorerForward() {
        guard let nextID = explorerForwardStack.popLast(),
              let root = explorerSnapshot?.presentedRoot,
              let node = StorageExplorerBuilder.node(withID: nextID, in: root) else { return }
        if let current = explorerFocusNode {
            explorerBackStack.append(current.id)
        }
        applyExplorerFocus(node)
    }

    func explorerGoUp() {
        guard explorerFocusPath.count > 1 else { return }
        focusExplorerPath(explorerFocusPath.count - 2)
    }

    func openCandidate(_ entityID: String) {
        selectedCandidateID = entityID
        presentationRequestID &+= 1
        presentationBinding = PresentationSelectionBinding(
            selectedEntityID: entityID,
            requestID: presentationRequestID
        )
        actionFlowPhase = .reviewing
        candidateDetail = coordinator.candidateDetail(entityID: entityID)
        preflight = nil
        pendingApproval = nil
        executionOutcome = nil
        showApprovalSheet = false
    }

    /// Apply async presentation/detail only if selection binding still matches.
    func applyAsyncPresentation(entityID: String, requestID: UInt64, detail: UICandidateDetail?) {
        guard presentationBinding.accepts(responseEntityID: entityID, responseRequestID: requestID) else {
            return
        }
        candidateDetail = detail
    }

    func runPreflight(action: StorageAction = .moveToTrash) async {
        guard let entityID = selectedCandidateID else { return }
        let requestID = presentationRequestID
        isPreflighting = true
        actionFlowPhase = .preflighting
        errorMessage = nil
        do {
            let result = try await coordinator.runFreshPreflight(entityID: entityID, action: action)
            guard presentationBinding.accepts(responseEntityID: entityID, responseRequestID: requestID) else {
                isPreflighting = false
                return
            }
            preflight = result
            if result.canApprove {
                actionFlowPhase = .awaitingApproval
            } else if result.userMessage.localizedCaseInsensitiveContains("changed") {
                actionFlowPhase = .needsReviewAgain
                errorMessage = ProductCopy.somethingChanged
            } else {
                actionFlowPhase = .failedSafe
            }
            syncFromCoordinator()
        } catch {
            if presentationBinding.accepts(responseEntityID: entityID, responseRequestID: requestID) {
                errorMessage = error.localizedDescription
                actionFlowPhase = .failedSafe
            }
        }
        isPreflighting = false
    }

    func presentApproval(action: StorageAction = .moveToTrash) {
        guard preflight?.canApprove == true else { return }
        showApprovalSheet = true
    }

    func confirmApproval(action: StorageAction = .moveToTrash) {
        guard let entityID = selectedCandidateID else { return }
        do {
            pendingApproval = try coordinator.submitApproval(entityID: entityID, action: action)
            showApprovalSheet = false
            syncFromCoordinator()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelApproval() {
        coordinator.cancelApproval()
        showApprovalSheet = false
        syncFromCoordinator()
    }

    func execute(action: StorageAction = .moveToTrash) async {
        guard let entityID = selectedCandidateID, pendingApproval != nil else { return }
        isExecuting = true
        errorMessage = nil
        do {
            executionOutcome = try await coordinator.executeApprovedAction(entityID: entityID, action: action)
            syncFromCoordinator()
            recentActions = coordinator.recentActions
        } catch StorageActionCoordinatorError.bindingChanged {
            errorMessage = "This item changed after your safety check. Nothing was moved."
            pendingApproval = nil
            preflight = nil
        } catch StorageActionCoordinatorError.candidateDisappeared {
            errorMessage = "This item changed or no longer exists."
            pendingApproval = nil
            preflight = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isExecuting = false
        if let outcome = executionOutcome, let plan = optimizationPlan {
            optimizationPlan = OptimizationPlanEngine.applyCompletion(plan, entityID: entityID, outcome: outcome)
        }
    }

    var canMoveToTrash: Bool {
        pendingApproval != nil && !isExecuting
    }

    func buildOptimizationPlan(gigabytes: Int? = nil) {
        if let gigabytes {
            goalGigabytesText = "\(gigabytes)"
        }
        let parsed = Int(goalGigabytesText.trimmingCharacters(in: .whitespaces)) ?? 0
        guard parsed > 0 else {
            errorMessage = "Enter a positive storage goal in GB."
            return
        }
        guard scanStage == .complete, !safeActions.isEmpty || !reviewNeeded.isEmpty || !protected.isEmpty else {
            errorMessage = ProductCopy.finishSafetyFirst
            showOptimizationPlan = true
            return
        }
        do {
            let goal = try OptimizationGoal.gigabytes(parsed)
            optimizationPlan = OptimizationPlanService.build(
                goal: goal,
                snapshot: experienceSnapshot,
                explorer: explorerSnapshot,
                safe: safeActions,
                review: reviewNeeded,
                protected: protected,
                extraFacts: coordinator.optimizationFacts,
                changeReport: changeReport,
                history: recentActions,
                falseGREEN: 0,
                duplicateEvaluations: 0
            )
            showOptimizationPlan = true
        } catch {
            errorMessage = "Enter a positive storage goal in GB."
        }
    }

    func removeFromOptimizationPlan(entityID: String) {
        guard let plan = optimizationPlan else { return }
        optimizationPlan = OptimizationPlanEngine.removing(entityID: entityID, from: plan)
    }

    func adoptPlan(_ plan: OptimizationPlan) {
        optimizationPlan = plan
    }

    var moveButtonDisabledReason: String? {
        if isExecuting { return "Action in progress" }
        if pendingApproval == nil { return "Complete safety check and approval first" }
        return nil
    }

    private func drillExplorer(to node: StorageNodePresentation) {
        focusExplorerNode(node)
    }

    private func applyExplorerFocus(_ node: StorageNodePresentation) {
        guard let root = explorerSnapshot?.presentedRoot,
              let path = StorageExplorerBuilder.pathTo(id: node.id, in: root) else { return }
        explorerFocusPath = path
        explorerFocusNode = node
        selectedExplorerNode = node
        selectedExplorerNodeID = node.id
    }

    private func resetExplorerFocusToRoot() {
        guard let root = coordinator.explorerSnapshot?.presentedRoot ?? explorerSnapshot?.presentedRoot else { return }
        explorerSnapshot = coordinator.explorerSnapshot
        explorerFocusNode = root
        explorerFocusPath = [root]
        selectedExplorerNode = root
        selectedExplorerNodeID = root.id
        explorerBackStack.removeAll()
        explorerForwardStack.removeAll()
    }

    private func buildPath(to target: StorageMapNode, from root: StorageMapNode) -> [StorageMapNode]? {
        if root.id == target.id { return [root] }
        for child in root.children {
            if child.id == target.id { return [root, child] }
            if let sub = buildPath(to: target, from: child) {
                return [root] + sub
            }
        }
        return nil
    }
}
