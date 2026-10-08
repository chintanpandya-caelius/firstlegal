@IsTest
private class CustomTicketListViewControllerTest {

    private static final String PORTAL_USERNAME_PREFIX =
        'custom.ticket.test.user.';

    private static final String ACCOUNT_OWNER_USERNAME_PREFIX =
        'custom.ticket.owner.';

    private static final String CUSTOM_PERMISSION_NAME =
        'Access_all_tickets_related_to_Account';


    // =============================================================
    // Test Setup
    // =============================================================
    @TestSetup
    static void setupData() {

        // ---------------------------------------------------------
        // Running user
        // ---------------------------------------------------------
        User runningUser = [
            SELECT Id, ProfileId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];


        // ---------------------------------------------------------
        // Existing User Role
        //
        // Account owner must have a Role for Experience Cloud
        // customer users.
        // ---------------------------------------------------------
        UserRole testRole = [
            SELECT Id
            FROM UserRole
            LIMIT 1
        ];


        // ---------------------------------------------------------
        // Internal Account Owner
        // ---------------------------------------------------------
        User accountOwner = new User(
            FirstName = 'Portal',
            LastName = 'AccountOwner',
            Alias = 'ptowner',
            Email = 'portal.owner@example.com',
            Username =
                ACCOUNT_OWNER_USERNAME_PREFIX +
                String.valueOf(DateTime.now().getTime()) +
                '@example.com',
            ProfileId = runningUser.ProfileId,
            UserRoleId = testRole.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        System.runAs(
            new User(Id = runningUser.Id)
        ) {
            insert accountOwner;
        }


        // ---------------------------------------------------------
        // Account
        // ---------------------------------------------------------
        Account acc = new Account(
            Name = 'Custom Ticket Test Account',
            OwnerId = accountOwner.Id
        );

        insert acc;


        // ---------------------------------------------------------
        // Contact
        // ---------------------------------------------------------
        Contact con = new Contact(
            FirstName = 'Ticket',
            LastName = 'Tester',
            Email = 'ticket.tester@example.com',
            Phone = '1234567890',
            AccountId = acc.Id,
            MailingStreet = '123 Test Street',
            MailingCity = 'San Francisco',
            MailingStateCode = 'CA',
            MailingPostalCode = '94105',
            MailingCountryCode = 'US'
        );

        insert con;


        // ---------------------------------------------------------
        // Experience Cloud profile
        // ---------------------------------------------------------
        Profile externalProfile = [
            SELECT Id, UserType
            FROM Profile
            WHERE Name IN (
                'Admin Customer User',
                'Portal Customer User'
            )
            LIMIT 1
        ];


        // ---------------------------------------------------------
        // Portal user
        //
        // Also create a temporary Permission Set and assign the
        // custom permission used by the controller.
        // ---------------------------------------------------------
        User portalUser = new User(
            FirstName = 'Ticket',
            LastName = 'Tester',
            Alias = 'tktusr',
            Email = 'ticket.tester@example.com',
            Username =
                PORTAL_USERNAME_PREFIX +
                String.valueOf(DateTime.now().getTime()) +
                '@example.com',
            ProfileId = externalProfile.Id,
            ContactId = con.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );


        CustomPermission accountTicketPermission = [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = :CUSTOM_PERMISSION_NAME
            LIMIT 1
        ];


        PermissionSet testPermissionSet = new PermissionSet(
            Name = 'CustomTicketListViewTestAccess',
            Label = 'Custom Ticket List View Test Access'
        );


        System.runAs(
            new User(Id = runningUser.Id)
        ) {

            insert portalUser;

            insert testPermissionSet;


            // -----------------------------------------------------
            // Link Custom Permission -> Permission Set
            // -----------------------------------------------------
            insert new SetupEntityAccess(
                ParentId = testPermissionSet.Id,
                SetupEntityId = accountTicketPermission.Id
            );


            // -----------------------------------------------------
            // Assign Permission Set -> Portal User
            // -----------------------------------------------------
            insert new PermissionSetAssignment(
                AssigneeId = portalUser.Id,
                PermissionSetId = testPermissionSet.Id
            );
        }


        // ---------------------------------------------------------
        // Case Statuses
        // ---------------------------------------------------------
        String openStatus;
        String closedStatus;
        String customStatus;

        for (CaseStatus cs : [
            SELECT MasterLabel, IsClosed
            FROM CaseStatus
            ORDER BY SortOrder
        ]) {

            if (openStatus == null && !cs.IsClosed) {
                openStatus = cs.MasterLabel;
            }

            if (closedStatus == null && cs.IsClosed) {
                closedStatus = cs.MasterLabel;
            }

            if (
                customStatus == null &&
                cs.MasterLabel != 'OPEN' &&
                cs.MasterLabel != 'CLOSED'
            ) {
                customStatus = cs.MasterLabel;
            }
        }


        System.assertNotEquals(
            null,
            openStatus,
            'The org must have at least one open Case status.'
        );

        System.assertNotEquals(
            null,
            closedStatus,
            'The org must have at least one closed Case status.'
        );

        System.assertNotEquals(
            null,
            customStatus,
            'The org must have a Case status that is not literally OPEN or CLOSED.'
        );


        // ---------------------------------------------------------
        // Picklist Values
        // ---------------------------------------------------------
        String originValue =
            getFirstActivePicklistValue(Case.Origin);

        String priorityValue =
            getFirstActivePicklistValue(Case.Priority);

        String typeValue =
            getFirstActivePicklistValue(Case.Type);

        String subTypeValue =
            getFirstActivePicklistValue(
                Case.Ticket_SubType__c
            );


        // ---------------------------------------------------------
        // Contact-linked Cases
        // ---------------------------------------------------------
        List<Case> tickets = new List<Case>();

        tickets.add(
            buildCase(
                con.Id,
                openStatus,
                originValue,
                priorityValue,
                typeValue,
                subTypeValue,
                'Open Ticket Alpha'
            )
        );

        tickets.add(
            buildCase(
                con.Id,
                openStatus,
                originValue,
                priorityValue,
                typeValue,
                subTypeValue,
                'Open Ticket Beta'
            )
        );

        tickets.add(
            buildCase(
                con.Id,
                closedStatus,
                originValue,
                priorityValue,
                typeValue,
                subTypeValue,
                'Closed Ticket Gamma'
            )
        );

        tickets.add(
            buildCase(
                con.Id,
                closedStatus,
                originValue,
                priorityValue,
                typeValue,
                subTypeValue,
                'Closed Searchable Ticket'
            )
        );

        tickets.add(
            buildCase(
                con.Id,
                customStatus,
                originValue,
                priorityValue,
                typeValue,
                subTypeValue,
                'Custom Status Ticket'
            )
        );

        tickets.add(
            buildCase(
                con.Id,
                openStatus,
                originValue,
                priorityValue,
                typeValue,
                subTypeValue,
                'Open Ticket Delta'
            )
        );

        insert tickets;


        // ---------------------------------------------------------
        // Case without Contact
        //
        // Used to exercise:
        //
        //     c.Contact != null ? c.Contact.Name : ''
        //
        // and the branch where the running user has no Contact.
        //
        // If this org has a validation rule requiring Contact on
        // Case, simply no record is inserted and the other tests
        // remain valid.
        // ---------------------------------------------------------
        Case noContactCase = new Case(
            Subject = 'Internal No Contact Ticket',
            Status = openStatus,
            Description = 'Test ticket without a Contact',
            AccountId = acc.Id
        );

        if (originValue != null) {
            noContactCase.Origin = originValue;
        }

        if (priorityValue != null) {
            noContactCase.Priority = priorityValue;
        }

        if (typeValue != null) {
            noContactCase.Type = typeValue;
        }

        if (subTypeValue != null) {
            noContactCase.Ticket_SubType__c = subTypeValue;
        }

        try {
            insert noContactCase;
        } catch (DmlException e) {
            // Some orgs may have a validation rule requiring
            // ContactId on Case. The remaining coverage tests
            // do not depend on this record.
        }
    }


    // =============================================================
    // getListViewOptions
    // =============================================================
    @IsTest
    static void testGetListViewOptions() {

        Test.startTest();

        List<Map<String, String>> result =
            CustomTicketListViewController.getListViewOptions();

        Test.stopTest();


        System.assertNotEquals(
            null,
            result
        );

        System.assertEquals(
            3,
            result.size()
        );

        System.assertEquals(
            'My Open Tickets',
            result[0].get('label')
        );

        System.assertEquals(
            'OPEN',
            result[0].get('value')
        );

        System.assertEquals(
            'My Closed Tickets',
            result[1].get('label')
        );

        System.assertEquals(
            'CLOSED',
            result[1].get('value')
        );

        System.assertEquals(
            'All My Tickets',
            result[2].get('label')
        );

        System.assertEquals(
            'ALL',
            result[2].get('value')
        );
    }


    // =============================================================
    // getTickets
    //
    // Covers:
    // - custom permission path
    // - ALL
    // - OPEN
    // - CLOSED
    // - custom Status
    // - search
    // - blank selectedView
    // - blank searchTerm
    // - null pagination
    // - zero pagination
    // - negative pagination
    // - pagination
    // - wrapper mapping
    // =============================================================
    @IsTest
    static void testGetTickets() {

        User portalUser = getPortalUser();

        Account testAccount = [
            SELECT Id
            FROM Account
            WHERE Name = 'Custom Ticket Test Account'
            LIMIT 1
        ];

        String customStatus = getCustomStatus();


        Integer totalTickets = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :testAccount.Id
            AND ContactId != null
        ];

        Integer openCount = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :testAccount.Id
            AND ContactId != null
            AND IsClosed = false
        ];

        Integer closedCount = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :testAccount.Id
            AND ContactId != null
            AND IsClosed = true
        ];

        Integer customStatusCount = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :testAccount.Id
            AND ContactId != null
            AND Status = :customStatus
        ];


        System.runAs(portalUser) {

            Test.startTest();

            // -----------------------------------------------------
            // ALL + null pagination
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult allResult =
                CustomTicketListViewController.getTickets(
                    'ALL',
                    null,
                    null,
                    null
                );


            // -----------------------------------------------------
            // OPEN
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult openResult =
                CustomTicketListViewController.getTickets(
                    'OPEN',
                    null,
                    10,
                    1
                );


            // -----------------------------------------------------
            // CLOSED
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult closedResult =
                CustomTicketListViewController.getTickets(
                    'CLOSED',
                    null,
                    10,
                    1
                );


            // -----------------------------------------------------
            // CUSTOM STATUS
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult customResult =
                CustomTicketListViewController.getTickets(
                    customStatus,
                    null,
                    10,
                    1
                );


            // -----------------------------------------------------
            // SEARCH BY SUBJECT
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult searchResult =
                CustomTicketListViewController.getTickets(
                    'ALL',
                    'Searchable',
                    10,
                    1
                );


            // -----------------------------------------------------
            // Blank selectedView + blank searchTerm
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult blankResult =
                CustomTicketListViewController.getTickets(
                    '',
                    '',
                    10,
                    1
                );


            // -----------------------------------------------------
            // Null selectedView + null searchTerm
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult nullFilterResult =
                CustomTicketListViewController.getTickets(
                    null,
                    null,
                    10,
                    1
                );


            // -----------------------------------------------------
            // Zero page size + zero page number
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult zeroPagingResult =
                CustomTicketListViewController.getTickets(
                    'ALL',
                    null,
                    0,
                    0
                );


            // -----------------------------------------------------
            // Negative page size + negative page number
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult negativePagingResult =
                CustomTicketListViewController.getTickets(
                    'ALL',
                    null,
                    -1,
                    -1
                );


            // -----------------------------------------------------
            // Pagination
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult pageResult =
                CustomTicketListViewController.getTickets(
                    'ALL',
                    null,
                    2,
                    2
                );

            Test.stopTest();
        }
    }


    // =============================================================
    // getAllTickets
    //
    // Covers:
    // - custom permission path
    // - ALL
    // - OPEN
    // - CLOSED
    // - custom Status
    // - search
    // - search by CaseNumber
    // - blank selectedView
    // - blank searchTerm
    // - null filters
    // - wrapper mapping
    // =============================================================
    @IsTest
    static void testGetAllTickets() {

        User portalUser = getPortalUser();

        Account testAccount = [
            SELECT Id
            FROM Account
            WHERE Name = 'Custom Ticket Test Account'
            LIMIT 1
        ];

        String customStatus = getCustomStatus();


        Integer totalTickets = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :testAccount.Id
            AND ContactId != null
        ];

        Integer openCount = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :testAccount.Id
            AND ContactId != null
            AND IsClosed = false
        ];

        Integer closedCount = [
            SELECT COUNT()
            FROM Case
            WHERE AccountId = :testAccount.Id
            AND ContactId != null
            AND IsClosed = true
        ];


        Case searchableCase = [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Subject = 'Closed Searchable Ticket'
            LIMIT 1
        ];


        System.runAs(portalUser) {

            Test.startTest();

            // -----------------------------------------------------
            // ALL
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult allResult =
                CustomTicketListViewController.getAllTickets(
                    'ALL',
                    null
                );


            // -----------------------------------------------------
            // OPEN
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult openResult =
                CustomTicketListViewController.getAllTickets(
                    'OPEN',
                    null
                );


            // -----------------------------------------------------
            // CLOSED
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult closedResult =
                CustomTicketListViewController.getAllTickets(
                    'CLOSED',
                    null
                );


            // -----------------------------------------------------
            // CUSTOM STATUS
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult customResult =
                CustomTicketListViewController.getAllTickets(
                    customStatus,
                    null
                );


            // -----------------------------------------------------
            // SUBJECT SEARCH
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult searchResult =
                CustomTicketListViewController.getAllTickets(
                    'ALL',
                    'Searchable'
                );


            // -----------------------------------------------------
            // CASE NUMBER SEARCH
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult caseNumberSearchResult =
                CustomTicketListViewController.getAllTickets(
                    'ALL',
                    searchableCase.CaseNumber
                );


            // -----------------------------------------------------
            // Blank filters
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult blankResult =
                CustomTicketListViewController.getAllTickets(
                    '',
                    ''
                );


            // -----------------------------------------------------
            // Null filters
            // -----------------------------------------------------
            CustomTicketListViewController.TicketResult nullResult =
                CustomTicketListViewController.getAllTickets(
                    null,
                    null
                );

            Test.stopTest();
        }
    }


    // =============================================================
    // Explicitly exercise the NO-CONTACT / ELSE branch
    // =============================================================
    @IsTest
    static void testControllerWithInternalUser() {

        User accountOwner = [
            SELECT Id
            FROM User
            WHERE Username LIKE :ACCOUNT_OWNER_USERNAME_PREFIX + '%'
            LIMIT 1
        ];


        System.runAs(accountOwner) {

            Test.startTest();

            CustomTicketListViewController.TicketResult ticketResult =
                CustomTicketListViewController.getTickets(
                    null,
                    null,
                    null,
                    null
                );

            CustomTicketListViewController.TicketResult allTicketResult =
                CustomTicketListViewController.getAllTickets(
                    null,
                    null
                );

            Test.stopTest();


            System.assertNotEquals(
                null,
                ticketResult
            );

            System.assertNotEquals(
                null,
                ticketResult.tickets
            );

            System.assertNotEquals(
                null,
                allTicketResult
            );

            System.assertNotEquals(
                null,
                allTicketResult.tickets
            );


            // If the org allowed creation of the no-contact Case,
            // verify that the controller found it and mapped the
            // empty contactName branch.
            Integer noContactCount = [
                SELECT COUNT()
                FROM Case
                WHERE Subject = 'Internal No Contact Ticket'
                AND ContactId = null
            ];


            if (noContactCount > 0) {

                System.assertEquals(
                    '',
                    ticketResult.tickets[0].contactName
                );
            }
        }
    }


    // =============================================================
    // Explicit pagination/filter boundary test
    // =============================================================
    @IsTest
    static void testGetTicketsBoundaryValues() {

        User portalUser = getPortalUser();

        System.runAs(portalUser) {

            Test.startTest();

            CustomTicketListViewController.TicketResult result1 =
                CustomTicketListViewController.getTickets(
                    ' ',
                    ' ',
                    -10,
                    -10
                );

            CustomTicketListViewController.TicketResult result2 =
                CustomTicketListViewController.getTickets(
                    null,
                    null,
                    0,
                    0
                );

            Test.stopTest();


            System.assertNotEquals(
                null,
                result1
            );

            System.assertNotEquals(
                null,
                result1.tickets
            );

            System.assertNotEquals(
                null,
                result2
            );

            System.assertNotEquals(
                null,
                result2.tickets
            );
        }
    }


    // =============================================================
    // Helpers
    // =============================================================

    private static User getPortalUser() {

        return [
            SELECT Id, ContactId
            FROM User
            WHERE Username LIKE :PORTAL_USERNAME_PREFIX + '%'
            LIMIT 1
        ];
    }


    private static String getCustomStatus() {

        for (CaseStatus cs : [
            SELECT MasterLabel, IsClosed
            FROM CaseStatus
            ORDER BY SortOrder
        ]) {

            if (
                cs.MasterLabel != 'OPEN' &&
                cs.MasterLabel != 'CLOSED'
            ) {
                return cs.MasterLabel;
            }
        }

        return null;
    }


    private static Case getCaseById(Id caseId) {

        return [
            SELECT Id, IsClosed
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
    }


    private static Case buildCase(
        Id contactId,
        String statusValue,
        String originValue,
        String priorityValue,
        String typeValue,
        String subTypeValue,
        String subject
    ) {

        Case c = new Case(
            ContactId = contactId,
            Subject = subject,
            Status = statusValue,
            Description = 'Test ticket description',
            Matter_Number__c = 'MAT-001',
            Court_Case_Number__c = 'COURT-001',
            Due_Date__c = Date.today().addDays(5)
        );


        if (originValue != null) {
            c.Origin = originValue;
        }


        if (priorityValue != null) {
            c.Priority = priorityValue;
        }


        if (typeValue != null) {
            c.Type = typeValue;
        }


        if (subTypeValue != null) {
            c.Ticket_SubType__c = subTypeValue;
        }


        return c;
    }


    private static String getFirstActivePicklistValue(
        Schema.SObjectField field
    ) {

        for (
            Schema.PicklistEntry entry :
            field.getDescribe().getPicklistValues()
        ) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }
}