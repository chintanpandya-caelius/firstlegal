import { LightningElement, wire } from 'lwc';
import USER_TIMEZONE from '@salesforce/i18n/timeZone';
import { CurrentPageReference } from 'lightning/navigation';
import getTimezoneData from '@salesforce/apex/TimezoneUtilityController.getTimezoneData';

export default class TimezoneUtilityBar extends LightningElement {
    // Do NOT declare @api recordId — utility bar reads it from CurrentPageReference only
    _recordId = null;

    currentTime  = new Date();
    timezoneRows = [];

    customerTimezone = null;   // null  → row is hidden
    accountTimezone  = null;   // null  → row is hidden

    intervalId;

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        // Show the static rows immediately before any wire result arrives
        this.buildRows();

        this.intervalId = setInterval(() => {
            this.currentTime = new Date();
            this.buildRows();
        }, 1000);
    }

    disconnectedCallback() {
        clearInterval(this.intervalId);
    }

    // ─── Navigation / record detection ────────────────────────────────────────

    /**
     * In a utility bar the component is never unmounted between navigations.
     * CurrentPageReference re-fires every time the user moves to a different page,
     * so it is the only reliable way to track which record is currently active.
     */
    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (!pageRef) return;

        // Standard record pages put the id in attributes;
        // some flows/communities put it in state — check both.
        const newId =
            pageRef.attributes?.recordId ||
            pageRef.state?.recordId ||
            null;

        if (newId === this._recordId) return; // same page, nothing to do

        this._recordId = newId;

        // Clear dynamic rows immediately so stale data is never shown
        this.customerTimezone = null;
        this.accountTimezone  = null;
        this.buildRows();

        // Always call loadData; Apex returns an empty map when recordId is null
        this.loadData();
    }

    // ─── Data loading ─────────────────────────────────────────────────────────

    async loadData() {
        try {
            const result = await getTimezoneData({ recordId: this._recordId });

            // Only set if Apex actually resolved a timezone from the state field.
            // If the key is absent the row stays hidden (null).
            this.customerTimezone = result.customerTimezone ?? null;
            this.accountTimezone  = result.accountTimezone  ?? null;
        } catch (error) {
            console.error('TimezoneUtilityBar – loadData error:', error);
            // Leave timezones null → rows stay hidden
        }

        this.buildRows();
    }

    // ─── Row construction ─────────────────────────────────────────────────────

    buildRows() {
        // Fixed rows are always shown
        const configs = [
            { label: 'PST',            timezone: 'America/Los_Angeles' },
            { label: 'CST',            timezone: 'America/Chicago'     },
            { label: 'EST',            timezone: 'America/New_York'    },
            { label: 'Logged In User', timezone: USER_TIMEZONE         },
        ];

        // Dynamic rows only appear when a timezone was resolved from the record
        if (this.customerTimezone) {
            configs.push({ label: 'Customer Timezone', timezone: this.customerTimezone });
        }
        if (this.accountTimezone) {
            configs.push({ label: 'Account Timezone', timezone: this.accountTimezone });
        }

        this.timezoneRows = configs.map(({ label, timezone }) => ({
            label,
            timezone,
            time:        this.formatTime(timezone),
            statusClass: this.getStatusClass(timezone),
        }));
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    formatTime(timezone) {
        return new Intl.DateTimeFormat('en-US', {
            hour:     '2-digit',
            minute:   '2-digit',
            second:   '2-digit',
            hour12:   true,
            timeZone: timezone,
        }).format(this.currentTime);
    }

    getStatusClass(timezone) {
        const hour = Number(
            new Intl.DateTimeFormat('en-US', {
                hour:     '2-digit',
                hour12:   false,
                timeZone: timezone,
            }).format(this.currentTime)
        );

        if (hour >= 9 && hour <= 17)                          return 'status online';
        if ((hour >= 7 && hour < 9) || (hour > 17 && hour <= 19)) return 'status warning';
        return 'status offline';
    }
}