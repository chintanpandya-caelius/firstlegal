public inherited sharing class AccountHierarchyUtil {

    private static final Integer DEFAULT_MAX_DEPTH = 10;

    public static Id getRootParentId(Id startAccountId, Map<Id, Account> hierarchyMap) {
        Id currentId = startAccountId;
        Set<Id> visited = new Set<Id>();

        while (currentId != null && hierarchyMap.containsKey(currentId)) {
            if (visited.contains(currentId)) break; 
            visited.add(currentId);

            Account current = hierarchyMap.get(currentId);
            if (current.ParentId == null) {
                return current.Id;
            }
            currentId = current.ParentId;
        }
        return currentId; 
    }

    public static Map<Id, Account> buildHierarchyMap(Set<Id> startAccountIds, Set<String> extraFields) {
        Map<Id, Account> hierarchyMap = new Map<Id, Account>();
        if (startAccountIds == null || startAccountIds.isEmpty()) return hierarchyMap;

        Set<String> fields = new Set<String>{'Id', 'ParentId'};
        if (extraFields != null) fields.addAll(extraFields);

        String query = 'SELECT ' + String.join(new List<String>(fields), ', ') +
                        ' FROM Account WHERE Id IN :idsToQuery';

        Set<Id> idsToQuery = new Set<Id>(startAccountIds);
        Integer level = 0;

        while (!idsToQuery.isEmpty() && level < DEFAULT_MAX_DEPTH) {
            Map<Id, Account> levelResults = new Map<Id, Account>(
                (List<Account>) Database.query(query, AccessLevel.SYSTEM_MODE)
            );
            hierarchyMap.putAll(levelResults);

            Set<Id> nextLevel = new Set<Id>();
            for (Account acc : levelResults.values()) {
                if (acc.ParentId != null && !hierarchyMap.containsKey(acc.ParentId)) {
                    nextLevel.add(acc.ParentId);
                }
            }
            idsToQuery = nextLevel;
            level++;
        }
        return hierarchyMap;
    }

    public static Account getRootAccount(Id startAccountId, Set<String> extraFields) {
        if (startAccountId == null) return null;
        Map<Id, Account> hierarchyMap = buildHierarchyMap(new Set<Id>{ startAccountId }, extraFields);
        Id rootId = getRootParentId(startAccountId, hierarchyMap);
        return hierarchyMap.get(rootId);
    }
}