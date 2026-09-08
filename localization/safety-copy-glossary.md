# Safety Copy Glossary (P5.3)

Presentation intent for translators. **Not** Safety authority.

| Concept | Canonical domain | Meaning to preserve | Avoid translating as |
|---------|------------------|---------------------|----------------------|
| KEEP | ActionDecision / presentation | Recommended to leave this storage as-is | permanently immutable / never removable |
| PROTECTED | presentation | App will not recommend destructive action because this data matters | antivirus / encryption / password lock |
| NEEDS VERIFICATION | VERIFY_MORE | Not enough reliable evidence yet | dangerous / corrupted / suspicious |
| READY | readiness | Safe path exists for review/approval | free to delete automatically |
| NEEDS APPROVAL | MutationReadiness | Human must approve exact target | already authorized |
| MOVE TO TRASH | MOVE_TO_TRASH | macOS Trash — still occupies disk until emptied | permanent delete / immediate free space |
| VERIFIED RECOVERED | verifiedRecoveredBytes | Post-verify confirmed recovery | expected / potential savings |
| RECOVERY PENDING | trash pending | Moved to Trash; space not yet freed | already freed |
| UNKNOWN | SafetyClass / measurement | Insufficient evidence | empty / zero / safe |
| LOCAL COPY | residency | Local bytes present | same as cloud delete |
| REMOTE COPY | remote proof | Remote exact artifact evidence | “backed up so delete locally” |
| DOWNLOAD AGAIN | reacquisition | Proven re-download path only | always regenerable |
| SOURCE OF TRUTH | SOT | Canonical origin of data | any large folder |
| APP-MANAGED DATA | vendor store | Managed by vendor contract | junk / cache by name |
| USER ORIGINAL | user content | User-owned originals (e.g. recordings) | disposable media |

## Cloud / delete distinctions (never collapse)

- synced ≠ remote verified ≠ cloud backed
- remove local copy ≠ delete everywhere

## Product name

Keep **AI Storage Manager** untranslated.
