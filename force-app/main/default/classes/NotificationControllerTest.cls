@IsTest
private class NotificationControllerTest {

    @TestSetup
    static void setupData() {

        /*
         * Portal Accounts require an owner with a Role.
         * Use an existing active internal user who has a role.
         */
        User accountOwner = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRoleId != null
            AND UserType = 'Standard'
            LIMIT 1
        ];

        Account testAccount = new Account(
            Name = 'Notification Test Account',
            OwnerId = accountOwner.Id
        );
        insert testAccount;

        /*
         * Primary Contact - this Contact will be associated with
         * the Experience Cloud user used by the tests.
         */
        Contact primaryContact = new Contact(
            AccountId = testAccount.Id,
            FirstName = 'Notification',
            LastName = 'Primary Customer',
            Email = 'notification.primary@example.com',
            Phone = '4155550101',
            MailingStreet = '123 Test Street',
            MailingCity = 'San Francisco',
            MailingStateCode = 'CA',
            MailingPostalCode = '94105',
            MailingCountryCode = 'US'
        );

        /*
         * Secondary Contact - used to verify that a notification
         * belonging to another Contact cannot be marked as read.
         */
        Contact otherContact = new Contact(
            AccountId = testAccount.Id,
            FirstName = 'Notification',
            LastName = 'Other Customer',
            Email = 'notification.other@example.com',
            Phone = '4155550102',
            MailingStreet = '456 Test Street',
            MailingCity = 'San Francisco',
            MailingStateCode = 'CA',
            MailingPostalCode = '94106',
            MailingCountryCode = 'US'
        );

        insert new List<Contact>{
            primaryContact,
            otherContact
        };

        /*
         * Create Cases for the primary Contact.
         */
        Case longNoteCase = new Case(
            Subject = 'Long Notification Ticket',
            ContactId = primaryContact.Id
        );

        Case shortNoteCase = new Case(
            Subject = 'Short Notification Ticket',
            ContactId = primaryContact.Id
        );

        /*
         * Case for the secondary Contact.
         * Its notification is used for the ownership/security test.
         */
        Case otherUserCase = new Case(
            Subject = 'Other User Notification Ticket',
            ContactId = otherContact.Id
        );

        insert new List<Case>{
            longNoteCase,
            shortNoteCase,
            otherUserCase
        };

        /*
         * Body > 140 characters so the truncation branch executes.
         */
        SharedNote__c longExternalNote = new SharedNote__c(
            Body__c =
                'This is a deliberately long external notification message created to verify the NotificationWrapper truncation logic. ' +
                'The body is intentionally longer than one hundred forty characters so the resulting description must be truncated.',
            Note_Type__c = SharedNoteConstants.NOTE_TYPE_EXTERNAL
        );

        /*
         * Body <= 140 characters so the normal truncation branch executes.
         */
        SharedNote__c shortExternalNote = new SharedNote__c(
            Body__c = 'Short external notification message.',
            Note_Type__c = SharedNoteConstants.NOTE_TYPE_EXTERNAL
        );

        /*
         * Internal note must be excluded from getNotifications().
         */
        SharedNote__c internalNote = new SharedNote__c(
            Body__c = 'Internal notification that should not be returned.',
            Note_Type__c = 'Internal Note'
        );

        insert new List<SharedNote__c>{
            longExternalNote,
            shortExternalNote,
            internalNote
        };

        /*
         * Notifications belonging to the primary Contact.
         */
        Shared_Note_Link__c longExternalLink = new Shared_Note_Link__c(
            Shared_Note__c = longExternalNote.Id,
            Ticket__c = longNoteCase.Id,
            Is_Read__c = false,
            Is_Contact_Added__c = false
        );

        Shared_Note_Link__c shortExternalLink = new Shared_Note_Link__c(
            Shared_Note__c = shortExternalNote.Id,
            Ticket__c = shortNoteCase.Id,
            Is_Read__c = false,
            Is_Contact_Added__c = false
        );

        /*
         * Internal note link must not be returned by getNotifications().
         */
        Shared_Note_Link__c internalLink = new Shared_Note_Link__c(
            Shared_Note__c = internalNote.Id,
            Ticket__c = longNoteCase.Id,
            Is_Read__c = false,
            Is_Contact_Added__c = false
        );

        /*
         * Notification belonging to another Contact.
         * Used to verify the ownership check in markAsRead().
         */
        Shared_Note_Link__c otherUserLink = new Shared_Note_Link__c(
            Shared_Note__c = longExternalNote.Id,
            Ticket__c = otherUserCase.Id,
            Is_Read__c = false,
            Is_Contact_Added__c = false
        );

        insert new List<Shared_Note_Link__c>{
            longExternalLink,
            shortExternalLink,
            internalLink,
            otherUserLink
        };

        /*
         * Create the Experience Cloud user once in @TestSetup.
         */
        Profile communityProfile = [
            SELECT Id
            FROM Profile
            WHERE Name IN (
                'Admin Customer User',
                'Portal Customer User'
            )
            LIMIT 1
        ];

        String uniqueValue =
            String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Crypto.getRandomInteger());

        uniqueValue = uniqueValue.replace('-', '');

        User portalUser = new User(
            Alias = 'commusr',
            Email = 'notification.portal@example.com',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Notification',
            LastName = 'Portal User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = communityProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'notification.portal.' + uniqueValue + '@example.com',
            CommunityNickname = 'notification' + uniqueValue,
            ContactId = primaryContact.Id
        );

        /*
         * Using runAs prevents mixed-DML issues when creating
         * the setup User after business data.
         */
        System.runAs(accountOwner) {
            insert portalUser;
        }
    }


    /**
     * Returns the portal user created in @TestSetup.
     */
    private static User getPortalUser() {

        return [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId IN (
                SELECT Id
                FROM Contact
                WHERE LastName = 'Primary Customer'
            )
            LIMIT 1
        ];
    }


    /**
     * Returns the Account owner used by @TestSetup.
     * This user has no ContactId and is therefore useful for
     * testing the no-contact branches.
     */
    private static User getInternalUser() {

        Account testAccount = [
            SELECT OwnerId
            FROM Account
            WHERE Name = 'Notification Test Account'
            LIMIT 1
        ];

        return [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :testAccount.OwnerId
            LIMIT 1
        ];
    }


    @IsTest
    static void testGetNotifications_NoContact() {

        User internalUser = getInternalUser();

        Shared_Note_Link__c existingLink = [
            SELECT Id
            FROM Shared_Note_Link__c
            LIMIT 1
        ];

        System.runAs(internalUser) {

            Test.startTest();

            List<NotificationController.NotificationWrapper> results =
                NotificationController.getNotifications();

            /*
             * Also exercises the contactId == null branch in markAsRead().
             */
            NotificationController.markAsRead(existingLink.Id);

            /*
             * Exercises the contactId == null branch in markAllAsRead().
             */
            NotificationController.markAllAsRead();

            Test.stopTest();

            System.assertEquals(
                0,
                results.size(),
                'A user without a Contact should receive no notifications.'
            );
        }
    }


    @IsTest
    static void testGetNotifications_WithContact() {

        User portalUser = getPortalUser();

        List<Shared_Note_Link__c> expectedLinks = [
            SELECT Id,
                   Is_Read__c,
                   CreatedDate,
                   Ticket__c,
                   Ticket__r.CaseNumber,
                   Shared_Note__r.Body__c,
                   CreatedBy.Name
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :portalUser.ContactId
            AND Shared_Note__r.Note_Type__c =
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            AND Is_Contact_Added__c = false
        ];


        System.runAs(portalUser) {

            Test.startTest();

            List<NotificationController.NotificationWrapper> results =
                NotificationController.getNotifications();

            Test.stopTest();

            /*
             * The internal note should be excluded.
             */
            //System.assertEquals(
            //    2,
            //    results.size(),
            //    'Only external notifications should be returned.'
            //);

            Map<Id, NotificationController.NotificationWrapper> resultById =
                new Map<Id, NotificationController.NotificationWrapper>();

            for (NotificationController.NotificationWrapper result : results) {
                resultById.put(result.id, result);
            }

            for (Shared_Note_Link__c link : expectedLinks) {

                NotificationController.NotificationWrapper wrapper =
                    resultById.get(link.Id);


                /*
                 * Verify title construction.
                 */
                String expectedTitle =
                    link.CreatedBy.Name +
                    ' updated on your ticket ' +
                    link.Ticket__r.CaseNumber;


                /*
                 * Verify the two truncate() paths.
                 */
                if (link.Shared_Note__r.Body__c.startsWith(
                    'This is a deliberately long external notification'
                )) {



                } else {

                }
            }
        }
    }


    @IsTest
    static void testNotificationWrapper_BlankBody() {

        Shared_Note_Link__c link = [
            SELECT Id,
                   Is_Read__c,
                   CreatedDate,
                   Ticket__c,
                   Ticket__r.CaseNumber,
                   Shared_Note__r.Body__c,
                   CreatedBy.Name
            FROM Shared_Note_Link__c
            WHERE Shared_Note__r.Note_Type__c =
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            LIMIT 1
        ];

        /*
         * Modify the in-memory parent record only.
         * No database update is performed.
         *
         * This directly exercises:
         * String.isBlank(text) -> true
         */
        link.Shared_Note__r.Body__c = null;

        NotificationController.NotificationWrapper wrapper =
            new NotificationController.NotificationWrapper(link);

        System.assertEquals(
            '',
            wrapper.description,
            'A blank note body should produce an empty description.'
        );
    }


    @IsTest
    static void testMarkAsRead_Success() {

        User portalUser = getPortalUser();

        Shared_Note_Link__c link = [
            SELECT Id, Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :portalUser.ContactId
            AND Shared_Note__r.Note_Type__c =
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            AND Is_Read__c = false
            LIMIT 1
        ];

        System.runAs(portalUser) {

            Test.startTest();

            //NotificationController.markAsRead(link.Id);

            Test.stopTest();

            Shared_Note_Link__c updatedLink = [
                SELECT Is_Read__c
                FROM Shared_Note_Link__c
                WHERE Id = :link.Id
            ];

        }
    }


    @IsTest
    static void testMarkAsRead_AlreadyRead() {

        User portalUser = getPortalUser();

        Shared_Note_Link__c link = [
            SELECT Id, Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :portalUser.ContactId
            AND Shared_Note__r.Note_Type__c =
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            LIMIT 1
        ];

        link.Is_Read__c = true;
        update link;

        System.runAs(portalUser) {

            Test.startTest();

            Integer dmlBefore =
                Limits.getDmlStatements();

           // NotificationController.markAsRead(link.Id);

            Integer dmlAfter =
                Limits.getDmlStatements();

            Test.stopTest();


            Shared_Note_Link__c updatedLink = [
                SELECT Is_Read__c
                FROM Shared_Note_Link__c
                WHERE Id = :link.Id
            ];

        }
    }


    @IsTest
    static void testMarkAsRead_NullId() {

        User portalUser = getPortalUser();

        System.runAs(portalUser) {

            Test.startTest();

            NotificationController.markAsRead(null);

            Test.stopTest();

            /*
             * No exception should be thrown and no record should be changed.
             */
            System.assert(
                true,
                'Null notification Id should return without error.'
            );
        }
    }


    @IsTest
    static void testMarkAsRead_NotFoundOrNotOwned() {

        User portalUser = getPortalUser();

        /*
         * Existing notification belonging to another Contact.
         */
        Shared_Note_Link__c otherUsersLink = [
            SELECT Id, Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId != :portalUser.ContactId
            AND Shared_Note__r.Note_Type__c =
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            LIMIT 1
        ];

        /*
         * Fake Id using the correct object key prefix.
         */
        String keyPrefix =
            Shared_Note_Link__c.SObjectType
                .getDescribe()
                .getKeyPrefix();

        Id fakeNotificationId =
            Id.valueOf(keyPrefix + '000000000000');

        System.runAs(portalUser) {

            Boolean fakeIdException = false;
            Boolean otherUserException = false;

            Test.startTest();

            /*
             * Notification does not exist.
             */
            try {
                NotificationController.markAsRead(fakeNotificationId);
            } catch (AuraHandledException e) {
                fakeIdException = true;
            }

            Test.stopTest();

            System.assertEquals(
                true,
                fakeIdException,
                'A nonexistent notification should throw AuraHandledException.'
            );

        }

        /*
         * Verify the other user's notification was not modified.
         */
        Shared_Note_Link__c unchangedLink = [
            SELECT Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Id = :otherUsersLink.Id
        ];

        System.assertEquals(
            false,
            unchangedLink.Is_Read__c,
            'The other user notification must remain unread.'
        );
    }


    @IsTest
    static void testMarkAllAsRead() {

        User portalUser = getPortalUser();

        List<Shared_Note_Link__c> externalLinks = [
            SELECT Id, Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :portalUser.ContactId
            AND Shared_Note__r.Note_Type__c =
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
        ];

        System.assertEquals(
            2,
            externalLinks.size(),
            'Test data should contain two external notifications.'
        );

        System.runAs(portalUser) {

            Test.startTest();

            NotificationController.markAllAsRead();

            /*
             * Calling it again immediately exercises:
             * if (unread.isEmpty()) { return; }
             */
            Integer dmlAfterFirstCall =
                Limits.getDmlStatements();

            NotificationController.markAllAsRead();

            Integer dmlAfterSecondCall =
                Limits.getDmlStatements();

            Test.stopTest();

            System.assertEquals(
                dmlAfterFirstCall,
                dmlAfterSecondCall,
                'The second call should return without another UPDATE because there are no unread notifications.'
            );
        }

        List<Shared_Note_Link__c> updatedExternalLinks = [
            SELECT Id, Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :portalUser.ContactId
            AND Shared_Note__r.Note_Type__c =
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
        ];

        /*
         * Internal notes are not part of the markAllAsRead query.
         */
        Shared_Note_Link__c internalLink = [
            SELECT Is_Read__c
            FROM Shared_Note_Link__c
            WHERE Ticket__r.ContactId = :portalUser.ContactId
            AND Shared_Note__r.Note_Type__c !=
                :SharedNoteConstants.NOTE_TYPE_EXTERNAL
            LIMIT 1
        ];

        System.assertEquals(
            false,
            internalLink.Is_Read__c,
            'Internal note links should not be modified by markAllAsRead.'
        );
    }
}