public class BusinessDayCalculator {

    private static Id defaultBHId;

    /**
     * Gets the default Business Hours record Id (cached).
     */
    public static Id getDefaultBusinessHoursId() {
        if (defaultBHId == null) {
            BusinessHours bh = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1];
            defaultBHId = bh.Id;
        }
        return defaultBHId;
    }

    /**
     * Adds N business days to a start date.
     * Skips weekends and holidays configured in BusinessHours.
     * Returns a Date (not DateTime).
     */
    public static Date addBusinessDays(Date startDate, Integer daysToAdd) {
        if (daysToAdd == null || daysToAdd <= 0) return startDate;

        Id bhId = getDefaultBusinessHoursId();
        // Start at 9 AM on the start date
        DateTime startDT = DateTime.newInstance(startDate, Time.newInstance(9, 0, 0, 0));
        DateTime resultDT = startDT;

        Integer daysAdded = 0;
        while (daysAdded < daysToAdd) {
            // Add 24 hours
            resultDT = resultDT.addDays(1);
            // Check if this day is a business day
            if (BusinessHours.isWithin(bhId, resultDT)) {
                daysAdded++;
            }
        }
        return resultDT.date();
    }

    /**
     * Adds N business hours to a start DateTime.
     * Used by Digital division.
     * Returns a DateTime.
     */
    public static DateTime addBusinessHours(DateTime startDT, Integer hoursToAdd) {
        if (hoursToAdd == null || hoursToAdd <= 0) return startDT;

        Id bhId = getDefaultBusinessHoursId();
        Long millisToAdd = (Long) hoursToAdd * 60 * 60 * 1000;
        return BusinessHours.add(bhId, startDT, millisToAdd);
    }

    /**
     * Gets 8 AM on the next business day after the given DateTime.
     * Used by Digital division for R3 ("8AM next business day").
     */
    public static DateTime getNext8AMBusinessDay(DateTime fromDT) {
        Id bhId = getDefaultBusinessHoursId();
        Date nextDay = fromDT.date().addDays(1);

        // Find the next business day
        DateTime checkDT = DateTime.newInstance(nextDay, Time.newInstance(9, 0, 0, 0));
        while (!BusinessHours.isWithin(bhId, checkDT)) {
            checkDT = checkDT.addDays(1);
        }
        // Return 8 AM on that day
        return DateTime.newInstance(checkDT.date(), Time.newInstance(8, 0, 0, 0));
    }

    /**
     * Calculates the auto-close date from WoC entry date for a given stream.
     */
    public static Date calculateAutoCloseDate(Date wocEntryDate, ReminderStreamConfig.StreamDef stream) {
        if (!stream.hasAutoClose) return null;
        Integer totalDays = ReminderStreamConfig.getTotalDaysToClose(stream);
        if (totalDays == null) return null;
        return addBusinessDays(wocEntryDate, totalDays);
    }

    /**
     * Calculates the next reminder DateTime based on current reminder count and stream config.
     */
    public static DateTime calculateNextReminderDateTime(DateTime fromDT, Integer currentReminderCount, ReminderStreamConfig.StreamDef stream) {
        if (currentReminderCount >= stream.reminderIntervals.size()) {
            // All reminders sent — check if agent notify or auto-close is next
            if (stream.hasAgentNotify) {
                return DateTime.newInstance(
                    addBusinessDays(fromDT.date(), stream.agentNotifyAfterLastReminder),
                    Time.newInstance(9, 0, 0, 0)
                );
            }
            if (stream.hasAutoClose) {
                return DateTime.newInstance(
                    addBusinessDays(fromDT.date(), stream.closeAfterLastReminder),
                    Time.newInstance(9, 0, 0, 0)
                );
            }
            return null; // Series complete, nothing more to do
        }

        Integer interval = stream.reminderIntervals[currentReminderCount];

        if (stream.useBusinessHours) {
            if (interval == -1) {
                // Special case: "8AM next business day"
                return getNext8AMBusinessDay(fromDT);
            }
            return addBusinessHours(fromDT, interval);
        } else {
            Date nextDate = addBusinessDays(fromDT.date(), interval);
            return DateTime.newInstance(nextDate, Time.newInstance(9, 0, 0, 0));
        }
    }
}