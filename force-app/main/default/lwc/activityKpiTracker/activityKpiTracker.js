import { LightningElement, track, wire, api } from 'lwc';
import getMyKPI from '@salesforce/apex/ActivityKPIController.getMyKPI';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class ActivityKpiTracker extends LightningElement {
    @api recordId;
    
    @track kpiData = [];
    @track selectedPeriod = 'Monthly';
    @track error;
    @track isLoading = true;
    
    wiredKpiResponse;

    periodOptions = [
        { label: 'Daily', value: 'Daily' },
        { label: 'Weekly', value: 'Weekly' },
        { label: 'Monthly', value: 'Monthly' },
        { label: 'Quarterly', value: 'Quarterly' }
    ];

    @wire(getMyKPI, { recordId: '$effectiveRecordId', selectedPeriod: '$selectedPeriod' })
    wiredKPI(response) {
        this.wiredKpiResponse = response;
        const { data, error } = response;
        
        if (data && data.kpiRows && data.kpiRows.length > 0) {
            const allowedYtdTypes = ['Emails', 'Calls', 'Events'];
            
            this.kpiData = data.kpiRows.map(row => {
                return {
                    ...row,
                    isTotal: row.activityType.toUpperCase() === 'TOTAL',
                    showYtd: this.selectedPeriod === 'Monthly' && allowedYtdTypes.includes(row.activityType)
                };
            });
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.kpiData = [];
        }
        this.isLoading = false;
    }

    // Returns Emails, Calls, Tasks, Events for the 2-column grid
    get regularKpiData() {
        return this.kpiData.filter(item => !item.isTotal);
    }

    // Returns TOTAL for the dedicated bottom row
    get totalKpiData() {
        return this.kpiData.find(item => item.isTotal);
    }

    get effectiveRecordId() {
        return this.recordId ? this.recordId : null;
    }

    get hasKpiData() {
        return Array.isArray(this.kpiData) && this.kpiData.length > 0;
    }

    handlePeriodChange(event) {
        this.isLoading = true;
        this.selectedPeriod = event.detail.value;
    }

    @api
    async refreshTracker() {
        this.isLoading = true;
        try {
            if (this.recordId) {
                await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            }
            await refreshApex(this.wiredKpiResponse);
        } catch (err) {
            console.error('Error refreshing KPI tracker:', err);
        } finally {
            this.isLoading = false;
        }
    }
}