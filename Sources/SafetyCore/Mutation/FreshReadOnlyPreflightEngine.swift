import Foundation

/// P2.0.6 — Single Entity × Action fresh read-only preflight. No mutation capability.
public enum FreshReadOnlyPreflightEngine {
    public struct RunResult: Sendable {
        public var session: FreshPreflightSession
        public var receipt: PreflightReceipt
        public var delta: PreflightStateDeltaReport
        public var freshRuntimeIndex: RuntimeObservationIndex
        public var freshRuntimeResolution: RuntimeStateResolution
        public var freshDecision: ActionDecision
        public var freshGateResult: MutationGateResult
        public var scanBindingFingerprint: ActionBindingFingerprint
        public var freshBindingFingerprint: ActionBindingFingerprint
        public var bindingValid: Bool
        public var sourceUnchanged: Bool
        public var sourceExists: Bool
        public var staticClaimsReused: [String]
        public var dynamicClaimsRefreshed: [String]
        public var causalBlockerChain: [String]
        public var firstBlocker: String?
        public var ollamaNativeInterface: OllamaNativeInterfaceResolution?
        public var ollamaRuntimeProof: OllamaExactRuntimeProof?
        public var huggingFaceNativeInterface: HuggingFaceNativeInterfaceResolution?
        public var huggingFaceDryRunPreview: HuggingFaceCacheRemovalPreview?
        public var nativeInterfaceResolutionMs: Int
        public var ollamaRuntimeObservationMs: Int
        public var hfDryRunMs: Int
        public var hfRuntimeProofMs: Int
    }

    public static func run(
        sessionID: String,
        item: ClassifiedItem,
        action: StorageAction,
        scanDecision: ActionDecision,
        scanGate: MutationGateResult,
        snapshot: EntitySafetySnapshot?,
        recommendation: ActionRecommendationResult?,
        preflight: ActionPreflightResult?,
        scanRuntimeResolution: RuntimeStateResolution?,
        ruleVersion: String,
        engine: SafetyRuleEngine,
        processes: any ProcessRunningChecker = ProcessCheck(),
        handles: any OpenHandleChecker = LSOFHandleChecker(),
        startedAt: Date = Date(),
        ollamaProcessRunner: (any BoundedProcessRunner)? = nil,
        refreshStaleRemoteProof: Bool = true
    ) -> RunResult {
        let totalStarted = Date()
        var staticReused: [String] = []
        var dynamicRefreshed: [String] = []
        var deltaEntries: [PreflightClaimDelta] = []
        var causalChain: [String] = []

        let canonicalPath = canonicalPath(for: item, snapshot: snapshot)
        let sourceExists = FileManager.default.fileExists(atPath: canonicalPath)
        dynamicRefreshed.append("source_exists")

        let runtimeStarted = Date()
        let (proc, file): (any ProcessRunningChecker, any OpenHandleChecker)
        if processes is ProcessCheck, handles is LSOFHandleChecker {
            let captured = RuntimeObservationWindow.capture(snapshots: 1, gapMs: 0)
            proc = captured.0
            file = captured.1
        } else {
            proc = processes
            file = handles
        }
        let runtimeIndex = RuntimeObservationIndex.build(processes: proc, handles: file, observedAt: Date())
        let runtimeObservationMs = Int(Date().timeIntervalSince(runtimeStarted) * 1000)
        dynamicRefreshed.append("runtime_observation_index")

        let procCompleteness = (proc as? ProcessTableSnapshot)?.completeness ?? .unknown
        let handleCompleteness = (file as? OpenFileSnapshot)?.completeness ?? .unknown
        let isOllamaNative = action == .vendorNativeCleanup && ActionPolicy.isOllamaModelEntity(item)
        let isHFNative = action == .vendorNativeCleanup && ActionPolicy.isHuggingFaceSnapshotEntity(item)
        let plan = RuntimeRequirementPlan(
            needsActive: true,
            needsOpenFile: !isOllamaNative,
            need: .requiredNow,
            deferReason: nil,
            deferReasons: []
        )
        let contract = RuntimeSensitiveContract.forEntity(item.detected)
        var freshRuntime = RuntimeStateBatchResolver.resolveActiveOpen(
            entity: item.detected,
            relatedPaths: contract.relatedExactPaths,
            contract: contract,
            index: runtimeIndex,
            processCompleteness: item.detected.associatedProcesses.isEmpty ? .unknown : procCompleteness,
            handleCompleteness: handleCompleteness,
            plan: plan
        )
        dynamicRefreshed.append(contentsOf: ["active_state", "open_file_state", "process_snapshot"])

        var workingItem = item
        var ollamaInterface: OllamaNativeInterfaceResolution?
        var ollamaProof: OllamaExactRuntimeProof?
        var hfInterface: HuggingFaceNativeInterfaceResolution?
        var hfPreview: HuggingFaceCacheRemovalPreview?
        var nativeInterfaceMs = 0
        var ollamaRuntimeMs = 0
        var hfDryRunMs = 0
        var hfRuntimeMs = 0
        if isOllamaNative {
            let runner = ollamaProcessRunner ?? FoundationProcessRunner()
            let model = ActionPolicy.ollamaCanonicalModelName(from: item) ?? item.detected.entity.displayName
            let processPaths = Array(runtimeIndex.referencedCommandPaths.filter {
                $0.lowercased().contains("ollama")
            })
            let ifaceStarted = Date()
            let ifaceCtx = OllamaNativeInterfaceResolver.Context(
                processRunner: runner,
                processExecutablePaths: processPaths,
                modelDataPresent: FileManager.default.fileExists(
                    atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
                )
            )
            let resolution = OllamaNativeInterfaceResolver.resolve(context: ifaceCtx)
            nativeInterfaceMs = Int(Date().timeIntervalSince(ifaceStarted) * 1000)
            ollamaInterface = resolution

            let runtimeStartedExact = Date()
            var proof = OllamaNativeInterfaceResolver.proveExactRuntime(
                canonicalModel: model,
                resolution: resolution,
                context: ifaceCtx
            )
            proof.targetEntityID = item.detected.entity.id
            ollamaRuntimeMs = Int(Date().timeIntervalSince(runtimeStartedExact) * 1000)
            ollamaProof = proof

            var v = workingItem.verification ?? VerificationAnnotation()
            v.activeState = proof.targetStatus
            v.activeStateConfidence = proof.targetConfidence
            v.activeStateCompleteness = proof.snapshotCompleteness
            v.vendorProofNotes.removeAll {
                $0.hasPrefix("OLLAMA_PS_")
                    || $0.hasPrefix("OLLAMA_INTERFACE=")
                    || $0.hasPrefix("OLLAMA_CLI_")
                    || $0 == "OLLAMA_EXECUTABLE_UNRESOLVED"
                    || $0 == "OLLAMA_EXECUTION_TRANSPORT_AVAILABLE"
                    || $0 == "OLLAMA_EXECUTION_TRANSPORT_UNAVAILABLE"
                    || $0.hasPrefix("OLLAMA_BINARY_FP=")
                    || $0.hasPrefix("OLLAMA_RUNTIME_SOURCE=")
            }
            v.vendorProofNotes.append("OLLAMA_INTERFACE=\(resolution.interfaceKind.rawValue)")
            v.vendorProofNotes.append("OLLAMA_RUNTIME_SOURCE=\(proof.observationSource)")
            if resolution.executionTransportAvailable, let path = resolution.cliExecutableURL {
                v.vendorProofNotes.append("OLLAMA_CLI_RESOLVED=\(path)")
                v.vendorProofNotes.append("OLLAMA_EXECUTION_TRANSPORT_AVAILABLE")
                if let fp = resolution.binaryFingerprint {
                    v.vendorProofNotes.append("OLLAMA_BINARY_FP=\(fp)")
                }
            } else {
                v.vendorProofNotes.append("OLLAMA_EXECUTABLE_UNRESOLVED")
                v.vendorProofNotes.append("OLLAMA_EXECUTION_TRANSPORT_UNAVAILABLE")
            }
            if proof.targetConfidence == .verified {
                v.vendorProofNotes.append("OLLAMA_PS_EXACT_MODEL=\(proof.targetStatus.rawValue)")
            } else {
                v.vendorProofNotes.append("OLLAMA_PS_INCOMPLETE=\(proof.failureReason ?? "UNKNOWN")")
            }
            let rem = VendorAbsentManagedDataAnalyzer.evaluateOllamaModel(
                item: workingItem,
                interface: resolution
            )
            VendorAbsentManagedDataAnalyzer.stamp(rem, onto: &v.vendorProofNotes)
            if rem.managedDataAvailability == .vendorAbsentManagedDataRemains {
                dynamicRefreshed.append("vendor_absent_managed_data_remediation")
            }
            if refreshStaleRemoteProof {
                let existing = v.remoteReacquisitionProof
                if existing == nil || existing?.isFresh != true {
                    if let refreshed = refreshOllamaRemote(for: workingItem) {
                        RemoteReacquisitionService.apply(proof: refreshed, to: &v)
                        dynamicRefreshed.append("remote_reacquisition_refresh")
                    }
                }
            }
            workingItem.verification = v
            // Exact model runtime overrides generic process association.
            // Service-running alone never proves target inactive/active.
            freshRuntime = RuntimeStateResolution(
                entityID: item.detected.entity.id,
                disposition: .resolved,
                deferReason: nil,
                activeState: proof.targetStatus,
                activeStateConfidence: proof.targetConfidence,
                activeStateCompleteness: proof.snapshotCompleteness,
                openFileHandle: .false,
                openFileConfidence: .verified,
                unknownReasons: proof.targetConfidence == .verified
                    ? []
                    : [proof.failureReason ?? "OLLAMA_RUNTIME_UNKNOWN"],
                lookupMs: ollamaRuntimeMs
            )
            dynamicRefreshed.append("ollama_native_interface_resolution")
            dynamicRefreshed.append("ollama_exact_runtime_proof")
        }

        if isHFNative {
            let runner = ollamaProcessRunner ?? FoundationProcessRunner()
            let ifaceStarted = Date()
            let processPaths = Array(runtimeIndex.referencedCommandPaths.filter {
                ($0 as NSString).lastPathComponent.lowercased() == "hf"
            })
            let resolution = HuggingFaceNativeInterfaceResolver.resolve(
                context: .init(
                    processRunner: runner,
                    processExecutablePaths: processPaths
                )
            )
            nativeInterfaceMs = Int(Date().timeIntervalSince(ifaceStarted) * 1000)
            hfInterface = resolution

            let rev = ActionPolicy.huggingFaceRevision(from: workingItem)
                ?? (workingItem.detected.entity.path as NSString).lastPathComponent
            let repo = ActionPolicy.huggingFaceRepoID(from: workingItem) ?? "unknown/unknown"
            let inv = HuggingFaceCacheDryRunPreviewer.captureLocalInventory(
                repoID: repo,
                revision: rev,
                itemPath: workingItem.detected.entity.path,
                uniqueBytes: workingItem.verification?.uniqueBytesProven,
                sharedBytes: workingItem.verification?.sharedBytesProven
            )
            let dryStarted = Date()
            let preview = HuggingFaceCacheDryRunPreviewer.preview(
                inventory: inv,
                interface: resolution,
                processRunner: runner,
                semanticExclusiveBlobCount: inv.exclusiveBlobCount,
                semanticSharedBlobCount: inv.sharedBlobCount
            )
            hfDryRunMs = Int(Date().timeIntervalSince(dryStarted) * 1000)
            hfPreview = preview

            let rtStarted = Date()
            // Prefer fresh open-file resolution already computed; stamp activity from it.
            let openInactive = freshRuntime.openFileHandle == .false
                && freshRuntime.openFileConfidence == .verified
                && handleCompleteness == .complete
            let openActive = freshRuntime.openFileHandle == .true
                && freshRuntime.openFileConfidence == .verified
            hfRuntimeMs = Int(Date().timeIntervalSince(rtStarted) * 1000)

            var v = workingItem.verification ?? VerificationAnnotation()
            v.vendorProofNotes.removeAll {
                $0.hasPrefix("HF_")
                    || $0 == "LOCAL_HF_CACHE_OWNERSHIP_VERIFIED"
                    || $0.hasPrefix("HF_DRY_RUN_")
            }
            v.vendorProofNotes.append("HF_INTERFACE=\(resolution.status.rawValue)")
            v.vendorProofNotes.append("HF_CACHE_ROOT=\(inv.cacheRoot)")
            v.vendorProofNotes.append("LOCAL_HF_CACHE_OWNERSHIP_VERIFIED")
            v.vendorProofNotes.append("HF_REVISION=\(rev)")
            v.vendorProofNotes.append("HF_REPO=\(repo)")
            v.vendorProofNotes.append("HF_DRY_RUN_FP=\(preview.consequenceFingerprint)")
            if resolution.executionTransportAvailable {
                if let path = resolution.cliExecutableURL {
                    v.vendorProofNotes.append("HF_CLI_RESOLVED=\(path)")
                }
                v.vendorProofNotes.append("HF_EXECUTION_TRANSPORT_AVAILABLE")
                if let fp = resolution.binaryFingerprint {
                    v.vendorProofNotes.append("HF_BINARY_FP=\(fp)")
                }
            } else {
                v.vendorProofNotes.append("HF_EXECUTABLE_UNRESOLVED")
                v.vendorProofNotes.append("HF_EXECUTION_TRANSPORT_UNAVAILABLE")
                v.vendorProofNotes.append(resolution.failureReason ?? "HF_CLI_UNRESOLVED")
            }
            if preview.previewComplete, !preview.dryRunMutationDetected, preview.targetedRevisionCount == 1 {
                v.vendorProofNotes.append("HF_DRY_RUN_COMPLETE")
            } else {
                v.vendorProofNotes.append("HF_DRY_RUN_INCOMPLETE")
            }
            if openActive {
                v.activeState = .active
                v.activeStateConfidence = .verified
                v.activeStateCompleteness = handleCompleteness
                freshRuntime = RuntimeStateResolution(
                    entityID: freshRuntime.entityID,
                    disposition: .resolved,
                    deferReason: nil,
                    activeState: .active,
                    activeStateConfidence: .verified,
                    activeStateCompleteness: handleCompleteness,
                    openFileHandle: .true,
                    openFileConfidence: .verified,
                    unknownReasons: [],
                    lookupMs: freshRuntime.lookupMs
                )
            } else if openInactive {
                v.activeState = .inactive
                v.activeStateConfidence = .verified
                v.activeStateCompleteness = handleCompleteness
                // Stamp onto freshRuntime so receipt/gate see INACTIVE VERIFIED (not stale active_state).
                freshRuntime = RuntimeStateResolution(
                    entityID: freshRuntime.entityID,
                    disposition: .resolved,
                    deferReason: nil,
                    activeState: .inactive,
                    activeStateConfidence: .verified,
                    activeStateCompleteness: handleCompleteness,
                    openFileHandle: .false,
                    openFileConfidence: .verified,
                    unknownReasons: [],
                    lookupMs: freshRuntime.lookupMs
                )
            } else {
                v.activeState = .unknown
                v.activeStateConfidence = .unknown
                v.activeStateCompleteness = handleCompleteness
            }
            if refreshStaleRemoteProof {
                let existing = v.remoteReacquisitionProof
                if existing == nil || existing?.isFresh != true {
                    if let refreshed = refreshHFRemote(for: workingItem, revision: rev) {
                        RemoteReacquisitionService.apply(proof: refreshed, to: &v)
                        dynamicRefreshed.append("remote_reacquisition_refresh")
                    }
                }
            }
            workingItem.verification = v
            dynamicRefreshed.append("hf_native_interface_resolution")
            dynamicRefreshed.append("hf_cache_dry_run_preview")
            dynamicRefreshed.append("hf_runtime_open_file_proof")
        }

        let scanRuntimeGeneration = snapshot?.cacheKey.runtimeGeneration ?? scanGate.actionBindingFingerprint?.runtimeGeneration ?? 0
        let scanGateInput = buildGateInput(
            item: workingItem,
            action: action,
            decision: scanDecision,
            snapshot: snapshot,
            recommendation: recommendation,
            preflight: preflight,
            runtime: scanRuntimeResolution,
            ruleVersion: ruleVersion,
            runtimeGeneration: scanRuntimeGeneration,
            receipt: nil
        )
        let scanFingerprint = scanGate.actionBindingFingerprint ?? ActionBindingFingerprintBuilder.compute(input: scanGateInput)

        let bindingValid = bindingMatchesPlanning(scan: scanFingerprint, item: workingItem, action: action, snapshot: snapshot)
        let sourceUnchanged = sourceExists
            && canonicalPath == scanFingerprint.canonicalPath
            && workingItem.detected.entity.id == scanFingerprint.entityID
            && action.rawValue == scanFingerprint.action.rawValue

        recordStaticReuse(snapshot: snapshot, action: action, into: &staticReused)
        deltaEntries.append(contentsOf: buildRuntimeDelta(
            scanRuntime: scanRuntimeResolution,
            freshRuntime: freshRuntime,
            procCompleteness: procCompleteness,
            handleCompleteness: handleCompleteness
        ))

        let claimEvalStarted = Date()
        var freshEvidence = snapshot?.evidence ?? EvidenceBundle(canonicalPath: canonicalPath)
        var freshState = snapshot?.state ?? RuntimeState()
        applyFreshRuntime(freshRuntime, evidence: &freshEvidence, state: &freshState)

        let safetyStarted = Date()
        let freshDecision = ActionSafetyEvaluator.evaluate(
            item: workingItem,
            action: action,
            engine: engine,
            evidence: freshEvidence,
            state: freshState,
            snapshot: snapshot,
            safetyDecisions: action == .moveToTrash ? [.moveToTrash: item.decision] : nil
        )
        let safetyReEvalMs = Int(Date().timeIntervalSince(safetyStarted) * 1000)

        let freshGateInput = buildGateInput(
            item: workingItem,
            action: action,
            decision: freshDecision,
            snapshot: snapshot,
            recommendation: recommendation,
            preflight: preflight,
            runtime: freshRuntime,
            ruleVersion: ruleVersion,
            runtimeGeneration: runtimeIndex.runtimeGeneration,
            receipt: nil
        )
        let freshFingerprint = ActionBindingFingerprintBuilder.compute(input: freshGateInput)

        let (receipt, resultCode, missingClaims, staleClaims, conflictedClaims, satisfiedClaims) = buildReceipt(
            item: workingItem,
            action: action,
            scanDecision: scanDecision,
            freshDecision: freshDecision,
            snapshot: snapshot,
            freshRuntime: freshRuntime,
            runtimeIndex: runtimeIndex,
            procCompleteness: procCompleteness,
            handleCompleteness: handleCompleteness,
            bindingValid: bindingValid,
            sourceExists: sourceExists,
            sourceUnchanged: sourceUnchanged,
            scanFingerprint: scanFingerprint,
            freshFingerprint: freshFingerprint
        )
        let claimEvaluationMs = Int(Date().timeIntervalSince(claimEvalStarted) * 1000)

        let gateStarted = Date()
        var gateInput = freshGateInput
        gateInput.freshPreflightReceipt = receipt
        let freshGateResult = MutationGate.evaluate(gateInput)
        let gateEvalMs = Int(Date().timeIntervalSince(gateStarted) * 1000)

        if !bindingValid {
            causalChain.append("BINDING_MISMATCH")
        }
        if !sourceExists {
            causalChain.append("SOURCE_MISSING")
        }
        if !sourceUnchanged {
            causalChain.append("SOURCE_IDENTITY_CHANGED")
        }
        if freshDecision.safetyClass == .red {
            causalChain.append(ActionBlockReason.safetyClassRed.rawValue)
        }
        if freshRuntime.activeState == .active, freshRuntime.activeStateConfidence == .verified {
            causalChain.append(ActionBlockReason.sourceActive.rawValue)
        }
        if !isOllamaNative, freshRuntime.openFileHandle == .true {
            causalChain.append(ActionBlockReason.sourceOpen.rawValue)
        }
        if freshRuntime.activeStateConfidence == .unknown {
            causalChain.append("ACTIVE_STATE_INCOMPLETE")
        }
        if !isOllamaNative, freshRuntime.openFileConfidence == .unknown, plan.needsOpenFile {
            causalChain.append("OPEN_FILE_INCOMPLETE")
        }
        causalChain.append(contentsOf: freshDecision.blockedReasons.map(\.rawValue))
        causalChain.append(contentsOf: missingClaims.map(\.rawValue))
        let firstBlocker = causalChain.first ?? freshGateResult.blockingReasons.first ?? freshGateResult.missingRequirements.first

        let completedAt = Date()
        let session = FreshPreflightSession(
            preflightSessionID: sessionID,
            startedAt: startedAt,
            completedAt: completedAt,
            entityID: item.detected.entity.id,
            action: action.rawValue,
            originalBindingFingerprint: scanFingerprint,
            freshRuntimeGeneration: runtimeIndex.runtimeGeneration,
            runtimeObservationMs: runtimeObservationMs,
            claimEvaluationMs: claimEvaluationMs,
            safetyReEvalMs: safetyReEvalMs,
            gateEvalMs: gateEvalMs,
            totalMs: Int(completedAt.timeIntervalSince(totalStarted) * 1000)
        )

        let delta = PreflightStateDeltaReport(
            entityID: item.detected.entity.id,
            action: action.rawValue,
            scanBindingFingerprint: scanFingerprint,
            freshBindingFingerprint: freshFingerprint,
            bindingValid: bindingValid,
            sourceUnchanged: sourceUnchanged,
            entries: deltaEntries
        )

        _ = resultCode
        _ = satisfiedClaims
        _ = staleClaims
        _ = conflictedClaims
        return RunResult(
            session: session,
            receipt: receipt,
            delta: delta,
            freshRuntimeIndex: runtimeIndex,
            freshRuntimeResolution: freshRuntime,
            freshDecision: freshDecision,
            freshGateResult: freshGateResult,
            scanBindingFingerprint: scanFingerprint,
            freshBindingFingerprint: freshFingerprint,
            bindingValid: bindingValid,
            sourceUnchanged: sourceUnchanged,
            sourceExists: sourceExists,
            staticClaimsReused: staticReused.sorted(),
            dynamicClaimsRefreshed: dynamicRefreshed.sorted(),
            causalBlockerChain: Array(Set(causalChain)).sorted(),
            firstBlocker: firstBlocker,
            ollamaNativeInterface: ollamaInterface,
            ollamaRuntimeProof: ollamaProof,
            huggingFaceNativeInterface: hfInterface,
            huggingFaceDryRunPreview: hfPreview,
            nativeInterfaceResolutionMs: nativeInterfaceMs,
            ollamaRuntimeObservationMs: ollamaRuntimeMs,
            hfDryRunMs: hfDryRunMs,
            hfRuntimeProofMs: hfRuntimeMs
        )
    }

    private static func refreshHFRemote(for item: ClassifiedItem, revision: String) -> RemoteReacquisitionProof? {
        guard let repo = ActionPolicy.huggingFaceRepoID(from: item) else { return nil }
        let inventories = VendorStorageProofIndex.allInventories()
        if let inv = inventories.first(where: { $0.vendor == .huggingFace }),
           let entity = inv.entities.first(where: { $0.entityID == item.detected.entity.id }) {
            let session = RemoteRequestSession()
            return HuggingFaceRemoteVerifier().verify(entity: entity, session: session)
        }
        let entity = VendorSemanticEntity(
            vendor: .huggingFace,
            entityKind: .snapshot,
            entityID: item.detected.entity.id,
            displayIdentity: "\(repo)@\(String(revision.prefix(12)))",
            canonicalPath: item.detected.entity.path,
            logicalBytes: item.verification?.logicalBytesProven ?? item.verification?.uniqueBytesProven ?? 0,
            uniqueBytes: item.verification?.uniqueBytesProven,
            sharedBytes: item.verification?.sharedBytesProven,
            originIdentity: repo,
            revisionIdentity: revision,
            referenceScope: .exclusive,
            referenceGraphComplete: item.verification?.referenceGraphConfidence == .verified
        )
        let session = RemoteRequestSession()
        return HuggingFaceRemoteVerifier().verify(entity: entity, session: session)
    }

    private static func refreshOllamaRemote(for item: ClassifiedItem) -> RemoteReacquisitionProof? {
        let inventories = VendorStorageProofIndex.allInventories()
        guard let inv = inventories.first(where: { $0.vendor == .ollama }) else { return nil }
        guard let entity = inv.entities.first(where: { $0.entityID == item.detected.entity.id }) else { return nil }
        let session = RemoteRequestSession()
        return OllamaRemoteVerifier().verify(entity: entity, session: session)
    }

    // MARK: - Private (continued from original helpers)
    private static func canonicalPath(for item: ClassifiedItem, snapshot: EntitySafetySnapshot?) -> String {
        let path = (snapshot?.evidence.canonicalPath.isEmpty == false
            ? snapshot!.evidence.canonicalPath
            : item.detected.entity.path)
        return (path as NSString).standardizingPath
    }

    private static func buildGateInput(
        item: ClassifiedItem,
        action: StorageAction,
        decision: ActionDecision,
        snapshot: EntitySafetySnapshot?,
        recommendation: ActionRecommendationResult?,
        preflight: ActionPreflightResult?,
        runtime: RuntimeStateResolution?,
        ruleVersion: String,
        runtimeGeneration: Int,
        receipt: PreflightReceipt?
    ) -> MutationGateInput {
        MutationGateInput(
            item: item,
            action: action,
            actionDecision: decision,
            snapshot: snapshot,
            recommendation: recommendation,
            preflight: preflight,
            runtimeResolution: runtime,
            transactionContract: TransactionContractRegistry.transactionContract(for: action, item: item),
            postVerifyContract: TransactionContractRegistry.postVerifyContract(for: action, item: item),
            auditContract: TransactionContractRegistry.auditContract(for: action, item: item),
            approvalState: .scanDefault,
            evidenceGeneration: snapshot?.evidence.snapshotVersion ?? 0,
            verificationGeneration: snapshot?.verification.snapshotGeneration ?? 0,
            runtimeGeneration: runtimeGeneration,
            ruleVersion: ruleVersion,
            freshPreflightReceipt: receipt
        )
    }

    private static func bindingMatchesPlanning(
        scan: ActionBindingFingerprint,
        item: ClassifiedItem,
        action: StorageAction,
        snapshot: EntitySafetySnapshot?
    ) -> Bool {
        guard scan.entityID == item.detected.entity.id else { return false }
        guard scan.action == action else { return false }
        let path = canonicalPath(for: item, snapshot: snapshot)
        guard scan.canonicalPath == path else { return false }
        let evidenceGen = snapshot?.evidence.snapshotVersion ?? scan.evidenceGeneration
        let verificationGen = snapshot?.verification.snapshotGeneration ?? scan.verificationGeneration
        guard scan.evidenceGeneration == evidenceGen else { return false }
        guard scan.verificationGeneration == verificationGen else { return false }
        return true
    }

    private static func recordStaticReuse(
        snapshot: EntitySafetySnapshot?,
        action: StorageAction,
        into reused: inout [String]
    ) {
        guard let snapshot else { return }
        reused.append("entity_identity")
        reused.append("canonical_path")
        if snapshot.predicates.hasCanonicalPath { reused.append("canonical_path_verified") }
        if action == .moveToTrash {
            if snapshot.predicates.sourceOfTruth.confidence == .verified,
               snapshot.predicates.sourceOfTruth.value == .false {
                reused.append("source_of_truth_false_verified")
            }
            if snapshot.predicates.regenerability.confidence == .verified,
               snapshot.predicates.regenerability.value == .true {
                reused.append("regenerable_true_verified")
            }
        }
        reused.append("transaction_contract")
        reused.append("post_verify_contract")
        reused.append("audit_contract")
    }

    private static func buildRuntimeDelta(
        scanRuntime: RuntimeStateResolution?,
        freshRuntime: RuntimeStateResolution,
        procCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness
    ) -> [PreflightClaimDelta] {
        func delta(
            _ requirement: String,
            freshness: String,
            previous: String?,
            current: String?,
            disposition: String,
            reason: String?
        ) -> PreflightClaimDelta {
            PreflightClaimDelta(
                requirement: requirement,
                freshnessClass: freshness,
                previousValue: previous,
                currentValue: current,
                changed: previous != current,
                disposition: disposition,
                reason: reason
            )
        }

        let prevActive = scanRuntime.map { "\($0.activeState.rawValue):\($0.activeStateConfidence.rawValue)" }
        let currActive = "\(freshRuntime.activeState.rawValue):\(freshRuntime.activeStateConfidence.rawValue)"
        let prevOpen = scanRuntime.map { "\($0.openFileHandle.rawValue):\($0.openFileConfidence.rawValue)" }
        let currOpen = "\(freshRuntime.openFileHandle.rawValue):\(freshRuntime.openFileConfidence.rawValue)"

        return [
            delta("active_state", freshness: FreshnessRequirement.runtimeFresh.rawValue,
                  previous: prevActive, current: currActive,
                  disposition: "REFRESHED", reason: nil),
            delta("open_file_state", freshness: FreshnessRequirement.runtimeFresh.rawValue,
                  previous: prevOpen, current: currOpen,
                  disposition: "REFRESHED", reason: nil),
            delta("process_snapshot_completeness", freshness: FreshnessRequirement.runtimeFresh.rawValue,
                  previous: scanRuntime == nil ? nil : "scan",
                  current: procCompleteness.rawValue,
                  disposition: procCompleteness == .complete ? "REFRESHED" : "UNKNOWN",
                  reason: procCompleteness != .complete ? "PROCESS_SNAPSHOT_INCOMPLETE" : nil),
            delta("handle_snapshot_completeness", freshness: FreshnessRequirement.runtimeFresh.rawValue,
                  previous: scanRuntime == nil ? nil : "scan",
                  current: handleCompleteness.rawValue,
                  disposition: handleCompleteness == .complete ? "REFRESHED" : "UNKNOWN",
                  reason: handleCompleteness != .complete ? "LSOF_INCOMPLETE" : nil),
        ]
    }

    private static func applyFreshRuntime(
        _ runtime: RuntimeStateResolution,
        evidence: inout EvidenceBundle,
        state: inout RuntimeState
    ) {
        if runtime.openFileConfidence == .verified {
            evidence.openFileHandle = runtime.openFileHandle
            evidence.predicateConfidence["no_open_file_handle"] = .verified
        }
        if runtime.activeStateConfidence == .verified {
            state.owningProcessRunning = runtime.activeState == .active
        }
        state.hasOpenHandles = runtime.openFileHandle == .true
    }

    private static func buildReceipt(
        item: ClassifiedItem,
        action: StorageAction,
        scanDecision: ActionDecision,
        freshDecision: ActionDecision,
        snapshot: EntitySafetySnapshot?,
        freshRuntime: RuntimeStateResolution,
        runtimeIndex: RuntimeObservationIndex,
        procCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness,
        bindingValid: Bool,
        sourceExists: Bool,
        sourceUnchanged: Bool,
        scanFingerprint: ActionBindingFingerprint,
        freshFingerprint: ActionBindingFingerprint
    ) -> (
        PreflightReceipt,
        PreflightResultCode,
        [ClaimType],
        [ClaimType],
        [ClaimType],
        [ClaimType]
    ) {
        var missing: [ClaimType] = []
        var stale: [ClaimType] = []
        var conflicted: [ClaimType] = []
        var satisfied: [ClaimType] = scanDecision.satisfiedClaimTypes

        if !bindingValid || !sourceUnchanged {
            let receipt = makeReceipt(
                item: item, action: action, fingerprint: scanFingerprint,
                required: scanDecision.requiredClaims.map(\.claimType),
                satisfied: satisfied, missing: [.canonicalPath], stale: stale, conflicted: conflicted,
                runtimeGeneration: runtimeIndex.runtimeGeneration, snapshot: snapshot,
                result: PreflightResultCode.candidateChanged.rawValue
            )
            return (receipt, .candidateChanged, missing, stale, conflicted, satisfied)
        }

        if !sourceExists {
            missing.append(.canonicalPath)
            let receipt = makeReceipt(
                item: item, action: action, fingerprint: freshFingerprint,
                required: scanDecision.requiredClaims.map(\.claimType),
                satisfied: satisfied, missing: missing, stale: stale, conflicted: conflicted,
                runtimeGeneration: runtimeIndex.runtimeGeneration, snapshot: snapshot,
                result: PreflightResultCode.realStateBlock.rawValue
            )
            return (receipt, .realStateBlock, missing, stale, conflicted, satisfied)
        }

        if freshRuntime.activeState == .active, freshRuntime.activeStateConfidence == .verified {
            missing.append(.activeState)
            conflicted.append(.activeState)
        } else if freshRuntime.activeStateConfidence == .verified, freshRuntime.activeState == .inactive {
            satisfied.append(.activeState)
        } else if freshRuntime.activeStateConfidence == .unknown {
            stale.append(.activeState)
            missing.append(.activeState)
        }

        if freshRuntime.openFileHandle == .true {
            missing.append(.openFileState)
        } else if freshRuntime.openFileConfidence == .verified, freshRuntime.openFileHandle == .false {
            satisfied.append(.openFileState)
        } else if freshRuntime.openFileConfidence == .unknown {
            stale.append(.openFileState)
            missing.append(.openFileState)
        }

        if procCompleteness != .complete || handleCompleteness != .complete {
            if freshRuntime.openFileConfidence == .unknown {
                stale.append(.openFileState)
            }
            if freshRuntime.activeStateConfidence == .unknown {
                stale.append(.activeState)
            }
        }

        if freshDecision.blockedReasons.contains(.evidenceConflict) {
            conflicted.append(contentsOf: freshDecision.missingClaimTypes)
        }

        missing.append(contentsOf: freshDecision.missingClaimTypes.filter { !satisfied.contains($0) && !stale.contains($0) })
        missing = Array(Set(missing))
        satisfied = Array(Set(satisfied.filter { !missing.contains($0) && !stale.contains($0) && !conflicted.contains($0) }))

        let resultCode: PreflightResultCode
        if !conflicted.isEmpty {
            resultCode = .conflicted
        } else if !stale.isEmpty {
            resultCode = .staleEvidence
        } else if !missing.isEmpty || !freshDecision.eligible {
            resultCode = .realStateBlock
        } else if freshDecision.safetyClass != .green, action != .vendorNativeCleanup {
            // Vendor-native intentionally stays UNKNOWN (never GREEN). That must not block SATISFIED_READ_ONLY.
            resultCode = .realStateBlock
        } else {
            resultCode = .satisfiedReadOnly
        }

        let receipt = makeReceipt(
            item: item, action: action, fingerprint: freshFingerprint,
            required: scanDecision.requiredClaims.map(\.claimType),
            satisfied: satisfied, missing: missing, stale: stale, conflicted: conflicted,
            runtimeGeneration: runtimeIndex.runtimeGeneration, snapshot: snapshot,
            result: resultCode.rawValue
        )
        return (receipt, resultCode, missing, stale, conflicted, satisfied)
    }

    private static func makeReceipt(
        item: ClassifiedItem,
        action: StorageAction,
        fingerprint: ActionBindingFingerprint,
        required: [ClaimType],
        satisfied: [ClaimType],
        missing: [ClaimType],
        stale: [ClaimType],
        conflicted: [ClaimType],
        runtimeGeneration: Int,
        snapshot: EntitySafetySnapshot?,
        result: String
    ) -> PreflightReceipt {
        PreflightReceipt(
            receiptID: "fresh-preflight-\(item.detected.entity.id)-\(action.rawValue)-\(UUID().uuidString.prefix(8))",
            entityID: item.detected.entity.id,
            action: action,
            bindingFingerprint: fingerprint,
            requiredClaims: required,
            satisfiedClaims: satisfied,
            missingClaims: missing,
            staleClaims: stale,
            conflictedClaims: conflicted,
            observedAt: Date(),
            freshnessValidity: [.runtimeFresh],
            evidenceGeneration: snapshot?.evidence.snapshotVersion ?? fingerprint.evidenceGeneration,
            verificationGeneration: snapshot?.verification.snapshotGeneration ?? fingerprint.verificationGeneration,
            runtimeGeneration: runtimeGeneration,
            result: result
        )
    }
}