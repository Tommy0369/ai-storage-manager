import XCTest
@testable import SafetyCore

final class P113RuntimeBatchResolutionTests: XCTestCase {
    private func claudeEntity(path: String, id: String = "claude.vm.test") -> DetectedEntity {
        DetectedEntity(
            entity: StorageEntity(
                id: id,
                kind: .applicationSupport,
                category: "AI",
                subcategory: "CLAUDE",
                displayName: "Claude VM",
                path: path,
                logicalBytes: 1_000_000
            ),
            bucket: .userData,
            domain: "AI Tools",
            associatedProcesses: ["Claude"],
            identified: true,
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 90,
                semanticType: "CLAUDE_VM",
                lifecycle: LifecycleEvidence(role: .runtime, roleConfidence: .verified, activeState: .unknown)
            )
        )
    }

    private func derivedEntity(path: String) -> DetectedEntity {
        DetectedEntity(
            entity: StorageEntity(
                id: "xcode.deriveddata.test",
                kind: .generatedBuild,
                category: "DEV",
                subcategory: "XCODE",
                displayName: "DerivedData",
                path: path,
                logicalBytes: 36_000_000
            ),
            bucket: .generated,
            domain: "Developer",
            associatedProcesses: ["Xcode"],
            identified: true,
            annotation: nil
        )
    }

    private func gitEntity(path: String) -> DetectedEntity {
        DetectedEntity(
            entity: StorageEntity(
                id: "git.repo.test",
                kind: .gitMetadata,
                category: "DEV",
                subcategory: "GIT",
                displayName: "Git Repo",
                path: path,
                logicalBytes: 500_000
            ),
            bucket: .developer,
            domain: "Developer",
            associatedProcesses: [],
            identified: true,
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 80,
                semanticType: "GIT_REPOSITORY",
                lifecycle: LifecycleEvidence(role: .history, roleConfidence: .verified, activeState: .unknown)
            )
        )
    }

    private func makeIndex(
        openPaths: [String] = [],
        commandLines: [String] = [],
        processNames: Set<String> = [],
        processComplete: ObservationCompleteness = .complete,
        handleComplete: ObservationCompleteness = .complete,
        processFailed: Bool = false,
        handleFailed: Bool = false
    ) -> RuntimeObservationIndex {
        let processes = ProcessTableSnapshot(
            names: processNames,
            commandLines: commandLines,
            snapshotFailed: processFailed,
            failureReason: processFailed ? "PS_FAILED" : nil,
            completeness: processComplete
        )
        let handles = OpenFileSnapshot(
            openPaths: openPaths,
            snapshotFailed: handleFailed,
            failureReason: handleFailed ? "LSOF_TIMEOUT" : nil,
            completeness: handleComplete
        )
        return RuntimeObservationIndex.build(processes: processes, handles: handles)
    }

    func testIndexBuiltOnceServesManyEntities() {
        let target = "/tmp/vm_bundles/a.bundle/rootfs.img"
        let sibling = "/tmp/vm_bundles/b.bundle/rootfs.img"
        let index = makeIndex(openPaths: [target])
        let entityA = claudeEntity(path: target, id: "claude.vm.a")
        let entityB = claudeEntity(path: sibling, id: "claude.vm.b")
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let a = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entityA,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entityA),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        let b = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entityB,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entityB),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        XCTAssertEqual(a.activeState, ObservedActiveState.active)
        XCTAssertEqual(a.activeStateConfidence, EvidenceConfidence.verified)
        XCTAssertEqual(b.activeState, ObservedActiveState.inactive)
        XCTAssertEqual(b.activeStateConfidence, EvidenceConfidence.verified)
    }

    func testParentOpenDoesNotMatchChildEntity() {
        let parent = "/tmp/vm_bundles"
        let child = "/tmp/vm_bundles/a.bundle"
        let index = makeIndex(openPaths: [parent])
        let entity = claudeEntity(path: child)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let resolved = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        XCTAssertNotEqual(resolved.activeState, ObservedActiveState.active)
        XCTAssertNotEqual(resolved.openFileHandle, PredicateValue.true)
    }

    func testSiblingOpenDoesNotMatchTargetEntity() {
        let target = "/tmp/vm_bundles/a.bundle/rootfs.img"
        let sibling = "/tmp/vm_bundles/b.bundle/rootfs.img"
        let index = makeIndex(openPaths: [sibling])
        let entity = claudeEntity(path: target)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let resolved = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        XCTAssertNotEqual(resolved.activeState, ObservedActiveState.active)
    }

    func testClaudeProcessOnlyInsufficientForInactiveVerified() {
        let target = "/tmp/vm_bundles/a.bundle/rootfs.img"
        let index = makeIndex(commandLines: ["/Applications/Claude.app/Contents/MacOS/Claude"], processNames: ["Claude"])
        let entity = claudeEntity(path: target)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let resolved = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        XCTAssertNotEqual(resolved.activeStateConfidence, EvidenceConfidence.verified)
        XCTAssertNotEqual(resolved.activeState, ObservedActiveState.inactive)
    }

    func testPartialProcessSnapshotCannotProveInactive() {
        let path = "/tmp/DerivedData/App-abc"
        let index = makeIndex(processNames: [], processComplete: .partial)
        let entity = derivedEntity(path: path)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let resolved = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .partial,
            handleCompleteness: .complete,
            plan: plan
        )
        XCTAssertNotEqual(resolved.activeState, ObservedActiveState.inactive)
        XCTAssertNotEqual(resolved.activeStateConfidence, EvidenceConfidence.verified)
    }

    func testLsofTimeoutCannotProveInactive() {
        let path = "/tmp/DerivedData/App-abc"
        let index = makeIndex(processNames: ["Xcode"], handleComplete: .partial, handleFailed: true)
        let entity = derivedEntity(path: path)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let resolved = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .partial,
            plan: plan
        )
        XCTAssertNotEqual(resolved.activeState, ObservedActiveState.inactive)
        XCTAssertEqual(resolved.openFileHandle, PredicateValue.unknown)
    }

    func testCompleteSnapshotsNoMatchCanProveInactiveForDerivedData() {
        let path = "/tmp/DerivedData/App-abc"
        let index = makeIndex(openPaths: [], processNames: [])
        let entity = derivedEntity(path: path)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let resolved = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        XCTAssertEqual(resolved.activeState, ObservedActiveState.inactive)
        XCTAssertEqual(resolved.activeStateConfidence, EvidenceConfidence.verified)
        XCTAssertEqual(resolved.openFileHandle, PredicateValue.false)
    }

    func testExactArgvPathCanProveActive() {
        let path = "/tmp/vm_bundles/a.bundle/rootfs.img"
        let index = makeIndex(commandLines: ["/Applications/Claude.app/Contents/MacOS/Claude --bundle \(path)"])
        let entity = claudeEntity(path: path)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let resolved = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        XCTAssertEqual(resolved.activeState, ObservedActiveState.active)
        XCTAssertEqual(resolved.activeStateConfidence, EvidenceConfidence.verified)
    }

    func testDeferredIsNotInactiveEvidence() {
        let entity = gitEntity(path: "/tmp/projects/my-repo/.git")
        let knowledge = KnowledgeBaseDocument(version: "t", principle: "t", rules: [])
        let index = SafetyRuleIndex(knowledge: knowledge)
        let plan = RuntimeResolutionNeedPlanner.plan(
            entity: entity,
            ruleIndex: index,
            verification: VerificationAnnotation()
        )
        XCTAssertEqual(plan.need, .notRequiredForCurrentDecision)
        let batch = RuntimeStateBatchResolver.resolveAll(
            entities: [entity],
            verifications: [entity.entity.id: VerificationAnnotation()],
            plans: [entity.entity.id: plan],
            index: makeIndex(),
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        let resolution = batch.resolutions[entity.entity.id]
        XCTAssertEqual(resolution?.disposition, .deferred)
        XCTAssertNotEqual(resolution?.activeStateConfidence, EvidenceConfidence.verified)
        XCTAssertEqual(resolution?.openFileHandle, PredicateValue.unknown)
    }

    func testDerivedDataRuntimeRequiredNotDeferred() {
        let entity = derivedEntity(path: "/tmp/DerivedData/App-abc")
        let knowledge = KnowledgeBaseDocument(
            version: "t",
            principle: "t",
            rules: [
                SafetyRule(
                    id: "test.derived",
                    entity: "derived",
                    category: "DEV",
                    subcategory: "XCODE",
                    match: RuleMatch(path: "**/DerivedData/**"),
                    defaultClass: .green,
                    baseScore: 95,
                    evaluationLayer: .exactVendor,
                    sourceOfTruth: false,
                    regenerable: true,
                    networkRequired: false,
                    requiredPredicates: ["not_source_of_truth", "regenerable", "no_open_file_handle"],
                    demoteToYellowIf: [],
                    demoteToRedIf: [],
                    hardBlockIf: [],
                    actionMode: .moveToTrash,
                    effects: [],
                    verification: [],
                    growthCauses: [],
                    explanationJA: "DerivedData",
                    reasonCodes: ["GENERATED_DATA"]
                ),
            ]
        )
        let index = SafetyRuleIndex(knowledge: knowledge)
        let plan = RuntimeResolutionNeedPlanner.plan(
            entity: entity,
            ruleIndex: index,
            verification: VerificationAnnotation()
        )
        XCTAssertEqual(plan.need, .requiredNow)
        XCTAssertTrue(plan.needsActive)
        XCTAssertTrue(plan.needsOpenFile)
    }

    func testReferenceEquivalenceBatchVsActiveStateResolver() {
        let path = "/tmp/DerivedData/App-abc"
        let entity = derivedEntity(path: path)
        let processes = ProcessTableSnapshot(
            names: ["Xcode"],
            commandLines: [],
            snapshotFailed: false,
            failureReason: nil,
            completeness: .complete
        )
        let handles = OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        let index = RuntimeObservationIndex.build(processes: processes, handles: handles)
        let plan = RuntimeRequirementPlan(needsActive: true, needsOpenFile: true, need: .requiredNow, deferReason: nil, deferReasons: [])
        let batch = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: entity,
            relatedPaths: [],
            contract: RuntimeSensitiveContract.forEntity(entity),
            index: index,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            plan: plan
        )
        let reference = RuntimeStateBatchResolver.resolveReference(
            entity: entity,
            processes: processes,
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertEqual(batch.activeState, reference.0)
        XCTAssertEqual(batch.activeStateConfidence, reference.1)
    }

    func testDeferredDoesNotSatisfyStrictPredicate() {
        let entity = gitEntity(path: "/tmp/projects/repo/.git")
        let resolution = RuntimeStateResolution(
            entityID: entity.entity.id,
            disposition: .deferred,
            deferReason: .relocationContractMissing,
            activeState: .unknown,
            activeStateConfidence: .unknown,
            activeStateCompleteness: .unknown,
            openFileHandle: .unknown,
            openFileConfidence: .unknown,
            unknownReasons: ["DEFERRED:RELOCATION_CONTRACT_MISSING"],
            lookupMs: 0
        )
        var evidence = EvidenceBundle(canonicalPath: entity.entity.path)
        EntitySafetySnapshotBuilder.applySnapshotConfidence(
            &evidence,
            entity: entity,
            context: VerificationLoopContext(
                resolver: EvidenceResolver(
                    processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
                    handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil)
                ),
                processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
                handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
                processCompleteness: .complete,
                handleCompleteness: .complete,
                proofTargets: []
            ),
            cache: EvidenceResolutionCache(),
            runtimeResolution: resolution,
            runtimeIndex: nil
        )
        XCTAssertEqual(evidence.openFileHandle, PredicateValue.unknown)
        XCTAssertFalse(evidence.satisfiesStrictPredicate("no_open_file_handle"))
    }

    func testRuntimeGenerationChangesIndex() {
        let a = makeIndex(openPaths: ["/tmp/a"])
        let b = makeIndex(openPaths: ["/tmp/b"])
        XCTAssertNotEqual(a.runtimeGeneration, b.runtimeGeneration)
    }

    func testBatchResolverRecordsDeferredCount() {
        let git = gitEntity(path: "/tmp/repo/.git")
        let derived = derivedEntity(path: "/tmp/DerivedData/X")
        let knowledge = KnowledgeBaseDocument(version: "t", principle: "t", rules: [])
        let ruleIndex = SafetyRuleIndex(knowledge: knowledge)
        let gitPlan = RuntimeResolutionNeedPlanner.plan(entity: git, ruleIndex: ruleIndex, verification: VerificationAnnotation())
        let ddPlan = RuntimeResolutionNeedPlanner.plan(entity: derived, ruleIndex: ruleIndex, verification: VerificationAnnotation())
        let batch = RuntimeStateBatchResolver.resolveAll(
            entities: [git, derived],
            verifications: [
                git.entity.id: VerificationAnnotation(),
                derived.entity.id: VerificationAnnotation(),
            ],
            plans: [git.entity.id: gitPlan, derived.entity.id: ddPlan],
            index: makeIndex(processNames: ["Xcode"]),
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        XCTAssertEqual(batch.report.runtimeResolutionDeferred, 1)
        XCTAssertEqual(batch.report.runtimeResolutionRequired, 1)
    }
}
