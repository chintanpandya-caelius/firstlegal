@IsTest
private class EmailMessageTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        insert new List<Case>{
            new Case(
                Subject = 'Closed Parent Case',
                Status = 'Closed',
                Origin = 'Email'
            ),
            new Case(
                Subject = 'Open Parent Case',
                Status = 'New',
                Origin = 'Email'
            )
        };
    }

    @IsTest
    static void testBeforeInsertClosedCase() {
        Case closedCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Closed Parent Case'
            LIMIT 1
        ];

        EmailMessage email = new EmailMessage(
            Incoming = true,
            RelatedToId = closedCase.Id,
            Subject = 'Customer Reply',
            TextBody = 'Customer reply body'
        );

        Test.startTest();
        EmailMessageTriggerHandler.handleBeforeInsert(
            new List<EmailMessage>{ email }
        );
        Test.stopTest();

        System.assertNotEquals(
            closedCase.Id,
            email.RelatedToId
        );
        System.assertEquals(
            email.RelatedToId,
            email.ParentId
        );

        Case childCase = [
            SELECT Id, ParentId, Subject, Origin, Description
            FROM Case
            WHERE ParentId = :closedCase.Id
            LIMIT 1
        ];

        System.assertEquals(closedCase.Id, childCase.ParentId);
        System.assertEquals('Customer Reply', childCase.Subject);
        System.assertEquals('Email', childCase.Origin);
        System.assertEquals('Customer reply body', childCase.Description);
    }

    @IsTest
    static void testBeforeInsertOtherPaths() {
        Case closedCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Closed Parent Case'
            LIMIT 1
        ];

        Case openCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Open Parent Case'
            LIMIT 1
        ];

        EmailMessage notIncoming = new EmailMessage(
            Incoming = false,
            RelatedToId = closedCase.Id,
            Subject = 'Outbound',
            TextBody = 'Outbound email'
        );

        EmailMessage openCaseEmail = new EmailMessage(
            Incoming = true,
            RelatedToId = openCase.Id,
            Subject = 'Open Case Reply',
            TextBody = 'Reply on open case'
        );

        EmailMessage nonCaseEmail = new EmailMessage(
            Incoming = true,
            Subject = 'No Case',
            TextBody = 'No related case'
        );

        Test.startTest();

        EmailMessageTriggerHandler.handleBeforeInsert(
            new List<EmailMessage>()
        );

        EmailMessageTriggerHandler.handleBeforeInsert(
            new List<EmailMessage>{ notIncoming }
        );

        EmailMessageTriggerHandler.handleBeforeInsert(
            new List<EmailMessage>{ openCaseEmail }
        );

        EmailMessageTriggerHandler.handleBeforeInsert(
            new List<EmailMessage>{ nonCaseEmail }
        );

        Test.stopTest();
    }

    @IsTest
    static void testBeforeInsertDmlException() {
        Case closedCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Closed Parent Case'
            LIMIT 1
        ];

        String oversizedBody = '';
        for (Integer i = 0; i < 40000; i++) {
            oversizedBody += 'X';
        }

        EmailMessage email = new EmailMessage(
            Incoming = true,
            RelatedToId = closedCase.Id,
            Subject = 'Exception Test',
            TextBody = oversizedBody
        );

        Test.startTest();
        EmailMessageTriggerHandler.handleBeforeInsert(
            new List<EmailMessage>{ email }
        );
        Test.stopTest();

        System.assertEquals(true, email.hasErrors());
    }

    @IsTest
    static void testAfterInsertEmpty() {
        Test.startTest();

        EmailMessageTriggerHandler.handleAfterInsert(
            new List<EmailMessage>()
        );

        Test.stopTest();
    }
}