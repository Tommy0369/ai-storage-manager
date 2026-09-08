#!/usr/bin/env python3
"""Compile Safety Knowledge Base. Does not destroy bootstrap source."""
from __future__ import annotations

import json
import shutil
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "knowledge" / "source"
COMPILED = ROOT / "knowledge" / "compiled"
SCHEMA = ROOT / "knowledge" / "schema"
VERSIONS = ROOT / "knowledge" / "versions"
SWIFT_COMPILED = ROOT / "Sources/SafetyCore/Resources/knowledge/compiled_rules_v0.1.json"
BOOTSTRAP = SRC / "bootstrap_rules_v0.1.json"
BOOTSTRAP_IDS = {
    "system.sip_root", "system.usr", "macos.keychain", "user.documents", "user.desktop",
    "user.photos_library", "macos.application_support", "macos.user_caches", "macos.tmpdir",
    "macos.logs", "user.downloads", "macos.trash", "icloud.local_materialized",
    "xcode.derived_data", "xcode.module_cache", "xcode.archives", "xcode.simulator_devices",
    "xcode.simulator_runtimes", "xcode.source_packages", "xcode.device_support",
    "node.npm_cache", "node.node_modules", "node.pnpm_store", "node.yarn_cache",
    "docker.build_cache", "docker.images", "docker.containers", "docker.volumes",
    "homebrew.cache", "python.pip_cache", "python.venv", "git.dot_git", "git.worktree_metadata",
    "ai.cursor_logs", "ai.cursor_app_support", "ai.claude_settings", "ai.claude_md",
    "ai.claude_sessions", "ai.ollama_models", "ai.huggingface_cache", "ai.lm_studio",
    "ai.unknown_embeddings", "media.final_cut_generated", "backup.ios", "backup.time_machine_local",
}

CLASSES = {"GREEN", "YELLOW", "RED", "UNKNOWN"}
ACTIONS = {
    "HARD_BLOCK", "NO_ACTION", "USER_REVIEW", "MOVE_TO_TRASH",
    "OS_API_ONLY", "APP_API_ONLY", "TOOL_CLI_ONLY", "PACKAGE_MANAGER_COMMAND",
    "APP_UNINSTALL", "CLOUD_EVICT_ONLY",
}
LAYERS = {
    "HARD_BLOCK", "USER_PROTECTION", "SOURCE_OF_TRUTH", "ACTIVE_USE",
    "SYNC_BLAST_RADIUS", "EXACT_VENDOR_RULE", "RUNTIME_PREDICATES",
    "GENERIC_CACHE_TEMP", "UNKNOWN_FALLBACK",
}
ALLOWED_PREDICATES = {
    "canonical_path", "owner_current_user", "not_symlink", "no_open_file_handle",
    "owning_process_not_running", "not_source_of_truth", "regenerable",
    "source_project_exists", "manifest_exists", "lockfile_exists", "backup_exists",
    "sync_would_not_delete_remote", "not_sip_protected", "icloud_evictable",
    "always", "active_file_handles", "unknown_bundle_owner", "source_project_missing",
    "unknown_manual_files_present", "sync_in_progress", "sync_would_delete_remote",
    "offline_needed", "private_dependency", "local_patch", "zero_install",
    "manifest_missing", "unpushed_local_image", "container_running",
    "simulator_booted", "worktree_still_checked_out", "model_in_use",
    "active_vector_db",
}


def rule(
    rid, entity, category, subcategory, path, default_class, layer, action,
    explanation, reasons, *, score=0, sot=False, regenerable=False, network=False,
    preds=None, yellow=None, red=None, hard=None, effects=None, verify=None,
    causes=None, native=None, signals=None, recovery=None, owner="current_user",
):
    return {
        "id": rid,
        "entity": entity,
        "category": category,
        "subcategory": subcategory,
        "match": {"path": path, "owner": owner, "follow_symlinks": False},
        "default_class": default_class,
        "base_score": score,
        "evaluation_layer": layer,
        "source_of_truth": sot,
        "regenerable": regenerable,
        "network_required": network,
        "required_predicates": preds or [],
        "demote_to_yellow_if": yellow or [],
        "demote_to_red_if": red or [],
        "hard_block_if": hard or [],
        "action_mode": action,
        "effects": effects or [],
        "verification": verify or [],
        "growth_causes": causes or [],
        "explanation_ja": explanation,
        "reason_codes": reasons,
        "rule_version": "0.1",
        "native_cleanup": native,
        "root_cause_signals": signals or [],
        "recovery_estimate_hint": recovery,
    }


GREEN_PREDS = ["regenerable", "not_source_of_truth", "canonical_path", "no_open_file_handle", "owning_process_not_running"]


def extra_rules():
    r = []
    hard = lambda rid, ent, path, exp: rule(
        rid, ent, "MACOS", "SYSTEM", path, "RED", "HARD_BLOCK", "HARD_BLOCK",
        exp, ["HARD_BLOCK"], sot=True, owner="root",
    )
    r += [
        hard("system.bin", "SYSTEM_BIN", "/bin/**", "システムの実行ファイルです。"),
        hard("system.sbin", "SYSTEM_SBIN", "/sbin/**", "システムの管理コマンドです。"),
        hard("system.private_var_db", "SYSTEM_VAR_DB", "/private/var/db/**", "システムの構成データベースです。"),
        hard("system.private_etc", "SYSTEM_ETC", "/private/etc/**", "システムの設定です。"),
        hard("system.preboot", "SYSTEM_PREBOOT", "/System/Volumes/Preboot/**", "起動用ボリュームです。"),
        hard("system.vm_swap", "SYSTEM_VM", "/private/var/vm/**", "仮想メモリ関連です。"),
        hard("system.library_keychains", "SYSTEM_KEYCHAINS", "/Library/Keychains/**", "システムの証明書保管です。"),
        rule("macos.system_caches", "SYSTEM_CACHES", "MACOS", "CACHE", "/Library/Caches/**", "YELLOW", "GENERIC_CACHE_TEMP", "USER_REVIEW",
             "システムの共有キャッシュです。ユーザーキャッシュより慎重に扱います。", ["SYSTEM_CACHE"], score=40, regenerable=True, preds=["no_open_file_handle"], owner="root"),
        rule("macos.containers", "APP_CONTAINERS", "MACOS", "SANDBOX", "~/Library/Containers/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "サンドボックスアプリのデータ本体です。丸ごと消しません。", ["CONTAINERS"], sot=True, score=5),
        rule("macos.group_containers", "GROUP_CONTAINERS", "MACOS", "SANDBOX", "~/Library/Group Containers/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "アプリ間共有データの本体です。", ["GROUP_CONTAINERS"], sot=True),
        rule("macos.preferences", "PREFERENCES", "MACOS", "SETTINGS", "~/Library/Preferences/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "アプリ設定です。設定の原本です。", ["PREFERENCES"], sot=True),
        rule("macos.saved_state", "SAVED_STATE", "MACOS", "SETTINGS", "~/Library/Saved Application State/**", "YELLOW", "GENERIC_CACHE_TEMP", "USER_REVIEW",
             "ウィンドウ状態です。設定本体より軽いですが、作業中復元に影響します。", ["SAVED_STATE"], score=55, regenerable=True),
        rule("macos.cookies", "COOKIES", "MACOS", "SETTINGS", "~/Library/Cookies/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "サイトのログイン状態を含みます。", ["COOKIES"], sot=True),
        rule("macos.fonts_user", "USER_FONTS", "MACOS", "FONTS", "~/Library/Fonts/**", "RED", "USER_PROTECTION", "NO_ACTION",
             "インストールしたフォントです。再取得できないことがあります。", ["FONTS"], sot=True),
        rule("macos.mail", "MAIL_DATA", "MACOS", "MAIL", "~/Library/Mail/**", "RED", "USER_PROTECTION", "HARD_BLOCK",
             "メールの原本です。", ["MAIL"], sot=True),
        rule("macos.messages", "MESSAGES", "MACOS", "MESSAGES", "~/Library/Messages/**", "RED", "USER_PROTECTION", "HARD_BLOCK",
             "メッセージの原本です。", ["MESSAGES"], sot=True),
        rule("macos.safari", "SAFARI_DATA", "MACOS", "BROWSER", "~/Library/Safari/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Safariの履歴とデータの本体です。キャッシュとは別です。", ["SAFARI"], sot=True),
        rule("macos.chrome_cache", "CHROME_CACHE", "MACOS", "BROWSER", "~/Library/Caches/Google/Chrome/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "Chromeのキャッシュです。ブックマーク本体ではありません。", ["BROWSER_CACHE"], score=82, regenerable=True, preds=GREEN_PREDS),
        rule("macos.chrome_profile", "CHROME_PROFILE", "MACOS", "BROWSER", "~/Library/Application Support/Google/Chrome/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Chromeのプロファイル本体です。", ["BROWSER_PROFILE"], sot=True),
        rule("macos.softwareupdate", "SOFTWAREUPDATE", "MACOS", "UPDATES", "/Library/Updates/**", "YELLOW", "EXACT_VENDOR_RULE", "OS_API_ONLY",
             "macOSアップデートの作業ファイルです。OSの仕組みで扱います。", ["SOFTWAREUPDATE"], score=45, regenerable=True, owner="root"),
        rule("macos.spotlight", "SPOTLIGHT", "MACOS", "INDEX", "/.Spotlight-V100/**", "YELLOW", "GENERIC_CACHE_TEMP", "OS_API_ONLY",
             "Spotlightの索引です。消すと再構築されます。", ["SPOTLIGHT"], score=35, regenerable=True, owner="root"),
        rule("macos.cores", "CORE_DUMPS", "MACOS", "LOGS", "/cores/**", "YELLOW", "GENERIC_CACHE_TEMP", "USER_REVIEW",
             "クラッシュダンプです。本体データではありません。", ["CORES"], score=60, regenerable=False, owner="root"),
        rule("macos.crashreporter", "CRASH_REPORTS", "MACOS", "LOGS", "~/Library/Logs/DiagnosticReports/**", "YELLOW", "GENERIC_CACHE_TEMP", "MOVE_TO_TRASH",
             "診断レポートです。", ["CRASH_REPORTS"], score=65, regenerable=True, preds=["no_open_file_handle"]),
        rule("macos.autosave", "AUTOSAVE", "MACOS", "DOCUMENTS", "~/Library/Autosave Information/**", "YELLOW", "USER_PROTECTION", "USER_REVIEW",
             "未保存文書の自動保存です。原本扱いします。", ["AUTOSAVE"], score=20, sot=False),
        rule("user.movies", "USER_MOVIES", "USER", "ORIGINALS", "~/Movies/**", "RED", "USER_PROTECTION", "NO_ACTION",
             "動画の原本です。", ["USER_ORIGINAL"], sot=True),
        rule("user.music", "USER_MUSIC", "USER", "ORIGINALS", "~/Music/**", "RED", "USER_PROTECTION", "NO_ACTION",
             "音楽ライブラリの原本です。", ["USER_ORIGINAL"], sot=True),
        rule("cloud.dropbox", "DROPBOX", "CLOUD", "DROPBOX", "~/Library/CloudStorage/Dropbox-**/**", "RED", "SYNC_BLAST_RADIUS", "CLOUD_EVICT_ONLY",
             "Dropboxの同期データです。削除は他端末へ波及します。ダウンロード解除だけが候補です。", ["CLOUD_SYNC"], network=True, preds=["icloud_evictable"]),
        rule("cloud.onedrive", "ONEDRIVE", "CLOUD", "ONEDRIVE", "~/Library/CloudStorage/OneDrive-**/**", "RED", "SYNC_BLAST_RADIUS", "HARD_BLOCK",
             "OneDriveの同期データです。削除semanticsが未確認なら削除しません。", ["CLOUD_SYNC"], network=True),
        rule("cloud.google_drive", "GOOGLE_DRIVE", "CLOUD", "GOOGLE", "~/Library/CloudStorage/GoogleDrive-**/**", "RED", "SYNC_BLAST_RADIUS", "HARD_BLOCK",
             "Google Driveの同期データです。", ["CLOUD_SYNC"], network=True),
        rule("cloud.fileprovider_generic", "FILE_PROVIDER", "CLOUD", "FILEPROVIDER", "~/Library/CloudStorage/**", "UNKNOWN", "UNKNOWN_FALLBACK", "USER_REVIEW",
             "File Provider領域です。プロバイダ固有ルールが無い場合はUNKNOWNです。", ["FILE_PROVIDER", "UNKNOWN"]),
        rule("cloud.icloud_photos", "ICLOUD_PHOTOS", "CLOUD", "ICLOUD", "~/Library/Mobile Documents/com~apple~cloudte~**/**", "RED", "USER_PROTECTION", "HARD_BLOCK",
             "iCloud写真の同期領域です。", ["ICLOUD_PHOTOS"], sot=True),
        rule("xcode.preview_cache", "XCODE_PREVIEW_CACHE", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/UserData/Previews/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "SwiftUI Previewの作業キャッシュです。プロジェクト本体ではありません。", ["PREVIEW_CACHE"], score=90, regenerable=True, preds=GREEN_PREDS),
        rule("xcode.swiftpm_cache", "SWIFTPM_CACHE", "DEVELOPER", "XCODE", "~/Library/Caches/org.swift.swiftpm/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "SwiftPMのグローバルキャッシュです。", ["SWIFTPM_CACHE"], score=88, regenerable=True, network=True, preds=GREEN_PREDS),
        rule("xcode.documentation_cache", "XCODE_DOCS_CACHE", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/DocumentationCache/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "Xcodeのドキュメントキャッシュです。", ["DOCS_CACHE"], score=85, regenerable=True, preds=GREEN_PREDS),
        rule("xcode.ios_device_logs", "XCODE_DEVICE_LOGS", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/iOS Device Logs/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "実機のログです。", ["DEVICE_LOGS"], score=55),
        rule("xcode.watchos_device_support", "WATCHOS_DEVICE_SUPPORT", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/watchOS DeviceSupport/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "watchOS実機用サポートファイルです。", ["DEVICE_SUPPORT"], score=50, regenerable=True, network=True),
        rule("xcode.tvos_device_support", "TVOS_DEVICE_SUPPORT", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/tvOS DeviceSupport/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "tvOS実機用サポートファイルです。", ["DEVICE_SUPPORT"], score=50, regenerable=True),
        rule("xcode.user_data", "XCODE_USERDATA", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/UserData/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Xcodeのキーバインドやテーマなどユーザー設定です。", ["XCODE_USERDATA"], sot=True),
        rule("xcode.provisioning", "XCODE_PROVISIONING", "DEVELOPER", "XCODE", "~/Library/MobileDevice/Provisioning Profiles/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "署名プロファイルです。", ["PROVISIONING"], sot=True),
        rule("node.yarn_berry_cache", "YARN_BERRY_CACHE", "DEVELOPER", "NODE", "**/.yarn/cache/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Yarn Berryのキャッシュです。Zero Installの場合は再構築できません。", ["YARN_CACHE"], score=60, regenerable=True, yellow=["zero_install"], native="yarn cache clean"),
        rule("node.corepack", "COREPACK", "DEVELOPER", "NODE", "~/Library/Caches/node/corepack/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Corepackのツールキャッシュです。", ["COREPACK"], score=70, regenerable=True, native="corepack cache clean"),
        rule("node.npm_logs", "NPM_LOGS", "DEVELOPER", "NODE", "~/.npm/_logs/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "npmのログです。", ["NPM_LOGS"], score=85, regenerable=True, preds=GREEN_PREDS),
        rule("node.nvm_versions", "NVM_VERSIONS", "DEVELOPER", "NODE", "~/.nvm/versions/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "nvmのNode本体です。キャッシュではありません。", ["NVM"], score=25),
        rule("node.bun_cache", "BUN_CACHE", "DEVELOPER", "NODE", "~/.bun/install/cache/**", "GREEN", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Bunのインストールキャッシュです。", ["BUN_CACHE"], score=86, regenerable=True, network=True, preds=GREEN_PREDS, native="bun pm cache rm"),
        rule("node.pnpm_home", "PNPM_HOME", "DEVELOPER", "NODE", "~/Library/pnpm/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "pnpmのホームです。store以外も含みます。", ["PNPM"], score=55, native="pnpm store prune"),
        rule("docker.networks", "DOCKER_NETWORKS", "DEVELOPER", "DOCKER", "entity://docker/networks/**", "YELLOW", "EXACT_VENDOR_RULE", "TOOL_CLI_ONLY",
             "Dockerネットワーク定義です。データ本体ではありません。", ["DOCKER_NETWORK"], score=40, native="docker network prune"),
        rule("docker.bind_mounts", "DOCKER_BIND_MOUNT", "DEVELOPER", "DOCKER", "entity://docker/bind-mounts/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "ホスト側のバインドマウントです。プロジェクト原本のことがあります。", ["BIND_MOUNT"], sot=True),
        rule("docker.desktop_vm", "DOCKER_DESKTOP_VM", "DEVELOPER", "DOCKER", "~/Library/Containers/com.docker.docker/Data/vms/**", "YELLOW", "EXACT_VENDOR_RULE", "APP_API_ONLY",
             "Docker Desktopの仮想ディスクです。中にvolumeが載ることがあります。", ["DOCKER_VM"], score=20, native="Docker Desktop settings"),
        rule("docker.overlay", "DOCKER_OVERLAY", "DEVELOPER", "DOCKER", "entity://docker/overlay2/**", "YELLOW", "EXACT_VENDOR_RULE", "TOOL_CLI_ONLY",
             "イメージ層です。volumeではありません。", ["DOCKER_OVERLAY"], score=50, native="docker system prune"),
        rule("homebrew.cellar", "HOMEBREW_CELLAR", "DEVELOPER", "HOMEBREW", "/opt/homebrew/Cellar/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "インストール済みformulaです。キャッシュではありません。", ["CELLAR"], score=15, native="brew uninstall"),
        rule("homebrew.caskroom", "HOMEBREW_CASKROOM", "DEVELOPER", "HOMEBREW", "/opt/homebrew/Caskroom/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Caskの展開済み実体です。", ["CASKROOM"], score=15),
        rule("homebrew.old_versions", "HOMEBREW_OLD_VERSIONS", "DEVELOPER", "HOMEBREW", "/opt/homebrew/Cellar/**/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "古いformula版が残っていることがあります。brew cleanup対象です。", ["OLD_FORMULA"], score=70, regenerable=True, native="brew cleanup"),
        rule("python.poetry_cache", "POETRY_CACHE", "DEVELOPER", "PYTHON", "~/Library/Caches/pypoetry/**", "GREEN", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Poetryのキャッシュです。仮想環境本体ではありません。", ["POETRY_CACHE"], score=88, regenerable=True, preds=GREEN_PREDS, native="poetry cache clear --all"),
        rule("python.uv_cache", "UV_CACHE", "DEVELOPER", "PYTHON", "~/Library/Caches/uv/**", "GREEN", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "uvのキャッシュです。", ["UV_CACHE"], score=90, regenerable=True, preds=GREEN_PREDS, native="uv cache clean"),
        rule("python.conda_pkgs", "CONDA_PKGS", "DEVELOPER", "PYTHON", "~/anaconda3/pkgs/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Condaのパッケージキャッシュです。環境本体ではありません。", ["CONDA_PKGS"], score=75, regenerable=True, native="conda clean -a"),
        rule("python.conda_envs", "CONDA_ENVS", "DEVELOPER", "PYTHON", "~/anaconda3/envs/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Conda環境です。キャッシュではありません。", ["CONDA_ENV"], score=20),
        rule("python.pycache", "PYCACHE", "DEVELOPER", "PYTHON", "**/__pycache__/**", "YELLOW", "GENERIC_CACHE_TEMP", "USER_REVIEW",
             "Pythonのバイトコードです。ソース本体ではありません。", ["PYCACHE"], score=70, regenerable=True),
        rule("python.venv_named", "PYTHON_VENV_NAMED", "DEVELOPER", "PYTHON", "**/venv/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "名前付きvenvです。キャッシュではありません。", ["VENV_NOT_CACHE"], score=40, preds=["manifest_exists"], red=["manifest_missing"]),
        rule("git.lfs", "GIT_LFS", "DEVELOPER", "GIT", "**/.git/lfs/**", "YELLOW", "EXACT_VENDOR_RULE", "TOOL_CLI_ONLY",
             "Git LFSのローカルオブジェクトです。履歴と結びつきます。", ["GIT_LFS"], score=30, native="git lfs prune"),
        rule("git.objects", "GIT_OBJECTS", "DEVELOPER", "GIT", "**/.git/objects/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Gitオブジェクトです。履歴本体です。", ["GIT_HISTORY"], sot=True),
        rule("git.packfiles", "GIT_PACK", "DEVELOPER", "GIT", "**/.git/objects/pack/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "packされた履歴です。", ["GIT_HISTORY"], sot=True),
        rule("git.working_tree", "GIT_WORKING_TREE", "DEVELOPER", "GIT", "**/.git", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "リポジトリの管理領域です。", ["GIT_SOURCE"], sot=True),
        rule("ai.vscode_logs", "VSCODE_LOGS", "AI_DEV", "VSCODE", "~/Library/Application Support/Code/logs/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "VS Codeのログです。設定本体ではありません。", ["VSCODE_LOGS"], score=80, regenerable=True, preds=GREEN_PREDS),
        rule("ai.vscode_app_support", "VSCODE_APP_SUPPORT", "AI_DEV", "VSCODE", "~/Library/Application Support/Code/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "VS Codeの設定と拡張の本体です。", ["VSCODE_STATE"], sot=True),
        rule("ai.codex", "CODEX_STATE", "AI_DEV", "CODEX", "~/.codex/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Codexの設定と履歴です。", ["CODEX"], sot=True),
        rule("ai.cursor_cache", "CURSOR_CACHE", "AI_DEV", "CURSOR", "~/Library/Caches/Cursor/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "Cursorのキャッシュです。Application Support本体ではありません。", ["CURSOR_CACHE"], score=84, regenerable=True, preds=GREEN_PREDS),
        rule("ai.claude_desktop", "CLAUDE_DESKTOP", "AI_DEV", "CLAUDE", "~/Library/Application Support/Claude/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Claude Desktopの状態です。", ["CLAUDE_DESKTOP"], sot=True),
        rule("ai.chroma", "CHROMA_DB", "AI_DEV", "VECTOR", "**/.chroma/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "ベクトルDBの可能性があります。未使用でも不要ではありません。", ["VECTOR_DB"], sot=True, red=["active_vector_db"]),
        rule("ai.lancedb", "LANCEDB", "AI_DEV", "VECTOR", "**/*.lancedb/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "LanceDBです。索引の原本です。", ["VECTOR_DB"], sot=True),
        rule("ai.qdrant", "QDRANT", "AI_DEV", "VECTOR", "**/.qdrant/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Qdrantストレージです。", ["VECTOR_DB"], sot=True),
        rule("ai.ollama_blobs", "OLLAMA_BLOBS", "AI_DEV", "OLLAMA", "~/.ollama/models/blobs/**", "YELLOW", "EXACT_VENDOR_RULE", "APP_API_ONLY",
             "Ollamaモデル実体です。再ダウンロードが大きいです。", ["OLLAMA"], score=45, regenerable=True, network=True, yellow=["model_in_use"]),
        rule("ai.hf_datasets", "HF_DATASETS", "AI_DEV", "HUGGINGFACE", "~/.cache/huggingface/datasets/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Hugging Faceデータセットキャッシュです。学習データの再取得コストがあります。", ["HF_DATASETS"], score=55, regenerable=True, network=True),
        rule("media.photoslibrary", "PHOTOS_LIBRARY", "USER", "PHOTOS", "**/*.photoslibrary/**", "RED", "USER_PROTECTION", "HARD_BLOCK",
             "写真ライブラリ本体です。", ["PHOTOS"], sot=True),
        rule("media.fcp_library", "FCP_LIBRARY", "MEDIA", "FINAL_CUT", "**/*.fcpbundle/**", "RED", "USER_PROTECTION", "HARD_BLOCK",
             "Final Cutライブラリ本体です。生成ファイルとは別です。", ["FCP_LIBRARY"], sot=True),
        rule("media.logic", "LOGIC_PROJECTS", "MEDIA", "LOGIC", "**/*.logicx/**", "RED", "USER_PROTECTION", "NO_ACTION",
             "Logicプロジェクトです。", ["LOGIC"], sot=True),
        rule("backup.itunes_mobile", "ITUNES_BACKUP", "BACKUP", "MOBILE", "~/Library/Application Support/MobileSync/**", "YELLOW", "SOURCE_OF_TRUTH", "USER_REVIEW",
             "モバイル同期関連です。", ["IOS_BACKUP"], score=25, sot=True),
        rule("cocoapods.cache", "COCOAPODS_CACHE", "DEVELOPER", "COCOAPODS", "~/Library/Caches/CocoaPods/**", "GREEN", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "CocoaPodsのキャッシュです。", ["PODS_CACHE"], score=87, regenerable=True, preds=GREEN_PREDS, native="pod cache clean --all"),
        rule("cargo.cache", "CARGO_CACHE", "DEVELOPER", "RUST", "~/Library/Caches/cargo/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Cargo関連キャッシュです。targetとは別に扱います。", ["CARGO"], score=70, regenerable=True, native="cargo cache"),
        rule("cargo.target", "CARGO_TARGET", "DEVELOPER", "RUST", "**/target/**", "YELLOW", "EXACT_VENDOR_RULE", "TOOL_CLI_ONLY",
             "Rustのビルド成果です。ソースではありません。", ["CARGO_TARGET"], score=75, regenerable=True, native="cargo clean"),
        rule("go.build_cache", "GO_CACHE", "DEVELOPER", "GO", "~/Library/Caches/go-build/**", "GREEN", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Goのビルドキャッシュです。", ["GO_CACHE"], score=90, regenerable=True, preds=GREEN_PREDS, native="go clean -cache"),
        rule("go.modcache", "GO_MODCACHE", "DEVELOPER", "GO", "~/go/pkg/mod/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Go module cacheです。", ["GO_MOD"], score=72, regenerable=True, network=True, native="go clean -modcache"),
        rule("gradle.caches", "GRADLE_CACHES", "DEVELOPER", "ANDROID", "~/.gradle/caches/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Gradleキャッシュです。", ["GRADLE"], score=70, regenerable=True),
        rule("android.avd", "ANDROID_AVD", "DEVELOPER", "ANDROID", "~/.android/avd/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Androidエミュレータの状態です。", ["AVD"], score=40),
        rule("maven.repo", "MAVEN_REPO", "DEVELOPER", "JAVA", "~/.m2/repository/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Mavenのローカルリポジトリです。", ["MAVEN"], score=60, regenerable=True, network=True),
        rule("system.library_apple", "APPLE_INTERNAL", "MACOS", "SYSTEM", "/Library/Apple/**", "RED", "HARD_BLOCK", "HARD_BLOCK",
             "Apple内部コンポーネントです。", ["HARD_BLOCK"], sot=True, owner="root"),
        rule("system.usr_standalone", "USR_STANDALONE", "MACOS", "SYSTEM", "/usr/standalone/**", "RED", "HARD_BLOCK", "HARD_BLOCK",
             "起動関連のスタンドアロン領域です。", ["HARD_BLOCK"], sot=True, owner="root"),
        rule("macos.launchagents_user", "LAUNCH_AGENTS", "MACOS", "SETTINGS", "~/Library/LaunchAgents/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "ユーザーの自動起動設定です。", ["LAUNCH_AGENTS"], sot=True),
        rule("macos.application_support_system", "SYSTEM_APP_SUPPORT", "MACOS", "APP_DATA", "/Library/Application Support/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "システムの Application Support です。", ["APP_SUPPORT"], sot=True, owner="root"),
        rule("macos.logs_system", "SYSTEM_LOGS", "MACOS", "LOGS", "/var/log/**", "YELLOW", "GENERIC_CACHE_TEMP", "OS_API_ONLY",
             "システムログです。", ["SYSTEM_LOGS"], score=40, owner="root"),
        rule("macos.tmpdir_var", "VAR_TMP", "MACOS", "TEMP", "/var/tmp/**", "YELLOW", "GENERIC_CACHE_TEMP", "USER_REVIEW",
             "共有一時領域です。", ["TEMP"], score=45, owner="root", preds=["no_open_file_handle"]),
        rule("user.library_root", "USER_LIBRARY", "USER", "LIBRARY", "~/Library/**", "UNKNOWN", "UNKNOWN_FALLBACK", "USER_REVIEW",
             "ユーザーLibraryの包括マッチです。より具体的なvendor ruleが無い場合のみUNKNOWN。", ["GENERIC_LIBRARY"]),
        rule("xcode.derived_data_root", "XCODE_DERIVED_DATA_ROOT", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/DerivedData", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "DerivedDataルートです。", ["GENERATED_DATA"], score=98, regenerable=True, preds=GREEN_PREDS),
        rule("xcode.simulator_root", "CORE_SIMULATOR_ROOT", "DEVELOPER", "XCODE", "~/Library/Developer/CoreSimulator/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "シミュレータ配下の包括です。DevicesとRuntimesは個別rule優先。", ["SIMULATOR"], score=50),
        rule("node.package_json", "PACKAGE_JSON", "DEVELOPER", "NODE", "**/package.json", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Nodeプロジェクトのマニフェストです。", ["MANIFEST"], sot=True),
        rule("node.package_lock", "PACKAGE_LOCK", "DEVELOPER", "NODE", "**/package-lock.json", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "npm lockfileです。", ["LOCKFILE"], sot=True),
        rule("node.pnpm_lock", "PNPM_LOCK", "DEVELOPER", "NODE", "**/pnpm-lock.yaml", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "pnpm lockfileです。", ["LOCKFILE"], sot=True),
        rule("node.yarn_lock", "YARN_LOCK", "DEVELOPER", "NODE", "**/yarn.lock", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Yarn lockfileです。", ["LOCKFILE"], sot=True),
        rule("docker.desktop_data", "DOCKER_DESKTOP_DATA", "DEVELOPER", "DOCKER", "~/Library/Containers/com.docker.docker/Data/**", "YELLOW", "EXACT_VENDOR_RULE", "APP_API_ONLY",
             "Docker Desktopデータです。volumeを含みうるので丸ごとGREENにしない。", ["DOCKER_DESKTOP"], score=25),
        rule("homebrew.downloads", "HOMEBREW_DOWNLOADS", "DEVELOPER", "HOMEBREW", "~/Library/Caches/Homebrew/downloads/**", "GREEN", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Homebrewのダウンロード実体です。", ["HOMEBREW_CACHE"], score=93, regenerable=True, preds=GREEN_PREDS, native="brew cleanup"),
        rule("python.pip_http", "PIP_HTTP_CACHE", "DEVELOPER", "PYTHON", "~/Library/Caches/pip/http/**", "GREEN", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "pip HTTPキャッシュです。", ["PIP_CACHE"], score=91, regenerable=True, preds=GREEN_PREDS, native="pip cache purge"),
        rule("python.miniconda_pkgs", "MINICONDA_PKGS", "DEVELOPER", "PYTHON", "~/miniconda3/pkgs/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "Minicondaのパッケージキャッシュです。", ["CONDA_PKGS"], score=75, native="conda clean -a"),
        rule("python.miniconda_envs", "MINICONDA_ENVS", "DEVELOPER", "PYTHON", "~/miniconda3/envs/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Miniconda環境です。", ["CONDA_ENV"], score=20),
        rule("git.hooks", "GIT_HOOKS", "DEVELOPER", "GIT", "**/.git/hooks/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Git hooksです。", ["GIT_HOOKS"], sot=True),
        rule("ai.continue", "CONTINUE_DEV", "AI_DEV", "CONTINUE", "~/.continue/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Continueの設定です。", ["CONTINUE"], sot=True),
        rule("ai.cursor_global_storage", "CURSOR_GLOBAL_STORAGE", "AI_DEV", "CURSOR", "~/Library/Application Support/Cursor/User/globalStorage/**", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Cursor拡張の永続データです。", ["CURSOR_STATE"], sot=True),
        rule("ai.ollama_manifests", "OLLAMA_MANIFESTS", "AI_DEV", "OLLAMA", "~/.ollama/models/manifests/**", "YELLOW", "EXACT_VENDOR_RULE", "APP_API_ONLY",
             "Ollamaのマニフェストです。", ["OLLAMA"], score=40),
        rule("ai.lmstudio_models", "LMSTUDIO_MODELS", "AI_DEV", "LM_STUDIO", "~/.cache/lm-studio/models/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "LM Studioモデルです。", ["LM_STUDIO"], score=48, regenerable=True, network=True),
        rule("backup.tm_snapshots_alt", "TM_SNAPSHOTS", "BACKUP", "TIMEMACHINE", "/Volumes/com.apple.TimeMachine.localsnapshots/**", "YELLOW", "EXACT_VENDOR_RULE", "OS_API_ONLY",
             "Time Machineローカルスナップショットです。", ["TM_SNAPSHOT"], score=40, sot=True, native="tmutil"),
        rule("cloud.icloud_drive_docs", "ICLOUD_DRIVE", "CLOUD", "ICLOUD", "~/Library/Mobile Documents/com~apple~CloudDocs/**", "GREEN", "SYNC_BLAST_RADIUS", "CLOUD_EVICT_ONLY",
             "iCloud Driveのローカル実体です。削除はRED。ダウンロード解除だけがGREEN候補。", ["ICLOUD"], network=True, regenerable=True, score=85, preds=GREEN_PREDS + ["icloud_evictable", "sync_would_not_delete_remote"]),
        rule("macos.mobile_documents", "MOBILE_DOCUMENTS", "CLOUD", "ICLOUD", "~/Library/Mobile Documents/**", "UNKNOWN", "SYNC_BLAST_RADIUS", "USER_REVIEW",
             "Mobile Documents包括です。具体cloud ruleが無いとUNKNOWN。", ["ICLOUD"]),
        rule("user.desktop_root", "DESKTOP_ROOT", "USER", "ORIGINALS", "~/Desktop", "RED", "USER_PROTECTION", "NO_ACTION",
             "デスクトップ直下です。", ["USER_ORIGINAL"], sot=True),
        rule("user.documents_root", "DOCUMENTS_ROOT", "USER", "ORIGINALS", "~/Documents", "RED", "USER_PROTECTION", "NO_ACTION",
             "書類フォルダです。", ["USER_ORIGINAL"], sot=True),
        rule("user.downloads_root", "DOWNLOADS_ROOT", "USER", "INBOX", "~/Downloads", "YELLOW", "USER_PROTECTION", "USER_REVIEW",
             "ダウンロードフォルダです。", ["USER_INBOX"], score=40),
        rule("macos.caches_root", "USER_CACHES_ROOT", "MACOS", "CACHE", "~/Library/Caches", "GREEN", "GENERIC_CACHE_TEMP", "MOVE_TO_TRASH",
             "ユーザーCachesルートです。中身はvendor rule優先。", ["CACHE"], score=70, regenerable=True, preds=GREEN_PREDS),
        rule("macos.logs_root", "USER_LOGS_ROOT", "MACOS", "LOGS", "~/Library/Logs", "YELLOW", "GENERIC_CACHE_TEMP", "MOVE_TO_TRASH",
             "ユーザーLogsルートです。", ["LOGS"], score=60, preds=["no_open_file_handle"]),
        rule("xcode.developer_root", "DEVELOPER_ROOT", "DEVELOPER", "XCODE", "~/Library/Developer/**", "UNKNOWN", "UNKNOWN_FALLBACK", "USER_REVIEW",
             "Developer配下の包括です。一括Junk禁止。未識別はUNKNOWN。", ["DEVELOPER_GENERIC"]),
        rule("ai.embeddings_dir", "EMBEDDINGS_DIR", "AI_DEV", "VECTOR", "**/embeddings/**", "UNKNOWN", "UNKNOWN_FALLBACK", "USER_REVIEW",
             "embeddingsディレクトリです。証拠不足はUNKNOWN。", ["UNKNOWN_EMBEDDINGS"]),
        rule("ai.index_dir", "INDEX_DIR", "AI_DEV", "VECTOR", "**/vector-index/**", "UNKNOWN", "UNKNOWN_FALLBACK", "USER_REVIEW",
             "vector-indexです。UNKNOWNのまま表示します。", ["UNKNOWN_INDEX"]),
        rule("docker.raw_disk", "DOCKER_RAW_DISK", "DEVELOPER", "DOCKER", "~/Library/Containers/com.docker.docker/Data/vms/0/data/**", "YELLOW", "EXACT_VENDOR_RULE", "APP_API_ONLY",
             "Dockerの仮想ディスクイメージです。", ["DOCKER_VM"], score=20),
        rule("node.npm_root", "NPM_ROOT", "DEVELOPER", "NODE", "~/.npm/**", "YELLOW", "EXACT_VENDOR_RULE", "PACKAGE_MANAGER_COMMAND",
             "npmホームです。cache以外も含みます。", ["NPM"], score=60, native="npm cache clean --force"),
        rule("python.uv_data", "UV_DATA", "DEVELOPER", "PYTHON", "~/.local/share/uv/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "uvの共有データです。", ["UV"], score=50),
        rule("git.lfs_tmp", "GIT_LFS_TMP", "DEVELOPER", "GIT", "**/.git/lfs/tmp/**", "YELLOW", "EXACT_VENDOR_RULE", "TOOL_CLI_ONLY",
             "Git LFS一時ファイルです。", ["GIT_LFS"], score=65, native="git lfs prune"),
        rule("macos.fileprovider_support", "FILEPROVIDER_SUPPORT", "CLOUD", "FILEPROVIDER", "~/Library/Application Support/FileProvider/**", "UNKNOWN", "SYNC_BLAST_RADIUS", "USER_REVIEW",
             "File Providerサポート領域です。sync未確認はUNKNOWN。", ["FILE_PROVIDER"]),
        rule("backup.device_backups", "DEVICE_BACKUPS", "BACKUP", "MOBILE", "~/Library/Application Support/MobileSync/Backup", "YELLOW", "SOURCE_OF_TRUTH", "USER_REVIEW",
             "iOSバックアップルートです。", ["IOS_BACKUP"], score=30, sot=True),
        rule("xcode.modulecache_alt", "MODULECACHE_ALT", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/DerivedData/ModuleCache/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "ModuleCacheです。", ["MODULE_CACHE"], score=97, regenerable=True, preds=GREEN_PREDS),
        rule("xcode.sourcepackages_root", "SOURCEPACKAGES_ROOT", "DEVELOPER", "XCODE", "~/Library/Developer/Xcode/DerivedData/SourcePackages/**", "YELLOW", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "SourcePackagesです。オフライン開発に影響します。", ["SWIFTPM"], score=70, regenerable=True, network=True, yellow=["offline_needed"]),
        rule("ai.vscode_cache", "VSCODE_CACHE", "AI_DEV", "VSCODE", "~/Library/Caches/com.microsoft.VSCode/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "VS Codeキャッシュです。", ["VSCODE_CACHE"], score=82, regenerable=True, preds=GREEN_PREDS),
        rule("media.imovie_library", "IMOVIE_LIBRARY", "MEDIA", "IMOVIE", "**/*.imovielibrary/**", "RED", "USER_PROTECTION", "NO_ACTION",
             "iMovieライブラリです。", ["IMOVIE"], sot=True),
        rule("user.pictures_root", "PICTURES_ROOT", "USER", "PHOTOS", "~/Pictures", "RED", "USER_PROTECTION", "HARD_BLOCK",
             "ピクチャフォルダです。", ["PHOTOS"], sot=True),
        rule("macos.group_containers_root", "GROUP_CONTAINERS_ROOT", "MACOS", "SANDBOX", "~/Library/Group Containers", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Group Containersルートです。", ["GROUP_CONTAINERS"], sot=True),
        rule("macos.containers_root", "CONTAINERS_ROOT", "MACOS", "SANDBOX", "~/Library/Containers", "RED", "SOURCE_OF_TRUTH", "NO_ACTION",
             "Containersルートです。", ["CONTAINERS"], sot=True),
        rule("ai.claude_code_cache", "CLAUDE_CACHE", "AI_DEV", "CLAUDE", "~/.claude/cache/**", "YELLOW", "EXACT_VENDOR_RULE", "USER_REVIEW",
             "Claude Codeのキャッシュ相当です。settings本体ではありません。", ["CLAUDE_CACHE"], score=50),
        rule("homebrew.logs", "HOMEBREW_LOGS", "DEVELOPER", "HOMEBREW", "~/Library/Logs/Homebrew/**", "GREEN", "EXACT_VENDOR_RULE", "MOVE_TO_TRASH",
             "Homebrewのログです。Cellar本体ではありません。", ["HOMEBREW_LOGS"], score=80, regenerable=True, preds=GREEN_PREDS),
    ]
    return r


def validate(doc, label):
    errors = []
    ids = []
    for i, ru in enumerate(doc["rules"]):
        rid = ru.get("id")
        ids.append(rid)
        if ru.get("default_class") not in CLASSES:
            errors.append(f"{label}:{rid} invalid class")
        if ru.get("action_mode") not in ACTIONS:
            errors.append(f"{label}:{rid} invalid action")
        if ru.get("evaluation_layer") not in LAYERS:
            errors.append(f"{label}:{rid} invalid layer")
        if ru.get("default_class") == "GREEN" and not ru.get("required_predicates"):
            errors.append(f"{label}:{rid} GREEN without required_predicates")
        for p in ru.get("required_predicates", []) + ru.get("demote_to_yellow_if", []) + ru.get("demote_to_red_if", []) + ru.get("hard_block_if", []):
            if p not in ALLOWED_PREDICATES:
                errors.append(f"{label}:{rid} unknown predicate {p}")
        if ru.get("action_mode") == "PERMANENT_DELETE":
            errors.append(f"{label}:{rid} permanent delete forbidden")
    dups = sorted({x for x in ids if ids.count(x) > 1})
    if dups:
        errors.append(f"{label} duplicate ids: {dups}")
    return errors


def conflicts(bootstrap, expansion):
    b = {r["id"]: r for r in bootstrap["rules"]}
    e = {r["id"]: r for r in expansion["rules"]}
    out = []
    for rid in sorted(set(b) & set(e)):
        # compare material fields ignoring extra keys added later
        keys = ["default_class", "action_mode", "match", "evaluation_layer", "entity"]
        if any(b[rid].get(k) != e[rid].get(k) for k in keys):
            out.append({"id": rid, "action": "keep_bootstrap", "reason": "field mismatch"})
    return out


def main():
    SRC.mkdir(parents=True, exist_ok=True)
    COMPILED.mkdir(parents=True, exist_ok=True)
    SCHEMA.mkdir(parents=True, exist_ok=True)
    VERSIONS.mkdir(parents=True, exist_ok=True)

    existing = json.loads(SWIFT_COMPILED.read_text()) if SWIFT_COMPILED.exists() else {"rules": []}
    if BOOTSTRAP.exists() and len(json.loads(BOOTSTRAP.read_text()).get("rules", [])) == 45:
        bootstrap = json.loads(BOOTSTRAP.read_text())
    else:
        bootstrap = {
            "version": "0.1",
            "principle": existing.get("principle", "UNDERSTAND over DELETE."),
            "rules": [r for r in existing.get("rules", []) if r.get("id") in BOOTSTRAP_IDS],
        }
    for ru in bootstrap["rules"]:
        ru.setdefault("rule_version", "0.1")
        ru.setdefault("native_cleanup", None)
        ru.setdefault("root_cause_signals", [])
        ru.setdefault("recovery_estimate_hint", None)

    (SRC / "bootstrap_rules_v0.1.json").write_text(json.dumps(bootstrap, ensure_ascii=False, indent=2) + "\n")

    extras = extra_rules()
    expansion = {
        "version": "0.1-spec-expansion",
        "principle": bootstrap["principle"],
        "origin": "Spec-derived expansion. Deep Research 178-rule JSON was not supplied; bootstrap is preserved.",
        "rules": extras,
    }
    (SRC / "spec_expansion_v0.1.json").write_text(json.dumps(expansion, ensure_ascii=False, indent=2) + "\n")

    # Merge: bootstrap first, add extras whose ids are new. Conflicts keep bootstrap.
    conf = conflicts(bootstrap, {"rules": extras})
    merged_ids = {r["id"]: deepcopy(r) for r in bootstrap["rules"]}
    added = []
    skipped = []
    for ru in extras:
        if ru["id"] in merged_ids:
            skipped.append(ru["id"])
            continue
        merged_ids[ru["id"]] = ru
        added.append(ru["id"])

    compiled = {
        "version": "0.1.1",
        "principle": bootstrap["principle"],
        "rule_count": len(merged_ids),
        "bootstrap_count": len(bootstrap["rules"]),
        "added_from_expansion": len(added),
        "rules": list(merged_ids.values()),
    }
    errors = validate(compiled, "compiled")
    report = {
        "errors": errors,
        "conflicts": conf,
        "skipped_expansion_ids_already_in_bootstrap": skipped,
        "added_ids": added,
        "compiled_count": len(compiled["rules"]),
        "class_counts": {},
    }
    for ru in compiled["rules"]:
        c = ru["default_class"]
        report["class_counts"][c] = report["class_counts"].get(c, 0) + 1

    if errors:
        raise SystemExit("validation failed:\n" + "\n".join(errors))

    (COMPILED / "compiled_rules_v0.1.json").write_text(json.dumps(compiled, ensure_ascii=False, indent=2) + "\n")
    (COMPILED / "compile_report_v0.1.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    shutil.copyfile(COMPILED / "compiled_rules_v0.1.json", SWIFT_COMPILED)

    placeholder = ROOT / "Sources/SafetyCore/Resources/knowledge/storage_safety_knowledge_base_v0.1.json"
    source_keep = SRC / "storage_safety_knowledge_base_v0.1.json"
    if placeholder.exists():
        shutil.copyfile(placeholder, source_keep)

    (SCHEMA / "rule.schema.json").write_text(json.dumps({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "SafetyRule",
        "type": "object",
        "required": ["id", "entity", "match", "default_class", "action_mode", "evaluation_layer", "required_predicates"],
        "properties": {
            "id": {"type": "string"},
            "default_class": {"enum": sorted(CLASSES)},
            "action_mode": {"enum": sorted(ACTIONS)},
            "evaluation_layer": {"enum": sorted(LAYERS)},
        },
    }, indent=2) + "\n")

    (VERSIONS / "0.1.md").write_text(
        f"# Knowledge Base 0.1.1\n\ncompiled={len(compiled['rules'])} bootstrap={len(bootstrap['rules'])} added={len(added)}\n"
    )
    print(json.dumps({k: report[k] for k in ("compiled_count", "class_counts", "errors", "conflicts")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
