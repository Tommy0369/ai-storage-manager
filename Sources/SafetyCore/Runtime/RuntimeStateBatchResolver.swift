import Foundation

public enum RuntimeStateBatchResolver {
    public static func resolveAll(
        entities: [DetectedEntity],
        verifications: [String: VerificationAnnotation],
        plans: [String: RuntimeRequirementPlan],
        index: RuntimeObservationIndex,
        processCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness
    ) -> (resolutions: [String: RuntimeStateResolution], report: RuntimeBatchResolutionReport, plannerMs: Int) {
        let batchStarted = Date()
        var out: [String: RuntimeStateResolution] = [:]
        var required = 0
        var deferred = 0
        var activeResolved = 0
        var openResolved = 0
        var positiveExact = 0
        var verifiedInactive = 0
        var unknownIncomplete = 0
        var conflicts = 0
        var lookupMsTotal = 0

        for entity in entities {
            let id = entity.entity.id
            let verification = verifications[id] ?? VerificationAnnotation()
            let plan = plans[id] ?? RuntimeRequirementPlan(
                needsActive: true,
                needsOpenFile: true,
                need: .requiredNow,
                deferReason: nil,
                deferReasons: []
            )

            if plan.need == .notRequiredForCurrentDecision {
                deferred += 1
                out[id] = RuntimeStateResolution(
                    entityID: id,
                    disposition: .deferred,
                    deferReason: plan.deferReason,
                    activeState: verification.activeState,
                    activeStateConfidence: verification.activeStateConfidence,
                    activeStateCompleteness: verification.activeStateCompleteness,
                    openFileHandle: .unknown,
                    openFileConfidence: .unknown,
                    unknownReasons: plan.deferReason.map { ["DEFERRED:\($0.rawValue)"] } ?? ["DEFERRED:NOT_DECISION_RELEVANT"],
                    lookupMs: 0
                )
                continue
            }

            required += 1
            let lookupStarted = Date()
            let contract = RuntimeSensitiveContract.forEntity(entity)
            let related = contract.relatedExactPaths

            if verification.activeStateConfidence == .verified {
                let open = (plan.needsOpenFile || contract.allowsDescendantOpenMatch)
                    ? openForPaths([entity.entity.path] + related, index: index)
                    : .unknown
                let openConf = openFileConfidence(open: open, needed: plan.needsOpenFile, completeness: handleCompleteness)
                let resolution = RuntimeStateResolution(
                    entityID: id,
                    disposition: .resolved,
                    deferReason: nil,
                    activeState: verification.activeState,
                    activeStateConfidence: verification.activeStateConfidence,
                    activeStateCompleteness: verification.activeStateCompleteness,
                    openFileHandle: open,
                    openFileConfidence: openConf,
                    unknownReasons: [],
                    lookupMs: msSince(lookupStarted)
                )
                out[id] = resolution
                activeResolved += 1
                openResolved += 1
                lookupMsTotal += resolution.lookupMs
                if verification.activeState == .active { positiveExact += 1 }
                if verification.activeState == .inactive { verifiedInactive += 1 }
                continue
            }

            let resolved = resolveActiveOpen(
                entity: entity,
                relatedPaths: related,
                contract: contract,
                index: index,
                processCompleteness: entity.associatedProcesses.isEmpty ? .unknown : processCompleteness,
                handleCompleteness: handleCompleteness,
                plan: plan
            )
            let lookupMs = msSince(lookupStarted)
            lookupMsTotal += lookupMs

            var final = resolved
            final.lookupMs = lookupMs
            out[id] = final
            activeResolved += 1
            openResolved += 1
            if final.activeState == .active, final.activeStateConfidence == .verified { positiveExact += 1 }
            if final.activeState == .inactive, final.activeStateConfidence == .verified { verifiedInactive += 1 }
            if final.activeStateConfidence == .unknown || final.openFileConfidence == .unknown { unknownIncomplete += 1 }
            if final.unknownReasons.contains(where: { $0.contains("CONFLICT") }) { conflicts += 1 }
        }

        let batchMs = msSince(batchStarted)
        let report = RuntimeBatchResolutionReport(
            totalEntities: entities.count,
            runtimeResolutionRequired: required,
            runtimeResolutionDeferred: deferred,
            activeResolved: activeResolved,
            openResolved: openResolved,
            positiveExactMatches: positiveExact,
            verifiedInactive: verifiedInactive,
            unknownIncompleteObservation: unknownIncomplete,
            conflicts: conflicts,
            indexEntries: index.exactOpenPaths.count + index.referencedCommandPaths.count,
            indexBuildRuntimeMs: index.buildRuntimeMs,
            batchLookupRuntimeMs: lookupMsTotal,
            totalRuntimeResolutionMs: batchMs,
            deferPlannerMs: 0
        )
        return (out, report, 0)
    }

    public static func resolveActiveOpen(
        entity: DetectedEntity,
        relatedPaths: [String],
        contract: RuntimeSensitiveContract,
        index: RuntimeObservationIndex,
        processCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness,
        plan: RuntimeRequirementPlan
    ) -> RuntimeStateResolution {
        var reasons: [String] = []
        let paths = [entity.entity.path] + relatedPaths
        var open: PredicateValue = .false
        if plan.needsOpenFile {
            open = openForPaths(paths, index: index)
            if handleCompleteness != .complete, open == .unknown {
                reasons.append(UnknownReasonCode.unknownEvidenceIncomplete.rawValue)
                return makeUnknown(entityID: entity.entity.id, open: open, reasons: reasons, handleCompleteness: handleCompleteness, plan: plan)
            }
            if open == .true {
                return RuntimeStateResolution(
                    entityID: entity.entity.id,
                    disposition: .resolved,
                    deferReason: nil,
                    activeState: .active,
                    activeStateConfidence: .verified,
                    activeStateCompleteness: .complete,
                    openFileHandle: .true,
                    openFileConfidence: .verified,
                    unknownReasons: [],
                    lookupMs: 0
                )
            }
        } else {
            open = .unknown
        }

        if plan.needsActive || plan.needsOpenFile {
            for p in paths where index.referencesPath(p, contract: contract) {
                return RuntimeStateResolution(
                    entityID: entity.entity.id,
                    disposition: .resolved,
                    deferReason: nil,
                    activeState: .active,
                    activeStateConfidence: .verified,
                    activeStateCompleteness: .complete,
                    openFileHandle: open,
                    openFileConfidence: openFileConfidence(open: open, needed: plan.needsOpenFile, completeness: handleCompleteness),
                    unknownReasons: [],
                    lookupMs: 0
                )
            }
        }

        let running: PredicateValue
        if entity.associatedProcesses.isEmpty {
            running = .unknown
            reasons.append(UnknownReasonCode.unknownProcessObservation.rawValue)
        } else if processCompleteness != .complete {
            running = .unknown
            reasons.append(UnknownReasonCode.unknownEvidenceIncomplete.rawValue)
        } else {
            running = index.isRunning(executableNames: entity.associatedProcesses)
        }

        if running == .true, open == .false, handleCompleteness == .complete, plan.needsOpenFile {
            reasons.append(UnknownReasonCode.unknownActiveState.rawValue)
            return RuntimeStateResolution(
                entityID: entity.entity.id,
                disposition: .resolved,
                deferReason: nil,
                activeState: .unknown,
                activeStateConfidence: .inferred,
                activeStateCompleteness: .partial,
                openFileHandle: open,
                openFileConfidence: openFileConfidence(open: open, needed: plan.needsOpenFile, completeness: handleCompleteness),
                unknownReasons: reasons,
                lookupMs: 0
            )
        }

        if processCompleteness == .complete, handleCompleteness == .complete,
           running == .false, open == .false, !entity.associatedProcesses.isEmpty, plan.needsActive {
            return RuntimeStateResolution(
                entityID: entity.entity.id,
                disposition: .resolved,
                deferReason: nil,
                activeState: .inactive,
                activeStateConfidence: .verified,
                activeStateCompleteness: .complete,
                openFileHandle: open,
                openFileConfidence: openFileConfidence(open: open, needed: plan.needsOpenFile, completeness: handleCompleteness),
                unknownReasons: [],
                lookupMs: 0
            )
        }

        reasons.append(UnknownReasonCode.unknownActiveState.rawValue)
        return makeUnknown(entityID: entity.entity.id, open: open, reasons: reasons, handleCompleteness: handleCompleteness, plan: plan)
    }

    public static func resolveReference(
        entity: DetectedEntity,
        processes: any ProcessRunningChecker,
        handles: any OpenHandleChecker,
        processCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness
    ) -> (ObservedActiveState, EvidenceConfidence, ObservationCompleteness, [String]) {
        let related = VerificationStrategies.claudeRelatedPaths(entity: entity)
        return ActiveStateResolver.resolve(
            entityPath: entity.entity.path,
            associatedProcesses: entity.associatedProcesses,
            processes: processes,
            handles: handles,
            processCompleteness: processCompleteness,
            handleCompleteness: handleCompleteness,
            relatedPaths: related
        )
    }

    static func openForPaths(_ paths: [String], index: RuntimeObservationIndex) -> PredicateValue {
        var open: PredicateValue = .false
        for p in paths {
            let v = index.openHandleMatchingReference(path: p)
            if v == .true { return .true }
            if v == .unknown { open = .unknown }
        }
        return open
    }

    static func openFileConfidence(open: PredicateValue, needed: Bool, completeness: ObservationCompleteness) -> EvidenceConfidence {
        if !needed { return .unknown }
        if completeness != .complete { return .unknown }
        return open == .unknown ? .unknown : .verified
    }

    static func makeUnknown(
        entityID: String,
        open: PredicateValue,
        reasons: [String],
        handleCompleteness: ObservationCompleteness,
        plan: RuntimeRequirementPlan
    ) -> RuntimeStateResolution {
        RuntimeStateResolution(
            entityID: entityID,
            disposition: .resolved,
            deferReason: nil,
            activeState: .unknown,
            activeStateConfidence: .unknown,
            activeStateCompleteness: .partial,
            openFileHandle: open,
            openFileConfidence: openFileConfidence(open: open, needed: plan.needsOpenFile, completeness: handleCompleteness),
            unknownReasons: reasons,
            lookupMs: 0
        )
    }

    static func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
