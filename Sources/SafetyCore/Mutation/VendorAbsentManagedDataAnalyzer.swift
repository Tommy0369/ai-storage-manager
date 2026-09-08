import Foundation

/// Read-only classifier for vendor-absent managed data. No install. No delete. No SafetyClass assignment.
public enum VendorAbsentManagedDataAnalyzer {
    public static let notePrefix = "VENDOR_MANAGED_DATA_AVAILABILITY="

    public static func evaluateOllamaModel(
        item: ClassifiedItem,
        interface: OllamaNativeInterfaceResolution,
        now: Date = Date()
    ) -> VendorManagedDataRemediation {
        let entityID = item.detected.entity.id
        let model = ActionPolicy.ollamaCanonicalModelName(from: item) ?? item.detected.entity.displayName
        let ownership = ActionPolicy.isOllamaModelEntity(item)
            && item.verification?.referenceGraphConfidence == .verified
        let remoteOK = item.verification?.remoteReacquisitionProof?.isStrictVerified == true
            || item.verification?.reacquisition.confidence == .verified
                && item.verification?.reacquisition.value == .true

        let customProtected = item.verification?.vendorProofNotes.contains(where: {
            $0.contains("USER_ORIGINAL") || $0.contains("CUSTOM")
        }) == true || item.detected.annotation?.lifecycle.role == .userContent

        let format = assessLocalFormatCompatibility(item: item)
        let appAbsent = !interface.ollamaAppFound
            && !interface.cliResolved
            && !interface.localAPIReachable
        let modelDataPresent = interface.installReality == .staleModelDataWithNoInstall
            || interface.resolutionEvidence.contains("MODEL_DATA_PRESENT")
            || FileManager.default.fileExists(
                atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
            )

        if !ActionPolicy.isOllamaModelEntity(item) {
            return remediation(
                vendor: .ollama,
                entityID: entityID,
                model: model,
                availability: .notApplicable,
                native: false,
                kind: .verifyMore,
                flow: .staleVendorDataDetected,
                install: false,
                ownership: false,
                remote: false,
                format: .unknown,
                explanation: "Not an Ollama model entity. Reinstall is not an authoritative cleanup route.",
                now: now
            )
        }

        if !ownership {
            return remediation(
                vendor: .ollama,
                entityID: entityID,
                model: model,
                availability: .vendorInstallStateUnknown,
                native: interface.executionTransportAvailable,
                kind: .verifyMore,
                flow: .staleVendorDataDetected,
                install: false,
                ownership: false,
                remote: remoteOK,
                format: format,
                explanation: "Files resemble Ollama storage, but semantic ownership is not VERIFIED. Do not treat reinstall as authoritative cleanup.",
                now: now
            )
        }

        if customProtected {
            return remediation(
                vendor: .ollama,
                entityID: entityID,
                model: model,
                availability: appAbsent && modelDataPresent
                    ? .vendorAbsentManagedDataRemains
                    : .vendorPresentNativeInterfaceUnavailable,
                native: false,
                kind: .keep,
                flow: .staleVendorDataDetected,
                install: false,
                ownership: true,
                remote: remoteOK,
                format: format,
                explanation: "Custom/user-original model data remains protected. Reinstall may be informational only; cleanup stays blocked.",
                now: now
            )
        }

        if interface.executionTransportAvailable {
            return remediation(
                vendor: .ollama,
                entityID: entityID,
                model: model,
                availability: .vendorPresentNativeInterfaceAvailable,
                native: true,
                kind: .verifyMore,
                flow: .staleVendorDataDetected,
                install: false,
                ownership: true,
                remote: remoteOK,
                format: format,
                explanation: "Ollama native interface is available. Continue normal cleanup Fresh Preflight — not install remediation.",
                now: now
            )
        }

        if interface.ollamaAppFound || interface.localAPIReachable || interface.cliResolved {
            return remediation(
                vendor: .ollama,
                entityID: entityID,
                model: model,
                availability: .vendorPresentNativeInterfaceUnavailable,
                native: false,
                kind: .verifyMore,
                flow: .staleVendorDataDetected,
                install: false,
                ownership: true,
                remote: remoteOK,
                format: format,
                explanation: "Ollama appears present but native cleanup transport is not proven. Continue interface/runtime verification.",
                now: now
            )
        }

        if appAbsent && modelDataPresent {
            let explanation = """
            Ollama is no longer installed, but approximately \(Self.byteLabel(item.exclusiveBytes)) of Ollama-managed model data remains. \
            AI Storage Manager will not delete these internal model files directly. \
            Reinstalling Ollama may restore its native model-management interface, allowing the model to be removed safely using Ollama.
            """
            return remediation(
                vendor: .ollama,
                entityID: entityID,
                model: model,
                availability: .vendorAbsentManagedDataRemains,
                native: false,
                kind: .reinstallVendorToRestoreNativeManagement,
                flow: .installAuthorizationRequired,
                install: true,
                ownership: true,
                remote: remoteOK,
                format: format,
                explanation: explanation,
                now: now
            )
        }

        return remediation(
            vendor: .ollama,
            entityID: entityID,
            model: model,
            availability: .vendorInstallStateUnknown,
            native: false,
            kind: .verifyMore,
            flow: .staleVendorDataDetected,
            install: false,
            ownership: ownership,
            remote: remoteOK,
            format: format,
            explanation: "Ollama install state could not be classified strictly.",
            now: now
        )
    }

    /// Bounded read-only layout clues. Never mutates.
    public static func assessLocalFormatCompatibility(item: ClassifiedItem) -> VendorLocalFormatCompatibility {
        let path = item.detected.entity.path
        let lower = path.lowercased()
        guard lower.contains("/.ollama/models") || lower.contains("/ollama/models") else {
            return .unknown
        }
        let modelsRoot: String
        if let range = lower.range(of: "/.ollama/models") {
            let end = path.index(path.startIndex, offsetBy: path.distance(from: path.startIndex, to: range.upperBound))
            modelsRoot = String(path[..<end])
        } else {
            modelsRoot = (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
        }
        let manifests = (modelsRoot as NSString).appendingPathComponent("manifests")
        let blobs = (modelsRoot as NSString).appendingPathComponent("blobs")
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifests), fm.fileExists(atPath: blobs) else {
            return .unknown
        }
        // Manifest JSON with schemaVersion / layers is the known Ollama layout.
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let hasLayers = obj["layers"] != nil
            let hasSchema = obj["schemaVersion"] != nil || obj["mediaType"] != nil
            if hasLayers && hasSchema {
                return .likelyCompatibleInferred
            }
        }
        // Directory layout alone is not COMPATIBLE_VERIFIED.
        return .likelyCompatibleInferred
    }

    public static func remediationPlanSteps() -> [VendorRemediationPlanStep] {
        [
            .init(order: 1, stepID: "restore_vendor", title: "Restore/reinstall Ollama", readOnly: false, requiresHumanAuthorization: true, canMutateUserData: false),
            .init(order: 2, stepID: "reverify_interface", title: "Reverify native CLI/API interface", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
            .init(order: 3, stepID: "reverify_model_recognition", title: "Confirm installed inventory recognizes exact model", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
            .init(order: 4, stepID: "reverify_manifest", title: "Rebind local manifest fingerprint", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
            .init(order: 5, stepID: "reverify_reference_graph", title: "Recompute reference graph", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
            .init(order: 6, stepID: "reverify_runtime", title: "COMPLETE running-model snapshot; target INACTIVE VERIFIED", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
            .init(order: 7, stepID: "refresh_remote_proof", title: "Refresh remote reacquisition if stale", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
            .init(order: 8, stepID: "cleanup_preflight", title: "Fresh cleanup preflight", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
            .init(order: 9, stepID: "cleanup_human_approval", title: "Separate human deletion approval", readOnly: false, requiresHumanAuthorization: true, canMutateUserData: false),
            .init(order: 10, stepID: "cleanup_execution", title: "Vendor-native ollama rm", readOnly: false, requiresHumanAuthorization: true, canMutateUserData: true),
            .init(order: 11, stepID: "postverify", title: "Post-mutation verification", readOnly: true, requiresHumanAuthorization: false, canMutateUserData: false),
        ]
    }

    public static func stamp(_ remediation: VendorManagedDataRemediation, onto notes: inout [String]) {
        notes.removeAll { $0.hasPrefix(notePrefix) || $0.hasPrefix("VENDOR_REMEDIATION=") }
        notes.append("\(notePrefix)\(remediation.managedDataAvailability.rawValue)")
        notes.append("VENDOR_REMEDIATION=\(remediation.recommendedRemediation.rawValue)")
    }

    private static func remediation(
        vendor: VendorStorageKind,
        entityID: String,
        model: String,
        availability: VendorManagedDataAvailability,
        native: Bool,
        kind: VendorManagedDataRemediationKind,
        flow: VendorRemediationFlowState,
        install: Bool,
        ownership: Bool,
        remote: Bool,
        format: VendorLocalFormatCompatibility,
        explanation: String,
        now: Date
    ) -> VendorManagedDataRemediation {
        VendorManagedDataRemediation(
            vendor: vendor,
            entityID: entityID,
            canonicalModel: model,
            managedDataAvailability: availability,
            nativeCleanupAvailable: native,
            recommendedRemediation: kind,
            flowState: flow,
            requiresSoftwareInstall: install,
            softwareInstallAuthorized: false,
            cleanupRequiresNewPreflight: true,
            cleanupRequiresSeparateApproval: true,
            rawDeleteAllowed: false,
            localFormatCompatibility: format,
            semanticOwnershipVerified: ownership,
            remoteReacquisitionVerified: remote,
            installationSource: .unknown,
            explanation: explanation,
            observedAt: now
        )
    }

    private static func byteLabel(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.0f MB", mb)
    }
}
