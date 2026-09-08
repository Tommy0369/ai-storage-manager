import Foundation

public enum EntitySafetySnapshotBuilder {
    static func build(
        entity: inout DetectedEntity,
        evidence: inout EvidenceBundle,
        verification: inout VerificationAnnotation,
        context: VerificationLoopContext,
        cache: EvidenceResolutionCache,
        resolverTracker: inout ResolverRuntimeTracker,
        runtimeResolution: RuntimeStateResolution? = nil,
        runtimeIndex: RuntimeObservationIndex? = nil
    ) -> EntityPredicateSnapshot {
        applySnapshotConfidence(
            &evidence,
            entity: entity,
            context: context,
            cache: cache,
            runtimeResolution: runtimeResolution,
            runtimeIndex: runtimeIndex
        )

        let entityID = entity.entity.id
        let sot = resolveSourceOfTruth(
            entity: entity,
            evidence: evidence,
            verification: verification,
            entityID: entityID,
            tracker: &resolverTracker
        )
        let regen = resolveRegenerability(
            entity: entity,
            evidence: evidence,
            verification: verification,
            sourceOfTruth: sot,
            entityID: entityID,
            tracker: &resolverTracker
        )
        evidence.sourceOfTruth = sot.value
        evidence.regenerable = regen.value
        evidence.predicateConfidence["not_source_of_truth"] = sot.confidence
        evidence.predicateConfidence["regenerable"] = regen.confidence
        if sot.value == .false, sot.confidence == .verified {
            evidence.predicateConfidence["not_source_of_truth"] = .verified
        }

        let related = VerificationStrategies.claudeRelatedPaths(entity: entity)
        let activeResult = resolveActiveState(
            entity: entity,
            verification: verification,
            context: context,
            relatedPaths: related,
            entityID: entityID,
            tracker: &resolverTracker,
            runtimeResolution: runtimeResolution
        )
        if var life = entity.annotation?.lifecycle {
            life.activeState = activeResult.state
            life.unknownReasons.append(contentsOf: activeResult.reasons)
            entity.annotation?.lifecycle = life
        }

        verification.sourceOfTruth = sot
        verification.regenerable = regen
        verification.activeState = activeResult.state
        verification.activeStateConfidence = activeResult.confidence
        verification.activeStateCompleteness = activeResult.completeness
        verification.provenanceConfidence = entity.annotation?.provenance.confidence ?? .unknown
        verification.unknownReasons = (entity.annotation?.unknownReasons ?? [])
            + activeResult.reasons
            + [sot.reasonCode, regen.reasonCode].compactMap { $0 }

        let placeholderDecision = SafetyDecision(
            entity: entity.entity,
            action: .userReview,
            safetyClass: .unknown,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: nil,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: evidence.confidence,
            userExplanationJA: "",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        let placeholder = ClassifiedItem(
            detected: entity,
            decision: placeholderDecision,
            semantic: SemanticResult(from: placeholderDecision),
            allocatedBytes: entity.entity.logicalBytes,
            actionVariants: [:],
            inclusiveBytes: entity.entity.logicalBytes,
            exclusiveBytes: entity.entity.logicalBytes,
            resolution: .l2Domain,
            verification: verification
        )

        let openConfidence = evidence.predicateConfidence["no_open_file_handle"] ?? .unknown
        let role = entity.annotation?.lifecycle.role
        return EntityPredicateSnapshot(
            sourceOfTruth: sot,
            regenerability: regen,
            activeState: activeResult.state,
            activeStateConfidence: activeResult.confidence,
            openFileHandle: evidence.openFileHandle,
            openFileConfidence: openConfidence,
            isGitRepository: ActionPolicy.isGitRepository(placeholder),
            isApplicationManaged: ActionPolicy.isClaudeRuntime(placeholder)
                || ActionPolicy.isDerivedData(placeholder)
                || ActionPolicy.isLibraryManagedPath(entity.entity.path),
            isDerivedData: ActionPolicy.isDerivedData(placeholder),
            isUserOwnedVerified: ActionPolicy.userOwnedVerified(placeholder),
            hasEvidenceConflict: verification.unknownReasons.contains { $0.contains("CONFLICT") },
            hasCanonicalPath: !evidence.canonicalPath.isEmpty,
            isSymlinkAmbiguity: evidence.isSymlink == .true,
            isUserOriginal: entity.entity.kind == .userOriginal || role == .userContent,
            isGeneratedArtifact: role == .generatedArtifact || role == .cache,
            isInsideProtectedRoot: HardSafetyGates.isHardBlocked(path: entity.entity.path),
            fileProviderBacked: ActionPolicy.fileProviderBacked(placeholder, evidence: evidence),
            remoteBackingVerified: (entity.annotation?.relationships ?? []).contains { $0.confidence == .verified },
            syncSafeVerified: evidence.syncWouldDeleteRemote == .false
        )
    }

    static func applySnapshotConfidence(
        _ evidence: inout EvidenceBundle,
        entity: DetectedEntity,
        context: VerificationLoopContext,
        cache: EvidenceResolutionCache,
        runtimeResolution: RuntimeStateResolution? = nil,
        runtimeIndex: RuntimeObservationIndex? = nil
    ) {
        evidence.observationCompleteness["process"] = entity.associatedProcesses.isEmpty ? .unknown : context.processCompleteness
        evidence.observationCompleteness["open_file"] = context.handleCompleteness

        if let runtime = runtimeResolution {
            switch runtime.disposition {
            case .deferred:
                evidence.openFileHandle = .unknown
                evidence.predicateConfidence["no_open_file_handle"] = .unknown
            case .resolved:
                evidence.openFileHandle = runtime.openFileHandle
                evidence.predicateConfidence["no_open_file_handle"] = runtime.openFileConfidence
            }
        } else if let index = runtimeIndex {
            let contract = RuntimeSensitiveContract.forEntity(entity)
            let open = index.openHandleMatchingReference(path: entity.entity.path)
            evidence.openFileHandle = open
            if context.handleCompleteness == .complete, open != .unknown {
                evidence.predicateConfidence["no_open_file_handle"] = .verified
            } else if context.handleCompleteness != .complete {
                evidence.openFileHandle = .unknown
                evidence.predicateConfidence["no_open_file_handle"] = .unknown
            }
            _ = contract
        } else {
            let open = cache.openHandle(path: entity.entity.path, handles: context.handles)
            evidence.openFileHandle = open
            if context.handleCompleteness == .complete, open != .unknown {
                evidence.predicateConfidence["no_open_file_handle"] = .verified
            } else if context.handleCompleteness != .complete {
                evidence.openFileHandle = .unknown
                evidence.predicateConfidence["no_open_file_handle"] = .unknown
            }
        }
        if !entity.associatedProcesses.isEmpty, context.processCompleteness == .complete, evidence.owningProcessRunning != .unknown {
            evidence.predicateConfidence["owning_process_not_running"] = .verified
        } else if !entity.associatedProcesses.isEmpty, context.processCompleteness != .complete {
            evidence.owningProcessRunning = .unknown
            evidence.predicateConfidence["owning_process_not_running"] = .unknown
        }
    }

    static func resolveSourceOfTruth(
        entity: DetectedEntity,
        evidence: EvidenceBundle,
        verification: VerificationAnnotation,
        entityID: String,
        tracker: inout ResolverRuntimeTracker
    ) -> ObservationRecord {
        if verification.sourceOfTruth.confidence == .verified {
            tracker.recordHit(resolver: "source_of_truth", entityID: entityID)
            return verification.sourceOfTruth
        }
        let started = Date()
        let resolved = SourceOfTruthResolver.resolve(
            entity: entity.entity,
            annotation: entity.annotation,
            evidence: evidence
        )
        tracker.recordMiss(
            resolver: "source_of_truth",
            entityID: entityID,
            durationMs: msSince(started),
            outcome: resolved.confidence.rawValue.uppercased()
        )
        return mergeClaim(existing: verification.sourceOfTruth, resolved: resolved)
    }

    static func resolveRegenerability(
        entity: DetectedEntity,
        evidence: EvidenceBundle,
        verification: VerificationAnnotation,
        sourceOfTruth: ObservationRecord,
        entityID: String,
        tracker: inout ResolverRuntimeTracker
    ) -> ObservationRecord {
        if verification.regenerable.confidence == .verified {
            tracker.recordHit(resolver: "regenerability", entityID: entityID)
            return verification.regenerable
        }
        let started = Date()
        let resolved = RegenerabilityResolver.resolve(
            entity: entity.entity,
            annotation: entity.annotation,
            evidence: evidence,
            sourceOfTruth: sourceOfTruth
        )
        tracker.recordMiss(
            resolver: "regenerability",
            entityID: entityID,
            durationMs: msSince(started),
            outcome: resolved.confidence.rawValue.uppercased()
        )
        return mergeClaim(existing: verification.regenerable, resolved: resolved)
    }

    static func resolveActiveState(
        entity: DetectedEntity,
        verification: VerificationAnnotation,
        context: VerificationLoopContext,
        relatedPaths: [String],
        entityID: String,
        tracker: inout ResolverRuntimeTracker,
        runtimeResolution: RuntimeStateResolution? = nil
    ) -> (state: ObservedActiveState, confidence: EvidenceConfidence, completeness: ObservationCompleteness, reasons: [String]) {
        if verification.activeStateConfidence == .verified {
            tracker.recordHit(resolver: "active_state", entityID: entityID)
            return (
                verification.activeState,
                verification.activeStateConfidence,
                verification.activeStateCompleteness,
                []
            )
        }
        if let runtime = runtimeResolution {
            switch runtime.disposition {
            case .deferred:
                tracker.recordHit(resolver: "active_state", entityID: entityID)
                return (
                    verification.activeState,
                    verification.activeStateConfidence,
                    verification.activeStateCompleteness,
                    runtime.unknownReasons
                )
            case .resolved:
                tracker.recordHit(resolver: "active_state", entityID: entityID)
                return (
                    runtime.activeState,
                    runtime.activeStateConfidence,
                    runtime.activeStateCompleteness,
                    runtime.unknownReasons
                )
            }
        }
        let started = Date()
        let (active, activeConf, activeComp, activeReasons) = ActiveStateResolver.resolve(
            entityPath: entity.entity.path,
            associatedProcesses: entity.associatedProcesses,
            processes: context.processes,
            handles: context.handles,
            processCompleteness: entity.associatedProcesses.isEmpty ? .unknown : context.processCompleteness,
            handleCompleteness: context.handleCompleteness,
            relatedPaths: relatedPaths
        )
        tracker.recordMiss(
            resolver: "active_state",
            entityID: entityID,
            durationMs: msSince(started),
            outcome: activeConf.rawValue.uppercased()
        )
        return (active, activeConf, activeComp, activeReasons)
    }

    static func mergeClaim(existing: ObservationRecord, resolved: ObservationRecord) -> ObservationRecord {
        if existing.confidence == .verified { return existing }
        if resolved.confidence == .verified { return resolved }
        if existing.confidence == .inferred, resolved.confidence == .unknown { return existing }
        if existing.value != resolved.value, existing.confidence != .unknown, resolved.confidence != .unknown {
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .unknown,
                reasonCode: "EVIDENCE_CONFLICT"
            )
        }
        return resolved.confidence.rank >= existing.confidence.rank ? resolved : existing
    }

    static func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

private extension EvidenceConfidence {
    var rank: Int {
        switch self {
        case .verified: return 3
        case .inferred: return 2
        case .unknown: return 1
        }
    }
}
