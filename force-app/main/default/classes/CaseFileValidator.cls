/**
 * Case-specific FileValidator.
 * Set the component's "Validator Apex Class" property to: CaseFileValidator
 *
 * Rules enforced:
 *   - New upload  : blocked if Case is Closed.
 *   - Edit/Delete : blocked if Case is Closed OR the running user is neither
 *                   the Case Owner nor the Assigned-To user (OwnerId / Contact.OwnerId
 *                   is not a meaningful "assigned" field — we use OwnerId as owner and
 *                   a custom lookup if present; by default we check OwnerId only since
 *                   standard Case has no "Assigned To" user field separate from Owner).
 *   - Download    : always allowed (no restriction).
 *
 * "Assigned To" note:
 *   Standard Case has OwnerId (queue or user). There is no separate "Assigned To User"
 *   field out of the box. If your org has a custom field for this (e.g. Assigned_To__c),
 *   add it to the query and the allowed-users set below.
 */
public with sharing class CaseFileValidator implements FileValidator {

    // ── new upload ─────────────────────────────────────────────────────────────
    public List<String> allownewFileUpload(Id recordId) {
        if (recordId == null) return new List<String>();
        if (recordId.getSObjectType().getDescribe().getName() != 'Case') return new List<String>();

        Case c = [SELECT Status, OwnerId FROM Case WHERE Id = :recordId LIMIT 1];

        if (c.Status == 'Closed') {
            return new List<String>{ 'Uploads are not allowed on a Closed Case.' };
        }
        if (!isAllowedUser(c.OwnerId, null)) {
            return new List<String>{ 'Only the Case owner or assigned user can upload files.' };
        }
        return new List<String>();
    }

    // ── bulk edit / delete / download check ────────────────────────────────────
    public Map<Id, FilePermissionResult> allowEditDeleteFileUpload(
        List<Id> contentVersionIds,
        Id recordId
    ) {
        Map<Id, FilePermissionResult> result = new Map<Id, FilePermissionResult>();
        if (contentVersionIds == null || contentVersionIds.isEmpty()) return result;

        // Default — fully permitted
        for (Id cvId : contentVersionIds) {
            result.put(cvId, new FilePermissionResult());
        }

        // Only applies to Case records
        if (recordId == null ||
            recordId.getSObjectType().getDescribe().getName() != 'Case') {
            return result;
        }

        Case c = [SELECT Status, OwnerId FROM Case WHERE Id = :recordId LIMIT 1];

        Boolean isClosed  = (c.Status == 'Closed');
        Boolean isAllowed = isAllowedUser(c.OwnerId, null);

        // If open and user is allowed — nothing to restrict
        if (!isClosed && isAllowed) return result;

        String editDeleteMsg = isClosed
            ? 'Edit and delete are not allowed on a Closed Case.'
            : 'Only the Case owner or assigned user can edit or delete files.';

        for (Id cvId : contentVersionIds) {
            FilePermissionResult r = result.get(cvId);
            r.canEdit   = false;
            r.canDelete = false;
            // canDownload stays true
            r.errors.add(editDeleteMsg);
        }

        return result;
    }

    // ── helper ─────────────────────────────────────────────────────────────────
    private Boolean isAllowedUser(Id ownerId, Id assignedToId) {
        Id currentUser = UserInfo.getUserId();
        if (currentUser == ownerId)     return true;
        if (currentUser == assignedToId) return true;
        return false;
    }
}