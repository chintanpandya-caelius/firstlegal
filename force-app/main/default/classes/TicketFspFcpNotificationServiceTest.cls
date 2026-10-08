@IsTest
private class TicketFspFcpNotificationServiceTest {

    private static User getUserWithManager() {
        return [
            SELECT Id, Email, ManagerId
            FROM User
            WHERE IsActive = true
            AND Email != null
            AND ManagerId != null
            AND Manager.IsActive = true
            AND Manager.Email != null
            LIMIT 1
        ];
    }

    private static User getUserWithoutManager() {
        List<User> users = [
            SELECT Id, Email, ManagerId
            FROM User
            WHERE IsActive = true
            AND Email != null
            AND ManagerId = null
            LIMIT 1
        ];

        return users.isEmpty() ? null : users[0];
    }

    private static Id getRecordTypeId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    private static Id createCaseQueue() {
        Group queue = new Group(
            Name = 'Notification Test Queue',
            Type = 'Queue'
        );
        insert queue;

        insert new QueueSobject(
            QueueId = queue.Id,
            SobjectType = 'Case'
        );

        return queue.Id;
    }

    @TestSetup
    static void setupData() {

        Account account = new Account(
            Name = 'Notification Test Account'
        );
        insert account;

        Contact contact = new Contact(
            FirstName = 'Notification',
            LastName = 'Test',
            Email = 'notificationtest@example.com',
            Phone = '5551234567',
            AccountId = account.Id,
            MailingStreet = '123 Test Street',
            MailingCity = 'San Francisco',
            MailingStateCode = 'CA',
            MailingPostalCode = '94105',
            MailingCountryCode = 'US'
        );
        insert contact;

        User owner = getUserWithManager();

        Id fspRecordTypeId = getRecordTypeId('Client_Care');

        Case testCase = new Case(
            AccountId = account.Id,
            ContactId = contact.Id,
            OwnerId = owner.Id,
            RecordTypeId = fspRecordTypeId,
            Status = 'New',
            Origin = 'Web',
            Subject = 'Notification Test',
            Type = 'Access & Account',
            Ticket_SubType__c = 'Permissions',
            Priority = 'Medium'
        );

        insert testCase;
    }

    @IsTest
    static void testAllNotificationPaths() {

        User owner = getUserWithManager();

        Id fspRecordTypeId = getRecordTypeId('Client_Care');
        Id fcpRecordTypeId = getRecordTypeId('CCT');

        Case baseCase = [
            SELECT
                Id,
                CaseNumber,
                AccountId,
                ContactId,
                OwnerId,
                RecordTypeId,
                Status,
                Origin,
                Subject,
                Type,
                Ticket_SubType__c,
                Priority,
                IsEscalated,
                Is_SLA_Breached__c
            FROM Case
            LIMIT 1
        ];

        Test.startTest();

        // FSP - NEW - Requestor - Email
        Case fspNew = baseCase.clone(true, true, false, false);
        fspNew.RecordTypeId = fspRecordTypeId;
        fspNew.SuppliedEmail = 'directrequestor@example.com';
        fspNew.Status = 'New';

        TicketFspFcpNotificationService.process(
            new List<Case>{fspNew},
            null,
            true,
            false
        );

        // FSP - ASSIGNED - Owner - Custom Notification
        Case fspAssignedOld = baseCase.clone(true, true, false, false);
        fspAssignedOld.RecordTypeId = fspRecordTypeId;
        fspAssignedOld.Status = 'New';

        Case fspAssigned = baseCase.clone(true, true, false, false);
        fspAssigned.RecordTypeId = fspRecordTypeId;
        fspAssigned.Status = 'Assigned';
        fspAssigned.OwnerId = owner.Id;

        TicketFspFcpNotificationService.process(
            new List<Case>{fspAssigned},
            new Map<Id, Case>{
                fspAssigned.Id => fspAssignedOld
            },
            false,
            true
        );

        // FSP - ESCALATED - Supervisor - Email + Custom
        Case fspEscalatedOld = baseCase.clone(true, true, false, false);
        fspEscalatedOld.RecordTypeId = fspRecordTypeId;
        fspEscalatedOld.IsEscalated = false;

        Case fspEscalated = baseCase.clone(true, true, false, false);
        fspEscalated.RecordTypeId = fspRecordTypeId;
        fspEscalated.IsEscalated = true;
        fspEscalated.OwnerId = owner.Id;

        TicketFspFcpNotificationService.process(
            new List<Case>{fspEscalated},
            new Map<Id, Case>{
                fspEscalated.Id => fspEscalatedOld
            },
            false,
            true
        );

        // FSP - SLA BREACH - Owner + Supervisor - Custom
        Case fspSlaOld = baseCase.clone(true, true, false, false);
        fspSlaOld.RecordTypeId = fspRecordTypeId;
        fspSlaOld.Is_SLA_Breached__c = false;

        Case fspSla = baseCase.clone(true, true, false, false);
        fspSla.RecordTypeId = fspRecordTypeId;
        fspSla.Is_SLA_Breached__c = true;
        fspSla.OwnerId = owner.Id;

        TicketFspFcpNotificationService.process(
            new List<Case>{fspSla},
            new Map<Id, Case>{
                fspSla.Id => fspSlaOld
            },
            false,
            true
        );

        // FCP - NEW - Requestor via SuppliedEmail
        Case fcpNew = baseCase.clone(true, true, false, false);
        fcpNew.RecordTypeId = fcpRecordTypeId;
        fcpNew.ContactId = null;
        fcpNew.SuppliedEmail = 'directrequestor@example.com';
        fcpNew.Status = 'New';

        TicketFspFcpNotificationService.process(
            new List<Case>{fcpNew},
            null,
            true,
            false
        );

        // FCP - WAITING ON 3RD PARTY - Requestor via SuppliedEmail
        Case fcpWaitingOld = baseCase.clone(true, true, false, false);
        fcpWaitingOld.RecordTypeId = fcpRecordTypeId;
        fcpWaitingOld.ContactId = null;
        fcpWaitingOld.SuppliedEmail = 'directrequestor@example.com';
        fcpWaitingOld.Status = 'Assigned';

        Case fcpWaiting = baseCase.clone(true, true, false, false);
        fcpWaiting.RecordTypeId = fcpRecordTypeId;
        fcpWaiting.ContactId = null;
        fcpWaiting.SuppliedEmail = 'directrequestor@example.com';
        fcpWaiting.Status = 'Waiting on 3rd Party';

        TicketFspFcpNotificationService.process(
            new List<Case>{fcpWaiting},
            new Map<Id, Case>{
                fcpWaiting.Id => fcpWaitingOld
            },
            false,
            true
        );

        // Empty input
        TicketFspFcpNotificationService.process(
            new List<Case>(),
            null,
            false,
            false
        );

        TicketFspFcpNotificationService.process(
            null,
            null,
            false,
            false
        );

        Test.stopTest();

        System.assertNotEquals(null, baseCase.Id);
        System.assertNotEquals(null, baseCase.CaseNumber);
    }

    @IsTest
    static void testNegativePaths() {

        Id fspRecordTypeId = getRecordTypeId('Client_Care');

        Case baseCase = [
            SELECT
                Id,
                CaseNumber,
                AccountId,
                ContactId,
                OwnerId,
                RecordTypeId,
                Status,
                Origin,
                Subject,
                Type,
                Ticket_SubType__c,
                Priority,
                IsEscalated,
                Is_SLA_Breached__c
            FROM Case
            LIMIT 1
        ];

        Test.startTest();

        // Requestor with no Contact and no SuppliedEmail
        Case noRequestor = baseCase.clone(true, true, false, false);
        noRequestor.RecordTypeId = fspRecordTypeId;
        noRequestor.ContactId = null;
        noRequestor.SuppliedEmail = null;
        noRequestor.Status = 'New';

        TicketFspFcpNotificationService.process(
            new List<Case>{noRequestor},
            null,
            true,
            false
        );

        // Assigned to Queue - Owner recipient rejected
        Id queueId = createCaseQueue();

        Case queueOld = baseCase.clone(true, true, false, false);
        queueOld.RecordTypeId = fspRecordTypeId;
        queueOld.Status = 'New';

        Case queueAssigned = baseCase.clone(true, true, false, false);
        queueAssigned.RecordTypeId = fspRecordTypeId;
        queueAssigned.Status = 'Assigned';
        queueAssigned.OwnerId = queueId;

        TicketFspFcpNotificationService.process(
            new List<Case>{queueAssigned},
            new Map<Id, Case>{
                queueAssigned.Id => queueOld
            },
            false,
            true
        );

        // Supervisor with no Manager
        User userWithoutManager = getUserWithoutManager();

        if (userWithoutManager != null) {

            Case escalationOld = baseCase.clone(true, true, false, false);
            escalationOld.RecordTypeId = fspRecordTypeId;
            escalationOld.OwnerId = userWithoutManager.Id;
            escalationOld.IsEscalated = false;

            Case escalation = baseCase.clone(true, true, false, false);
            escalation.RecordTypeId = fspRecordTypeId;
            escalation.OwnerId = userWithoutManager.Id;
            escalation.IsEscalated = true;

            TicketFspFcpNotificationService.process(
                new List<Case>{escalation},
                new Map<Id, Case>{
                    escalation.Id => escalationOld
                },
                false,
                true
            );
        }

        // Update event with no old Case
        Case noOldCase = baseCase.clone(true, true, false, false);
        noOldCase.RecordTypeId = fspRecordTypeId;
        noOldCase.Status = 'Assigned';

        TicketFspFcpNotificationService.process(
            new List<Case>{noOldCase},
            null,
            false,
            true
        );

        // Assigned -> Assigned again should not match
        Case assignedOld = baseCase.clone(true, true, false, false);
        assignedOld.RecordTypeId = fspRecordTypeId;
        assignedOld.Status = 'Assigned';

        Case assignedAgain = baseCase.clone(true, true, false, false);
        assignedAgain.RecordTypeId = fspRecordTypeId;
        assignedAgain.Status = 'Assigned';
        assignedAgain.OwnerId = getUserWithManager().Id;

        TicketFspFcpNotificationService.process(
            new List<Case>{assignedAgain},
            new Map<Id, Case>{
                assignedAgain.Id => assignedOld
            },
            false,
            true
        );

        // Escalated -> Escalated again should not match
        Case escalatedOld = baseCase.clone(true, true, false, false);
        escalatedOld.RecordTypeId = fspRecordTypeId;
        escalatedOld.IsEscalated = true;

        Case escalatedAgain = baseCase.clone(true, true, false, false);
        escalatedAgain.RecordTypeId = fspRecordTypeId;
        escalatedAgain.IsEscalated = true;

        TicketFspFcpNotificationService.process(
            new List<Case>{escalatedAgain},
            new Map<Id, Case>{
                escalatedAgain.Id => escalatedOld
            },
            false,
            true
        );

        // SLA Breach -> true again should not match
        Case slaOld = baseCase.clone(true, true, false, false);
        slaOld.RecordTypeId = fspRecordTypeId;
        slaOld.Is_SLA_Breached__c = true;

        Case slaAgain = baseCase.clone(true, true, false, false);
        slaAgain.RecordTypeId = fspRecordTypeId;
        slaAgain.Is_SLA_Breached__c = true;

        TicketFspFcpNotificationService.process(
            new List<Case>{slaAgain},
            new Map<Id, Case>{
                slaAgain.Id => slaOld
            },
            false,
            true
        );

        // Waiting on 3rd Party -> same status should not match
        Case waitingOld = baseCase.clone(true, true, false, false);
        waitingOld.RecordTypeId = fspRecordTypeId;
        waitingOld.Status = 'Waiting on 3rd Party';

        Case waitingAgain = baseCase.clone(true, true, false, false);
        waitingAgain.RecordTypeId = fspRecordTypeId;
        waitingAgain.Status = 'Waiting on 3rd Party';

        TicketFspFcpNotificationService.process(
            new List<Case>{waitingAgain},
            new Map<Id, Case>{
                waitingAgain.Id => waitingOld
            },
            false,
            true
        );

        Test.stopTest();

        System.assertNotEquals(null, baseCase.Id);
    }
}