#!/usr/bin/env python3
"""Generate LocalizationCatalog.json — single canonical catalog for P5.3."""
from __future__ import annotations
import json
from pathlib import Path

LOCALES = ["en", "ja", "zh-Hans", "zh-Hant", "ko", "es", "fr", "de", "pt-BR"]

# Each key: {locale: translation}. English is required.
# Meaning notes for translators live in safety-copy-glossary.md

def T(**kwargs):
    assert "en" in kwargs
    for loc in LOCALES:
        kwargs.setdefault(loc, kwargs["en"])  # temporary: fill gaps then override
    return kwargs

# Override defaults carefully — start with en, then set all locales for critical keys.
CATALOG: dict[str, dict[str, str]] = {}

def add(key: str, **translations: str):
    alias = {"zhHans": "zh-Hans", "zhHant": "zh-Hant", "ptBR": "pt-BR"}
    norm = {}
    for k, v in translations.items():
        norm[alias.get(k, k)] = v
    assert "en" in norm, key
    row = {loc: norm.get(loc, norm["en"]) for loc in LOCALES}
    CATALOG[key] = row

# --- Navigation ---
add("navigation.storage",
    en="Storage", ja="ストレージ", zhHans="存储", zhHant="儲存",
    ko="저장공간", es="Almacenamiento", fr="Stockage", de="Speicher", ptBR="Armazenamento")
add("navigation.plan",
    en="Plan", ja="プラン", zhHans="计划", zhHant="計畫",
    ko="계획", es="Plan", fr="Plan", de="Plan", ptBR="Plano")
add("navigation.history",
    en="History", ja="履歴", zhHans="历史", zhHant="歷程",
    ko="기록", es="Historial", fr="Historique", de="Verlauf", ptBR="Histórico")
add("navigation.settings",
    en="Settings", ja="設定", zhHans="设置", zhHant="設定",
    ko="설정", es="Ajustes", fr="Réglages", de="Einstellungen", ptBR="Ajustes")

# --- Decisions (Safety-critical meaning) ---
add("decision.keep.title",
    en="Keep", ja="残す", zhHans="保留", zhHant="保留",
    ko="유지", es="Conservar", fr="Conserver", de="Behalten", ptBR="Manter")
add("decision.protected.title",
    en="Protected", ja="保護", zhHans="受保护", zhHant="受保護",
    ko="보호됨", es="Protegido", fr="Protégé", de="Geschützt", ptBR="Protegido")
add("decision.verifyMore.title",
    en="Needs Verification", ja="要確認", zhHans="需要核实", zhHant="需要核實",
    ko="확인 필요", es="Necesita verificación", fr="Vérification requise", de="Überprüfung nötig", ptBR="Precisa de verificação")
add("decision.ready.title",
    en="Ready", ja="準備完了", zhHans="就绪", zhHant="就緒",
    ko="준비됨", es="Listo", fr="Prêt", de="Bereit", ptBR="Pronto")
add("decision.needsApproval.title",
    en="Needs Your Approval", ja="承認が必要", zhHans="需要您的批准", zhHant="需要您的核准",
    ko="승인 필요", es="Necesita su aprobación", fr="Nécessite votre approbation", de="Ihre Freigabe erforderlich", ptBR="Precisa da sua aprovação")
add("decision.recoveryPending.title",
    en="Recovery Pending", ja="回復は保留中", zhHans="回收待确认", zhHant="回收待確認",
    ko="회수 대기", es="Recuperación pendiente", fr="Récupération en attente", de="Freigabe ausstehend", ptBR="Recuperação pendente")
add("decision.noRecommendation.title",
    en="No recommendation", ja="推奨なし", zhHans="暂无建议", zhHant="暫無建議",
    ko="권장 없음", es="Sin recomendación", fr="Aucune recommandation", de="Keine Empfehlung", ptBR="Sem recomendação")
add("decision.info.title",
    en="Info", ja="情報", zhHans="信息", zhHant="資訊",
    ko="정보", es="Info", fr="Info", de="Info", ptBR="Info")
add("decision.unknown.human",
    en="Not enough information yet", ja="まだ情報が足りません", zhHans="信息还不够", zhHant="資訊還不夠",
    ko="아직 정보가 부족합니다", es="Aún no hay información suficiente", fr="Pas encore assez d’informations", de="Noch nicht genug Informationen", ptBR="Ainda não há informação suficiente")

# --- Actions ---
add("action.scanStorage",
    en="Scan Storage", ja="ストレージをスキャン", zhHans="扫描存储", zhHant="掃描儲存",
    ko="저장공간 검사", es="Analizar almacenamiento", fr="Analyser le stockage", de="Speicher scannen", ptBR="Analisar armazenamento")
add("action.scanning",
    en="Scanning…", ja="スキャン中…", zhHans="正在扫描…", zhHant="正在掃描…",
    ko="검사 중…", es="Analizando…", fr="Analyse…", de="Scannen…", ptBR="Analisando…")
add("action.moveToTrash.title",
    en="Move to Trash", ja="ゴミ箱に入れる", zhHans="移到废纸篓", zhHant="移到垃圾桶",
    ko="휴지통으로 이동", es="Mover a la Papelera", fr="Mettre à la Corbeille", de="In den Papierkorb legen", ptBR="Mover para o Lixo")
add("action.vendorCleanup.title",
    en="Clean with %@", ja="%@で整理", zhHans="用%@清理", zhHant="用%@清理",
    ko="%@(으)로 정리", es="Limpiar con %@", fr="Nettoyer avec %@", de="Mit %@ bereinigen", ptBR="Limpar com %@")
add("action.reviewAndApprove",
    en="Review & Approve…", ja="確認して承認…", zhHans="检查并批准…", zhHant="檢查並核准…",
    ko="검토 후 승인…", es="Revisar y aprobar…", fr="Examiner et approuver…", de="Prüfen & freigeben…", ptBR="Revisar e aprovar…")
add("action.reviewAgain",
    en="Review Again", ja="もう一度確認", zhHans="再次检查", zhHant="再次檢查",
    ko="다시 검토", es="Revisar de nuevo", fr="Réexaminer", de="Erneut prüfen", ptBR="Revisar novamente")
add("action.checkCurrentSafety",
    en="Check Current Safety", ja="いまの安全性を確認", zhHans="检查当前安全性", zhHant="檢查目前安全性",
    ko="현재 안전성 확인", es="Comprobar seguridad actual", fr="Vérifier la sécurité actuelle", de="Aktuelle Sicherheit prüfen", ptBR="Verificar segurança atual")
add("action.revealInFinder",
    en="Reveal in Finder", ja="Finderで表示", zhHans="在访达中显示", zhHant="在 Finder 中顯示",
    ko="Finder에서 보기", es="Mostrar en el Finder", fr="Afficher dans le Finder", de="Im Finder zeigen", ptBR="Mostrar no Finder")
add("action.preview",
    en="Preview", ja="プレビュー", zhHans="预览", zhHant="預覽",
    ko="미리보기", es="Vista previa", fr="Aperçu", de="Vorschau", ptBR="Pré-visualizar")
add("action.buildSafePlan",
    en="Build a safe plan", ja="安全なプランを作る", zhHans="生成安全计划", zhHant="建立安全計畫",
    ko="안전한 계획 만들기", es="Crear un plan seguro", fr="Créer un plan sûr", de="Sicheren Plan erstellen", ptBR="Criar um plano seguro")
add("action.refreshPlan",
    en="Refresh Plan", ja="プランを更新", zhHans="刷新计划", zhHant="重新整理計畫",
    ko="계획 새로고침", es="Actualizar plan", fr="Actualiser le plan", de="Plan aktualisieren", ptBR="Atualizar plano")

# --- Scan ---
add("scan.mappingStorage",
    en="Mapping your storage", ja="ストレージを地図化しています", zhHans="正在绘制存储地图", zhHant="正在繪製儲存地圖",
    ko="저장공간을 매핑하는 중", es="Mapeando su almacenamiento", fr="Cartographie du stockage", de="Speicher wird kartiert", ptBR="Mapeando seu armazenamento")
add("scan.understandingApps",
    en="Understanding your apps", ja="アプリを理解しています", zhHans="正在理解您的应用", zhHant="正在理解您的 App",
    ko="앱을 파악하는 중", es="Entendiendo sus apps", fr="Compréhension de vos apps", de="Apps werden verstanden", ptBR="Entendendo seus apps")
add("scan.checkingSafety",
    en="Checking what's safe", ja="安全なものを確認しています", zhHans="正在检查哪些可以安全处理", zhHant="正在檢查哪些可安全處理",
    ko="안전한지 확인하는 중", es="Comprobando qué es seguro", fr="Vérification de ce qui est sûr", de="Sicherheit wird geprüft", ptBR="Verificando o que é seguro")
add("scan.ready",
    en="Ready", ja="準備完了", zhHans="就绪", zhHant="就緒",
    ko="준비됨", es="Listo", fr="Prêt", de="Bereit", ptBR="Pronto")
add("scan.failed",
    en="Scan failed", ja="スキャンに失敗しました", zhHans="扫描失败", zhHant="掃描失敗",
    ko="검사 실패", es="Error al analizar", fr="Échec de l’analyse", de="Scan fehlgeschlagen", ptBR="Falha na análise")
add("scan.deeper",
    en="Scanning deeper…", ja="さらに詳しくスキャン中…", zhHans="正在深入扫描…", zhHant="正在深入掃描…",
    ko="더 깊이 검사 중…", es="Analizando en profundidad…", fr="Analyse plus approfondie…", de="Tieferer Scan…", ptBR="Analisando mais a fundo…")
# --- v0.2 UX FIX 001: canonical scan status ---
# ACTIVE / DEEPENING / PARTIAL+CONTINUING / COMPLETE / TRUE FAILURE.
# A partial scan is NOT a failed scan — never present it as one.
# --- v0.2 UX FIX 001: sidebar section headers (were hardcoded English) ---
add("sidebar.navigate",
    en="Navigate", ja="移動", zhHans="导航", zhHant="導覽",
    ko="이동", es="Navegar", fr="Naviguer", de="Navigation", ptBR="Navegar")
add("sidebar.ataGlance",
    en="At a glance", ja="ひと目で", zhHans="概览", zhHant="概覽",
    ko="한눈에", es="De un vistazo", fr="En un coup d’œil", de="Auf einen Blick", ptBR="Visão geral")

add("scan.status.active",
    en="Scanning…", ja="スキャン中…", zhHans="正在扫描…", zhHant="正在掃描…",
    ko="검사 중…", es="Analizando…", fr="Analyse en cours…", de="Scan läuft…", ptBR="Analisando…")
add("scan.status.deepening",
    en="Taking a closer look…", ja="さらに詳しく確認しています…",
    zhHans="正在进一步确认…", zhHant="正在進一步確認…",
    ko="더 자세히 확인하는 중…", es="Revisando con más detalle…",
    fr="Examen plus détaillé…", de="Genauere Prüfung…", ptBR="Verificando com mais detalhes…")
add("scan.status.partialContinuing",
    en="Some areas couldn’t be read. Still scanning the rest…",
    ja="一部を確認できませんでした。残りをスキャンしています…",
    zhHans="部分区域无法读取。正在扫描其余部分…",
    zhHant="部分區域無法讀取。正在掃描其餘部分…",
    ko="일부 영역을 읽지 못했습니다. 나머지를 검사하는 중…",
    es="No se pudieron leer algunas zonas. Analizando el resto…",
    fr="Certaines zones n’ont pas pu être lues. Analyse du reste…",
    de="Einige Bereiche konnten nicht gelesen werden. Der Rest wird gescannt…",
    ptBR="Não foi possível ler algumas áreas. Analisando o restante…")
add("scan.status.complete",
    en="Scan complete", ja="スキャン完了", zhHans="扫描完成", zhHant="掃描完成",
    ko="검사 완료", es="Análisis completado", fr="Analyse terminée",
    de="Scan abgeschlossen", ptBR="Análise concluída")
add("scan.status.failed",
    en="Couldn’t complete the scan", ja="スキャンを完了できませんでした",
    zhHans="无法完成扫描", zhHant="無法完成掃描",
    ko="검사를 완료하지 못했습니다", es="No se pudo completar el análisis",
    fr="Impossible de terminer l’analyse", de="Scan konnte nicht abgeschlossen werden",
    ptBR="Não foi possível concluir a análise")
# Coverage is a STATE, not progress. Used when the map is partial but nothing is running.
add("scan.coverage.partial",
    en="Some areas couldn’t be read", ja="一部を確認できませんでした",
    zhHans="部分区域无法读取", zhHant="部分區域無法讀取",
    ko="일부 영역을 읽지 못했습니다", es="No se pudieron leer algunas zonas",
    fr="Certaines zones n’ont pas pu être lues",
    de="Einige Bereiche konnten nicht gelesen werden",
    ptBR="Não foi possível ler algumas áreas")

# --- v0.2 UX FIX 001: lens labels (presentation only; rawValue stays STRUCTURE/MEANING/DECISION) ---
add("lens.structure",
    en="Where?", ja="どこにある？", zhHans="在哪里？", zhHant="在哪裡？",
    ko="어디에?", es="¿Dónde?", fr="Où ?", de="Wo?", ptBR="Onde?")
add("lens.meaning",
    en="What is it?", ja="これは何？", zhHans="这是什么？", zhHant="這是什麼？",
    ko="이게 뭔가요?", es="¿Qué es?", fr="Qu’est-ce que c’est ?", de="Was ist das?", ptBR="O que é?")
add("lens.decision",
    en="What can I do?", ja="どうする？", zhHans="能做什么？", zhHant="能做什麼？",
    ko="뭘 할 수 있나요?", es="¿Qué puedo hacer?", fr="Que puis-je faire ?",
    de="Was kann ich tun?", ptBR="O que posso fazer?")

# --- v0.2 UX FIX 001: top-bar story copy (was hardcoded English) ---
add("story.largestFolder",
    en="%1$@ is the largest mapped folder: %2$@",
    ja="%1$@ が現在もっとも大きいフォルダです：%2$@",
    zhHans="%1$@ 是目前最大的文件夹：%2$@",
    zhHant="%1$@ 是目前最大的資料夾：%2$@",
    ko="%1$@ 이(가) 현재 가장 큰 폴더입니다: %2$@",
    es="%1$@ es la carpeta más grande: %2$@",
    fr="%1$@ est le plus grand dossier : %2$@",
    de="%1$@ ist der größte Ordner: %2$@",
    ptBR="%1$@ é a maior pasta: %2$@")
add("map.inThisFolder",
    en="In this folder", ja="このフォルダ直下", zhHans="此文件夹内", zhHant="此資料夾內",
    ko="이 폴더 안", es="En esta carpeta", fr="Dans ce dossier",
    de="In diesem Ordner", ptBR="Nesta pasta")

add("scan.stagesJoined",
    en="Mapping storage · Understanding apps · Checking what is safe",
    ja="ストレージ地図化 · アプリ理解 · 安全性の確認",
    zhHans="绘制存储 · 理解应用 · 检查安全性", zhHant="繪製儲存 · 理解 App · 檢查安全性",
    ko="저장공간 매핑 · 앱 파악 · 안전성 확인",
    es="Mapear · Entender apps · Comprobar seguridad",
    fr="Cartographier · Comprendre · Vérifier",
    de="Kartieren · Apps verstehen · Sicherheit prüfen",
    ptBR="Mapear · Entender apps · Verificar segurança")

# --- Verification / recovery ---
add("verification.recovered.title",
    en="Verified recovered", ja="検証済みの回復量", zhHans="已验证回收", zhHant="已驗證回收",
    ko="검증된 회수량", es="Recuperado verificado", fr="Récupéré et vérifié", de="Verifiziert freigegeben", ptBR="Recuperado verificado")
add("verification.recovered.hint",
    en="Confirmed after completed actions.", ja="完了した操作のあとで確認済みです。", zhHans="在已完成的操作之后确认。", zhHant="在已完成的操作之後確認。",
    ko="완료된 작업 이후 확인됨.", es="Confirmado tras acciones completadas.", fr="Confirmé après des actions terminées.", de="Nach abgeschlossenen Aktionen bestätigt.", ptBR="Confirmado após ações concluídas.")
add("verification.recoveryPending.trash",
    en="Recovered storage: Pending — the data still exists in Trash.",
    ja="回復容量: 保留中 — データはまだゴミ箱にあります。",
    zhHans="回收空间：待确认 — 数据仍在废纸篓中。", zhHant="回收空間：待確認 — 資料仍在垃圾桶中。",
    ko="회수 용량: 대기 — 데이터가 아직 휴지통에 있습니다.",
    es="Almacenamiento recuperado: Pendiente — los datos siguen en la Papelera.",
    fr="Stockage récupéré : En attente — les données sont encore dans la Corbeille.",
    de="Freigegebener Speicher: Ausstehend — die Daten liegen noch im Papierkorb.",
    ptBR="Armazenamento recuperado: Pendente — os dados ainda estão no Lixo.")
add("verification.trashStillOccupies",
    en="Files in Trash still occupy disk space.",
    ja="ゴミ箱のファイルはまだディスク容量を使います。",
    zhHans="废纸篓中的文件仍占用磁盘空间。", zhHant="垃圾桶中的檔案仍佔用磁碟空間。",
    ko="휴지통의 파일은 여전히 디스크 공간을 사용합니다.",
    es="Los archivos en la Papelera siguen ocupando espacio.",
    fr="Les fichiers dans la Corbeille occupent encore de l’espace disque.",
    de="Dateien im Papierkorb belegen weiterhin Speicherplatz.",
    ptBR="Arquivos no Lixo ainda ocupam espaço em disco.")
add("verification.somethingChanged",
    en="Something changed since this was analyzed.",
    ja="分析したあと、状態が変わりました。",
    zhHans="自分析以来，状态已发生变化。", zhHant="自分析以來，狀態已改變。",
    ko="분석 이후 상태가 변경되었습니다.",
    es="Algo cambió desde que se analizó.",
    fr="Quelque chose a changé depuis l’analyse.",
    de="Seit der Analyse hat sich etwas geändert.",
    ptBR="Algo mudou desde que isto foi analisado.")

# --- Permission ---
add("permission.fullDiskAccess.title",
    en="See more of your Mac", ja="Macをもっと見えるように", zhHans="查看更多 Mac 内容", zhHant="查看更多 Mac 內容",
    ko="Mac을 더 살펴보기", es="Ver más de su Mac", fr="Voir plus de votre Mac", de="Mehr von Ihrem Mac sehen", ptBR="Ver mais do seu Mac")
add("permission.fullDiskAccess.description",
    en="AI Storage Manager can map more of your Mac if you allow Full Disk Access. Without it, the app still works on what is visible — inaccessible areas stay unknown, never empty or safe.",
    ja="フルディスクアクセスを許可すると、AI Storage Manager は Mac のより広い範囲を地図化できます。許可しなくても見える範囲では動作し、見えない領域は未知のままです（空でも安全でもありません）。",
    zhHans="如果允许“完全磁盘访问权限”，AI Storage Manager 可以绘制更多 Mac 存储地图。即使不授权，应用仍可处理可见内容——无法访问的区域保持未知，绝不会被当作空或安全。", zhHant="如果允許「完全磁碟存取」，AI Storage Manager 可以繪製更多 Mac 儲存地圖。即使不授權，App 仍可處理可見內容——無法存取的區域保持未知，絕不會被視為空或安全。",
    ko="전체 디스크 접근을 허용하면 AI Storage Manager가 Mac을 더 넓게 매핑할 수 있습니다. 허용하지 않아도 보이는 범위에서는 동작하며, 접근할 수 없는 영역은 알 수 없음으로 남고 비어 있거나 안전하다고 취급되지 않습니다.",
    es="AI Storage Manager puede mapear más de su Mac si permite Acceso completo al disco. Sin él, la app sigue funcionando con lo visible: las zonas inaccesibles permanecen desconocidas, nunca vacías ni seguras.",
    fr="AI Storage Manager peut cartographier davantage votre Mac si vous autorisez l’accès complet au disque. Sans cela, l’app fonctionne toujours sur le visible — les zones inaccessibles restent inconnues, jamais vides ni sûres.",
    de="AI Storage Manager kann mehr von Ihrem Mac kartieren, wenn Sie Vollen Festplattenzugriff erlauben. Ohne diesen funktioniert die App weiterhin mit dem Sichtbaren — unzugängliche Bereiche bleiben unbekannt, nie leer oder sicher.",
    ptBR="O AI Storage Manager pode mapear mais do seu Mac se você permitir Acesso Total ao Disco. Sem isso, o app ainda funciona com o que é visível — áreas inacessíveis permanecem desconhecidas, nunca vazias ou seguras.")
add("permission.limitedVisibility.note",
    en="Limited visibility is OK. Unknown regions stay Unknown.",
    ja="見える範囲が限られても大丈夫です。未知は未知のままです。",
    zhHans="可见范围有限也没关系。未知区域保持未知。", zhHant="可見範圍有限也沒關係。未知區域保持未知。",
    ko="보이는 범위가 제한되어도 괜찮습니다. 알 수 없는 영역은 알 수 없음으로 남습니다.",
    es="La visibilidad limitada está bien. Las regiones desconocidas siguen desconocidas.",
    fr="Une visibilité limitée convient. Les zones inconnues restent inconnues.",
    de="Eingeschränkte Sicht ist in Ordnung. Unbekannte Bereiche bleiben unbekannt.",
    ptBR="Visibilidade limitada está ok. Regiões desconhecidas permanecem desconhecidas.")

# --- Categories ---
for key, tr in {
    "category.personalFiles": dict(en="Personal Files", ja="個人ファイル", zhHans="个人文件", zhHant="個人檔案", ko="개인 파일", es="Archivos personales", fr="Fichiers personnels", de="Persönliche Dateien", ptBR="Arquivos pessoais"),
    "category.applications": dict(en="Applications", ja="アプリケーション", zhHans="应用程序", zhHant="應用程式", ko="애플리케이션", es="Aplicaciones", fr="Applications", de="Programme", ptBR="Aplicativos"),
    "category.developer": dict(en="Developer", ja="開発", zhHans="开发", zhHant="開發", ko="개발", es="Desarrollo", fr="Développement", de="Entwicklung", ptBR="Desenvolvimento"),
    "category.aiTools": dict(en="AI Tools", ja="AIツール", zhHans="AI 工具", zhHant="AI 工具", ko="AI 도구", es="Herramientas de IA", fr="Outils d’IA", de="KI-Werkzeuge", ptBR="Ferramentas de IA"),
    "category.cloud": dict(en="Cloud", ja="クラウド", zhHans="云", zhHant="雲端", ko="클라우드", es="Nube", fr="Cloud", de="Cloud", ptBR="Nuvem"),
    "category.macOSSystem": dict(en="macOS / System", ja="macOS / システム", zhHans="macOS / 系统", zhHant="macOS / 系統", ko="macOS / 시스템", es="macOS / Sistema", fr="macOS / Système", de="macOS / System", ptBR="macOS / Sistema"),
    "category.backups": dict(en="Backups", ja="バックアップ", zhHans="备份", zhHant="備份", ko="백업", es="Copias de seguridad", fr="Sauvegardes", de="Backups", ptBR="Backups"),
    "category.generatedData": dict(en="Generated Data", ja="生成データ", zhHans="生成数据", zhHant="產生的資料", ko="생성 데이터", es="Datos generados", fr="Données générées", de="Generierte Daten", ptBR="Dados gerados"),
    "category.trash": dict(en="Trash", ja="ゴミ箱", zhHans="废纸篓", zhHant="垃圾桶", ko="휴지통", es="Papelera", fr="Corbeille", de="Papierkorb", ptBR="Lixo"),
    "category.otherUnknown": dict(en="Other / Not Yet Classified", ja="その他 / 未分類", zhHans="其他 / 尚未分类", zhHant="其他 / 尚未分類", ko="기타 / 미분류", es="Otros / Sin clasificar", fr="Autre / Non classé", de="Sonstiges / Noch nicht klassifiziert", ptBR="Outros / Ainda não classificados"),
    "category.aiModels": dict(en="AI Models", ja="AIモデル", zhHans="AI 模型", zhHant="AI 模型", ko="AI 모델", es="Modelos de IA", fr="Modèles d’IA", de="KI-Modelle", ptBR="Modelos de IA"),
    "category.recordings": dict(en="Recordings", ja="録音", zhHans="录音", zhHant="錄音", ko="녹음", es="Grabaciones", fr="Enregistrements", de="Aufnahmen", ptBR="Gravações"),
    "category.browserData": dict(en="Browser Data", ja="ブラウザデータ", zhHans="浏览器数据", zhHant="瀏覽器資料", ko="브라우저 데이터", es="Datos del navegador", fr="Données du navigateur", de="Browserdaten", ptBR="Dados do navegador"),
}.items():
    add(key, **tr)

# --- Disk / overview ---
add("disk.total", en="Total capacity", ja="合計容量", zhHans="总容量", zhHant="總容量", ko="총 용량", es="Capacidad total", fr="Capacité totale", de="Gesamtkapazität", ptBR="Capacidade total")
add("disk.used", en="Used on disk", ja="使用中", zhHans="已用空间", zhHant="已用空間", ko="사용 중", es="Usado en disco", fr="Utilisé sur le disque", de="Belegt", ptBR="Usado no disco")
add("disk.free", en="Available", ja="空き容量", zhHans="可用", zhHant="可用", ko="사용 가능", es="Disponible", fr="Disponible", de="Verfügbar", ptBR="Disponível")
add("overview.noScan.title", en="No scan yet", ja="まだスキャンがありません", zhHans="尚未扫描", zhHant="尚未掃描", ko="아직 검사 없음", es="Aún no hay análisis", fr="Pas encore d’analyse", de="Noch kein Scan", ptBR="Nenhuma análise ainda")
add("overview.noScan.description", en="Scan storage to see your disk map and recommendations.", ja="ストレージをスキャンして、地図と推奨を表示します。", zhHans="扫描存储以查看磁盘地图和建议。", zhHant="掃描儲存以查看磁碟地圖與建議。", ko="저장공간을 검사해 디스크 맵과 권장을 확인하세요.", es="Analice el almacenamiento para ver el mapa y las recomendaciones.", fr="Analysez le stockage pour voir la carte et les recommandations.", de="Scannen Sie den Speicher, um Karte und Empfehlungen zu sehen.", ptBR="Analise o armazenamento para ver o mapa e as recomendações.")
add("overview.atAGlance", en="At a glance", ja="ひと目で", zhHans="概览", zhHant="概覽", ko="한눈에", es="De un vistazo", fr="En un coup d’œil", de="Auf einen Blick", ptBR="Em um relance")
add("overview.readyHint", en="Safe to review now", ja="いま確認できます", zhHans="现在可以查看", zhHant="現在可以查看", ko="지금 검토 가능", es="Listo para revisar", fr="Prêt à examiner", de="Jetzt prüfbar", ptBR="Pronto para revisar")
add("overview.needsReviewHint", en="Needs verification", ja="確認が必要", zhHans="需要核实", zhHant="需要核實", ko="확인 필요", es="Necesita verificación", fr="Vérification requise", de="Überprüfung nötig", ptBR="Precisa de verificação")
add("overview.protectedHint", en="Worth keeping", ja="残す価値あり", zhHans="值得保留", zhHant="值得保留", ko="유지할 가치 있음", es="Conviene conservar", fr="À conserver", de="Wert zu behalten", ptBR="Vale a pena manter")

# --- Inspector ---
add("inspector.whatIsThis", en="What is this?", ja="これは何？", zhHans="这是什么？", zhHant="這是什麼？", ko="이것은 무엇인가요?", es="¿Qué es esto?", fr="Qu’est-ce que c’est ?", de="Was ist das?", ptBR="O que é isto?")
add("inspector.whyLarge", en="Why is it using space?", ja="なぜ容量を使っている？", zhHans="为什么占用空间？", zhHant="為什麼佔用空間？", ko="왜 공간을 쓰나요?", es="¿Por qué usa espacio?", fr="Pourquoi utilise-t-il de l’espace ?", de="Warum belegt es Speicherplatz?", ptBR="Por que está usando espaço?")
add("inspector.doINeedIt", en="Do I need it?", ja="必要？", zhHans="我需要它吗？", zhHant="我需要它嗎？", ko="필요한가요?", es="¿Lo necesito?", fr="En ai-je besoin ?", de="Brauche ich das?", ptBR="Eu preciso disso?")
add("inspector.whyCantAct", en="Why can't I do something?", ja="なぜ操作できない？", zhHans="为什么无法操作？", zhHant="為什麼無法操作？", ko="왜 작업할 수 없나요?", es="¿Por qué no puedo actuar?", fr="Pourquoi ne puis-je pas agir ?", de="Warum kann ich nichts tun?", ptBR="Por que não posso agir?")
add("inspector.selectHint", en="Select a category or item to see details here.", ja="カテゴリか項目を選ぶと、ここに詳細が表示されます。", zhHans="选择类别或项目以在此查看详情。", zhHant="選擇類別或項目以在此查看詳細資料。", ko="카테고리나 항목을 선택하면 여기에 세부정보가 표시됩니다.", es="Seleccione una categoría o elemento para ver detalles.", fr="Sélectionnez une catégorie ou un élément pour voir les détails.", de="Wählen Sie eine Kategorie oder ein Element für Details.", ptBR="Selecione uma categoria ou item para ver detalhes.")

# --- History ---
add("history.empty", en="No previous scan yet. Storage history starts after your first scan.", ja="まだ以前のスキャンがありません。履歴は最初のスキャンのあとに始まります。", zhHans="尚无先前扫描。存储历史将在首次扫描后开始。", zhHant="尚無先前掃描。儲存歷程將在首次掃描後開始。", ko="이전 검사가 없습니다. 기록은 첫 검사 이후 시작됩니다.", es="Aún no hay análisis previos. El historial comienza tras el primero.", fr="Pas encore d’analyse. L’historique commence après la première.", de="Noch kein früherer Scan. Der Verlauf beginnt nach dem ersten Scan.", ptBR="Ainda não há análise anterior. O histórico começa após a primeira.")
add("history.noComparison", en="No comparison yet", ja="まだ比較できません", zhHans="尚无可比较内容", zhHant="尚無可比較內容", ko="아직 비교할 수 없음", es="Aún no hay comparación", fr="Pas encore de comparaison", de="Noch kein Vergleich", ptBR="Ainda sem comparação")
add("history.seeWhatChanged", en="See what changed", ja="変化を見る", zhHans="查看变化", zhHant="查看變化", ko="변경 내용 보기", es="Ver qué cambió", fr="Voir ce qui a changé", de="Änderungen ansehen", ptBR="Ver o que mudou")

# --- Plan ---
add("plan.needMoreSpace", en="Need more space?", ja="空き容量が必要？", zhHans="需要更多空间？", zhHant="需要更多空間？", ko="공간이 더 필요하신가요?", es="¿Necesita más espacio?", fr="Besoin de plus d’espace ?", de="Mehr Speicherplatz nötig?", ptBR="Precisa de mais espaço?")
add("plan.howMuch", en="How much space do you want to free?", ja="どのくらい空けたいですか？", zhHans="您想释放多少空间？", zhHant="您想釋放多少空間？", ko="얼마나 비우고 싶으신가요?", es="¿Cuánto espacio desea liberar?", fr="Combien d’espace voulez-vous libérer ?", de="Wie viel Speicherplatz möchten Sie freigeben?", ptBR="Quanto espaço você quer liberar?")
add("plan.free10GB", en="Free 10 GB", ja="10 GB 空ける", zhHans="释放 10 GB", zhHant="釋放 10 GB", ko="10 GB 확보", es="Liberar 10 GB", fr="Libérer 10 Go", de="10 GB freigeben", ptBR="Liberar 10 GB")
add("plan.free20GB", en="Free 20 GB", ja="20 GB 空ける", zhHans="释放 20 GB", zhHant="釋放 20 GB", ko="20 GB 확보", es="Liberar 20 GB", fr="Libérer 20 Go", de="20 GB freigeben", ptBR="Liberar 20 GB")
add("plan.custom", en="Custom", ja="カスタム", zhHans="自定义", zhHant="自訂", ko="사용자 지정", es="Personalizado", fr="Personnalisé", de="Benutzerdefiniert", ptBR="Personalizado")
add("plan.yourPlan", en="Your plan", ja="あなたのプラン", zhHans="您的计划", zhHant="您的計畫", ko="내 계획", es="Su plan", fr="Votre plan", de="Ihr Plan", ptBR="Seu plano")
add("plan.noActionsReady", en="No actions are currently ready.", ja="いま実行できる操作はありません。", zhHans="当前没有可执行的操作。", zhHant="目前沒有可執行的操作。", ko="현재 실행 가능한 작업이 없습니다.", es="No hay acciones listas ahora.", fr="Aucune action n’est prête.", de="Derzeit sind keine Aktionen bereit.", ptBR="Nenhuma ação está pronta agora.")
add("plan.importantExcluded", en="Important or unverified data is not in this plan.", ja="重要または未確認のデータはこのプランに含まれません。", zhHans="重要或未核实的数据不在此计划中。", zhHant="重要或未核實的資料不在此計畫中。", ko="중요하거나 미확인 데이터는 이 계획에 포함되지 않습니다.", es="Los datos importantes o no verificados no están en este plan.", fr="Les données importantes ou non vérifiées ne sont pas dans ce plan.", de="Wichtige oder ungeprüfte Daten sind nicht in diesem Plan.", ptBR="Dados importantes ou não verificados não estão neste plano.")
add("plan.diskRecoveryLater", en="Disk recovery happens after Trash is emptied — Empty Trash is not offered.", ja="ディスク容量の回復はゴミ箱を空にしたあとになります。空にする操作は提供しません。", zhHans="磁盘空间要在清空废纸篓之后才会回收——应用不会提供“清空废纸篓”。", zhHant="磁碟空間要在清空垃圾桶之後才會回收——App 不會提供「清空垃圾桶」。", ko="디스크 공간 회수는 휴지통을 비운 뒤에 이뤄집니다. 비우기 기능은 제공하지 않습니다.", es="La recuperación de disco ocurre al vaciar la Papelera — no se ofrece Vaciar.", fr="La récupération d’espace a lieu après le vidage de la Corbeille — non proposé ici.", de="Speicher wird erst nach dem Leeren des Papierkorbs frei — Leeren wird nicht angeboten.", ptBR="A recuperação de disco ocorre após esvaziar o Lixo — Esvaziar não é oferecido.")
add("plan.stale", en="This plan is stale. Refresh before acting.", ja="このプランは古いです。操作の前に更新してください。", zhHans="此计划已过期。操作前请刷新。", zhHant="此計畫已過期。操作前請重新整理。", ko="이 계획은 오래되었습니다. 실행 전에 새로고침하세요.", es="Este plan está desactualizado. Actualice antes de actuar.", fr="Ce plan est obsolète. Actualisez avant d’agir.", de="Dieser Plan ist veraltet. Vor dem Handeln aktualisieren.", ptBR="Este plano está desatualizado. Atualize antes de agir.")
add("plan.moveToTrashPotential", en="can be moved to Trash", ja="ゴミ箱に入れられます", zhHans="可移到废纸篓", zhHant="可移到垃圾桶", ko="휴지통으로 이동 가능", es="se puede mover a la Papelera", fr="peut être mis à la Corbeille", de="kann in den Papierkorb", ptBR="pode ser movido para o Lixo")

# --- Settings / language ---
add("settings.language", en="Language", ja="言語", zhHans="语言", zhHant="語言", ko="언어", es="Idioma", fr="Langue", de="Sprache", ptBR="Idioma")
add("settings.language.system", en="System Default", ja="システム設定に合わせる", zhHans="跟随系统", zhHant="跟隨系統", ko="시스템 기본값", es="Predeterminado del sistema", fr="Par défaut du système", de="Systemstandard", ptBR="Padrão do sistema")
add("settings.language.restartNote", en="Some macOS surfaces may need a relaunch to fully refresh.", ja="一部のmacOS表示は、完全に更新するため再起動が必要な場合があります。", zhHans="部分 macOS 界面可能需要重新启动应用才能完全刷新。", zhHant="部分 macOS 介面可能需要重新啟動 App 才能完全重新整理。", ko="일부 macOS 화면은 완전히 새로고침하려면 앱을 다시 시작해야 할 수 있습니다.", es="Algunas superficies de macOS pueden requerir reiniciar la app.", fr="Certaines surfaces macOS peuvent nécessiter un redémarrage.", de="Einige macOS-Oberflächen brauchen ggf. einen Neustart der App.", ptBR="Algumas superfícies do macOS podem exigir reabrir o app.")
add("settings.about", en="About", ja="情報", zhHans="关于", zhHant="關於", ko="정보", es="Acerca de", fr="À propos", de="Info", ptBR="Sobre")
add("settings.developer", en="Developer", ja="開発者", zhHans="开发者", zhHant="開發者", ko="개발자", es="Desarrollador", fr="Développeur", de="Entwickler", ptBR="Desenvolvedor")
add("settings.enableDiagnostics", en="Enable technical diagnostics", ja="技術診断を有効にする", zhHans="启用技术诊断", zhHant="啟用技術診斷", ko="기술 진단 사용", es="Activar diagnósticos técnicos", fr="Activer les diagnostics techniques", de="Technische Diagnosen aktivieren", ptBR="Ativar diagnósticos técnicos")
add("settings.openTechnical", en="Open Technical Details…", ja="技術詳細を開く…", zhHans="打开技术详情…", zhHant="開啟技術詳細資料…", ko="기술 세부정보 열기…", es="Abrir detalles técnicos…", fr="Ouvrir les détails techniques…", de="Technische Details öffnen…", ptBR="Abrir detalhes técnicos…")
add("settings.technicalDetails", en="Technical Details", ja="技術詳細", zhHans="技术详情", zhHant="技術詳細資料", ko="기술 세부정보", es="Detalles técnicos", fr="Détails techniques", de="Technische Details", ptBR="Detalhes técnicos")

# --- Entity presentation (Safety-critical) ---
add("entity.xcodeBuildData.title", en="Xcode Build Data", ja="Xcode ビルドデータ", zhHans="Xcode 构建数据", zhHant="Xcode 建置資料", ko="Xcode 빌드 데이터", es="Datos de compilación de Xcode", fr="Données de build Xcode", de="Xcode-Build-Daten", ptBR="Dados de build do Xcode")
add("entity.xcodeBuildData.what", en="Build output Xcode can create again.", ja="Xcodeが再生成できるビルド出力です。", zhHans="Xcode 可以再次生成的构建输出。", zhHant="Xcode 可以再次產生的建置輸出。", ko="Xcode가 다시 만들 수 있는 빌드 출력입니다.", es="Salida de compilación que Xcode puede volver a crear.", fr="Sortie de build que Xcode peut recréer.", de="Build-Ausgabe, die Xcode erneut erzeugen kann.", ptBR="Saída de build que o Xcode pode criar de novo.")
add("entity.ollamaModel.title", en="Ollama model", ja="Ollama モデル", zhHans="Ollama 模型", zhHant="Ollama 模型", ko="Ollama 모델", es="Modelo de Ollama", fr="Modèle Ollama", de="Ollama-Modell", ptBR="Modelo Ollama")
add("entity.ollamaModel.what", en="A downloaded AI model.", ja="ダウンロード済みのAIモデルです。", zhHans="已下载的 AI 模型。", zhHant="已下載的 AI 模型。", ko="다운로드된 AI 모델입니다.", es="Un modelo de IA descargado.", fr="Un modèle d’IA téléchargé.", de="Ein heruntergeladenes KI-Modell.", ptBR="Um modelo de IA baixado.")
add("entity.hfSnapshot.title", en="Hugging Face snapshot", ja="Hugging Face スナップショット", zhHans="Hugging Face 快照", zhHant="Hugging Face 快照", ko="Hugging Face 스냅샷", es="Instantánea de Hugging Face", fr="Instantané Hugging Face", de="Hugging-Face-Snapshot", ptBR="Snapshot do Hugging Face")
add("entity.hfSnapshot.what", en="A local AI model snapshot (exact revision).", ja="ローカルのAIモデルスナップショット（正確なリビジョン）です。", zhHans="本地 AI 模型快照（精确修订）。", zhHant="本機 AI 模型快照（精確修訂）。", ko="로컬 AI 모델 스냅샷(정확한 리비전)입니다.", es="Una instantánea local de modelo de IA (revisión exacta).", fr="Un instantané local de modèle d’IA (révision exacte).", de="Ein lokaler KI-Modell-Snapshot (genaue Revision).", ptBR="Um snapshot local de modelo de IA (revisão exata).")
add("entity.cursorState.title", en="Cursor AI & conversation state", ja="Cursor のAI・会話状態", zhHans="Cursor AI 与对话状态", zhHant="Cursor AI 與對話狀態", ko="Cursor AI 및 대화 상태", es="Estado de IA y conversación de Cursor", fr="État IA et conversation Cursor", de="Cursor-KI- und Gesprächszustand", ptBR="Estado de IA e conversa do Cursor")
add("entity.cursorState.what", en="Cursor uses this to restore chats and agent work.", ja="Cursorがチャットとエージェント作業を復元するために使います。", zhHans="Cursor 用它来恢复聊天和代理工作。", zhHant="Cursor 用它來還原聊天與代理工作。", ko="Cursor가 채팅과 에이전트 작업을 복원하는 데 사용합니다.", es="Cursor lo usa para restaurar chats y trabajo del agente.", fr="Cursor l’utilise pour restaurer chats et travail d’agent.", de="Cursor nutzt dies, um Chats und Agentenarbeit wiederherzustellen.", ptBR="O Cursor usa isto para restaurar chats e trabalho do agente.")
add("entity.cursorState.whyLarge", en="Most of this space is Cursor's AI conversation and agent state.", ja="この容量の多くはCursorのAI会話とエージェント状態です。", zhHans="大部分空间是 Cursor 的 AI 对话与代理状态。", zhHant="大部分空間是 Cursor 的 AI 對話與代理狀態。", ko="이 공간의 대부분은 Cursor의 AI 대화와 에이전트 상태입니다.", es="La mayor parte es estado de conversación e agente de Cursor.", fr="L’essentiel est l’état de conversation et d’agent Cursor.", de="Der Großteil ist KI-Gesprächs- und Agentenzustand von Cursor.", ptBR="A maior parte é estado de conversa e agente do Cursor.")
add("entity.cursorState.keepReason", en="Keep — Cursor is actively using this state.", ja="残す — Cursorがこの状態を使っています。", zhHans="保留 — Cursor 正在使用此状态。", zhHant="保留 — Cursor 正在使用此狀態。", ko="유지 — Cursor가 이 상태를 사용 중입니다.", es="Conservar — Cursor está usando este estado.", fr="Conserver — Cursor utilise cet état.", de="Behalten — Cursor nutzt diesen Zustand aktiv.", ptBR="Manter — o Cursor está usando este estado.")
add("entity.cursorBackup.title", en="Cursor recovery backup", ja="Cursor 回復バックアップ", zhHans="Cursor 恢复备份", zhHant="Cursor 復原備份", ko="Cursor 복구 백업", es="Copia de recuperación de Cursor", fr="Sauvegarde de récupération Cursor", de="Cursor-Wiederherstellungsbackup", ptBR="Backup de recuperação do Cursor")
add("entity.cursorBackup.keepReason", en="Keep — this is Cursor's recovery backup.", ja="残す — Cursorの回復用バックアップです。", zhHans="保留 — 这是 Cursor 的恢复备份。", zhHant="保留 — 這是 Cursor 的復原備份。", ko="유지 — Cursor의 복구 백업입니다.", es="Conservar — es la copia de recuperación de Cursor.", fr="Conserver — c’est la sauvegarde de récupération Cursor.", de="Behalten — dies ist das Wiederherstellungsbackup von Cursor.", ptBR="Manter — este é o backup de recuperação do Cursor.")
add("entity.cursorBackup.block", en="This is the current recovery backup.", ja="これは現在の回復バックアップです。", zhHans="这是当前的恢复备份。", zhHant="這是目前的復原備份。", ko="현재 복구 백업입니다.", es="Esta es la copia de recuperación actual.", fr="Ceci est la sauvegarde de récupération actuelle.", de="Dies ist das aktuelle Wiederherstellungsbackup.", ptBR="Este é o backup de recuperação atual.")
add("entity.voiceMemos.title", en="Your recordings", ja="あなたの録音", zhHans="您的录音", zhHant="您的錄音", ko="내 녹음", es="Sus grabaciones", fr="Vos enregistrements", de="Ihre Aufnahmen", ptBR="Suas gravações")
add("entity.voiceMemos.what", en="These are your original recordings.", ja="あなた自身のオリジナル録音です。", zhHans="这些是您的原始录音。", zhHant="這些是您的原始錄音。", ko="사용자의 원본 녹음입니다.", es="Estas son sus grabaciones originales.", fr="Ce sont vos enregistrements originaux.", de="Das sind Ihre Originalaufnahmen.", ptBR="Estas são suas gravações originais.")
add("entity.voiceMemos.whyLarge", en="Most of this space is your original audio recordings.", ja="この容量の多くはあなたの音声録音です。", zhHans="大部分空间是您的原始音频录音。", zhHant="大部分空間是您的原始音訊錄音。", ko="이 공간의 대부분은 원본 오디오 녹음입니다.", es="La mayor parte son sus grabaciones de audio originales.", fr="L’essentiel est constitué de vos enregistrements audio originaux.", de="Der Großteil sind Ihre originalen Audioaufnahmen.", ptBR="A maior parte são suas gravações de áudio originais.")
add("entity.voiceMemos.keepReason", en="Keep — these are your recordings.", ja="残す — あなたの録音です。", zhHans="保留 — 这些是您的录音。", zhHant="保留 — 這些是您的錄音。", ko="유지 — 사용자의 녹음입니다.", es="Conservar — son sus grabaciones.", fr="Conserver — ce sont vos enregistrements.", de="Behalten — das sind Ihre Aufnahmen.", ptBR="Manter — estas são suas gravações.")
add("entity.voiceMemos.block", en="Apple does not provide a verified local-only removal action for these recordings.", ja="Appleは、これらの録音向けに検証済みのローカルのみ削除手段を提供していません。", zhHans="Apple 未提供经核实的、仅删除本地副本的操作。", zhHant="Apple 未提供經驗證的、僅刪除本機副本的操作。", ko="Apple은 이 녹음에 대해 검증된 로컬 전용 제거 동작을 제공하지 않습니다.", es="Apple no ofrece una acción verificada de eliminación solo local para estas grabaciones.", fr="Apple ne fournit pas d’action vérifiée de suppression locale seule pour ces enregistrements.", de="Apple bietet keine verifizierte nur-lokale Entfernung für diese Aufnahmen.", ptBR="A Apple não fornece uma ação verificada de remoção apenas local para estas gravações.")
add("entity.chrome.title", en="Chrome browser data", ja="Chrome ブラウザデータ", zhHans="Chrome 浏览器数据", zhHant="Chrome 瀏覽器資料", ko="Chrome 브라우저 데이터", es="Datos del navegador Chrome", fr="Données du navigateur Chrome", de="Chrome-Browserdaten", ptBR="Dados do navegador Chrome")
add("entity.chrome.what", en="Browser & website data — site state plus some verified cache.", ja="ブラウザとサイトのデータ — サイト状態と一部の検証済みキャッシュ。", zhHans="浏览器与网站数据 — 站点状态加上部分已验证缓存。", zhHant="瀏覽器與網站資料 — 網站狀態加上部分已驗證快取。", ko="브라우저 및 웹사이트 데이터 — 사이트 상태와 일부 검증된 캐시.", es="Datos del navegador y sitios — estado del sitio más algo de caché verificada.", fr="Données navigateur et sites — état des sites plus un cache vérifié partiel.", de="Browser- und Website-Daten — Site-Zustand plus etwas verifizierten Cache.", ptBR="Dados do navegador e sites — estado do site mais algum cache verificado.")
add("entity.chrome.whyLarge", en="This contains website/app data plus some verified cache.", ja="サイト/アプリのデータと、一部の検証済みキャッシュが含まれます。", zhHans="包含网站/应用数据以及部分已验证缓存。", zhHant="包含網站/App 資料以及部分已驗證快取。", ko="웹사이트/앱 데이터와 일부 검증된 캐시가 포함됩니다.", es="Contiene datos de sitios/apps y algo de caché verificada.", fr="Contient des données de sites/apps et un cache vérifié partiel.", de="Enthält Website-/App-Daten sowie etwas verifizierten Cache.", ptBR="Contém dados de sites/apps e algum cache verificado.")
add("entity.chrome.keepReason", en="Protect website and app state; do not treat the whole profile as cache.", ja="サイトとアプリの状態を守ります。プロファイル全体をキャッシュ扱いしません。", zhHans="保护网站与应用状态；不要把整个配置文件当作缓存。", zhHant="保護網站與 App 狀態；不要把整個設定檔當作快取。", ko="웹사이트와 앱 상태를 보호합니다. 프로필 전체를 캐시로 취급하지 마세요.", es="Proteja el estado de sitios y apps; no trate todo el perfil como caché.", fr="Protégez l’état des sites et apps ; ne traitez pas tout le profil comme cache.", de="Website- und App-Zustand schützen; das gesamte Profil nicht als Cache behandeln.", ptBR="Proteja o estado de sites e apps; não trate o perfil inteiro como cache.")
add("entity.chrome.block", en="This contains website state, not just cache.", ja="これはキャッシュだけではなく、サイト状態を含みます。", zhHans="这包含网站状态，而不仅仅是缓存。", zhHant="這包含網站狀態，而不僅僅是快取。", ko="캐시만이 아니라 웹사이트 상태가 포함됩니다.", es="Contiene estado del sitio, no solo caché.", fr="Contient l’état du site, pas seulement du cache.", de="Enthält Website-Zustand, nicht nur Cache.", ptBR="Contém estado do site, não apenas cache.")
add("entity.claude.title", en="Claude runtime", ja="Claude ランタイム", zhHans="Claude 运行时", zhHant="Claude 執行階段", ko="Claude 런타임", es="Runtime de Claude", fr="Runtime Claude", de="Claude-Runtime", ptBR="Runtime do Claude")
add("entity.claude.what", en="Claude's base runtime and mutable session data.", ja="Claudeのベースランタイムと変更可能なセッションデータです。", zhHans="Claude 的基础运行时与可变会话数据。", zhHant="Claude 的基礎執行階段與可變工作階段資料。", ko="Claude의 기본 런타임과 변경 가능한 세션 데이터입니다.", es="Runtime base de Claude y datos de sesión mutables.", fr="Runtime de base Claude et données de session mutables.", de="Basis-Runtime von Claude und veränderliche Sitzungsdaten.", ptBR="Runtime base do Claude e dados de sessão mutáveis.")
add("entity.claude.keepReason", en="Keep — Claude is currently using this runtime.", ja="残す — Claudeがこのランタイムを使っています。", zhHans="保留 — Claude 正在使用此运行时。", zhHant="保留 — Claude 正在使用此執行階段。", ko="유지 — Claude가 이 런타임을 사용 중입니다.", es="Conservar — Claude está usando este runtime.", fr="Conserver — Claude utilise ce runtime.", de="Behalten — Claude nutzt diese Runtime gerade.", ptBR="Manter — o Claude está usando este runtime.")
add("entity.claude.block", en="Claude is currently using this.", ja="Claudeがいまこれを使っています。", zhHans="Claude 正在使用此项。", zhHant="Claude 正在使用此項目。", ko="Claude가 현재 이것을 사용 중입니다.", es="Claude lo está usando ahora.", fr="Claude l’utilise actuellement.", de="Claude nutzt dies gerade.", ptBR="O Claude está usando isto agora.")

add("settings.product", en="Product", ja="製品", zhHans="产品", zhHant="產品", ko="제품", es="Producto", fr="Produit", de="Produkt", ptBR="Produto")
add("settings.version", en="Version", ja="バージョン", zhHans="版本", zhHant="版本", ko="버전", es="Versión", fr="Version", de="Version", ptBR="Versão")
add("settings.bundleID", en="Bundle ID", ja="バンドルID", zhHans="Bundle ID", zhHant="Bundle ID", ko="번들 ID", es="Bundle ID", fr="Bundle ID", de="Bundle-ID", ptBR="Bundle ID")
add("settings.minimumMacOS", en="Minimum macOS", ja="対応macOS", zhHans="最低 macOS", zhHant="最低 macOS", ko="최소 macOS", es="macOS mínimo", fr="macOS minimum", de="Mindest-macOS", ptBR="macOS mínimo")
add("settings.productLoop", en="Product loop", ja="製品ループ", zhHans="产品循环", zhHant="產品循環", ko="제품 루프", es="Bucle del producto", fr="Boucle produit", de="Produktzyklus", ptBR="Ciclo do produto")
add("settings.productLoop.value", en="See → Understand → Decide → Act → Verify", ja="見る → 理解する → 決める → 動く → 確かめる", zhHans="看见 → 理解 → 决定 → 行动 → 验证", zhHant="看見 → 理解 → 決定 → 行動 → 驗證", ko="보기 → 이해하기 → 결정 → 행동 → 확인", es="Ver → Entender → Decidir → Actuar → Verificar", fr="Voir → Comprendre → Décider → Agir → Vérifier", de="Sehen → Verstehen → Entscheiden → Handeln → Prüfen", ptBR="Ver → Entender → Decidir → Agir → Verificar")
add("settings.research", en="Research", ja="リサーチ", zhHans="研究", zhHant="研究", ko="리서치", es="Investigación", fr="Recherche", de="Forschung", ptBR="Pesquisa")
add("settings.research.frozen", en="Frozen (complete)", ja="凍結（完了）", zhHans="已冻结（完成）", zhHant="已凍結（完成）", ko="동결(완료)", es="Congelado (completo)", fr="Gelé (terminé)", de="Eingefroren (fertig)", ptBR="Congelado (completo)")

# --- Fine-grained entity subtype titles (P5.4 leftovers) ---
add("entity.cursorAgentCLI.title",
    en="Cursor agent CLI toolchain", ja="Cursor エージェント CLI ツールチェーン",
    zhHans="Cursor 代理 CLI 工具链", zhHant="Cursor 代理 CLI 工具鏈",
    ko="Cursor 에이전트 CLI 툴체인", es="Cadena de herramientas CLI del agente Cursor",
    fr="Chaîne d’outils CLI de l’agent Cursor", de="Cursor-Agent-CLI-Toolchain",
    ptBR="Ferramentas CLI do agente Cursor")
add("entity.chromeWebsiteState.title",
    en="Website & app data", ja="サイトとアプリのデータ",
    zhHans="网站与应用数据", zhHant="網站與 App 資料",
    ko="웹사이트 및 앱 데이터", es="Datos de sitios y apps",
    fr="Données de sites et d’apps", de="Website- und App-Daten",
    ptBR="Dados de sites e apps")
add("entity.claudeMutableState.title",
    en="Claude session state", ja="Claude のセッション状態",
    zhHans="Claude 会话状态", zhHant="Claude 工作階段狀態",
    ko="Claude 세션 상태", es="Estado de sesión de Claude",
    fr="État de session Claude", de="Claude-Sitzungszustand",
    ptBR="Estado de sessão do Claude")
add("entity.claudeRuntimeBase.title",
    en="Claude runtime base", ja="Claude ランタイム基盤",
    zhHans="Claude 运行时基础", zhHant="Claude 執行階段基礎",
    ko="Claude 런타임 기반", es="Base del runtime de Claude",
    fr="Base du runtime Claude", de="Claude-Runtime-Basis",
    ptBR="Base do runtime Claude")
add("entity.ollamaModels.title",
    en="Ollama Models", ja="Ollama モデル",
    zhHans="Ollama 模型", zhHant="Ollama 模型",
    ko="Ollama 모델", es="Modelos de Ollama",
    fr="Modèles Ollama", de="Ollama-Modelle",
    ptBR="Modelos Ollama")
add("entity.hfModels.title",
    en="Hugging Face Models", ja="Hugging Face モデル",
    zhHans="Hugging Face 模型", zhHant="Hugging Face 模型",
    ko="Hugging Face 모델", es="Modelos de Hugging Face",
    fr="Modèles Hugging Face", de="Hugging-Face-Modelle",
    ptBR="Modelos Hugging Face")
add("entity.claudeData.title",
    en="Claude Data", ja="Claude データ",
    zhHans="Claude 数据", zhHant="Claude 資料",
    ko="Claude 데이터", es="Datos de Claude",
    fr="Données Claude", de="Claude-Daten",
    ptBR="Dados do Claude")
add("entity.cursor.title",
    en="Cursor", ja="Cursor", zhHans="Cursor", zhHant="Cursor",
    ko="Cursor", es="Cursor", fr="Cursor", de="Cursor", ptBR="Cursor")
add("entity.codex.title",
    en="Codex", ja="Codex", zhHans="Codex", zhHant="Codex",
    ko="Codex", es="Codex", fr="Codex", de="Codex", ptBR="Codex")
add("entity.simulatorDevices.title",
    en="Simulator Devices", ja="シミュレータデバイス",
    zhHans="模拟器设备", zhHant="模擬器裝置",
    ko="시뮬레이터 기기", es="Dispositivos del simulador",
    fr="Appareils simulateur", de="Simulator-Geräte",
    ptBR="Dispositivos do simulador")
add("entity.gitRepository.title",
    en="Git Repository", ja="Git リポジトリ",
    zhHans="Git 仓库", zhHant="Git 儲存庫",
    ko="Git 저장소", es="Repositorio Git",
    fr="Dépôt Git", de="Git-Repository",
    ptBR="Repositório Git")
add("entity.icloudData.title",
    en="iCloud Data", ja="iCloud データ",
    zhHans="iCloud 数据", zhHant="iCloud 資料",
    ko="iCloud 데이터", es="Datos de iCloud",
    fr="Données iCloud", de="iCloud-Daten",
    ptBR="Dados do iCloud")
add("entity.macosUpdateCache.title",
    en="macOS Update Cache", ja="macOS アップデートキャッシュ",
    zhHans="macOS 更新缓存", zhHant="macOS 更新快取",
    ko="macOS 업데이트 캐시", es="Caché de actualizaciones de macOS",
    fr="Cache de mises à jour macOS", de="macOS-Update-Cache",
    ptBR="Cache de atualização do macOS")
add("entity.iphoneBackup.title",
    en="iPhone Backup", ja="iPhone バックアップ",
    zhHans="iPhone 备份", zhHant="iPhone 備份",
    ko="iPhone 백업", es="Copia de iPhone",
    fr="Sauvegarde iPhone", de="iPhone-Backup",
    ptBR="Backup do iPhone")
add("entity.trash.title",
    en="Trash", ja="ゴミ箱",
    zhHans="废纸篓", zhHant="垃圾桶",
    ko="휴지통", es="Papelera",
    fr="Corbeille", de="Papierkorb",
    ptBR="Lixeira")
add("entity.generic.storageUsed",
    en="Storage used by this item on your Mac.", ja="この項目がMac上で使っている容量です。",
    zhHans="此项在您的 Mac 上占用的空间。", zhHant="此項目在您的 Mac 上佔用的空間。",
    ko="이 항목이 Mac에서 사용하는 저장공간입니다.", es="Almacenamiento que usa este elemento en su Mac.",
    fr="Espace utilisé par cet élément sur votre Mac.", de="Speicher, den dieses Element auf Ihrem Mac belegt.",
    ptBR="Armazenamento que este item usa no seu Mac.")
add("entity.desc.developer",
    en="Developer tools and build-related data on your Mac.", ja="Mac上の開発ツールとビルド関連データです。",
    zhHans="Mac 上的开发工具与构建相关数据。", zhHant="Mac 上的開發工具與建置相關資料。",
    ko="Mac의 개발 도구 및 빌드 관련 데이터입니다.", es="Herramientas de desarrollo y datos de compilación en su Mac.",
    fr="Outils de développement et données de build sur votre Mac.", de="Entwicklertools und Build-Daten auf Ihrem Mac.",
    ptBR="Ferramentas de desenvolvimento e dados de build no seu Mac.")
add("entity.desc.aiTools",
    en="AI development tools and locally stored model data.", ja="AI開発ツールとローカル保存のモデルデータです。",
    zhHans="AI 开发工具与本地存储的模型数据。", zhHant="AI 開發工具與本機儲存的模型資料。",
    ko="AI 개발 도구와 로컬에 저장된 모델 데이터입니다.", es="Herramientas de IA y datos de modelos almacenados localmente.",
    fr="Outils d’IA et données de modèles stockées localement.", de="KI-Entwicklungstools und lokal gespeicherte Modelldaten.",
    ptBR="Ferramentas de IA e dados de modelos armazenados localmente.")
add("entity.desc.cloud",
    en="Cloud-backed or synchronized storage.", ja="クラウド連携または同期されたストレージです。",
    zhHans="云端支持或已同步的存储。", zhHant="雲端支援或已同步的儲存。",
    ko="클라우드 지원 또는 동기화된 저장공간입니다.", es="Almacenamiento en la nube o sincronizado.",
    fr="Stockage cloud ou synchronisé.", de="Cloud-gestützter oder synchronisierter Speicher.",
    ptBR="Armazenamento na nuvem ou sincronizado.")
add("entity.desc.backups",
    en="Backup data stored locally.", ja="ローカルに保存されたバックアップデータです。",
    zhHans="本地存储的备份数据。", zhHant="本機儲存的備份資料。",
    ko="로컬에 저장된 백업 데이터입니다.", es="Datos de copia de seguridad almacenados localmente.",
    fr="Données de sauvegarde stockées localement.", de="Lokal gespeicherte Backup-Daten.",
    ptBR="Dados de backup armazenados localmente.")
add("entity.desc.macOSSystem",
    en="System-related caches and support files.", ja="システム関連のキャッシュとサポートファイルです。",
    zhHans="系统相关缓存与支持文件。", zhHant="系統相關快取與支援檔案。",
    ko="시스템 관련 캐시와 지원 파일입니다.", es="Cachés y archivos de soporte del sistema.",
    fr="Caches et fichiers de support liés au système.", de="Systembezogene Caches und Supportdateien.",
    ptBR="Caches e arquivos de suporte do sistema.")
add("entity.desc.generatedData",
    en="Generated or cache data.", ja="生成データまたはキャッシュです。",
    zhHans="生成数据或缓存。", zhHant="產生的資料或快取。",
    ko="생성된 데이터 또는 캐시입니다.", es="Datos generados o de caché.",
    fr="Données générées ou de cache.", de="Generierte Daten oder Cache.",
    ptBR="Dados gerados ou de cache.")
add("entity.desc.personalFiles",
    en="Personal files in your home folder.", ja="ホームフォルダ内の個人ファイルです。",
    zhHans="主文件夹中的个人文件。", zhHant="主資料夾中的個人檔案。",
    ko="홈 폴더의 개인 파일입니다.", es="Archivos personales en su carpeta de inicio.",
    fr="Fichiers personnels dans votre dossier de départ.", de="Persönliche Dateien in Ihrem Benutzerordner.",
    ptBR="Arquivos pessoais na sua pasta pessoal.")
add("entity.why.aiTools",
    en="AI models and tool caches can grow to many gigabytes.", ja="AIモデルとツールのキャッシュは数GBまで増え得ます。",
    zhHans="AI 模型与工具缓存可能增至数 GB。", zhHant="AI 模型與工具快取可能增至數 GB。",
    ko="AI 모델과 도구 캐시는 수 GB까지 커질 수 있습니다.", es="Los modelos de IA y cachés de herramientas pueden crecer muchos GB.",
    fr="Les modèles d’IA et caches d’outils peuvent atteindre plusieurs Go.", de="KI-Modelle und Tool-Caches können viele GB groß werden.",
    ptBR="Modelos de IA e caches de ferramentas podem crescer muitos GB.")
add("entity.why.developer",
    en="Build artifacts, simulators, and package caches accumulate over time.", ja="ビルド成果物、シミュレータ、パッケージキャッシュは時間とともに増えます。",
    zhHans="构建产物、模拟器和软件包缓存会随时间累积。", zhHant="建置產物、模擬器與套件快取會隨時間累積。",
    ko="빌드 산출물, 시뮬레이터, 패키지 캐시는 시간이 지나며 쌓입니다.", es="Artefactos de build, simuladores y cachés de paquetes se acumulan.",
    fr="Les artefacts de build, simulateurs et caches de paquets s’accumulent.", de="Build-Artefakte, Simulatoren und Paket-Caches wachsen mit der Zeit.",
    ptBR="Artefatos de build, simuladores e caches de pacotes acumulam com o tempo.")
add("entity.why.backups",
    en="Device backups store full snapshots locally.", ja="デバイスバックアップは完全なスナップショットをローカルに保存します。",
    zhHans="设备备份会在本地存储完整快照。", zhHant="裝置備份會在本機儲存完整快照。",
    ko="기기 백업은 전체 스냅샷을 로컬에 저장합니다.", es="Las copias de dispositivo guardan instantáneas completas localmente.",
    fr="Les sauvegardes d’appareil stockent des instantanés complets localement.", de="Geräte-Backups speichern vollständige Snapshots lokal.",
    ptBR="Backups de dispositivo armazenam snapshots completos localmente.")
add("entity.protect.voiceMemos",
    en="Keep — these are your original recordings. Deleting can sync across Apple devices, and Apple doesn’t expose a verified local-only offload for Voice Memos.",
    ja="残す — あなた自身のオリジナル録音です。削除はAppleデバイス間で同期され得ます。Voice Memos向けの検証済みローカルのみ退避は提供されていません。",
    zhHans="保留 — 这些是您的原始录音。删除可能在 Apple 设备间同步，且 Apple 未提供经核实的仅本地卸载方式。",
    zhHant="保留 — 這些是您的原始錄音。刪除可能在 Apple 裝置間同步，且 Apple 未提供經驗證的僅本機卸載方式。",
    ko="유지 — 원본 녹음입니다. 삭제는 Apple 기기 간에 동기화될 수 있으며, Voice Memos용 검증된 로컬 전용 오프로드는 없습니다.",
    es="Conservar — son sus grabaciones originales. Borrar puede sincronizarse entre dispositivos Apple, y Apple no ofrece una descarga solo local verificada para Notas de Voz.",
    fr="Conserver — ce sont vos enregistrements originaux. La suppression peut se synchroniser entre appareils Apple, et Apple n’expose pas de déchargement local vérifié pour Mémos vocaux.",
    de="Behalten — das sind Ihre Originalaufnahmen. Löschen kann auf Apple-Geräten synchronisieren; Apple bietet kein verifiziertes nur-lokales Auslagern für Sprachnotizen.",
    ptBR="Manter — estas são suas gravações originais. Excluir pode sincronizar entre dispositivos Apple, e a Apple não oferece remoção apenas local verificada para Memorando de Voz.")
add("entity.protect.iosBackup",
    en="Keep — this is a local device backup. Moving this folder directly may make the backup unusable.",
    ja="残す — ローカルのデバイスバックアップです。このフォルダを直接動かすとバックアップが使えなくなることがあります。",
    zhHans="保留 — 这是本地设备备份。直接移动此文件夹可能导致备份无法使用。",
    zhHant="保留 — 這是本機裝置備份。直接移動此資料夾可能使備份無法使用。",
    ko="유지 — 로컬 기기 백업입니다. 이 폴더를 직접 옮기면 백업을 쓸 수 없게 될 수 있습니다.",
    es="Conservar — es una copia local del dispositivo. Mover esta carpeta directamente puede inutilizar la copia.",
    fr="Conserver — c’est une sauvegarde locale d’appareil. Déplacer ce dossier directement peut rendre la sauvegarde inutilisable.",
    de="Behalten — dies ist ein lokales Geräte-Backup. Direkter Ordnerzugriff kann das Backup unbrauchbar machen.",
    ptBR="Manter — este é um backup local do dispositivo. Mover esta pasta diretamente pode inutilizar o backup.")
add("entity.protect.git",
    en="Keep — Git repository data requires relocation contracts. Bulk delete is blocked.",
    ja="残す — Gitリポジトリデータは移設契約が必要です。一括削除は遮断されています。",
    zhHans="保留 — Git 仓库数据需要迁移约定。批量删除已阻止。",
    zhHant="保留 — Git 儲存庫資料需要遷移約定。大量刪除已阻擋。",
    ko="유지 — Git 저장소 데이터는 이전 계약이 필요합니다. 대량 삭제는 차단됩니다.",
    es="Conservar — los datos de Git requieren contratos de reubicación. El borrado masivo está bloqueado.",
    fr="Conserver — les données Git exigent des contrats de relocation. La suppression en masse est bloquée.",
    de="Behalten — Git-Repository-Daten brauchen Umzugsverträge. Massenlöschen ist gesperrt.",
    ptBR="Manter — dados de repositório Git exigem contratos de relocação. Exclusão em massa está bloqueada.")
add("entity.protect.claude",
    en="Keep — Claude’s runtime includes a base system and mutable session state. Active runtimes stay protected.",
    ja="残す — Claudeのランタイムは基盤と変更可能なセッション状態を含みます。稼働中は保護されます。",
    zhHans="保留 — Claude 运行时包含基础系统与可变会话状态。活动运行时保持受保护。",
    zhHant="保留 — Claude 執行階段包含基礎系統與可變工作階段狀態。活動執行階段維持受保護。",
    ko="유지 — Claude 런타임은 기반 시스템과 변경 가능한 세션 상태를 포함합니다. 활성 런타임은 보호됩니다.",
    es="Conservar — el runtime de Claude incluye un sistema base y estado de sesión mutable. Los runtimes activos quedan protegidos.",
    fr="Conserver — le runtime Claude inclut un système de base et un état de session mutable. Les runtimes actifs restent protégés.",
    de="Behalten — Claudes Runtime umfasst Basis und veränderlichen Sitzungszustand. Aktive Runtimes bleiben geschützt.",
    ptBR="Manter — o runtime do Claude inclui sistema base e estado de sessão mutável. Runtimes ativos permanecem protegidos.")
add("entity.protect.chrome",
    en="Keep site and app data protected. Browser “cache” names alone aren’t enough to treat this as disposable.",
    ja="サイトとアプリのデータを保護します。ブラウザの「キャッシュ」という名前だけでは捨ててよいと判断しません。",
    zhHans="保护网站与应用数据。仅凭浏览器“缓存”名称不足以视为可丢弃。",
    zhHant="保護網站與 App 資料。僅憑瀏覽器「快取」名稱不足以視為可丟棄。",
    ko="사이트와 앱 데이터를 보호합니다. 브라우저 ‘캐시’라는 이름만으로 버려도 된다고 보지 않습니다.",
    es="Mantenga protegidos los datos de sitios y apps. El nombre “caché” del navegador no basta para tratarlos como desechables.",
    fr="Gardez protégées les données de sites et d’apps. Le seul nom « cache » du navigateur ne suffit pas à les traiter comme jetables.",
    de="Website- und App-Daten geschützt halten. Der bloße Browser-Name „Cache“ reicht nicht aus, sie als entbehrlich zu behandeln.",
    ptBR="Mantenha protegidos os dados de sites e apps. O nome “cache” do navegador sozinho não basta para tratá-los como descartáveis.")
add("entity.protect.cursor",
    en="Keep — Cursor uses this state to restore your work. Cleanup isn’t available for this store.",
    ja="残す — Cursorはこの状態で作業を復元します。このストアのクリーンアップはありません。",
    zhHans="保留 — Cursor 用此状态恢复您的工作。此存储不提供清理。",
    zhHant="保留 — Cursor 用此狀態還原您的工作。此存放區不提供清理。",
    ko="유지 — Cursor가 이 상태로 작업을 복원합니다. 이 저장소에는 정리 기능이 없습니다.",
    es="Conservar — Cursor usa este estado para restaurar su trabajo. No hay limpieza para este almacén.",
    fr="Conserver — Cursor utilise cet état pour restaurer votre travail. Aucun nettoyage n’est disponible pour ce magasin.",
    de="Behalten — Cursor nutzt diesen Zustand, um Ihre Arbeit wiederherzustellen. Für diesen Speicher gibt es keine Bereinigung.",
    ptBR="Manter — o Cursor usa este estado para restaurar seu trabalho. Não há limpeza para este armazenamento.")
add("entity.protect.generic",
    en="Keep — this data is protected.", ja="残す — このデータは保護されています。",
    zhHans="保留 — 此数据受保护。", zhHant="保留 — 此資料受保護。",
    ko="유지 — 이 데이터는 보호됩니다.", es="Conservar — estos datos están protegidos.",
    fr="Conserver — ces données sont protégées.", de="Behalten — diese Daten sind geschützt.",
    ptBR="Manter — estes dados estão protegidos.")
add("entity.protect.noAction",
    en="No generic action is available for this item yet.", ja="この項目向けの汎用操作はまだありません。",
    zhHans="此项尚无通用操作。", zhHant="此項目尚無通用操作。",
    ko="이 항목에 대한 일반 동작은 아직 없습니다.", es="Aún no hay una acción genérica para este elemento.",
    fr="Aucune action générique n’est encore disponible pour cet élément.", de="Für dieses Element ist noch keine allgemeine Aktion verfügbar.",
    ptBR="Ainda não há uma ação genérica para este item.")
add("review.safetyIncomplete",
    en="Safety evidence incomplete", ja="Safetyの根拠が不足しています",
    zhHans="安全证据不足", zhHant="安全證據不足",
    ko="Safety 근거가 부족합니다", es="Evidencia de seguridad incompleta",
    fr="Preuves de sécurité incomplètes", de="Safety-Nachweis unvollständig",
    ptBR="Evidência de segurança incompleta")
add("review.manualReview",
    en="Need manual review before any action", ja="操作前に人手確認が必要です",
    zhHans="操作前需要人工核实", zhHant="操作前需要人工核實",
    ko="동작 전에 수동 확인이 필요합니다", es="Se necesita revisión manual antes de cualquier acción",
    fr="Révision manuelle requise avant toute action", de="Manuelle Prüfung vor jeder Aktion nötig",
    ptBR="Revisão manual necessária antes de qualquer ação")
add("review.verifyInUse",
    en="Need to verify whether this is still in use", ja="まだ使われているか確認が必要です",
    zhHans="需要核实是否仍在使用", zhHant="需要核實是否仍在使用",
    ko="아직 사용 중인지 확인이 필요합니다", es="Hay que verificar si sigue en uso",
    fr="Il faut vérifier si c’est encore utilisé", de="Prüfen, ob dies noch verwendet wird",
    ptBR="É preciso verificar se ainda está em uso")
add("review.appManaged",
    en="Application-managed data", ja="アプリ管理データ",
    zhHans="应用管理的数据", zhHant="App 管理的資料",
    ko="앱 관리 데이터", es="Datos gestionados por la app",
    fr="Données gérées par l’app", de="App-verwaltete Daten",
    ptBR="Dados gerenciados pelo app")
add("review.needsMore",
    en="Needs more verification", ja="追加の確認が必要です",
    zhHans="需要进一步核实", zhHant="需要進一步核實",
    ko="추가 확인이 필요합니다", es="Necesita más verificación",
    fr="Nécessite davantage de vérification", de="Mehr Überprüfung nötig",
    ptBR="Precisa de mais verificação")
add("review.openByProcess",
    en="Open by another process", ja="別プロセスが使用中",
    zhHans="被其他进程打开", zhHant="被其他行程開啟",
    ko="다른 프로세스가 사용 중", es="Abierto por otro proceso",
    fr="Ouvert par un autre processus", de="Von anderem Prozess geöffnet",
    ptBR="Aberto por outro processo")
add("review.verifyCloud",
    en="Need to verify cloud sync", ja="クラウド同期の確認が必要です",
    zhHans="需要核实云同步", zhHant="需要核實雲端同步",
    ko="클라우드 동기화 확인이 필요합니다", es="Hay que verificar la sincronización en la nube",
    fr="Il faut vérifier la synchro cloud", de="Cloud-Sync prüfen",
    ptBR="É preciso verificar a sincronização na nuvem")
add("review.cannotVerifySource",
    en="Cannot verify original source", ja="原本を確認できません",
    zhHans="无法核实原始来源", zhHant="無法核實原始來源",
    ko="원본을 확인할 수 없습니다", es="No se puede verificar el origen",
    fr="Impossible de vérifier la source d’origine", de="Originalquelle nicht verifizierbar",
    ptBR="Não é possível verificar a origem")

# --- Accessibility / misc ---
add("a11y.mapHint", en="Storage map. Use the child list for VoiceOver navigation.", ja="ストレージ地図。VoiceOverでは子リストを使ってください。", zhHans="存储地图。请使用子列表进行 VoiceOver 导航。", zhHant="儲存地圖。請使用子清單進行 VoiceOver 導覽。", ko="저장공간 맵. VoiceOver 탐색에는 하위 목록을 사용하세요.", es="Mapa de almacenamiento. Use la lista hija para VoiceOver.", fr="Carte de stockage. Utilisez la liste enfant pour VoiceOver.", de="Speicherkarte. Nutzen Sie die Kinderliste für VoiceOver.", ptBR="Mapa de armazenamento. Use a lista filha para o VoiceOver.")
add("common.searchPlaceholder", en="Search files, folders, tools…", ja="ファイル、フォルダ、ツールを検索…", zhHans="搜索文件、文件夹、工具…", zhHant="搜尋檔案、資料夾、工具…", ko="파일, 폴더, 도구 검색…", es="Buscar archivos, carpetas, herramientas…", fr="Rechercher fichiers, dossiers, outils…", de="Dateien, Ordner, Tools suchen…", ptBR="Pesquisar arquivos, pastas, ferramentas…")
add("common.clear", en="Clear", ja="クリア", zhHans="清除", zhHant="清除", ko="지우기", es="Borrar", fr="Effacer", de="Löschen", ptBR="Limpar")
add("common.firstRunPromise", en="See what's using your Mac. Understand what it is. Only act when it's safe.", ja="Macの容量の使い道を見る。何かを理解する。安全なときだけ動く。", zhHans="看看 Mac 的空间用在哪里。理解它是什么。只有安全时才行动。", zhHant="看看 Mac 的空間用在哪裡。理解它是什麼。只有安全時才行動。", ko="Mac이 무엇을 쓰는지 보고, 무엇인지 이해한 뒤, 안전할 때만 행동하세요.", es="Vea qué usa su Mac. Entienda qué es. Actúe solo cuando sea seguro.", fr="Voyez ce qui utilise votre Mac. Comprenez ce que c’est. Agissez seulement si c’est sûr.", de="Sehen Sie, was Speicher belegt. Verstehen Sie, was es ist. Handeln Sie nur, wenn es sicher ist.", ptBR="Veja o que usa seu Mac. Entenda o que é. Só aja quando for seguro.")
add("error.partialScan", en="Some storage couldn't be inspected.", ja="一部のストレージを調べられませんでした。", zhHans="部分存储无法检查。", zhHant="部分儲存無法檢查。", ko="일부 저장공간을 검사할 수 없었습니다.", es="Parte del almacenamiento no se pudo inspeccionar.", fr="Une partie du stockage n’a pas pu être inspectée.", de="Ein Teil des Speichers konnte nicht geprüft werden.", ptBR="Parte do armazenamento não pôde ser inspecionada.")
add("error.weDontKnowEnough", en="We don't know enough yet.", ja="まだ十分な情報がありません。", zhHans="我们还不够了解。", zhHant="我們還不夠了解。", ko="아직 충분히 알지 못합니다.", es="Aún no sabemos lo suficiente.", fr="Nous n’en savons pas encore assez.", de="Wir wissen noch nicht genug.", ptBR="Ainda não sabemos o suficiente.")
add("plural.verificationAreas", en="We found %d areas that need more verification.", ja="確認が必要な領域が %d 件あります。", zhHans="发现 %d 处需要进一步核实。", zhHant="發現 %d 處需要進一步核實。", ko="추가 확인이 필요한 영역이 %d개 있습니다.", es="Encontramos %d áreas que necesitan más verificación.", fr="Nous avons trouvé %d zones nécessitant davantage de vérification.", de="Wir haben %d Bereiche gefunden, die mehr Überprüfung brauchen.", ptBR="Encontramos %d áreas que precisam de mais verificação.")

add("map.footnote.mapped",
    en="mapped", ja="マップ済み", zhHans="已映射", zhHant="已對應",
    ko="매핑됨", es="asignado", fr="cartographié", de="zugeordnet", ptBR="mapeado")
add("map.footnote.folder",
    en="folder", ja="フォルダ", zhHans="文件夹", zhHant="資料夾",
    ko="폴더", es="carpeta", fr="dossier", de="Ordner", ptBR="pasta")
add("map.footnote.item",
    en="item", ja="項目", zhHans="项目", zhHant="項目",
    ko="항목", es="elemento", fr="élément", de="Element", ptBR="item")
add("map.footnote.unavailable",
    en="Mapping unavailable", ja="マップ不可", zhHans="无法映射", zhHant="無法對應",
    ko="매핑 불가", es="Asignación no disponible", fr="Cartographie indisponible", de="Zuordnung nicht verfügbar", ptBR="Mapeamento indisponível")
add("entity.restrictedNotScanned.title",
    en="Restricted / Not Scanned", ja="制限あり / 未スキャン",
    zhHans="受限 / 未扫描", zhHant="受限 / 未掃描",
    ko="제한됨 / 미검사", es="Restringido / No analizado",
    fr="Restreint / Non analysé", de="Eingeschränkt / Nicht gescannt",
    ptBR="Restrito / Não analisado")
add("entity.restrictedNotScanned.what",
    en="This area could not be read. It is not represented as empty.",
    ja="この領域は読めませんでした。空としては扱いません。",
    zhHans="无法读取此区域。不会把它显示为空。",
    zhHant="無法讀取此區域。不會把它顯示為空。",
    ko="이 영역을 읽을 수 없었습니다. 비어 있는 것으로 표시하지 않습니다.",
    es="No se pudo leer esta área. No se representa como vacía.",
    fr="Cette zone n’a pas pu être lue. Elle n’est pas représentée comme vide.",
    de="Dieser Bereich konnte nicht gelesen werden. Er wird nicht als leer dargestellt.",
    ptBR="Esta área não pôde ser lida. Não é representada como vazia.")
add("entity.generic.file",
    en="A file on your Mac. AI Storage Manager has not identified this item's role yet.",
    ja="Mac上のファイルです。役割はまだ特定していません。",
    zhHans="Mac 上的文件。尚未识别其用途。",
    zhHant="Mac 上的檔案。尚未識別其用途。",
    ko="Mac의 파일입니다. 역할을 아직 확인하지 않았습니다.",
    es="Un archivo en su Mac. Aún no se ha identificado su función.",
    fr="Un fichier sur votre Mac. Son rôle n’est pas encore identifié.",
    de="Eine Datei auf Ihrem Mac. Die Rolle ist noch nicht erkannt.",
    ptBR="Um arquivo no seu Mac. A função ainda não foi identificada.")
add("entity.generic.package",
    en="A macOS package. Drill in only if you need the contents.",
    ja="macOSパッケージです。中身が必要なときだけ掘り下げてください。",
    zhHans="macOS 软件包。仅在需要内容时再深入。",
    zhHant="macOS 套件。僅在需要內容時再深入。",
    ko="macOS 패키지입니다. 내용이 필요할 때만 들어가세요.",
    es="Un paquete de macOS. Entre solo si necesita el contenido.",
    fr="Un paquet macOS. N’explorez que si vous avez besoin du contenu.",
    de="Ein macOS-Paket. Nur bei Bedarf hineinblicken.",
    ptBR="Um pacote do macOS. Entre só se precisar do conteúdo.")
add("entity.generic.symlink",
    en="A symbolic link. The map does not follow it, so bytes are not duplicated.",
    ja="シンボリックリンクです。地図は追跡しないので、容量は二重計上しません。",
    zhHans="符号链接。地图不会跟随它，因此不会重复计算容量。",
    zhHant="符號連結。地圖不會跟隨它，因此不會重複計算容量。",
    ko="심볼릭 링크입니다. 맵이 따라가지 않아 용량을 중복 계산하지 않습니다.",
    es="Un enlace simbólico. El mapa no lo sigue, así que no duplica bytes.",
    fr="Un lien symbolique. La carte ne le suit pas, donc les octets ne sont pas dupliqués.",
    de="Ein symbolischer Link. Die Karte folgt ihm nicht — Bytes werden nicht doppelt gezählt.",
    ptBR="Um link simbólico. O mapa não o segue, então os bytes não são duplicados.")
add("entity.generic.aggregate",
    en="Smaller items grouped so the map stays readable. The underlying folders remain discoverable.",
    ja="地図を読みやすくするため小さい項目をまとめています。実体のフォルダは辿れます。",
    zhHans="为保持地图可读而合并的较小项目。底层文件夹仍可发现。",
    zhHant="為保持地圖可讀而合併的較小項目。底層資料夾仍可發現。",
    ko="맵을 읽기 쉽게 작은 항목을 묶었습니다. 실제 폴더는 탐색할 수 있습니다.",
    es="Elementos pequeños agrupados para que el mapa sea legible. Las carpetas siguen descubribles.",
    fr="Petits éléments regroupés pour garder la carte lisible. Les dossiers restent trouvables.",
    de="Kleinere Elemente gruppiert, damit die Karte lesbar bleibt. Ordner bleiben auffindbar.",
    ptBR="Itens menores agrupados para o mapa ficar legível. As pastas continuam descobíveis.")
add("entity.generic.unidentified",
    en="AI Storage Manager has not identified this item's role yet.",
    ja="この項目の役割はまだ特定していません。",
    zhHans="尚未识别此项的用途。",
    zhHant="尚未識別此項目的用途。",
    ko="이 항목의 역할을 아직 확인하지 않았습니다.",
    es="Aún no se ha identificado la función de este elemento.",
    fr="Le rôle de cet élément n’est pas encore identifié.",
    de="Die Rolle dieses Elements ist noch nicht erkannt.",
    ptBR="A função deste item ainda não foi identificada.")
add("history.usedDelta",
    en="%@ used", ja="使用 %@", zhHans="已用 %@", zhHant="已用 %@",
    ko="사용 %@", es="%@ usados", fr="%@ utilisés", de="%@ belegt", ptBR="%@ usados")

# --- Fixture / screenshot labels (P5.4 visual QA; not live storage truth) ---
add("fixture.reviewAction",
    en="Review action", ja="操作を確認", zhHans="检查操作", zhHant="檢查操作",
    ko="작업 검토", es="Revisar acción", fr="Examiner l’action", de="Aktion prüfen", ptBR="Revisar ação")
add("fixture.whatWillHappen",
    en="What will happen", ja="何が起きるか", zhHans="将会发生什么", zhHant="將會發生什麼",
    ko="무슨 일이 일어나는지", es="Qué ocurrirá", fr="Ce qui va se passer", de="Was passiert", ptBR="O que vai acontecer")
add("fixture.whatWillRemain",
    en="What will remain", ja="何が残るか", zhHans="会保留什么", zhHant="會保留什麼",
    ko="무엇이 남는지", es="Qué permanecerá", fr="Ce qui restera", de="Was bleibt", ptBR="O que permanece")
add("fixture.canItComeBack",
    en="Can it come back?", ja="戻せますか？", zhHans="还能回来吗？", zhHant="還能回來嗎？",
    ko="다시 가져올 수 있나요?", es="¿Puede volver?", fr="Peut-il revenir ?", de="Kann es zurückkommen?", ptBR="Pode voltar?")
add("fixture.whoPerforms",
    en="Who performs this?", ja="誰が実行するか", zhHans="谁来执行？", zhHant="誰來執行？",
    ko="누가 수행하나요?", es="¿Quién lo realiza?", fr="Qui l’effectue ?", de="Wer führt das aus?", ptBR="Quem executa?")
add("fixture.ollamaRemoveExact",
    en="Ollama will remove this exact model from local storage.",
    ja="Ollamaがこの正確なモデルをローカルから削除します。",
    zhHans="Ollama 将从本地存储移除此精确模型。",
    zhHant="Ollama 將從本機儲存移除此精確模型。",
    ko="Ollama가 이 정확한 모델을 로컬 저장공간에서 제거합니다.",
    es="Ollama eliminará este modelo exacto del almacenamiento local.",
    fr="Ollama retirera ce modèle exact du stockage local.",
    de="Ollama entfernt genau dieses Modell aus dem lokalen Speicher.",
    ptBR="O Ollama removerá este modelo exato do armazenamento local.")
add("fixture.otherModelsStay",
    en="Your other models stay. Hub/remote availability is unchanged.",
    ja="他のモデルはそのままです。Hub/リモートの可用性は変わりません。",
    zhHans="其他模型保留。Hub/远程可用性不变。",
    zhHant="其他模型保留。Hub/遠端可用性不變。",
    ko="다른 모델은 그대로입니다. Hub/원격 가용성은 변하지 않습니다.",
    es="Sus otros modelos permanecen. La disponibilidad remota/Hub no cambia.",
    fr="Vos autres modèles restent. La disponibilité Hub/distante est inchangée.",
    de="Ihre anderen Modelle bleiben. Hub-/Remote-Verfügbarkeit bleibt gleich.",
    ptBR="Seus outros modelos permanecem. A disponibilidade Hub/remota não muda.")
add("fixture.downloadAgain",
    en="Yes — you can download the model again with Ollama later.",
    ja="はい — あとでOllamaでモデルを再ダウンロードできます。",
    zhHans="可以 — 之后可用 Ollama 再次下载该模型。",
    zhHant="可以 — 之後可用 Ollama 再次下載該模型。",
    ko="예 — 나중에 Ollama로 모델을 다시 다운로드할 수 있습니다.",
    es="Sí — puede volver a descargar el modelo con Ollama más tarde.",
    fr="Oui — vous pourrez retélécharger le modèle avec Ollama plus tard.",
    de="Ja — Sie können das Modell später erneut mit Ollama laden.",
    ptBR="Sim — você pode baixar o modelo de novo com o Ollama depois.")
add("fixture.ollamaVendorNative",
    en="Ollama (vendor-native cleanup). Exact target: library/qwen3:4b",
    ja="Ollama（ベンダー固有クリーンアップ）。正確な対象: library/qwen3:4b",
    zhHans="Ollama（厂商原生清理）。精确目标：library/qwen3:4b",
    zhHant="Ollama（廠商原生清理）。精確目標：library/qwen3:4b",
    ko="Ollama(벤더 네이티브 정리). 정확한 대상: library/qwen3:4b",
    es="Ollama (limpieza nativa del proveedor). Objetivo exacto: library/qwen3:4b",
    fr="Ollama (nettoyage natif du fournisseur). Cible exacte : library/qwen3:4b",
    de="Ollama (herstellereigene Bereinigung). Exaktes Ziel: library/qwen3:4b",
    ptBR="Ollama (limpeza nativa do fornecedor). Alvo exato: library/qwen3:4b")
add("fixture.historicalNote",
    en="FIXTURE / HISTORICAL — not a live candidate. Approval is separate from recommendation.",
    ja="FIXTURE / 履歴 — ライブ候補ではありません。承認は推奨とは別です。",
    zhHans="FIXTURE / 历史 — 非实时候选。批准与建议是分开的。",
    zhHant="FIXTURE / 歷程 — 非即時候選。核准與建議是分開的。",
    ko="FIXTURE / 기록 — 라이브 후보가 아닙니다. 승인은 권장과 별개입니다.",
    es="FIXTURE / HISTÓRICO — no es un candidato en vivo. La aprobación es distinta de la recomendación.",
    fr="FIXTURE / HISTORIQUE — pas un candidat en direct. L’approbation est distincte de la recommandation.",
    de="FIXTURE / HISTORISCH — kein Live-Kandidat. Freigabe ist getrennt von der Empfehlung.",
    ptBR="FIXTURE / HISTÓRICO — não é candidato ao vivo. Aprovação é separada da recomendação.")
add("fixture.somethingChanged",
    en="Something changed", ja="状態が変わりました", zhHans="状态已变化", zhHant="狀態已變更",
    ko="상태가 바뀌었습니다", es="Algo cambió", fr="Quelque chose a changé", de="Etwas hat sich geändert", ptBR="Algo mudou")
add("fixture.stateNoLongerMatches",
    en="Since we analyzed this item, its state no longer matches.",
    ja="分析以降、この項目の状態が一致しなくなりました。",
    zhHans="自分析以来，此项状态已不再匹配。",
    zhHant="自分析以來，此項目狀態已不再相符。",
    ko="분석 이후 이 항목의 상태가 더 이상 일치하지 않습니다.",
    es="Desde el análisis, el estado de este elemento ya no coincide.",
    fr="Depuis l’analyse, l’état de cet élément ne correspond plus.",
    de="Seit der Analyse stimmt der Zustand dieses Elements nicht mehr.",
    ptBR="Desde a análise, o estado deste item não corresponde mais.")
add("fixture.currentCheck",
    en="Current check", ja="現在の確認", zhHans="当前检查", zhHant="目前檢查",
    ko="현재 확인", es="Comprobación actual", fr="Vérification actuelle", de="Aktuelle Prüfung", ptBR="Verificação atual")
add("fixture.checkingDone",
    en="Checking current state… done", ja="現在の状態を確認…完了", zhHans="正在检查当前状态…完成", zhHant="正在檢查目前狀態…完成",
    ko="현재 상태 확인… 완료", es="Comprobando estado actual… listo", fr="Vérification de l’état actuel… terminée", de="Aktuellen Zustand prüfen… fertig", ptBR="Verificando estado atual… concluído")
add("fixture.readyNoLongerAvailable",
    en="Ready for review — no longer available", ja="確認準備 — もう利用できません", zhHans="可供检查 — 已不可用", zhHant="可供檢查 — 已不可用",
    ko="검토 준비됨 — 더 이상 사용 불가", es="Listo para revisar — ya no disponible", fr="Prêt à examiner — plus disponible", de="Zur Prüfung bereit — nicht mehr verfügbar", ptBR="Pronto para revisão — não está mais disponível")
add("fixture.changedSinceAnalyzed",
    en="Something changed since we analyzed this.",
    ja="分析以降に何かが変わりました。",
    zhHans="自分析以来发生了变化。",
    zhHant="自分析以來發生了變更。",
    ko="분석 이후 무언가 바뀌었습니다.",
    es="Algo cambió desde que lo analizamos.",
    fr="Quelque chose a changé depuis l’analyse.",
    de="Seit der Analyse hat sich etwas geändert.",
    ptBR="Algo mudou desde que analisamos.")
add("fixture.reviewAgain",
    en="Review Again", ja="もう一度確認", zhHans="再次检查", zhHant="再次檢查",
    ko="다시 검토", es="Revisar de nuevo", fr="Examiner à nouveau", de="Erneut prüfen", ptBR="Revisar novamente")
add("fixture.changedStateNote",
    en="FIXTURE — changed-state UX. Not a generic error.",
    ja="FIXTURE — 状態変化UX。汎用エラーではありません。",
    zhHans="FIXTURE — 状态变化 UX。不是通用错误。",
    zhHant="FIXTURE — 狀態變更 UX。不是通用錯誤。",
    ko="FIXTURE — 상태 변경 UX. 일반 오류가 아닙니다.",
    es="FIXTURE — UX de estado cambiado. No es un error genérico.",
    fr="FIXTURE — UX d’état modifié. Pas une erreur générique.",
    de="FIXTURE — UX für geänderten Zustand. Kein generischer Fehler.",
    ptBR="FIXTURE — UX de estado alterado. Não é um erro genérico.")
add("fixture.verifiedResult",
    en="Verified result", ja="検証済みの結果", zhHans="已验证结果", zhHant="已驗證結果",
    ko="검증된 결과", es="Resultado verificado", fr="Résultat vérifié", de="Verifiziertes Ergebnis", ptBR="Resultado verificado")
add("fixture.verifiedRecoveredHeadline",
    en="%@ verified recovered", ja="検証済み回復 %@", zhHans="已验证回收 %@", zhHant="已驗證回收 %@",
    ko="검증된 회수 %@", es="%@ recuperados verificados", fr="%@ récupérés vérifiés", de="%@ verifiziert freigegeben", ptBR="%@ recuperados verificados")
add("fixture.removedLocalSnapshot",
    en="✓ Removed local snapshot", ja="✓ ローカルスナップショットを削除", zhHans="✓ 已移除本地快照", zhHant="✓ 已移除本機快照",
    ko="✓ 로컬 스냅샷 제거됨", es="✓ Instantánea local eliminada", fr="✓ Instantané local retiré", de="✓ Lokaler Snapshot entfernt", ptBR="✓ Snapshot local removido")
add("fixture.exactTargetGone",
    en="✓ Exact target no longer exists locally", ja="✓ 正確な対象はローカルに存在しません", zhHans="✓ 精确目标本地已不存在", zhHant="✓ 精確目標本機已不存在",
    ko="✓ 정확한 대상이 로컬에 더 이상 없음", es="✓ El objetivo exacto ya no existe localmente", fr="✓ La cible exacte n’existe plus localement", de="✓ Exaktes Ziel existiert lokal nicht mehr", ptBR="✓ O alvo exato não existe mais localmente")
add("fixture.remoteRevisionAvailable",
    en="✓ Remote revision is still available", ja="✓ リモートリビジョンはまだ利用可能", zhHans="✓ 远程修订仍然可用", zhHant="✓ 遠端修訂仍然可用",
    ko="✓ 원격 리비전이 여전히 사용 가능", es="✓ La revisión remota sigue disponible", fr="✓ La révision distante est toujours disponible", de="✓ Remote-Revision ist weiterhin verfügbar", ptBR="✓ A revisão remota ainda está disponível")
add("fixture.diskFreeSeparate",
    en="Disk free change: +%@ (separate from verified)",
    ja="空き容量の変化: +%@（検証済みとは別）",
    zhHans="磁盘可用变化：+%@（与已验证回收分开）",
    zhHant="磁碟可用變化：+%@（與已驗證回收分開）",
    ko="디스크 여유 변화: +%@ (검증과 별개)",
    es="Cambio de espacio libre: +%@ (separado de lo verificado)",
    fr="Changement d’espace libre : +%@ (séparé du vérifié)",
    de="Freier Speicher: +%@ (getrennt vom Verifizierten)",
    ptBR="Mudança de espaço livre: +%@ (separado do verificado)")
add("fixture.receiptHistoricalNote",
    en="FIXTURE / HISTORICAL_VERIFIED_ACTION — P3.2B.3 receipt. Not current live disk truth.",
    ja="FIXTURE / HISTORICAL_VERIFIED_ACTION — P3.2B.3 レシート。現在のライブディスク真実ではありません。",
    zhHans="FIXTURE / HISTORICAL_VERIFIED_ACTION — P3.2B.3 回执。非当前实时磁盘真相。",
    zhHant="FIXTURE / HISTORICAL_VERIFIED_ACTION — P3.2B.3 回執。非目前即時磁碟真相。",
    ko="FIXTURE / HISTORICAL_VERIFIED_ACTION — P3.2B.3 영수증. 현재 라이브 디스크 진실이 아닙니다.",
    es="FIXTURE / HISTORICAL_VERIFIED_ACTION — recibo P3.2B.3. No es la verdad actual del disco.",
    fr="FIXTURE / HISTORICAL_VERIFIED_ACTION — reçu P3.2B.3. Pas la vérité disque actuelle.",
    de="FIXTURE / HISTORICAL_VERIFIED_ACTION — Beleg P3.2B.3. Keine aktuelle Live-Disk-Wahrheit.",
    ptBR="FIXTURE / HISTORICAL_VERIFIED_ACTION — recibo P3.2B.3. Não é a verdade atual do disco.")
add("fixture.movedToTrash",
    en="Moved to Trash", ja="ゴミ箱へ移動済み", zhHans="已移到废纸篓", zhHant="已移到垃圾桶",
    ko="휴지통으로 이동됨", es="Movido a la Papelera", fr="Déplacé vers la Corbeille", de="In den Papierkorb gelegt", ptBR="Movido para a Lixeira")
add("fixture.spacePending",
    en="Space recovered: Pending", ja="容量回復: 保留中", zhHans="空间回收：待确认", zhHant="空間回收：待確認",
    ko="공간 회수: 대기 중", es="Espacio recuperado: Pendiente", fr="Espace récupéré : En attente", de="Freigabe: Ausstehend", ptBR="Espaço recuperado: Pendente")
add("fixture.movedToTrashCheck",
    en="✓ Moved to Trash", ja="✓ ゴミ箱へ移動", zhHans="✓ 已移到废纸篓", zhHant="✓ 已移到垃圾桶",
    ko="✓ 휴지통으로 이동됨", es="✓ Movido a la Papelera", fr="✓ Déplacé vers la Corbeille", de="✓ In den Papierkorb gelegt", ptBR="✓ Movido para a Lixeira")
add("fixture.spacePendingCheck",
    en="○ Space recovered: Pending", ja="○ 容量回復: 保留中", zhHans="○ 空间回收：待确认", zhHant="○ 空間回收：待確認",
    ko="○ 공간 회수: 대기 중", es="○ Espacio recuperado: Pendiente", fr="○ Espace récupéré : En attente", de="○ Freigabe: Ausstehend", ptBR="○ Espaço recuperado: Pendente")
add("fixture.trashStillOccupies",
    en="Files in Trash still occupy disk space.",
    ja="ゴミ箱内のファイルはまだディスク容量を使います。",
    zhHans="废纸篓中的文件仍占用磁盘空间。",
    zhHant="垃圾桶中的檔案仍佔用磁碟空間。",
    ko="휴지통의 파일은 여전히 디스크 공간을 차지합니다.",
    es="Los archivos en la Papelera siguen ocupando espacio.",
    fr="Les fichiers dans la Corbeille occupent encore de l’espace.",
    de="Dateien im Papierkorb belegen weiterhin Speicherplatz.",
    ptBR="Arquivos na Lixeira ainda ocupam espaço em disco.")
add("fixture.emptyTrashNotOffered",
    en="Empty Trash is not offered by this app.",
    ja="このアプリはゴミ箱を空にする操作を提供しません。",
    zhHans="本应用不提供清空废纸篓。",
    zhHant="本 App 不提供清空垃圾桶。",
    ko="이 앱은 휴지통 비우기를 제공하지 않습니다.",
    es="Vaciar la Papelera no lo ofrece esta app.",
    fr="Vider la Corbeille n’est pas proposé par cette app.",
    de="Papierkorb leeren bietet diese App nicht an.",
    ptBR="Esvaziar a Lixeira não é oferecido por este app.")
add("fixture.trashPendingNote",
    en="FIXTURE — MOVE_TO_TRASH pending recovery semantics. Not a failed execution.",
    ja="FIXTURE — MOVE_TO_TRASH の回復保留セマンティクス。失敗実行ではありません。",
    zhHans="FIXTURE — MOVE_TO_TRASH 待确认回收语义。不是失败执行。",
    zhHant="FIXTURE — MOVE_TO_TRASH 待確認回收語意。不是失敗執行。",
    ko="FIXTURE — MOVE_TO_TRASH 회수 대기 의미. 실패한 실행이 아닙니다.",
    es="FIXTURE — semántica de recuperación pendiente MOVE_TO_TRASH. No es una ejecución fallida.",
    fr="FIXTURE — sémantique de récupération en attente MOVE_TO_TRASH. Pas une exécution échouée.",
    de="FIXTURE — MOVE_TO_TRASH mit ausstehender Freigabe. Keine fehlgeschlagene Ausführung.",
    ptBR="FIXTURE — semântica de recuperação pendente MOVE_TO_TRASH. Não é execução falha.")
add("fixture.remoteCopyVerified",
    en="Remote copy: Previously verified available",
    ja="リモートコピー: 以前に利用可能と検証済み",
    zhHans="远程副本：先前已验证可用",
    zhHant="遠端副本：先前已驗證可用",
    ko="원격 사본: 이전에 사용 가능으로 검증됨",
    es="Copia remota: previamente verificada como disponible",
    fr="Copie distante : précédemment vérifiée comme disponible",
    de="Remote-Kopie: zuvor als verfügbar verifiziert",
    ptBR="Cópia remota: previamente verificada como disponível")
add("fixture.proofCoverage",
    en="Proof coverage", ja="根拠の範囲", zhHans="证据覆盖", zhHant="證據涵蓋",
    ko="근거 범위", es="Cobertura de prueba", fr="Couverture de preuve", de="Nachweisabdeckung", ptBR="Cobertura de prova")
add("overview.readyCount",
    en="Ready: %d", ja="準備完了: %d", zhHans="就绪：%d", zhHant="就緒：%d",
    ko="준비됨: %d", es="Listo: %d", fr="Prêt : %d", de="Bereit: %d", ptBR="Pronto: %d")
add("overview.reviewCount",
    en="Review: %d", ja="要確認: %d", zhHans="需核实：%d", zhHant="需核實：%d",
    ko="확인: %d", es="Revisión: %d", fr="À vérifier : %d", de="Prüfung: %d", ptBR="Revisão: %d")
add("overview.protectedCount",
    en="Protected: %d", ja="保護: %d", zhHans="受保护：%d", zhHant="受保護：%d",
    ko="보호됨: %d", es="Protegido: %d", fr="Protégé : %d", de="Geschützt: %d", ptBR="Protegido: %d")
add("common.done",
    en="Done", ja="完了", zhHans="完成", zhHant="完成",
    ko="완료", es="Listo", fr="Terminé", de="Fertig", ptBR="Concluído")
add("common.cancel",
    en="Cancel", ja="キャンセル", zhHans="取消", zhHant="取消",
    ko="취소", es="Cancelar", fr="Annuler", de="Abbrechen", ptBR="Cancelar")

# --- v0.2 remaining English UI recovery ---
add("list.recommendations",
    en="Recommendations", ja="おすすめ", zhHans="建议", zhHant="建議",
    ko="추천", es="Recomendaciones", fr="Recommandations", de="Empfehlungen", ptBR="Recomendações")
add("list.recommendation",
    en="Recommendation", ja="推奨", zhHans="建议", zhHant="建議",
    ko="권장", es="Recomendación", fr="Recommandation", de="Empfehlung", ptBR="Recomendação")
add("list.review",
    en="Review", ja="確認", zhHans="检查", zhHant="檢查",
    ko="검토", es="Revisar", fr="Examiner", de="Prüfen", ptBR="Revisar")
add("list.needsReviewEmpty",
    en="Nothing needs review right now.", ja="いま確認が必要なものはありません。", zhHans="当前没有需要核实的项目。", zhHant="目前沒有需要核實的項目。",
    ko="지금 확인할 항목이 없습니다.", es="Ahora no hay nada que revisar.", fr="Rien à vérifier pour le moment.", de="Derzeit nichts zu prüfen.", ptBR="Nada precisa de revisão agora.")
add("list.protectedEmpty",
    en="No protected items in this scan.", ja="このスキャンに保護項目はありません。", zhHans="本次扫描中没有受保护项目。", zhHant="本次掃描中沒有受保護項目。",
    ko="이 검사에 보호된 항목이 없습니다.", es="No hay elementos protegidos en este análisis.", fr="Aucun élément protégé dans cette analyse.", de="Keine geschützten Einträge in diesem Scan.", ptBR="Nenhum item protegido nesta análise.")
add("history.recentActions",
    en="Recent Actions", ja="最近の操作", zhHans="最近的操作", zhHant="最近的操作",
    ko="최근 작업", es="Acciones recientes", fr="Actions récentes", de="Letzte Aktionen", ptBR="Ações recentes")
add("history.noActionsYet",
    en="No actions yet.", ja="まだ操作はありません。", zhHans="尚无操作。", zhHant="尚無操作。",
    ko="아직 작업이 없습니다.", es="Aún no hay acciones.", fr="Aucune action pour l’instant.", de="Noch keine Aktionen.", ptBR="Ainda não há ações.")
add("history.unexplainedNotMappedGrowth",
    en="This is not invented as mapped growth.", ja="これは地図上の増加としてでっち上げたものではありません。", zhHans="这不是当作已映射增长而编造的。", zhHant="這不是當作已對應成長而捏造的。",
    ko="매핑된 증가로 지어낸 것이 아닙니다.", es="Esto no se inventa como crecimiento mapeado.", fr="Ceci n’est pas inventé comme une croissance cartographiée.", de="Das ist kein erfundenes kartiertes Wachstum.", ptBR="Isso não é inventado como crescimento mapeado.")
add("detail.whyRemovable",
    en="Why this may be removable", ja="削除候補になりうる理由", zhHans="可能可移除的原因", zhHant="可能可移除的原因",
    ko="제거 가능할 수 있는 이유", es="Por qué podría ser eliminable", fr="Pourquoi cela peut être supprimable", de="Warum dies entfernbar sein kann", ptBR="Por que isso pode ser removível")
add("detail.recommended",
    en="Recommended", ja="推奨", zhHans="推荐", zhHant="建議",
    ko="권장", es="Recomendado", fr="Recommandé", de="Empfohlen", ptBR="Recomendado")
add("detail.checkingSafety",
    en="Checking current safety…", ja="いまの安全性を確認中…", zhHans="正在检查当前安全性…", zhHant="正在檢查目前安全性…",
    ko="현재 안전성 확인 중…", es="Comprobando seguridad actual…", fr="Vérification de la sécurité actuelle…", de="Aktuelle Sicherheit wird geprüft…", ptBR="Verificando segurança atual…")
add("detail.freshSafetyCheck",
    en="Fresh Safety Check", ja="最新の安全確認", zhHans="最新安全检查", zhHant="最新安全檢查",
    ko="최신 안전 확인", es="Comprobación de seguridad reciente", fr="Contrôle de sécurité à jour", de="Aktuelle Sicherheitsprüfung", ptBR="Verificação de segurança atual")
add("detail.movingToTrash",
    en="Moving to Trash…", ja="ゴミ箱へ移動中…", zhHans="正在移到废纸篓…", zhHant="正在移到垃圾桶…",
    ko="휴지통으로 이동 중…", es="Moviendo a la Papelera…", fr="Mise à la Corbeille…", de="Wird in den Papierkorb gelegt…", ptBR="Movendo para o Lixo…")
add("detail.runSafetyCheckAgain",
    en="Run safety check again", ja="安全確認をもう一度実行", zhHans="再次运行安全检查", zhHant="再次執行安全檢查",
    ko="안전 확인 다시 실행", es="Volver a comprobar seguridad", fr="Relancer le contrôle de sécurité", de="Sicherheitsprüfung erneut ausführen", ptBR="Executar verificação de segurança novamente")
add("detail.openFullReview",
    en="Open full review", ja="詳細確認を開く", zhHans="打开完整检查", zhHant="開啟完整檢查",
    ko="전체 검토 열기", es="Abrir revisión completa", fr="Ouvrir l’examen complet", de="Vollständige Prüfung öffnen", ptBR="Abrir revisão completa")
add("detail.whatShouldIDo",
    en="What should I do?", ja="どうすればいい？", zhHans="我该怎么做？", zhHant="我該怎麼做？",
    ko="어떻게 해야 하나요?", es="¿Qué debo hacer?", fr="Que dois-je faire ?", de="Was soll ich tun?", ptBR="O que devo fazer?")
add("detail.storageItem",
    en="Storage Item", ja="ストレージ項目", zhHans="存储项目", zhHant="儲存項目",
    ko="저장공간 항목", es="Elemento de almacenamiento", fr="Élément de stockage", de="Speicherelement", ptBR="Item de armazenamento")
add("action.runSafetyCheck",
    en="Run Safety Check", ja="安全確認を実行", zhHans="运行安全检查", zhHant="執行安全檢查",
    ko="안전 확인 실행", es="Ejecutar comprobación de seguridad", fr="Lancer le contrôle de sécurité", de="Sicherheitsprüfung ausführen", ptBR="Executar verificação de segurança")
add("approval.title",
    en="Approve Action", ja="操作を承認", zhHans="批准操作", zhHant="核准操作",
    ko="작업 승인", es="Aprobar acción", fr="Approuver l’action", de="Aktion freigeben", ptBR="Aprovar ação")
add("approval.actionMoveToTrash",
    en="Action: Move to Trash", ja="操作: ゴミ箱に入れる", zhHans="操作：移到废纸篓", zhHant="操作：移到垃圾桶",
    ko="작업: 휴지통으로 이동", es="Acción: Mover a la Papelera", fr="Action : Mettre à la Corbeille", de="Aktion: In den Papierkorb legen", ptBR="Ação: Mover para o Lixo")
add("approval.expectedSize",
    en="Expected size: %@", ja="想定サイズ: %@", zhHans="预计大小：%@", zhHant="預計大小：%@",
    ko="예상 크기: %@", es="Tamaño esperado: %@", fr="Taille attendue : %@", de="Erwartete Größe: %@", ptBR="Tamanho esperado: %@")
add("approval.whatWillHappen",
    en="What will happen", ja="何が起きるか", zhHans="将会发生什么", zhHant="將會發生什麼",
    ko="어떤 일이 일어나는지", es="Qué sucederá", fr="Ce qui va se passer", de="Was passiert", ptBR="O que vai acontecer")
add("approval.diskRecovery",
    en="Disk recovery", ja="ディスク回復", zhHans="磁盘回收", zhHant="磁碟回收",
    ko="디스크 회수", es="Recuperación de disco", fr="Récupération disque", de="Speicherfreigabe", ptBR="Recuperação de disco")
add("map.listView",
    en="List view", ja="リスト表示", zhHans="列表视图", zhHant="列表檢視",
    ko="목록 보기", es="Vista de lista", fr="Vue liste", de="Listenansicht", ptBR="Visualização em lista")
add("a11y.mapListAlternative",
    en="Category list alternative to storage map", ja="ストレージ地図の代わりのカテゴリリスト", zhHans="存储地图的类别列表替代", zhHant="儲存地圖的類別清單替代",
    ko="저장공간 맵 대신 카테고리 목록", es="Lista de categorías alternativa al mapa", fr="Liste de catégories alternative à la carte", de="Kategorieliste als Alternative zur Speicherkarte", ptBR="Lista de categorias alternativa ao mapa")
add("a11y.diskSummary",
    en="Disk summary with verified recovered storage", ja="検証済み回復量つきのディスク概要", zhHans="含已验证回收量的磁盘摘要", zhHant="含已驗證回收量的磁碟摘要",
    ko="검증된 회수량이 포함된 디스크 요약", es="Resumen de disco con almacenamiento recuperado verificado", fr="Résumé disque avec stockage récupéré vérifié", de="Festplattenübersicht mit verifiziert freigegebenem Speicher", ptBR="Resumo do disco com armazenamento recuperado verificado")
add("plan.goalLabel",
    en="Goal", ja="目標", zhHans="目标", zhHant="目標",
    ko="목표", es="Objetivo", fr="Objectif", de="Ziel", ptBR="Meta")
add("debug.technicalTitle",
    en="Technical / Debug", ja="技術 / デバッグ", zhHans="技术 / 调试", zhHant="技術 / 除錯",
    ko="기술 / 디버그", es="Técnico / Depuración", fr="Technique / Débogage", de="Technik / Debug", ptBR="Técnico / Depuração")
add("debug.searchPlaceholder",
    en="Search name, category, ID, path", ja="名前・カテゴリ・ID・パスで検索", zhHans="按名称、类别、ID、路径搜索", zhHant="依名稱、類別、ID、路徑搜尋",
    ko="이름, 카테고리, ID, 경로 검색", es="Buscar nombre, categoría, ID, ruta", fr="Rechercher nom, catégorie, ID, chemin", de="Name, Kategorie, ID, Pfad suchen", ptBR="Pesquisar nome, categoria, ID, caminho")
add("debug.safeActions",
    en="Safe Actions", ja="安全な操作", zhHans="安全操作", zhHant="安全操作",
    ko="안전한 작업", es="Acciones seguras", fr="Actions sûres", de="Sichere Aktionen", ptBR="Ações seguras")
add("map.otherSmallerItems",
    en="Other smaller items", ja="その他の小さい項目", zhHans="其他较小项目", zhHant="其他較小項目",
    ko="기타 작은 항목", es="Otros elementos más pequeños", fr="Autres éléments plus petits", de="Weitere kleinere Elemente", ptBR="Outros itens menores")
add("map.containsLargeChildren",
    en="Contains large child items: %@.", ja="大きな子項目を含みます: %@。", zhHans="包含较大的子项：%@。", zhHant="包含較大的子項目：%@。",
    ko="큰 하위 항목 포함: %@.", es="Contiene elementos secundarios grandes: %@.", fr="Contient de grands éléments enfants : %@.", de="Enthält große Unterelemente: %@.", ptBR="Contém itens filhos grandes: %@.")
add("map.containsAIModels",
    en="Contains downloaded AI models or tool data.", ja="ダウンロード済みのAIモデルやツールデータを含みます。", zhHans="包含已下载的 AI 模型或工具数据。", zhHant="包含已下載的 AI 模型或工具資料。",
    ko="다운로드된 AI 모델 또는 도구 데이터를 포함합니다.", es="Contiene modelos de IA o datos de herramientas descargados.", fr="Contient des modèles IA ou données d’outils téléchargés.", de="Enthält heruntergeladene KI-Modelle oder Tool-Daten.", ptBR="Contém modelos de IA ou dados de ferramentas baixados.")
add("map.containsDeveloper",
    en="Contains generated build artifacts or developer caches.", ja="生成されたビルド成果物や開発者キャッシュを含みます。", zhHans="包含生成的构建产物或开发者缓存。", zhHant="包含產生的建置產物或開發者快取。",
    ko="생성된 빌드 산출물 또는 개발자 캐시를 포함합니다.", es="Contiene artefactos de compilación o cachés de desarrollo.", fr="Contient des artefacts de build ou caches développeur.", de="Enthält Build-Artefakte oder Entwickler-Caches.", ptBR="Contém artefatos de build ou caches de desenvolvedor.")
add("map.containsAppSupport",
    en="Contains application support data.", ja="アプリケーションサポートデータを含みます。", zhHans="包含应用程序支持数据。", zhHant="包含應用程式支援資料。",
    ko="애플리케이션 지원 데이터를 포함합니다.", es="Contiene datos de soporte de aplicaciones.", fr="Contient des données de support d’applications.", de="Enthält Application-Support-Daten.", ptBR="Contém dados de suporte de aplicativos.")
add("map.containsCloud",
    en="Contains local cloud materialization.", ja="クラウドのローカル実体化を含みます。", zhHans="包含云内容的本地实体。", zhHant="包含雲端內容的本機實體。",
    ko="로컬 클라우드 실체화를 포함합니다.", es="Contiene materialización local en la nube.", fr="Contient une matérialisation cloud locale.", de="Enthält lokale Cloud-Materialisierung.", ptBR="Contém materialização local na nuvem.")
add("detail.ollamaLocal",
    en="Locally stored Ollama model data.", ja="ローカルに保存された Ollama モデルデータ。", zhHans="本地存储的 Ollama 模型数据。", zhHant="本機儲存的 Ollama 模型資料。",
    ko="로컬에 저장된 Ollama 모델 데이터.", es="Datos de modelo Ollama almacenados localmente.", fr="Données de modèles Ollama stockées localement.", de="Lokal gespeicherte Ollama-Modelldaten.", ptBR="Dados de modelo Ollama armazenados localmente.")
add("detail.hfLocal",
    en="Locally stored AI model data from Hugging Face Hub cache.", ja="Hugging Face Hub キャッシュ由来のローカルAIモデルデータ。", zhHans="来自 Hugging Face Hub 缓存的本地 AI 模型数据。", zhHant="來自 Hugging Face Hub 快取的本機 AI 模型資料。",
    ko="Hugging Face Hub 캐시의 로컬 AI 모델 데이터.", es="Datos de modelo IA locales de la caché de Hugging Face Hub.", fr="Données de modèles IA locales du cache Hugging Face Hub.", de="Lokale KI-Modelldaten aus dem Hugging-Face-Hub-Cache.", ptBR="Dados de modelo de IA locais do cache do Hugging Face Hub.")
add("detail.categoryOnMac",
    en="Storage in this category on your Mac.", ja="このカテゴリの Mac 上のストレージ。", zhHans="Mac 上此类别的存储。", zhHant="Mac 上此類別的儲存。",
    ko="Mac의 이 카테고리 저장공간.", es="Almacenamiento de esta categoría en su Mac.", fr="Stockage de cette catégorie sur votre Mac.", de="Speicher dieser Kategorie auf Ihrem Mac.", ptBR="Armazenamento desta categoria no seu Mac.")
add("detail.ollamaSharedNote",
    en="Some model files may be shared by multiple models. AI Storage Manager checks those relationships before recommending cleanup.", ja="一部のモデルファイルは複数モデルで共有されることがあります。整理を勧める前に、その関係を確認します。", zhHans="部分模型文件可能被多个模型共享。在建议清理前，本应用会检查这些关系。", zhHant="部分模型檔案可能被多個模型共用。在建議清理前，本 App 會檢查這些關係。",
    ko="일부 모델 파일은 여러 모델이 공유할 수 있습니다. 정리를 권하기 전에 그 관계를 확인합니다.", es="Algunos archivos de modelo pueden compartirse. Se comprueban esas relaciones antes de recomendar limpieza.", fr="Certains fichiers de modèle peuvent être partagés. Ces relations sont vérifiées avant toute recommandation.", de="Einige Modelldateien können geteilt sein. Beziehungen werden vor einer Empfehlung geprüft.", ptBR="Alguns arquivos de modelo podem ser compartilhados. Essas relações são verificadas antes de recomendar limpeza.")
add("detail.hfRedownloadNote",
    en="Need to verify whether these models can be downloaded again before recommending cleanup.", ja="整理を勧める前に、これらのモデルを再ダウンロードできるか確認が必要です。", zhHans="在建议清理前，需要确认这些模型是否可以重新下载。", zhHant="在建議清理前，需要確認這些模型是否可以重新下載。",
    ko="정리를 권하기 전에 이 모델을 다시 다운로드할 수 있는지 확인해야 합니다.", es="Hay que verificar si estos modelos se pueden volver a descargar antes de recomendar limpieza.", fr="Il faut vérifier si ces modèles peuvent être retéléchargés avant de recommander un nettoyage.", de="Vor einer Empfehlung muss geprüft werden, ob diese Modelle erneut heruntergeladen werden können.", ptBR="É preciso verificar se esses modelos podem ser baixados de novo antes de recomendar limpeza.")
add("presentation.readyToOptimize",
    en="Ready to optimize", ja="最適化の準備完了", zhHans="可优化", zhHant="可最佳化",
    ko="최적화 준비됨", es="Listo para optimizar", fr="Prêt à optimiser", de="Bereit zur Optimierung", ptBR="Pronto para otimizar")
add("presentation.verificationNeeded",
    en="Verification needed", ja="確認が必要", zhHans="需要核实", zhHant="需要核實",
    ko="확인 필요", es="Verificación necesaria", fr="Vérification nécessaire", de="Überprüfung nötig", ptBR="Verificação necessária")
add("presentation.recoveryPending",
    en="Recovery pending", ja="回復は保留中", zhHans="回收待确认", zhHant="回收待確認",
    ko="회수 대기", es="Recuperación pendiente", fr="Récupération en attente", de="Freigabe ausstehend", ptBR="Recuperação pendente")
add("presentation.diskRecoveryPending",
    en="Disk recovery pending", ja="ディスク回復は保留中", zhHans="磁盘回收待确认", zhHant="磁碟回收待確認",
    ko="디스크 회수 대기", es="Recuperación de disco pendiente", fr="Récupération disque en attente", de="Speicherfreigabe ausstehend", ptBR="Recuperação de disco pendente")
add("presentation.noRecommendationYet",
    en="No recommendation yet", ja="まだ推奨はありません", zhHans="暂无建议", zhHant="暫無建議",
    ko="아직 권장 없음", es="Aún sin recomendación", fr="Pas encore de recommandation", de="Noch keine Empfehlung", ptBR="Ainda sem recomendação")
add("presentation.informational",
    en="Informational", ja="参考情報", zhHans="参考信息", zhHant="參考資訊",
    ko="참고 정보", es="Informativo", fr="Information", de="Hinweis", ptBR="Informativo")

out = Path("Sources/AppServices/Resources/Localization/LocalizationCatalog.json")
out.parent.mkdir(parents=True, exist_ok=True)
payload = {
    "schemaVersion": 1,
    "productName": "AI Storage Manager",
    "locales": LOCALES,
    "strings": CATALOG,
}
out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"wrote {out} keys={len(CATALOG)} locales={len(LOCALES)}")

# Also emit minimal xcstrings-compatible sidecar for tooling awareness
xc = {
    "sourceLanguage": "en",
    "version": "1.0",
    "strings": {
        k: {
            "extractionState": "manual",
            "localizations": {
                loc: {"stringUnit": {"state": "translated", "value": val}}
                for loc, val in locs.items()
            },
        }
        for k, locs in CATALOG.items()
    },
}
xc_path = Path("Sources/AppServices/Resources/Localization/Localizable.xcstrings")
xc_path.write_text(json.dumps(xc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"wrote {xc_path}")
