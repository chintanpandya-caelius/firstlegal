public with sharing class SLADueDateCalculator {

    public class SLARequest {
        @InvocableVariable(required=true)
        public Id recordId;

        @InvocableVariable(required=true)
        public Id businessHoursId;

        @InvocableVariable(required=true)
        public Datetime recordDateTime;

        @InvocableVariable(required=true)
        public String slaTier;

        @InvocableVariable(required=true)
        public String calculationMode;
    }

    public class SLAResponse {
        @InvocableVariable
        public Datetime slaStartDate;

        @InvocableVariable
        public Datetime slaDueDate;

        @InvocableVariable
        public String status;

        @InvocableVariable
        public String errorMessage;
    }

    @InvocableMethod(
        label='Calculate and Update SLA'
        description='Calculates SLA dates using Salesforce Business Hours and updates the source record.'
    )
    public static List<SLAResponse> calculateAndUpdate(
        List<SLARequest> requests
    ) {

        List<SLAResponse> responses = new List<SLAResponse>();
        List<SObject> recordsToUpdate = new List<SObject>();

        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        Set<Id> businessHoursIds = new Set<Id>();

        for (SLARequest request : requests) {
            if (request.businessHoursId != null) {
                businessHoursIds.add(request.businessHoursId);
            }
        }

        Map<Id, BusinessHours> businessHoursMap =
            new Map<Id, BusinessHours>();

        if (!businessHoursIds.isEmpty()) {

            for (BusinessHours bh : [
                SELECT Id,
                       Name,
                       TimeZoneSidKey,
                       MondayStartTime,
                       MondayEndTime,
                       TuesdayStartTime,
                       TuesdayEndTime,
                       WednesdayStartTime,
                       WednesdayEndTime,
                       ThursdayStartTime,
                       ThursdayEndTime,
                       FridayStartTime,
                       FridayEndTime,
                       SaturdayStartTime,
                       SaturdayEndTime,
                       SundayStartTime,
                       SundayEndTime
                FROM BusinessHours
                WHERE Id IN :businessHoursIds
            ]) {
                businessHoursMap.put(bh.Id, bh);
            }
        }

        for (SLARequest request : requests) {

            SLAResponse response = new SLAResponse();

            try {

                if (request.recordId == null) {
                    throw new SLAException(
                        'Record Id is required.'
                    );
                }

                if (request.businessHoursId == null) {
                    throw new SLAException(
                        'Business Hours Id is required.'
                    );
                }

                if (String.isBlank(request.slaTier)) {
                    throw new SLAException(
                        'SLA Tier is required.'
                    );
                }

                BusinessHours bhRecord =
                    businessHoursMap.get(
                        request.businessHoursId
                    );

                if (bhRecord == null) {
                    throw new SLAException(
                        'Business Hours record was not found.'
                    );
                }

                Schema.SObjectType objectType =
                    request.recordId.getSObjectType();

                String objectApiName =
                    objectType.getDescribe().getName();

                if (
                    objectApiName != 'Lead' &&
                    objectApiName != 'Opportunity' &&
                    objectApiName != 'Account'
                ) {
                    throw new SLAException(
                        'Unsupported SLA object: ' +
                        objectApiName
                    );
                }

                if (
                    objectApiName == 'Account' &&
                    request.slaTier != 'S1' &&
                    request.slaTier != 'S2'
                ) {
                    throw new SLAException(
                        'Account SLA Tier must be S1 or S2.'
                    );
                }

                if (
                    (objectApiName == 'Lead' ||
                     objectApiName == 'Opportunity') &&
                    request.slaTier != 'S1' &&
                    request.slaTier != 'S2' &&
                    request.slaTier != 'S3' &&
                    request.slaTier != 'S4'
                ) {
                    throw new SLAException(
                        'Lead and Opportunity SLA Tier must be S1, S2, S3 or S4.'
                    );
                }

                Datetime calculationDateTime =
                    request.recordDateTime;

                if (calculationDateTime == null) {
                    calculationDateTime = System.now();
                }

                Datetime slaStartDate =
                    getAdjustedStartDate(
                        calculationDateTime,
                        request.businessHoursId,
                        bhRecord
                    );

                Datetime slaDueDate =
                    calculateDueDate(
                        objectApiName,
                        request.slaTier,
                        slaStartDate,
                        request.businessHoursId,
                        bhRecord
                    );

                SObject record =
                    objectType.newSObject();

                record.put(
                    'Id',
                    request.recordId
                );

                record.put(
                    'SLA_Tier__c',
                    request.slaTier
                );

                record.put(
                    'SLA_Start_Date__c',
                    slaStartDate
                );

                record.put(
                    'SLA_Due_Date__c',
                    slaDueDate
                );

                if (
                    request.calculationMode == 'INITIALIZE'
                ) {

                    record.put(
                        'SLA_Completion_Date__c',
                        null
                    );

                    record.put(
                        'SLA_Breached__c',
                        false
                    );

                    record.put(
                        'SLA_Breach_Notified__c',
                        false
                    );
                }

                recordsToUpdate.add(record);

                response.slaStartDate =
                    slaStartDate;

                response.slaDueDate =
                    slaDueDate;

                response.status =
                    'SUCCESS';

            } catch (Exception e) {

                response.status =
                    'ERROR';

                response.errorMessage =
                    e.getMessage();
            }

            responses.add(response);
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }

        return responses;
    }

    private static Datetime getAdjustedStartDate(
        Datetime recordDateTime,
        Id businessHoursId,
        BusinessHours bhRecord
    ) {

        if (
            System.BusinessHours.isWithin(
                businessHoursId,
                recordDateTime
            )
        ) {
            return recordDateTime;
        }

        Date currentDate =
            recordDateTime.date();

        Time currentTime =
            recordDateTime.time();

        for (Integer i = 0; i < 14; i++) {

            Date candidateDate =
                currentDate.addDays(i);

            Time startTime =
                getStartTimeForDate(
                    candidateDate,
                    bhRecord
                );

            if (startTime == null) {
                continue;
            }

            Datetime candidateStart =
                Datetime.newInstance(
                    candidateDate,
                    startTime
                );

            if (i == 0 && currentTime < startTime) {

                if (
                    System.BusinessHours.isWithin(
                        businessHoursId,
                        candidateStart
                    )
                ) {
                    return candidateStart;
                }
            }

            if (i > 0) {

                if (
                    System.BusinessHours.isWithin(
                        businessHoursId,
                        candidateStart
                    )
                ) {
                    return candidateStart;
                }
            }
        }

        throw new SLAException(
            'Unable to determine the next business start time.'
        );
    }

    private static Datetime calculateDueDate(
        String objectApiName,
        String tier,
        Datetime startDate,
        Id businessHoursId,
        BusinessHours bhRecord
    ) {

        if (objectApiName == 'Lead') {

            if (tier == 'S1') {
                return addBusinessHours(
                    businessHoursId,
                    startDate,
                    1
                );
            }

            if (tier == 'S2') {
                return getBusinessDayEnd(
                    startDate,
                    businessHoursId,
                    bhRecord
                );
            }

            if (tier == 'S3') {
                return addBusinessHours(
                    businessHoursId,
                    startDate,
                    24
                );
            }

            if (tier == 'S4') {
                return addBusinessHours(
                    businessHoursId,
                    startDate,
                    48
                );
            }
        }

        if (objectApiName == 'Opportunity') {

            if (tier == 'S1') {
                return addBusinessHours(
                    businessHoursId,
                    startDate,
                    1
                );
            }

            if (tier == 'S2') {
                return getBusinessDayEnd(
                    startDate,
                    businessHoursId,
                    bhRecord
                );
            }

            if (tier == 'S3') {
                return addBusinessHours(
                    businessHoursId,
                    startDate,
                    24
                );
            }

            if (tier == 'S4') {
                return addBusinessHours(
                    businessHoursId,
                    startDate,
                    48
                );
            }
        }

        if (objectApiName == 'Account') {

            if (tier == 'S1') {
                return addBusinessHours(
                    businessHoursId,
                    startDate,
                    1
                );
            }

            if (tier == 'S2') {
                return addBusinessDays(
                    startDate,
                    businessHoursId,
                    bhRecord,
                    3
                );
            }
        }

        throw new SLAException(
            'Invalid SLA Tier ' +
            tier +
            ' for ' +
            objectApiName
        );
    }

    private static Datetime addBusinessHours(
        Id businessHoursId,
        Datetime startDate,
        Integer hours
    ) {

        Long milliseconds =
            hours * 60L * 60L * 1000L;

        return System.BusinessHours.add(
            businessHoursId,
            startDate,
            milliseconds
        );
    }

    private static Datetime addBusinessDays(
        Datetime startDate,
        Id businessHoursId,
        BusinessHours bhRecord,
        Integer numberOfDays
    ) {

        Date currentDate =
            startDate.date();

        Time originalTime =
            startDate.time();

        Integer businessDaysAdded = 0;

        for (Integer i = 1; i <= 370; i++) {

            currentDate =
                currentDate.addDays(1);

            Time startTime =
                getStartTimeForDate(
                    currentDate,
                    bhRecord
                );

            if (startTime == null) {
                continue;
            }

            Datetime candidate =
                Datetime.newInstance(
                    currentDate,
                    originalTime
                );

            if (
                System.BusinessHours.isWithin(
                    businessHoursId,
                    candidate
                )
            ) {

                businessDaysAdded++;

                if (
                    businessDaysAdded ==
                    numberOfDays
                ) {
                    return candidate;
                }
            }
        }

        throw new SLAException(
            'Unable to calculate business days.'
        );
    }

    private static Datetime getBusinessDayEnd(
        Datetime startDate,
        Id businessHoursId,
        BusinessHours bhRecord
    ) {

        Time endTime =
            getEndTimeForDate(
                startDate.date(),
                bhRecord
            );

        if (endTime != null) {

            Datetime businessDayEnd =
                Datetime.newInstance(
                    startDate.date(),
                    endTime
                );

            if (
                businessDayEnd > startDate &&
                System.BusinessHours.isWithin(
                    businessHoursId,
                    startDate
                )
            ) {
                return businessDayEnd;
            }
        }

        for (Integer i = 1; i <= 14; i++) {

            Date nextDate =
                startDate.date().addDays(i);

            Time nextStartTime =
                getStartTimeForDate(
                    nextDate,
                    bhRecord
                );

            Time nextEndTime =
                getEndTimeForDate(
                    nextDate,
                    bhRecord
                );

            if (
                nextStartTime == null ||
                nextEndTime == null
            ) {
                continue;
            }

            Datetime nextStart =
                Datetime.newInstance(
                    nextDate,
                    nextStartTime
                );

            Datetime nextEnd =
                Datetime.newInstance(
                    nextDate,
                    nextEndTime
                );

            if (
                System.BusinessHours.isWithin(
                    businessHoursId,
                    nextStart
                )
            ) {
                return nextEnd;
            }
        }

        throw new SLAException(
            'Unable to determine business day end.'
        );
    }

    private static Time getStartTimeForDate(
        Date dateValue,
        BusinessHours bhRecord
    ) {

        Integer dayOfWeek =
            Integer.valueOf(
                Datetime.newInstance(
                    dateValue,
                    Time.newInstance(
                        0,
                        0,
                        0,
                        0
                    )
                ).format('u')
            );

        switch on dayOfWeek {

            when 1 {
                return bhRecord.MondayStartTime;
            }

            when 2 {
                return bhRecord.TuesdayStartTime;
            }

            when 3 {
                return bhRecord.WednesdayStartTime;
            }

            when 4 {
                return bhRecord.ThursdayStartTime;
            }

            when 5 {
                return bhRecord.FridayStartTime;
            }

            when 6 {
                return bhRecord.SaturdayStartTime;
            }

            when 7 {
                return bhRecord.SundayStartTime;
            }

            when else {
                return null;
            }
        }
    }

    private static Time getEndTimeForDate(
        Date dateValue,
        BusinessHours bhRecord
    ) {

        Integer dayOfWeek =
            Integer.valueOf(
                Datetime.newInstance(
                    dateValue,
                    Time.newInstance(
                        0,
                        0,
                        0,
                        0
                    )
                ).format('u')
            );

        switch on dayOfWeek {

            when 1 {
                return bhRecord.MondayEndTime;
            }

            when 2 {
                return bhRecord.TuesdayEndTime;
            }

            when 3 {
                return bhRecord.WednesdayEndTime;
            }

            when 4 {
                return bhRecord.ThursdayEndTime;
            }

            when 5 {
                return bhRecord.FridayEndTime;
            }

            when 6 {
                return bhRecord.SaturdayEndTime;
            }

            when 7 {
                return bhRecord.SundayEndTime;
            }

            when else {
                return null;
            }
        }
    }

    public class SLAException extends Exception {}
}