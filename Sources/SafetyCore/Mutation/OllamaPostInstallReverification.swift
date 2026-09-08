import Foundation

/// Post-install read-only re-proof. Never creates model-removal approval or cleanup permit.
public enum OllamaPostInstallReverification {
    public struct Result: Sendable {
        public var outcome: PostInstallRestorePhaseOutcome
        public var restore: VendorManagementRestoreResult
        public var interface: OllamaNativeInterfaceResolution?
        public var inventory: OllamaInstalledModelInventory.Snapshot?
        public var recognitionStatus: InstalledModelRecognitionStatus?
        public var recognizedCanonical: String?
        public var runtimeProof: OllamaExactRuntimeProof?
        public var preflight: FreshReadOnlyPreflightEngine.RunResult?
        public var remainingBlockers: [String]
        public var uxPrimaryLabel: String
        public var uxSecondaryLabel: String?
        public var modelRemovalApprovalCreated: Bool
        public var cleanupExecutionPermitCreated: Bool
        public var cleanupExecutorInvoked: Bool
        public var ollamaRmExecuted: Bool
        public var modelPullExecuted: Bool
        public var modelRunExecuted: Bool
        public var rawDeletionExecuted: Bool
        public var priorCleanupProofsInvalidated: Bool
    }

    public struct Context: Sendable {
        public var processRunner: any BoundedProcessRunner
        public var fileManager: FileManager
        public var modelDataPresent: Bool
        public var bundleLookup: (@Sendable ([String]) -> (id: String, url: URL, version: String?)?)?
        public var httpGET: (@Sendable (URL) -> (status: Int, body: Data)?)?
        public var now: Date

        public init(
            processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
            fileManager: FileManager = .default,
            modelDataPresent: Bool = true,
            bundleLookup: (@Sendable ([String]) -> (id: String, url: URL, version: String?)?)? = nil,
            httpGET: (@Sendable (URL) -> (status: Int, body: Data)?)? = nil,
            now: Date = Date()
        ) {
            self.processRunner = processRunner
            self.fileManager = fileManager
            self.modelDataPresent = modelDataPresent
            self.bundleLookup = bundleLookup
            self.httpGET = httpGET
            self.now = now
        }
    }

    /// After install: trust nothing old. Re-resolve interface, inventory, runtime.
    /// Optionally run Fresh Preflight when caller supplies scan materials.
    public static func reverify(
        restore: VendorManagementRestoreResult,
        targetEntityID: String,
        targetCanonicalModel: String,
        preInstall: PreInstallManagedDataReceipt,
        context: Context = Context(),
        freshPreflight: (
            (
                _ interface: OllamaNativeInterfaceResolution,
                _ runner: any BoundedProcessRunner
            ) -> FreshReadOnlyPreflightEngine.RunResult?
        )? = nil
    ) -> Result {
        var blockers: [String] = []
        let invalidated = true // install always invalidates prior cleanup proofs

        if restore.unexpectedDataMutation {
            return Result(
                outcome: .dataDamageStop,
                restore: restore,
                interface: nil,
                inventory: nil,
                recognitionStatus: .dataUnexpectedlyAltered,
                recognizedCanonical: nil,
                runtimeProof: nil,
                preflight: nil,
                remainingBlockers: ["UNEXPECTED_MODEL_DATA_LOSS"],
                uxPrimaryLabel: OllamaRestoreUXLabel.moreVerificationRequired,
                uxSecondaryLabel: nil,
                modelRemovalApprovalCreated: false,
                cleanupExecutionPermitCreated: false,
                cleanupExecutorInvoked: false,
                ollamaRmExecuted: false,
                modelPullExecuted: false,
                modelRunExecuted: false,
                rawDeletionExecuted: false,
                priorCleanupProofsInvalidated: invalidated
            )
        }

        guard restore.installationSucceeded else {
            return Result(
                outcome: .installFailed,
                restore: restore,
                interface: nil,
                inventory: nil,
                recognitionStatus: nil,
                recognizedCanonical: nil,
                runtimeProof: nil,
                preflight: nil,
                remainingBlockers: [restore.failureReason ?? "INSTALL_FAILED"],
                uxPrimaryLabel: OllamaRestoreUXLabel.moreVerificationRequired,
                uxSecondaryLabel: nil,
                modelRemovalApprovalCreated: false,
                cleanupExecutionPermitCreated: false,
                cleanupExecutorInvoked: false,
                ollamaRmExecuted: false,
                modelPullExecuted: false,
                modelRunExecuted: false,
                rawDeletionExecuted: false,
                priorCleanupProofsInvalidated: invalidated
            )
        }

        // Post-install presence check vs pre-install receipt.
        let rootStill = context.fileManager.fileExists(atPath: preInstall.managedDataRootPath)
        let manifestPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(OllamaManagementRestoreInstaller.qwenManifestRelativePath)
        let manifestStill = context.fileManager.fileExists(atPath: manifestPath)
        if preInstall.manifestPresentOnDisk && !manifestStill {
            return Result(
                outcome: .dataDamageStop,
                restore: restore,
                interface: nil,
                inventory: nil,
                recognitionStatus: .dataUnexpectedlyAltered,
                recognizedCanonical: nil,
                runtimeProof: nil,
                preflight: nil,
                remainingBlockers: ["MANIFEST_MISSING_AFTER_INSTALL"],
                uxPrimaryLabel: OllamaRestoreUXLabel.moreVerificationRequired,
                uxSecondaryLabel: nil,
                modelRemovalApprovalCreated: false,
                cleanupExecutionPermitCreated: false,
                cleanupExecutorInvoked: false,
                ollamaRmExecuted: false,
                modelPullExecuted: false,
                modelRunExecuted: false,
                rawDeletionExecuted: false,
                priorCleanupProofsInvalidated: invalidated
            )
        }
        if preInstall.managedDataRootExists && !rootStill {
            blockers.append("MANAGED_DATA_ROOT_MISSING_AFTER_INSTALL")
        }

        let ifaceCtx = OllamaNativeInterfaceResolver.Context(
            fileManager: context.fileManager,
            processRunner: context.processRunner,
            modelDataPresent: context.modelDataPresent || rootStill,
            httpGET: context.httpGET,
            bundleLookup: context.bundleLookup,
            now: context.now
        )
        let interface = OllamaNativeInterfaceResolver.resolve(context: ifaceCtx)
        var restoreMut = restore
        restoreMut.nativeInterfaceDetected = interface.cliResolved || interface.ollamaAppFound
        if interface.bundleIdentifier != nil {
            restoreMut.bundleIdentifier = interface.bundleIdentifier
        }
        if restoreMut.installedVersion == nil {
            restoreMut.installedVersion = interface.cliVersion ?? interface.bundleVersion
        }

        if !interface.cliResolved {
            blockers.append("OLLAMA_EXECUTABLE_UNRESOLVED")
        }
        if !interface.supportsPS {
            blockers.append("OLLAMA_SUPPORTS_PS_FALSE")
        }
        if !interface.supportsRM {
            blockers.append("OLLAMA_SUPPORTS_RM_FALSE")
            blockers.append("EXECUTOR_CONTRACT_UNAVAILABLE")
        }

        var inventory: OllamaInstalledModelInventory.Snapshot?
        var recognition: InstalledModelRecognitionStatus = .inventoryUnavailable
        var recognizedCanonical: String?
        if let cliPath = interface.cliExecutableURL {
            let snap = OllamaInstalledModelInventory.capture(
                cliURL: URL(fileURLWithPath: cliPath),
                runner: context.processRunner,
                now: context.now
            )
            inventory = snap
            recognition = OllamaInstalledModelInventory.recognition(
                targetCanonical: targetCanonicalModel,
                inventory: snap
            )
            if recognition == .recognizedExact {
                recognizedCanonical = targetCanonicalModel
            } else if recognition == .dataRemainsUnrecognized {
                blockers.append("MODEL_NOT_RECOGNIZED_BY_VENDOR_INVENTORY")
            } else if recognition == .identityAmbiguous {
                blockers.append("MODEL_IDENTITY_AMBIGUOUS")
            } else {
                blockers.append("MODEL_INVENTORY_UNAVAILABLE")
            }
        } else {
            blockers.append("MODEL_INVENTORY_UNAVAILABLE")
        }

        if recognition == .dataRemainsUnrecognized {
            return Result(
                outcome: .vendorRestoredModelUnrecognized,
                restore: restoreMut,
                interface: interface,
                inventory: inventory,
                recognitionStatus: recognition,
                recognizedCanonical: nil,
                runtimeProof: nil,
                preflight: nil,
                remainingBlockers: Array(Set(blockers)).sorted(),
                uxPrimaryLabel: OllamaRestoreUXLabel.managementRestored,
                uxSecondaryLabel: OllamaRestoreUXLabel.moreVerificationRequired,
                modelRemovalApprovalCreated: false,
                cleanupExecutionPermitCreated: false,
                cleanupExecutorInvoked: false,
                ollamaRmExecuted: false,
                modelPullExecuted: false,
                modelRunExecuted: false,
                rawDeletionExecuted: false,
                priorCleanupProofsInvalidated: invalidated
            )
        }

        var proof = OllamaNativeInterfaceResolver.proveExactRuntime(
            canonicalModel: targetCanonicalModel,
            resolution: interface,
            context: ifaceCtx
        )
        proof.targetEntityID = targetEntityID

        if proof.isStrictActive {
            return Result(
                outcome: .blockedActive,
                restore: restoreMut,
                interface: interface,
                inventory: inventory,
                recognitionStatus: recognition,
                recognizedCanonical: recognizedCanonical,
                runtimeProof: proof,
                preflight: nil,
                remainingBlockers: ["OLLAMA_MODEL_RUNTIME_ACTIVE_VERIFIED"],
                uxPrimaryLabel: OllamaRestoreUXLabel.managementRestored,
                uxSecondaryLabel: OllamaRestoreUXLabel.modelCurrentlyActive,
                modelRemovalApprovalCreated: false,
                cleanupExecutionPermitCreated: false,
                cleanupExecutorInvoked: false,
                ollamaRmExecuted: false,
                modelPullExecuted: false,
                modelRunExecuted: false,
                rawDeletionExecuted: false,
                priorCleanupProofsInvalidated: invalidated
            )
        }
        if !proof.isStrictInactive {
            blockers.append("OLLAMA_MODEL_RUNTIME_NOT_INACTIVE_VERIFIED")
        }

        var preflightResult: FreshReadOnlyPreflightEngine.RunResult?
        if recognition == .recognizedExact,
           interface.supportsRM,
           let runnerPreflight = freshPreflight {
            preflightResult = runnerPreflight(interface, context.processRunner)
            if let pf = preflightResult {
                let rawBlockers = pf.freshGateResult.blockingReasons + pf.freshGateResult.missingRequirements
                let ready = pf.freshGateResult.readiness == MutationReadiness.approvalRequired.rawValue
                    || pf.freshGateResult.readiness == MutationReadiness.contractSatisfiedReadOnly.rawValue
                // At APPROVAL_REQUIRED, only USER_APPROVAL may remain — drop soft/stale residue.
                if ready, proof.isStrictInactive {
                    let technical = rawBlockers.filter {
                        OllamaVendorNativeStrictPredicateCatalog.isTechnicalMissing($0)
                            && $0 != ActionBlockReason.regenerabilityUnknown.rawValue
                    }
                    blockers = technical.isEmpty ? ["USER_APPROVAL"] : Array(Set(technical)).sorted()
                    let outcome: PostInstallRestorePhaseOutcome =
                        technical.isEmpty
                        ? (pf.freshGateResult.readiness == MutationReadiness.approvalRequired.rawValue
                            ? .approvalRequired
                            : .readyForModelRemovalAuthorization)
                        : .verifyMore
                    return Result(
                        outcome: outcome,
                        restore: restoreMut,
                        interface: interface,
                        inventory: inventory,
                        recognitionStatus: recognition,
                        recognizedCanonical: recognizedCanonical,
                        runtimeProof: proof,
                        preflight: pf,
                        remainingBlockers: blockers,
                        uxPrimaryLabel: technical.isEmpty
                            ? OllamaRestoreUXLabel.readyForReview
                            : OllamaRestoreUXLabel.moreVerificationRequired,
                        uxSecondaryLabel: technical.isEmpty
                            ? OllamaRestoreUXLabel.removeOllamaModel
                            : nil,
                        modelRemovalApprovalCreated: false,
                        cleanupExecutionPermitCreated: false,
                        cleanupExecutorInvoked: false,
                        ollamaRmExecuted: false,
                        modelPullExecuted: false,
                        modelRunExecuted: false,
                        rawDeletionExecuted: false,
                        priorCleanupProofsInvalidated: invalidated
                    )
                }
                blockers = Array(Set(rawBlockers.filter {
                    $0 != ActionBlockReason.regenerabilityUnknown.rawValue
                })).sorted()
            }
        }

        return Result(
            outcome: .verifyMore,
            restore: restoreMut,
            interface: interface,
            inventory: inventory,
            recognitionStatus: recognition,
            recognizedCanonical: recognizedCanonical,
            runtimeProof: proof,
            preflight: preflightResult,
            remainingBlockers: Array(Set(blockers)).sorted(),
            uxPrimaryLabel: OllamaRestoreUXLabel.managementRestored,
            uxSecondaryLabel: OllamaRestoreUXLabel.checkingSafety,
            modelRemovalApprovalCreated: false,
            cleanupExecutionPermitCreated: false,
            cleanupExecutorInvoked: false,
            ollamaRmExecuted: false,
            modelPullExecuted: false,
            modelRunExecuted: false,
            rawDeletionExecuted: false,
            priorCleanupProofsInvalidated: invalidated
        )
    }
}
