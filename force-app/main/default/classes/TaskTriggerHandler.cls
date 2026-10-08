public class TaskTriggerHandler {

    // Closed statuses for both Task and Case
    private static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Closed', 'Resolved' };

    public static void handle(
        List<Task> newTasks,
        Map<Id, Task> oldMap,
        Boolean isDelete
    ) {

        System.debug(LoggingLevel.DEBUG,
            'TaskTriggerHandler.handle START | isDelete=' + isDelete);

        try {

            // On delete, newTasks is null — use old records
            List<Task> workingList = isDelete ? oldMap.values() : newTasks;

            System.debug(LoggingLevel.DEBUG,
                'handle | workingList size=' +
                (workingList != null ? workingList.size() : 0));

            // Collect Case IDs from WhatId
            Set<Id> caseIds = new Set<Id>();

            for (Task t : workingList) {

                System.debug(LoggingLevel.DEBUG,
                    'handle | Processing Task Id=' + t.Id +
                    ' | WhatId=' + t.WhatId +
                    ' | Status=' + t.Status);

                if (t.WhatId != null &&
                    t.WhatId.getSObjectType() == Case.SObjectType) {

                    caseIds.add(t.WhatId);

                    System.debug(LoggingLevel.DEBUG,
                        'handle | Added Case Id=' + t.WhatId);
                }
            }

            System.debug(LoggingLevel.DEBUG,
                'handle | Collected Case IDs=' + caseIds);

            if (caseIds.isEmpty()) {

                System.debug(LoggingLevel.DEBUG,
                    'handle | No Case IDs found. Returning.');

                return;
            }

            // Bulk query Cases
            System.debug(LoggingLevel.DEBUG,
                'handle | Querying Cases for IDs=' + caseIds);

            Map<Id, Case> caseMap = new Map<Id, Case>(
                [
                    SELECT Id, Status, Open_Task_Count__c
                    FROM Case
                    WHERE Id IN :caseIds
                ]
            );

            System.debug(LoggingLevel.DEBUG,
                'handle | Cases queried=' + caseMap.size());

            if (!isDelete) {

                System.debug(LoggingLevel.DEBUG,
                    'handle | Calling blockTasksOnClosedCases');

                blockTasksOnClosedCases(newTasks, oldMap, caseMap);
            }

            System.debug(LoggingLevel.DEBUG,
                'handle | Calling recalculateOpenTaskCount');

            recalculateOpenTaskCount(
                caseIds,
                newTasks,
                oldMap,
                isDelete,
                caseMap
            );

            System.debug(LoggingLevel.DEBUG,
                'TaskTriggerHandler.handle END');

        } catch (Exception e) {

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.handle ERROR | ' + e.getMessage());

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.handle STACK TRACE | ' +
                e.getStackTraceString());

            throw e;
        }
    }


    // ─────────────────────────────────────────────────────────────
    // RULE 1 — Block creating or reopening a Task on a Closed Case
    // ─────────────────────────────────────────────────────────────

    private static void blockTasksOnClosedCases(
        List<Task> newTasks,
        Map<Id, Task> oldMap,
        Map<Id, Case> caseMap
    ) {

        System.debug(LoggingLevel.DEBUG,
            'TaskTriggerHandler.blockTasksOnClosedCases START');

        try {

            for (Task t : newTasks) {

                System.debug(LoggingLevel.DEBUG,
                    'blockTasksOnClosedCases | Task Id=' + t.Id +
                    ' | WhatId=' + t.WhatId +
                    ' | Status=' + t.Status);

                if (t.WhatId == null) {

                    System.debug(LoggingLevel.DEBUG,
                        'blockTasksOnClosedCases | Task has no WhatId. Skipping.');

                    continue;
                }

                Case c = caseMap.get(t.WhatId);

                if (c == null) {

                    System.debug(LoggingLevel.WARN,
                        'blockTasksOnClosedCases | Case not found for WhatId=' +
                        t.WhatId);

                    continue;
                }

                System.debug(LoggingLevel.DEBUG,
                    'blockTasksOnClosedCases | Case Id=' + c.Id +
                    ' | Case Status=' + c.Status);

                if (!CLOSED_STATUSES.contains(c.Status)) {

                    System.debug(LoggingLevel.DEBUG,
                        'blockTasksOnClosedCases | Case is not closed/resolved. Skipping.');

                    continue;
                }

                Boolean isInsert =
                    (oldMap == null || !oldMap.containsKey(t.Id));

                Boolean isReopening =
                    !isInsert
                    && CLOSED_STATUSES.contains(oldMap.get(t.Id).Status)
                    && !CLOSED_STATUSES.contains(t.Status);

                System.debug(LoggingLevel.DEBUG,
                    'blockTasksOnClosedCases | isInsert=' + isInsert +
                    ' | isReopening=' + isReopening);

                if (isInsert || isReopening) {

                    System.debug(LoggingLevel.WARN,
                        'blockTasksOnClosedCases | BLOCKING Task Id=' +
                        t.Id +
                        ' because Case Id=' +
                        c.Id +
                        ' is ' +
                        c.Status);

                    t.addError(
                        'You cannot open a task on a closed or resolved case (Case: ' +
                        c.Id +
                        ').'
                    );
                }
            }

            System.debug(LoggingLevel.DEBUG,
                'TaskTriggerHandler.blockTasksOnClosedCases END');

        } catch (Exception e) {

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.blockTasksOnClosedCases ERROR | ' +
                e.getMessage());

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.blockTasksOnClosedCases STACK TRACE | ' +
                e.getStackTraceString());

            throw e;
        }
    }


    // ─────────────────────────────────────────────────────────────
    // RULE 2 — Recalculate Open_Task_Count__c on affected Cases
    // ─────────────────────────────────────────────────────────────

    private static void recalculateOpenTaskCount(
        Set<Id> caseIds,
        List<Task> newTasks,
        Map<Id, Task> oldMap,
        Boolean isDelete,
        Map<Id, Case> caseMap
    ) {

        System.debug(LoggingLevel.DEBUG,
            'TaskTriggerHandler.recalculateOpenTaskCount START');

        try {

            System.debug(LoggingLevel.DEBUG,
                'recalculateOpenTaskCount | caseIds=' + caseIds +
                ' | isDelete=' + isDelete);

            // IDs of tasks currently being processed
            Set<Id> inFlightIds = new Set<Id>();

            if (!isDelete && newTasks != null) {

                for (Task t : newTasks) {

                    if (t.Id != null) {
                        inFlightIds.add(t.Id);
                    }
                }

            } else if (isDelete && oldMap != null) {

                inFlightIds.addAll(oldMap.keySet());
            }

            System.debug(LoggingLevel.DEBUG,
                'recalculateOpenTaskCount | inFlightIds=' +
                inFlightIds);

            // Query existing Tasks
            System.debug(LoggingLevel.DEBUG,
                'recalculateOpenTaskCount | Querying existing Tasks');

            List<Task> existingTasks = [
                SELECT Id, WhatId, Status
                FROM Task
                WHERE What.Id IN :caseIds
                AND Id NOT IN :inFlightIds
            ];

            System.debug(LoggingLevel.DEBUG,
                'recalculateOpenTaskCount | Existing Tasks found=' +
                existingTasks.size());

            // Seed open-task counter per Case
            Map<Id, Integer> openCountByCaseId =
                new Map<Id, Integer>();

            for (Id cId : caseIds) {

                openCountByCaseId.put(cId, 0);

                System.debug(LoggingLevel.DEBUG,
                    'recalculateOpenTaskCount | Initialized Case ' +
                    cId +
                    ' count=0');
            }

            // Count open tasks already in database
            for (Task t : existingTasks) {

                System.debug(LoggingLevel.DEBUG,
                    'recalculateOpenTaskCount | Existing Task Id=' +
                    t.Id +
                    ' | WhatId=' +
                    t.WhatId +
                    ' | Status=' +
                    t.Status);

                if (t.WhatId != null && isOpen(t.Status)) {

                    Integer currentCount =
                        openCountByCaseId.get(t.WhatId);

                    openCountByCaseId.put(
                        t.WhatId,
                        currentCount + 1
                    );

                    System.debug(LoggingLevel.DEBUG,
                        'recalculateOpenTaskCount | Incremented Case ' +
                        t.WhatId +
                        ' count to ' +
                        (currentCount + 1));
                }
            }

            System.debug(LoggingLevel.DEBUG,
                'recalculateOpenTaskCount | Count after DB Tasks=' +
                openCountByCaseId);

            // Overlay in-flight changes
            if (!isDelete && newTasks != null) {

                for (Task t : newTasks) {

                    if (t.WhatId == null ||
                        !openCountByCaseId.containsKey(t.WhatId)) {

                        System.debug(LoggingLevel.DEBUG,
                            'recalculateOpenTaskCount | Skipping in-flight Task Id=' +
                            t.Id);

                        continue;
                    }

                    Boolean wasOpen =
                        (oldMap != null && oldMap.containsKey(t.Id))
                        ? isOpen(oldMap.get(t.Id).Status)
                        : false;

                    Boolean isNowOpen = isOpen(t.Status);

                    Integer count =
                        openCountByCaseId.get(t.WhatId);

                    System.debug(LoggingLevel.DEBUG,
                        'recalculateOpenTaskCount | Task Id=' + t.Id +
                        ' | wasOpen=' + wasOpen +
                        ' | isNowOpen=' + isNowOpen +
                        ' | currentCount=' + count);

                    if (!wasOpen && isNowOpen) {

                        openCountByCaseId.put(
                            t.WhatId,
                            count + 1
                        );

                        System.debug(LoggingLevel.DEBUG,
                            'recalculateOpenTaskCount | OPEN Task added. Case ' +
                            t.WhatId +
                            ' count=' +
                            (count + 1));

                    } else if (wasOpen && !isNowOpen) {

                        openCountByCaseId.put(
                            t.WhatId,
                            Math.max(0, count - 1)
                        );

                        System.debug(LoggingLevel.DEBUG,
                            'recalculateOpenTaskCount | Task closed. Case ' +
                            t.WhatId +
                            ' count=' +
                            Math.max(0, count - 1));
                    }

                }

            } else if (isDelete && oldMap != null) {

                System.debug(LoggingLevel.DEBUG,
                    'recalculateOpenTaskCount | Processing deleted Tasks');

                // Deleting a task — remove its contribution if it was open
                for (Task t : oldMap.values()) {

                    if (t.WhatId == null ||
                        !openCountByCaseId.containsKey(t.WhatId)) {

                        continue;
                    }

                    if (isOpen(t.Status)) {

                        Integer count =
                            openCountByCaseId.get(t.WhatId);

                        openCountByCaseId.put(
                            t.WhatId,
                            Math.max(0, count - 1)
                        );

                        System.debug(LoggingLevel.DEBUG,
                            'recalculateOpenTaskCount | Deleted open Task Id=' +
                            t.Id +
                            ' | Case=' +
                            t.WhatId +
                            ' | New Count=' +
                            Math.max(0, count - 1));
                    }
                }
            }

            System.debug(LoggingLevel.DEBUG,
                'recalculateOpenTaskCount | Final counts=' +
                openCountByCaseId);

            // Update Cases where count changed
            List<Case> casesToUpdate = new List<Case>();

            for (Id cId : openCountByCaseId.keySet()) {

                Case c = caseMap.get(cId);

                if (c == null) {

                    System.debug(LoggingLevel.WARN,
                        'recalculateOpenTaskCount | Case not found in caseMap: ' +
                        cId);

                    continue;
                }

                Integer newCount =
                    openCountByCaseId.get(cId);

                Integer existingCount =
                    c.Open_Task_Count__c != null
                    ? Integer.valueOf(c.Open_Task_Count__c)
                    : 0;

                System.debug(LoggingLevel.DEBUG,
                    'recalculateOpenTaskCount | Case=' + cId +
                    ' | Existing Count=' + existingCount +
                    ' | New Count=' + newCount);

                // Only DML if value actually changed
                if (existingCount != newCount) {

                    casesToUpdate.add(
                        new Case(
                            Id = cId,
                            Open_Task_Count__c = newCount
                        )
                    );

                    System.debug(LoggingLevel.DEBUG,
                        'recalculateOpenTaskCount | Case queued for update=' +
                        cId);
                }
            }

            System.debug(LoggingLevel.DEBUG,
                'recalculateOpenTaskCount | Cases to update=' +
                casesToUpdate.size());

            if (!casesToUpdate.isEmpty()) {

                System.debug(LoggingLevel.DEBUG,
                    'recalculateOpenTaskCount | Updating Cases=' +
                    casesToUpdate);

                update casesToUpdate;

                System.debug(LoggingLevel.DEBUG,
                    'recalculateOpenTaskCount | Case update SUCCESS');
            }

            System.debug(LoggingLevel.DEBUG,
                'TaskTriggerHandler.recalculateOpenTaskCount END');

        } catch (Exception e) {

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.recalculateOpenTaskCount ERROR | ' +
                e.getMessage());

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.recalculateOpenTaskCount STACK TRACE | ' +
                e.getStackTraceString());

            throw e;
        }
    }


    private static Boolean isOpen(String status) {

        System.debug(LoggingLevel.DEBUG,
            'TaskTriggerHandler.isOpen | Status=' + status);

        try {

            Boolean result =
                status != null &&
                !CLOSED_STATUSES.contains(status);

            System.debug(LoggingLevel.DEBUG,
                'TaskTriggerHandler.isOpen | Result=' + result);

            return result;

        } catch (Exception e) {

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.isOpen ERROR | ' +
                e.getMessage());

            System.debug(LoggingLevel.ERROR,
                'TaskTriggerHandler.isOpen STACK TRACE | ' +
                e.getStackTraceString());

            throw e;
        }
    }
}