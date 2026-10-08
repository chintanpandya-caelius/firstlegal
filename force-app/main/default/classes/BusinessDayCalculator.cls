public class BusinessDayCalculator {

    private static Map<String, Id> bhIdMap;

    /**
     * Returns the ID of a Business Hours record by name.
     * Falls back to the Org Default if the name isn't found.
     */
    public static Id getBusinessHoursId(String bhName) {

        if (bhIdMap == null) {

            bhIdMap = new Map<String, Id>();

            for (BusinessHours bh : [
                SELECT Id, Name, IsDefault
                FROM BusinessHours
            ]) {

                bhIdMap.put(bh.Name, bh.Id);

                if (bh.IsDefault) {
                    bhIdMap.put('Default', bh.Id);
                }
            }
        }

        if (String.isNotBlank(bhName) && bhIdMap.containsKey(bhName)) {
            return bhIdMap.get(bhName);
        }

        return bhIdMap.get('Default');
    }


    // ═══════════════════════════════════════════════════════════════════════════
    // OVERLOADED METHODS (Backward Compatibility)
    // These prevent "Method does not exist" errors in existing classes.
    // ═══════════════════════════════════════════════════════════════════════════

    public static Date addBusinessDays(Date startDate, Integer daysToAdd) {
        return addBusinessDays(startDate, daysToAdd, null);
    }

    public static DateTime addBusinessHours(DateTime startDT, Integer hoursToAdd) {
        return addBusinessHours(startDT, hoursToAdd, null);
    }

    public static DateTime getNext8AMBusinessDay(DateTime fromDT) {
        return getNext8AMBusinessDay(fromDT, null);
    }


    // ═══════════════════════════════════════════════════════════════════════════
    // PRIMARY METHODS (Stream-Aware)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Adds N business days to a start date using specific Business Hours.
     */
    public static Date addBusinessDays(
        Date startDate,
        Integer daysToAdd,
        String bhName
    ) {

        if (daysToAdd == null || daysToAdd <= 0) {
            return startDate;
        }

        Id bhId = getBusinessHoursId(bhName);

        // Use nextStartDate to find the beginning of the business day
        // (e.g., 7:30 AM for Digital)
        DateTime startDT = DateTime.newInstance(
            startDate,
            Time.newInstance(0, 0, 0, 0)
        );

        DateTime currentDT = BusinessHours.nextStartDate(
            bhId,
            startDT
        );

        Integer daysAdded = 0;

        while (daysAdded < daysToAdd) {

            currentDT = currentDT.addDays(1);

            /*
             * CHANGE:
             * Replaced BusinessHours.isWithin() with a day-of-week check.
             *
             * Monday    = 1
             * Tuesday   = 2
             * Wednesday = 3
             * Thursday  = 4
             * Friday    = 5
             * Saturday  = 6
             * Sunday    = 7
             *
             * Only Monday-Friday are counted as business days.
             */

            Integer dayOfWeek = Integer.valueOf(
                currentDT.format('u')
            );

            if (dayOfWeek >= 1 && dayOfWeek <= 5) {
                daysAdded++;
            }
        }

        return currentDT.date();
    }


    /**
     * Adds N business hours to a start DateTime.
     */
    public static DateTime addBusinessHours(
        DateTime startDT,
        Integer hoursToAdd,
        String bhName
    ) {

        if (hoursToAdd == null || hoursToAdd <= 0) {
            return startDT;
        }

        Id bhId = getBusinessHoursId(bhName);

        Long millisToAdd = (Long) hoursToAdd * 60 * 60 * 1000;

        return BusinessHours.add(
            bhId,
            startDT,
            millisToAdd
        );
    }


    /**
     * Gets 8 AM on the next business day.
     */
    public static DateTime getNext8AMBusinessDay(
        DateTime fromDT,
        String bhName
    ) {

        Id bhId = getBusinessHoursId(bhName);

        DateTime nextDay = fromDT.addDays(1);

        DateTime nextStart = BusinessHours.nextStartDate(
            bhId,
            nextDay
        );

        return DateTime.newInstance(
            nextStart.date(),
            Time.newInstance(8, 0, 0, 0)
        );
    }


    /**
     * Calculates the auto-close date based on the stream's specific Business Hours.
     */
    public static Date calculateAutoCloseDate(
        Date wocEntryDate,
        ReminderStreamConfig.StreamDef stream
    ) {

        if (!stream.hasAutoClose) {
            return null;
        }

        Integer totalDays =
            ReminderStreamConfig.getTotalDaysToClose(stream);

        if (totalDays == null) {
            return null;
        }

        return addBusinessDays(
            wocEntryDate,
            totalDays,
            stream.businessHoursName
        );
    }


    /**
     * Main calculation engine.
     */
    public static DateTime calculateNextReminderDateTime(
        DateTime fromDT,
        Integer currentReminderCount,
        ReminderStreamConfig.StreamDef stream
    ) {

        if (currentReminderCount >= stream.reminderIntervals.size()) {

            if (stream.hasAgentNotify) {

                return DateTime.newInstance(
                    addBusinessDays(
                        fromDT.date(),
                        stream.agentNotifyAfterLastReminder,
                        stream.businessHoursName
                    ),
                    Time.newInstance(9, 0, 0, 0)
                );
            }

            if (stream.hasAutoClose) {

                return DateTime.newInstance(
                    addBusinessDays(
                        fromDT.date(),
                        stream.closeAfterLastReminder,
                        stream.businessHoursName
                    ),
                    Time.newInstance(9, 0, 0, 0)
                );
            }

            return null;
        }

        Integer interval =
            stream.reminderIntervals[currentReminderCount];

        String bhName =
            stream.businessHoursName;

        if (stream.useBusinessHours) {

            if (interval == -1) {
                return getNext8AMBusinessDay(
                    fromDT,
                    bhName
                );
            }

            return addBusinessHours(
                fromDT,
                interval,
                bhName
            );

        } else {

            Date nextDate = addBusinessDays(
                fromDT.date(),
                interval,
                bhName
            );

            return DateTime.newInstance(
                nextDate,
                Time.newInstance(9, 0, 0, 0)
            );
        }
    }
}